#include "decoded_source_store.h"
#include "frame_cache_budget.h"
#include <algorithm>
#include <mutex>
#include <utility>
#include <vector>

namespace negaflow::pipeline::develop_export_detail {
namespace {
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
    negaflow::color::InputGammaInterpretation input_gamma{};
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
    EncodedSourceImage encoded_image{};
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
    return decoded_bytes(entry.source_image) + decoded_bytes(entry.cleaned_image)
        + (entry.encoded_image ? entry.encoded_image->samples.size() * sizeof(std::uint16_t)
            + entry.encoded_image->icc_profile.size() : 0ULL);
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

} // namespace

[[nodiscard]] std::shared_ptr<const negaflow::imaging::WorkingImage> decoded_source_try_take(
    const std::filesystem::path& path,
    const negaflow::imageio::ImageFileObservation& observation,
    const std::uint32_t box_width,
    const std::uint32_t box_height,
    const negaflow::color::InputGammaInterpretation input_gamma) noexcept {
    const std::lock_guard<std::mutex> guard{g_decoded_mutex};
    // 새 할당이 없어도 시스템이 저메모리로 바뀌었으면 첫 재사용에서 과거 프레임을 내립니다.
    trim_decoded_locked();
    for (std::size_t index = 0U; index < g_decoded_sources.size(); ++index) {
        DecodedSourceEntry& entry = g_decoded_sources[index];
        if (entry.path != path || entry.input_gamma != input_gamma ||
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

void decoded_source_put(
    const std::filesystem::path& path,
    const negaflow::imageio::ImageFileObservation& observation,
    const std::uint32_t box_width,
    const std::uint32_t box_height,
    std::shared_ptr<const negaflow::imaging::WorkingImage> image,
    const negaflow::color::InputGammaInterpretation input_gamma) noexcept {
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
                if (existing.input_gamma != input_gamma) {
                    existing.input_gamma = input_gamma;
                    existing.cleaned_image.reset();
                    existing.cleaned_recipe_sha256.reset();
                }
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
        entry.input_gamma = input_gamma;
        entry.observation = observation;
        entry.box_width = box_width;
        entry.box_height = box_height;
        entry.source_image = std::move(image);
        g_decoded_sources.push_back(std::move(entry));
        trim_decoded_locked();
    } catch (...) {
    }
}


void decoded_source_store_reset() noexcept {
    const std::lock_guard<std::mutex> guard{g_decoded_mutex};
    g_decoded_sources.clear();
    report_cache_resident_bytes(FrameCacheKind::decoded_source, 0ULL);
}

EncodedSourceImage encoded_source_try_take(const std::filesystem::path& path,
    const negaflow::imageio::ImageFileObservation& observation,
    const std::uint32_t box_width, const std::uint32_t box_height) noexcept {
    const std::lock_guard guard{g_decoded_mutex};
    trim_decoded_locked();
    for (std::size_t index = 0; index < g_decoded_sources.size(); ++index) {
        auto& entry = g_decoded_sources[index];
        if (entry.path != path || entry.box_width != box_width || entry.box_height != box_height ||
            !entry.encoded_image || !negaflow::imageio::same_image_file_observation(entry.observation, observation)) { continue; }
        auto image = entry.encoded_image;
        std::rotate(g_decoded_sources.begin() + static_cast<std::ptrdiff_t>(index),
            g_decoded_sources.begin() + static_cast<std::ptrdiff_t>(index + 1U), g_decoded_sources.end());
        return image;
    }
    return nullptr;
}

void encoded_source_put(const std::filesystem::path& path,
    const negaflow::imageio::ImageFileObservation& observation,
    const std::uint32_t box_width, const std::uint32_t box_height, EncodedSourceImage image) noexcept {
    if (!image || image->samples.empty()) { return; }
    try {
        const std::lock_guard guard{g_decoded_mutex};
        for (auto& entry : g_decoded_sources) {
            if (entry.path != path || entry.box_width != box_width || entry.box_height != box_height) { continue; }
            if (!negaflow::imageio::same_image_file_observation(entry.observation, observation)) {
                entry.source_image.reset(); entry.cleaned_image.reset(); entry.cleaned_recipe_sha256.reset();
                entry.observation = observation;
            }
            entry.encoded_image = std::move(image);
            trim_decoded_locked();
            return;
        }
        DecodedSourceEntry entry{};
        entry.path = path; entry.observation = observation;
        entry.box_width = box_width; entry.box_height = box_height;
        entry.encoded_image = std::move(image);
        g_decoded_sources.push_back(std::move(entry));
        trim_decoded_locked();
    } catch (...) { }
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
    DefectRecipeStageInfo& info,
    const negaflow::color::InputGammaInterpretation input_gamma) noexcept {
    const std::lock_guard<std::mutex> guard{g_decoded_mutex};
    trim_decoded_locked();
    for (std::size_t index = 0U; index < g_decoded_sources.size(); ++index) {
        DecodedSourceEntry& entry = g_decoded_sources[index];
        if (entry.path != path || entry.input_gamma != input_gamma || entry.cleaned_image == nullptr ||
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
    const DefectRecipeStageInfo& info,
    const negaflow::color::InputGammaInterpretation input_gamma) noexcept {
    if (image == nullptr) {
        return;
    }
    try {
        const std::lock_guard<std::mutex> guard{g_decoded_mutex};
        for (std::size_t index = 0U; index < g_decoded_sources.size(); ++index) {
            DecodedSourceEntry& entry = g_decoded_sources[index];
            if (entry.path != path || entry.input_gamma != input_gamma) {
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
        entry.input_gamma = input_gamma;
        entry.observation = observation;
        entry.cleaned_recipe_sha256 = recipe_sha256;
        entry.cleaned_image = std::move(image);
        entry.cleaned_info = info;
        g_decoded_sources.push_back(std::move(entry));
        trim_decoded_locked();
    } catch (...) {
    }
}


} // namespace negaflow::pipeline::develop_export_detail
