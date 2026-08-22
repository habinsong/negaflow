#include "observe.h"

#include "export/support/outcome.h"

#include "negaflow/imageio/image_content_hash.h"

#include <algorithm>
#include <array>
#include <mutex>
#include <string>

namespace negaflow::pipeline::develop_export_detail {
namespace {

// **이 해시가 슬라이더 한 틱마다 돌고 있었습니다.**
//
// 결함 편집이 있는 프레임은 요청에 `expected_defect_source_identity` 가 실리고, 그러면
// 아래 갈래가 **원본 TIFF 전체**를 SHA-256 합니다. 실측: `frame_1`(5088x3401, 약 104MB)
// 에서 틱당 약 140ms — 단계 표 어디에도 안 잡히는 시간이었고, 그동안 파일은 한 번도
// 바뀌지 않았습니다. 8ms 간격 드래그에서 매번 100MB 를 다시 읽는 셈입니다.
//
// 관측(볼륨 일련번호 · 파일 인덱스 · 바이트 수 · 마지막 쓰기 시각)이 같으면 같은
// 파일입니다. 이 코드가 이미 `same_image_file_observation` 으로 "읽는 동안 안 바뀌었다"를
// 판정하는 바로 그 근거이므로, 같은 근거를 열쇠로 마지막 해시들을 들고 있습니다.
// 넷 중 하나라도 다르면 그대로 다시 해시합니다 — **판정은 하나도 느슨해지지 않습니다.**
//
// 자리를 여럿 두는 이유: 이웃 예열이 배경에서 다른 사진을 돌리므로 한 자리면 서로
// 밀어내 캐시가 없는 것과 같아집니다.
constexpr std::size_t hashed_source_slots = 8U;

struct HashedSource final {
    std::string path{};
    negaflow::imageio::ImageFileObservation observation{};
    std::uint64_t file_bytes{0U};
    std::array<std::uint8_t, 32U> sha256{};
    bool valid{false};
};

std::mutex hashed_source_lock{};
HashedSource hashed_sources[hashed_source_slots]{};
std::size_t hashed_source_next = 0U;

[[nodiscard]] bool take_hashed_source(
    const std::string& path,
    const negaflow::imageio::ImageFileObservation& observation,
    std::uint64_t& file_bytes,
    std::array<std::uint8_t, 32U>& sha256) noexcept {
    const std::lock_guard<std::mutex> guard{hashed_source_lock};
    for (const HashedSource& slot : hashed_sources) {
        if (slot.valid && slot.path == path &&
            negaflow::imageio::same_image_file_observation(
                slot.observation, observation)) {
            file_bytes = slot.file_bytes;
            sha256 = slot.sha256;
            return true;
        }
    }
    return false;
}

void remember_hashed_source(
    const std::string& path,
    const negaflow::imageio::ImageFileObservation& observation,
    const std::uint64_t file_bytes,
    const std::array<std::uint8_t, 32U>& sha256) noexcept {
    const std::lock_guard<std::mutex> guard{hashed_source_lock};
    for (HashedSource& slot : hashed_sources) {
        if (slot.valid && slot.path == path) {
            slot.observation = observation;
            slot.file_bytes = file_bytes;
            slot.sha256 = sha256;
            return;
        }
    }
    HashedSource& slot = hashed_sources[hashed_source_next];
    hashed_source_next = (hashed_source_next + 1U) % hashed_source_slots;
    try {
        slot.path = path;
    } catch (...) {
        slot.valid = false;
        return;
    }
    slot.observation = observation;
    slot.file_bytes = file_bytes;
    slot.sha256 = sha256;
    slot.valid = true;
}

} // namespace

std::optional<DevelopExportOutcome> observe_source_before(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    std::stop_source& stop,
    ObservedSource& observed) noexcept {
    observed.before = negaflow::imageio::observe_image_file(request.source);
    if (observed.before.status != negaflow::imageio::ImageFileObservationStatus::ok) {
        return fail(
            DevelopExportStage::observe_source_before,
            negaflow::imageio::image_file_observation_status_name(observed.before.status),
            observed.before.native_error_code);
    }
    if (request.expected_defect_source_identity) {
        tracker.begin(DevelopExportStage::observe_source_before, 0U);
        const ExpectedSourceIdentity& expected =
            *request.expected_defect_source_identity;

        // **sha 가 전부 0 이면 "바이트 수만 확인" 입니다.**
        //
        // 설정 `이미지 내용 해시` 의 기본값은 끔인데, ABI 는 결함 편집이 있으면
        // identity 를 요구합니다(`has_edits == has_identity`). 그래서 셸이 sha 자리를
        // 0 으로 채워 보내고 여기서 그 뜻을 읽습니다
        // (`Shell.Core/Develop/DevelopRequestFactory.cs`).
        // 실제 파일의 SHA-256 이 64자리 0 일 수는 없으므로 뜻이 겹치지 않습니다.
        //
        // 켜져 있지도 않은 검사에 frame_1(104MB)에서 **슬라이더 틱당 약 140ms** 를
        // 쓰고 있었습니다. 파일이 바뀌면 바이트 수·수정 시각이 먼저 달라지므로,
        // 값싼 확인만으로도 마스크를 엉뚱한 사진에 거는 일은 막힙니다.
        const bool content_check_disabled = std::all_of(
            expected.sha256.begin(),
            expected.sha256.end(),
            [](const std::uint8_t byte) noexcept { return byte == 0U; });
        if (content_check_disabled) {
            if (observed.before.observation.file_bytes != expected.file_bytes) {
                return fail(
                    DevelopExportStage::observe_source_before,
                    "defect_source_identity_mismatch");
            }
            return std::nullopt;
        }

        // 내용 해시가 켜져 있어도 바이트 수가 다르면 읽을 이유가 없습니다.
        if (observed.before.observation.file_bytes != expected.file_bytes) {
            return fail(
                DevelopExportStage::observe_source_before,
                "defect_source_identity_mismatch");
        }

        std::string key{};
        bool have_key = false;
        try {
            key = request.source.string();
            have_key = true;
        } catch (...) {
            have_key = false;
        }

        std::uint64_t file_bytes = 0U;
        std::array<std::uint8_t, 32U> sha256{};
        if (have_key &&
            take_hashed_source(key, observed.before.observation, file_bytes, sha256)) {
            if (file_bytes != expected.file_bytes || sha256 != expected.sha256) {
                return fail(
                    DevelopExportStage::observe_source_before,
                    "defect_source_identity_mismatch");
            }
            return std::nullopt;
        }

        HashProgressBridge hash_progress{tracker, stop};
        negaflow::imageio::ImageContentHashControl hash_control{};
        hash_control.mode = negaflow::imageio::ImageContentHashMode::sha256;
        hash_control.stop_token = stop.get_token();
        hash_control.progress_observer = &hash_progress;
        const negaflow::imageio::ImageContentHashResult hashed =
            negaflow::imageio::hash_image_content(request.source, hash_control);
        if (hashed.status == negaflow::imageio::ImageContentHashStatus::cancelled) {
            return cancelled_outcome(DevelopExportStage::observe_source_before);
        }
        if (hashed.status != negaflow::imageio::ImageContentHashStatus::ok) {
            return fail(
                DevelopExportStage::observe_source_before,
                negaflow::imageio::image_content_hash_status_name(hashed.status),
                hashed.native_error_code);
        }
        if (!negaflow::imageio::same_image_file_observation(
                observed.before.observation,
                hashed.observation)) {
            return fail(
                DevelopExportStage::observe_source_before,
                "source_changed_before_decode");
        }
        // 해시가 끝난 뒤의 관측을 열쇠로 남깁니다 — 위에서 두 관측이 같음을 이미 확인했습니다.
        if (have_key) {
            remember_hashed_source(
                key, hashed.observation, hashed.file_bytes, hashed.sha256);
        }
        if (hashed.file_bytes != expected.file_bytes ||
            hashed.sha256 != expected.sha256) {
            return fail(
                DevelopExportStage::observe_source_before,
                "defect_source_identity_mismatch");
        }
    }
    return std::nullopt;
}

} // namespace negaflow::pipeline::develop_export_detail
