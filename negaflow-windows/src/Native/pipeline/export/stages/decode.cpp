#include "decode.h"

#include "../support/preview_proxy.h"

#include "export/support/frame_cache_budget.h"
#include "export/support/outcome.h"

#include "negaflow/imageio/wic_standard_image_decoder.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"

#include <cwchar>
#include <memory>
#include <mutex>
#include <utility>
#include <vector>

namespace negaflow::pipeline::develop_export_detail {
namespace {

[[nodiscard]] bool is_tiff_source(const std::filesystem::path& path) noexcept {
    const std::wstring extension = path.extension().wstring();
    return _wcsicmp(extension.c_str(), L".tif") == 0 ||
           _wcsicmp(extension.c_str(), L".tiff") == 0;
}

// macOS `ScanFrame.cleanedRawImage` 상주 자리(`FrameCacheManager.residentCleanedRawIDs`)에
// 해당합니다. 같은 파일·같은 관측이면 디스크 TIFF 를 다시 읽지 않습니다.
//
// 앞 판은 **단일 슬롯 + 잠금 없음**이었습니다. 그런데 이 캐시를 지나는 것은 현상
// 프리뷰만이 아닙니다 — `ThumbnailService` 가 프레임마다 `develop_preview` 를 부르고
// (동시 3개), 자동 조정·검출·내보내기도 각자 스레드에서 들어옵니다. 그래서
// ① 썸네일이 다른 프레임을 디코드할 때마다 현상 중인 프레임의 디코드가 날아갔고
// ② 한쪽이 `image` 를 갈아 끼우는 동안 다른 쪽이 그것을 복사해 use-after-free 가 났습니다.
// 프레임별로 나누고, 잠그고, `shared_ptr<const>` 로 넘깁니다.
struct DecodedSourceEntry final {
    std::filesystem::path path{};
    negaflow::imageio::ImageFileObservation observation{};
    // **어느 크기로 푼 것인가.** 0 이면 원본 그대로입니다.
    //
    // 프리뷰는 프리뷰 크기로 풉니다. 그것을 크기 없이 담아 두면 내보내기가 작은 화상을
    // 원본이라 믿고 집어갑니다. 반대로 크기를 담지 않는다고 캐시를 통째로 끄면, 슬라이더를
    // 움직일 때마다 도는 정착 패스가 **디코드 도중에 취소돼** 아무것도 남기지 못하고
    // 다음 번에 처음부터 다시 풉니다 - 실기 기록에서 같은 프레임의 정착 패스가
    // 1,401 / 1,419 / 1,440 ms 로 세 번 연속 취소됐고, 그 사이에 낀 다음 조작이
    // 그만큼 밀렸습니다(2026-08-26 `preview-trace.txt`). 크기를 함께 담아 둘 다 지킵니다.
    std::uint32_t box_width{0U};
    std::uint32_t box_height{0U};
    std::shared_ptr<const negaflow::imaging::WorkingImage> source_image{};
    std::optional<std::array<std::uint8_t, 32U>> cleaned_recipe_sha256{};
    std::shared_ptr<const negaflow::imaging::WorkingImage> cleaned_image{};
    DefectRecipeStageInfo cleaned_info{};
};

// 앞이 오래된 것 — macOS `residentCleanedRawIDs` 와 같은 차례입니다.
std::vector<DecodedSourceEntry> g_decoded_sources{};
std::mutex g_decoded_mutex{};

[[nodiscard]] std::uint64_t decoded_bytes(
    const std::shared_ptr<const negaflow::imaging::WorkingImage>& image) noexcept {
    return image == nullptr
        ? 0ULL
        : static_cast<std::uint64_t>(image->pixels.size()) *
              sizeof(negaflow::core::Rgba32F);
}

[[nodiscard]] std::uint64_t decoded_bytes(const DecodedSourceEntry& entry) noexcept {
    return decoded_bytes(entry.source_image) + decoded_bytes(entry.cleaned_image);
}

[[nodiscard]] std::uint64_t decoded_budget_bytes() noexcept {
    return decoded_source_budget_bytes();
}

// macOS `trimCleanedRaw` — 한도를 넘으면 오래된 것부터 내려놓습니다.
// 방금 넣은 것을 곧바로 버리지 않도록 마지막 하나는 남깁니다.
void trim_decoded_locked() noexcept {
    std::uint64_t resident = 0ULL;
    for (const DecodedSourceEntry& entry : g_decoded_sources) {
        resident += decoded_bytes(entry);
    }
    // 예산을 물어보기 **전에** 알립니다. 자동 예산은 "프로세스 private 에서 캐시 몫을 뺀
    // 나머지" 를 간접비로 보므로, 내 몫을 안 알리면 그것까지 간접비로 세어 예산이 두 배로
    // 깎입니다.
    report_cache_resident_bytes(FrameCacheKind::decoded_source, resident);
    const std::uint64_t budget = decoded_budget_bytes();
    while (g_decoded_sources.size() > 1U && resident > budget) {
        resident -= decoded_bytes(g_decoded_sources.front());
        g_decoded_sources.erase(g_decoded_sources.begin());
    }
    report_cache_resident_bytes(FrameCacheKind::decoded_source, resident);
}

// macOS `markCleanedRawResident` 의 FIFO 재등록 — 쓰인 것은 뒤로 갑니다. 그래서 현상
// 중인 프레임은 썸네일이 아무리 흘러가도 가장 마지막에 밀려납니다.
[[nodiscard]] std::shared_ptr<const negaflow::imaging::WorkingImage> take_decoded(
    const std::filesystem::path& path,
    const negaflow::imageio::ImageFileObservation& observation,
    const std::uint32_t box_width,
    const std::uint32_t box_height) noexcept {
    const std::lock_guard<std::mutex> guard{g_decoded_mutex};
    // 새 할당이 없어도 시스템이 저메모리로 바뀌었으면 첫 재사용에서 과거 프레임을 내립니다.
    trim_decoded_locked();
    for (std::size_t index = 0U; index < g_decoded_sources.size(); ++index) {
        DecodedSourceEntry& entry = g_decoded_sources[index];
        if (entry.path != path ||
            entry.box_width != box_width || entry.box_height != box_height ||
            !negaflow::imageio::same_image_file_observation(
                entry.observation, observation)) {
            continue;
        }
        if (entry.source_image == nullptr) {
            continue;
        }
        std::shared_ptr<const negaflow::imaging::WorkingImage> image = entry.source_image;
        try {
            DecodedSourceEntry moved = std::move(entry);
            g_decoded_sources.erase(
                g_decoded_sources.begin() + static_cast<std::ptrdiff_t>(index));
            g_decoded_sources.push_back(std::move(moved));
        } catch (...) {
            // 재등록에 실패해도 꺼낸 화상은 유효합니다.
        }
        return image;
    }
    return nullptr;
}

void put_decoded(
    const std::filesystem::path& path,
    const negaflow::imageio::ImageFileObservation& observation,
    const std::uint32_t box_width,
    const std::uint32_t box_height,
    std::shared_ptr<const negaflow::imaging::WorkingImage> image) noexcept {
    if (image == nullptr) {
        return;
    }
    try {
        const std::lock_guard<std::mutex> guard{g_decoded_mutex};
        for (std::size_t index = 0U; index < g_decoded_sources.size(); ++index) {
            DecodedSourceEntry& existing = g_decoded_sources[index];
            if (existing.path != path ||
                existing.box_width != box_width || existing.box_height != box_height) {
                continue;
            }
            if (negaflow::imageio::same_image_file_observation(
                    existing.observation, observation)) {
                existing.source_image = std::move(image);
                DecodedSourceEntry moved = std::move(existing);
                g_decoded_sources.erase(
                    g_decoded_sources.begin() + static_cast<std::ptrdiff_t>(index));
                g_decoded_sources.push_back(std::move(moved));
                trim_decoded_locked();
                return;
            }
            g_decoded_sources.erase(
                g_decoded_sources.begin() + static_cast<std::ptrdiff_t>(index));
            break;
        }
        DecodedSourceEntry entry{};
        entry.path = path;
        entry.observation = observation;
        entry.box_width = box_width;
        entry.box_height = box_height;
        entry.source_image = std::move(image);
        g_decoded_sources.push_back(std::move(entry));
        trim_decoded_locked();
    } catch (...) {
    }
}

} // namespace

void decoded_source_store_reset() noexcept {
    const std::lock_guard<std::mutex> guard{g_decoded_mutex};
    g_decoded_sources.clear();
}

std::uint64_t decoded_source_store_resident_bytes() noexcept {
    const std::lock_guard<std::mutex> guard{g_decoded_mutex};
    std::uint64_t resident = 0ULL;
    for (const DecodedSourceEntry& entry : g_decoded_sources) {
        resident += decoded_bytes(entry);
    }
    return resident;
}

bool decoded_cleaned_raw_try_take(
    const std::filesystem::path& path,
    const negaflow::imageio::ImageFileObservation& observation,
    const std::array<std::uint8_t, 32U>& recipe_sha256,
    std::shared_ptr<const negaflow::imaging::WorkingImage>& image,
    DefectRecipeStageInfo& info) noexcept {
    const std::lock_guard<std::mutex> guard{g_decoded_mutex};
    trim_decoded_locked();
    for (std::size_t index = 0U; index < g_decoded_sources.size(); ++index) {
        DecodedSourceEntry& entry = g_decoded_sources[index];
        if (entry.path != path || entry.cleaned_image == nullptr ||
            entry.cleaned_recipe_sha256 != recipe_sha256 ||
            !negaflow::imageio::same_image_file_observation(
                entry.observation, observation)) {
            continue;
        }
        image = entry.cleaned_image;
        info = entry.cleaned_info;
        try {
            DecodedSourceEntry moved = std::move(entry);
            g_decoded_sources.erase(
                g_decoded_sources.begin() + static_cast<std::ptrdiff_t>(index));
            g_decoded_sources.push_back(std::move(moved));
        } catch (...) {
        }
        return true;
    }
    return false;
}

void decoded_cleaned_raw_put(
    const std::filesystem::path& path,
    const negaflow::imageio::ImageFileObservation& observation,
    const std::array<std::uint8_t, 32U>& recipe_sha256,
    std::shared_ptr<const negaflow::imaging::WorkingImage> image,
    const DefectRecipeStageInfo& info) noexcept {
    if (image == nullptr) {
        return;
    }
    try {
        const std::lock_guard<std::mutex> guard{g_decoded_mutex};
        for (std::size_t index = 0U; index < g_decoded_sources.size(); ++index) {
            DecodedSourceEntry& entry = g_decoded_sources[index];
            if (entry.path != path) {
                continue;
            }
            if (!negaflow::imageio::same_image_file_observation(
                    entry.observation, observation)) {
                g_decoded_sources.erase(
                    g_decoded_sources.begin() + static_cast<std::ptrdiff_t>(index));
                break;
            }
            entry.cleaned_recipe_sha256 = recipe_sha256;
            entry.cleaned_image = std::move(image);
            entry.cleaned_info = info;
            DecodedSourceEntry moved = std::move(entry);
            g_decoded_sources.erase(
                g_decoded_sources.begin() + static_cast<std::ptrdiff_t>(index));
            g_decoded_sources.push_back(std::move(moved));
            trim_decoded_locked();
            return;
        }
        DecodedSourceEntry entry{};
        entry.path = path;
        entry.observation = observation;
        entry.cleaned_recipe_sha256 = recipe_sha256;
        entry.cleaned_image = std::move(image);
        entry.cleaned_info = info;
        g_decoded_sources.push_back(std::move(entry));
        trim_decoded_locked();
    } catch (...) {
    }
}

std::optional<DevelopExportOutcome> decode_source(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    std::stop_source& stop,
    const ObservedSource& observed,
    negaflow::imaging::WorkingImage& decoded_image,
    const PreviewTarget* preview) noexcept {
    tracker.begin(DevelopExportStage::decode, cost_of(decode_cost, true));
    // 전체 해상도가 필요한 조건은 아래 두 갈래가 같습니다 - defect 편집의 ROI 가 원본 화소
    // 좌표라 프리뷰 크기로 줄이면 그 좌표가 화상 밖으로 나갑니다.
    const bool decodes_full_resolution =
        preview == nullptr || !request.defect_recipe.order.empty();
    // **요청 상자가 무엇이든 디코드는 정착 크기로 한 번만 합니다.**
    //
    // 앱은 한 프레임에 인터랙티브(2560)와 정착(3600)을 이어서 부릅니다. 요청 상자 그대로
    // 풀면 같은 파일을 두 번 풀고(실기: 1,982 ms + 2,047 ms), 캐시에도 두 벌이 남아
    // 프레임당 메모리가 두 배가 됩니다. 정착 크기 한 벌만 두면 인터랙티브는 그것을
    // 줄여 쓰면 됩니다 — `preview_proxy_materialize` 가 이미 Lanczos 로 줄입니다.
    const std::uint32_t box_width =
        decodes_full_resolution ? 0U : preview_full_max_dimension;
    const std::uint32_t box_height =
        decodes_full_resolution ? 0U : preview_full_max_dimension;
    // 잠금은 참조를 꺼낼 때만 잡습니다. 277MB 복사를 잠금 안에서 하면 다른 스레드가
    // 그동안 통째로 멈춥니다 — 참조를 들고 있으므로 복사 중에 해제되지 않습니다.
    if (const std::shared_ptr<const negaflow::imaging::WorkingImage> cached =
            take_decoded(request.source, observed.before.observation, box_width, box_height)) {
        try {
            decoded_image = *cached;
        } catch (...) {
            return fail(DevelopExportStage::decode, "decoded_source_copy_failed");
        }
        tracker.finish();
        if (tracker.cancelled()) {
            return cancelled_outcome(DevelopExportStage::decode);
        }
        return std::nullopt;
    }

    DecodeProgressBridge decode_progress{tracker, stop};
    negaflow::imageio::WicTiffDecodeControl decode_control{};
    decode_control.rows_per_copy = request.rows_per_copy;
    decode_control.stop_token = stop.get_token();
    decode_control.progress_observer = &decode_progress;
    if (preview != nullptr) {
        // region 과 infrared 편집의 ROI·마스크는 원본 화소 좌표입니다. 디코드가 프리뷰 크기로
        // 줄면 그 좌표가 작아진 이미지 밖으로 나가 defect 단계 전체가 invalid_argument 로
        // 끝납니다(실제 OpticFilm8100_frame_7: 5088x3401 기준 roi (1332,3340) 52x36 을
        // 1536x1026 이미지에 적용). brush 와 clone 은 정규화 좌표라 크기와 무관합니다.
        if (!decodes_full_resolution) {
            decode_control.max_output_width = box_width;
            decode_control.max_output_height = box_height;
        }
        decode_control.validate_compressed_streams = false;
    }
    if (is_tiff_source(request.source)) {
        auto prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
            request.source,
            {},
            {},
            decode_control);
        if (preview != nullptr &&
            decode_control.max_output_width != 0U &&
            prepared.decode.status != negaflow::imageio::WicTiffDecodeStatus::cancelled &&
            (prepared.decode.status != negaflow::imageio::WicTiffDecodeStatus::ok ||
             prepared.working.status != negaflow::imaging::ScannerToWorkingStatus::ok)) {
            decode_control.max_output_width = 0U;
            decode_control.max_output_height = 0U;
            prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
                request.source,
                {},
                {},
                decode_control);
        }
        if (prepared.decode.status == negaflow::imageio::WicTiffDecodeStatus::cancelled) {
            return cancelled_outcome(DevelopExportStage::decode);
        }
        if (prepared.decode.status != negaflow::imageio::WicTiffDecodeStatus::ok) {
            if (prepared.decode.status ==
                    negaflow::imageio::WicTiffDecodeStatus::row_sink_failed &&
                prepared.working.status !=
                    negaflow::imaging::ScannerToWorkingStatus::invalid_argument) {
                return fail(
                    DevelopExportStage::decode,
                    negaflow::imaging::scanner_to_working_status_name(
                        prepared.working.status),
                    prepared.working.info.native_error_code);
            }
            return fail(
                DevelopExportStage::decode,
                negaflow::imageio::wic_tiff_decode_status_name(prepared.decode.status));
        }
        if (prepared.working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
            return fail(
                DevelopExportStage::decode,
                negaflow::imaging::scanner_to_working_status_name(
                    prepared.working.status),
                prepared.working.info.native_error_code);
        }
        decoded_image = std::move(prepared.working.image);
    } else {
        // 프리뷰는 프리뷰 크기로 풉니다. 스캐너 TIFF 는 위에서 이미 그렇게 하고 있었고,
        // 표준·RAW 경로에만 빠져 있어서 사진 한 장을 처음 열 때마다 원본 전체를 풀었습니다
        // (실측: 2.2~13.1 초, 7 장에 peak 1,232 MB). 전체 해상도가 필요한 조건은 위와
        // 같습니다 - defect 편집의 ROI 가 원본 화소 좌표이기 때문입니다.
        negaflow::imageio::WicStandardImageDecodeControl standard_control{};
        if (!decodes_full_resolution) {
            standard_control.max_output_width = box_width;
            standard_control.max_output_height = box_height;
            standard_control.prefer_speed = true;
        }
        const negaflow::imageio::WicStandardImageDecodeResult decoded =
            negaflow::imageio::decode_standard_image_with_wic(
                request.source,
                {},
                stop.get_token(),
                standard_control);
        if (decoded.status == negaflow::imageio::WicStandardImageDecodeStatus::cancelled) {
            return cancelled_outcome(DevelopExportStage::decode);
        }
        if (decoded.status != negaflow::imageio::WicStandardImageDecodeStatus::ok) {
            return fail(
                DevelopExportStage::decode,
                negaflow::imageio::wic_standard_image_decode_status_name(decoded.status));
        }
        negaflow::imaging::ScannerToWorkingResult working =
            negaflow::imaging::convert_scanner_to_working(decoded.image);
        if (working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
            return fail(
                DevelopExportStage::decode,
                negaflow::imaging::scanner_to_working_status_name(working.status),
                working.info.native_error_code);
        }
        decoded_image = std::move(working.image);
    }

    const negaflow::imageio::ImageFileObservationResult after =
        negaflow::imageio::observe_image_file(request.source);
    if (after.status != negaflow::imageio::ImageFileObservationStatus::ok) {
        return fail(
            DevelopExportStage::observe_source_after,
            negaflow::imageio::image_file_observation_status_name(after.status),
            after.native_error_code);
    }
    if (!negaflow::imageio::same_image_file_observation(
            observed.before.observation,
            after.observation)) {
        return fail(
            DevelopExportStage::observe_source_after, "source_changed_during_decode");
    }

    // **프리뷰도 담습니다.** 예전에는 프리뷰를 빼 두어서, 슬라이더를 움직이는 동안 도는
    // 정착 패스가 디코드 도중 취소될 때마다 아무것도 남기지 못하고 다음 번에 처음부터 다시
    // 풀었습니다. 크기를 함께 담으므로 내보내기가 작은 화상을 집어갈 위험은 없습니다.
    try {
        put_decoded(
            request.source,
            observed.before.observation,
            box_width,
            box_height,
            std::make_shared<const negaflow::imaging::WorkingImage>(decoded_image));
    } catch (...) {
        // 캐시에 못 남겨도 이번 디코드 결과는 `decoded_image` 에 있습니다.
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::decode);
    }
    return std::nullopt;
}

} // namespace negaflow::pipeline::develop_export_detail
