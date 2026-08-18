#include "grain_mend_detector.h"

#include "grain_mend_detection_image.h"
#include "grain_mend_morphology.h"
#include "grain_mend_scratch_angles.h"

#include "negaflow/imaging/kernel_accelerator.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <future>
#include <thread>
#include <utility>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {
namespace {

constexpr float clip_high = 0.985F;
constexpr float clip_low = 0.020F;
constexpr float dust_far_context_multiplier = 6.0F;
// macOS `DefectContrastField.largeDustContextRadius` — 큰 이물의 내부까지 주변 정상 톤과
// 비교하는 고정 문맥 반경입니다. ROI 크기에 따라 창이 바뀌면 같은 결함의 타일/비타일
// 결과가 달라지므로 물리 화소로 고정합니다.
constexpr std::uint32_t large_dust_context_radius = 80U;
// macOS `microNoiseScale` 의 반경입니다. 일반 반경 12 통계는 가까운 먼지 여러 개를 서로의
// 잡음으로 세어 자기억제하므로 8 로 분리합니다.
constexpr std::uint32_t micro_noise_radius = 8U;
// macOS `hasLargeContext` — 짧은 변이 이보다 작으면 큰 이물 문맥을 잡을 수 없습니다.
constexpr std::uint32_t large_context_minimum_side = 224U;

/// macOS `DefectDustDetector.passesSoft` — SNR 통과 또는 절대 강도 면제입니다.
[[nodiscard]] inline bool passes_soft(
    const float magnitude,
    const float noise_multiplier,
    const float noise,
    const float strong_magnitude) noexcept {
    return magnitude > noise_multiplier * noise || magnitude > strong_magnitude;
}

/// macOS `DefectDustDetector.passesHard` — 절대 강도 면제에 farTexture 컨텍스트 게이트를
/// 더합니다.
[[nodiscard]] inline bool passes_hard(
    const float magnitude,
    const float noise_multiplier,
    const float noise,
    const float strong_magnitude,
    const float far) noexcept {
    return magnitude > noise_multiplier * noise ||
           (magnitude > strong_magnitude &&
            magnitude > dust_far_context_multiplier * far);
}

/// 한 채널의 임계 묶음입니다. macOS `candidatesLeveled` 이 normal·micro·large 세 벌을
/// 같은 모양으로 계산하므로 한 표로 둡니다.
struct ChannelThresholds final {
    float absolute{0.0F};
    float weak_absolute{0.0F};
    float noise_multiplier{0.0F};
    float strong_magnitude{0.0F};
};

[[nodiscard]] ChannelThresholds make_thresholds(
    const double base,
    const double base_slope,
    const double noise_base,
    const double noise_slope,
    const double strong_multiple,
    const double sensitivity) noexcept {
    ChannelThresholds thresholds{};
    thresholds.absolute = static_cast<float>(base - sensitivity * base_slope);
    thresholds.weak_absolute = thresholds.absolute * 0.5F;
    thresholds.noise_multiplier = static_cast<float>(
        noise_base - sensitivity * noise_slope);
    thresholds.strong_magnitude = thresholds.absolute *
        static_cast<float>(strong_multiple);
    return thresholds;
}

}  // namespace

CandidateMaps find_candidates(
    const DetectionImage& image,
    const double dust_sensitivity,
    const double scratch_sensitivity,
    const double protect_detail,
    const bool labeled_detection,
    const bool extended_dust_scales,
    const negaflow::core::CancelFlag cancel) {
    CandidateMaps result{};
    find_candidates(
        image,
        dust_sensitivity,
        scratch_sensitivity,
        protect_detail,
        labeled_detection,
        extended_dust_scales,
        result,
        cancel);
    return result;
}

void find_candidates(
    const DetectionImage& image,
    const double dust_sensitivity,
    const double scratch_sensitivity,
    const double protect_detail,
    const bool labeled_detection,
    const bool extended_dust_scales,
    CandidateMaps& result,
    const negaflow::core::CancelFlag cancel) {
    const std::size_t count = checked_pixel_count(image.width, image.height);
    result.weak.resize(count);
    result.strong.resize(count);
    result.scratch_response.resize(count);
    std::fill(
        result.weak.begin(),
        result.weak.end(),
        static_cast<std::uint8_t>(0U));
    std::fill(
        result.strong.begin(),
        result.strong.end(),
        static_cast<std::uint8_t>(0U));
    std::fill(
        result.scratch_response.begin(),
        result.scratch_response.end(),
        0.0F);
    if (image.width <= 2U || image.height <= 2U) {
        return;
    }

    result.valid.assign(count, 0U);
    std::vector<std::uint8_t>& valid = result.valid;
    {
        const std::vector<float> luma_open =
            opening(image.luminance, image.width, image.height, 4U);
        const std::vector<float> luma_close =
            closing(image.luminance, image.width, image.height, 4U);
        for (std::size_t index = 0U; index < count; ++index) {
            valid[index] = luma_open[index] < clip_high &&
                                   luma_close[index] > clip_low
                ? 1U
                : 0U;
        }
    }
    const auto dust_started = std::chrono::steady_clock::now();
    {
        std::vector<float> dust_magnitude(count, 0.0F);
        std::vector<float> thin_magnitude(count, 0.0F);
        std::vector<float> noise_scale{};
        std::vector<float> far_texture{};
        constexpr std::array<std::uint32_t, 3U> dust_radii{4U, 8U, 12U};
        for (const std::uint32_t radius : dust_radii) {
            if (cancel.requested()) {
                return;
            }
            const RgbPlanes packed = bipolar_top_hat_rgb(
                image.channels[0],
                image.channels[1],
                image.channels[2],
                image.width,
                image.height,
                radius);
            const bool used_packed = !packed.red.empty();
            const std::array<const std::vector<float>*, 3U> magnitudes{
                used_packed ? &packed.red : nullptr,
                used_packed ? &packed.green : nullptr,
                used_packed ? &packed.blue : nullptr};
            for (std::size_t channel = 0U; channel < image.channels.size(); ++channel) {
                const std::vector<float> fallback = used_packed
                    ? std::vector<float>{}
                    : bipolar_top_hat(
                          image.channels[channel], image.width, image.height, radius);
                const std::vector<float>& magnitude =
                    used_packed ? *magnitudes[channel] : fallback;
                for (std::size_t index = 0U; index < count; ++index) {
                    dust_magnitude[index] =
                        std::max(dust_magnitude[index], magnitude[index]);
                    if (radius == 4U) {
                        thin_magnitude[index] =
                            std::max(thin_magnitude[index], magnitude[index]);
                    }
                }
            }
        }
        noise_scale = box_mean(
            dust_magnitude, image.width, image.height, 12U);
        far_texture = box_mean(
            dust_magnitude, image.width, image.height, 36U);

        // macOS `DefectContrastField` 확장 스케일. `micro` 는 이미 계산한 반경 4 결과를
        // 낮은 임계로 재사용하고, `large` 는 단일 적분영상 박스평균과의 편차로 봅니다 —
        // 추가 opening/closing 은 돌지 않습니다(macOS 도 그 8단계를 제거했습니다).
        const bool has_large_context =
            std::min(image.width, image.height) >= large_context_minimum_side;
        std::vector<float> micro_noise_scale{};
        std::vector<float> large_magnitude{};
        if (extended_dust_scales) {
            micro_noise_scale = box_mean(
                thin_magnitude, image.width, image.height, micro_noise_radius);
            if (has_large_context) {
                const std::vector<float> background = box_mean(
                    image.luminance,
                    image.width,
                    image.height,
                    large_dust_context_radius);
                large_magnitude.resize(count);
                for (std::size_t index = 0U; index < count; ++index) {
                    large_magnitude[index] = std::abs(
                        image.luminance[index] - background[index]);
                }
            }
        }

        const double dust_s = std::clamp(dust_sensitivity, 0.0, 1.0);
        // macOS `candidatesLeveled` 의 세 벌 임계입니다(aggressive=false 가지).
        const ChannelThresholds normal = make_thresholds(
            0.14, 0.08, 4.5, 1.5, 5.0 - dust_s * 3.0, dust_s);
        const ChannelThresholds micro = make_thresholds(
            0.06, 0.04, 4.5, 1.5, 2.5, dust_s);
        const ChannelThresholds large = make_thresholds(
            0.12, 0.07, 4.5, 1.5, 2.0, dust_s);
        // macOS `compactAbsoluteStrong` — 여러 고대비 먼지가 가까우면 서로 farTexture 를
        // 높여 normalStrong 이 전부 꺼질 수 있으므로, 보수 임계의 1.5배를 넘는 화소는 절대
        // 대비 코어로 인정합니다.
        const float compact_absolute_strong = std::max(
            0.16F, normal.absolute * 1.5F);
        const bool has_micro = extended_dust_scales &&
            micro_noise_scale.size() == count;
        const bool has_large = extended_dust_scales &&
            large_magnitude.size() == count;
        if (extended_dust_scales) {
            result.trusted_strong.assign(count, 0U);
        }
        for (std::size_t index = 0U; index < count; ++index) {
            if (valid[index] == 0U) {
                continue;
            }
            ++result.valid_pixels;
            const float magnitude = dust_magnitude[index];
            const float noise = noise_scale[index];
            const float far = far_texture[index];
            result.dust_magnitude_sum += static_cast<double>(magnitude);
            result.dust_noise_sum += static_cast<double>(noise);
            if (magnitude > normal.weak_absolute) {
                ++result.dust_pixels_above_weak_abs;
            }
            if (magnitude > normal.absolute) {
                ++result.dust_pixels_above_abs;
            }
            const bool normal_weak = magnitude > normal.weak_absolute &&
                passes_soft(
                    magnitude,
                    normal.noise_multiplier,
                    noise,
                    normal.strong_magnitude);
            const float micro_magnitude = has_micro
                ? thin_magnitude[index]
                : 0.0F;
            const float micro_noise = has_micro
                ? micro_noise_scale[index]
                : 0.0F;
            const bool micro_weak = has_micro &&
                micro_magnitude > micro.weak_absolute &&
                passes_soft(
                    micro_magnitude,
                    micro.noise_multiplier,
                    micro_noise,
                    micro.strong_magnitude);
            const float large_value = has_large ? large_magnitude[index] : 0.0F;
            const bool large_weak = has_large &&
                large_value > large.weak_absolute &&
                passes_soft(
                    large_value,
                    large.noise_multiplier,
                    noise,
                    large.strong_magnitude);
            if (!normal_weak && !micro_weak && !large_weak) {
                continue;
            }
            result.weak[index] |= 1U;
            const bool normal_strong = magnitude > normal.absolute &&
                passes_hard(
                    magnitude,
                    normal.noise_multiplier,
                    noise,
                    normal.strong_magnitude,
                    far);
            const bool micro_strong = has_micro &&
                micro_magnitude > micro.absolute &&
                passes_hard(
                    micro_magnitude,
                    micro.noise_multiplier,
                    micro_noise,
                    micro.strong_magnitude,
                    far);
            const bool large_strong = has_large &&
                large_value > large.absolute &&
                passes_hard(
                    large_value,
                    large.noise_multiplier,
                    noise,
                    large.strong_magnitude,
                    far);
            if (normal_strong || micro_strong || large_strong) {
                result.strong[index] |= 1U;
            }
            if (!result.trusted_strong.empty() &&
                (normal_strong || large_strong ||
                 magnitude > compact_absolute_strong)) {
                result.trusted_strong[index] = 1U;
            }
        }
        if (labeled_detection) {
            const float thin_absolute = static_cast<float>(
                0.14 - scratch_sensitivity * 0.08);
            const float thin_weak_absolute = thin_absolute * 0.5F;
            const float thin_noise_multiplier = static_cast<float>(
                4.5 - scratch_sensitivity * 1.5);
            const float thin_strong_magnitude = thin_absolute * static_cast<float>(
                5.0 - scratch_sensitivity * 3.0);
            for (std::size_t index = 0U; index < count; ++index) {
                if (valid[index] == 0U) {
                    continue;
                }
                const float magnitude = thin_magnitude[index];
                const bool soft =
                    magnitude > thin_noise_multiplier * noise_scale[index] ||
                    magnitude > thin_strong_magnitude;
                if (magnitude > thin_weak_absolute && soft) {
                    result.weak[index] |= 2U;
                }
                const bool hard =
                    magnitude > thin_noise_multiplier * noise_scale[index] ||
                    (magnitude > thin_strong_magnitude &&
                     magnitude > dust_far_context_multiplier * far_texture[index]);
                if (magnitude > thin_absolute && hard) {
                    result.strong[index] |= 2U;
                }
            }
        }
        // 분류기가 읽을 국소 통계를 넘깁니다. 이미 계산해 둔 배열을 옮기기만 하므로 검출
        // 비용이 늘지 않습니다 — macOS 도 DefectContrastField 를 분류까지 들고 있습니다.
        result.dust_magnitude = std::move(dust_magnitude);
        result.thin_magnitude = std::move(thin_magnitude);
        result.noise_scale = std::move(noise_scale);
    }
    const auto scratch_started = std::chrono::steady_clock::now();
    result.dust_morphology_microseconds =
        static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(
            scratch_started - dust_started).count());
    std::vector<float>& best = result.scratch_response;
    std::vector<float> local_ridge(count, 0.0F);
    constexpr std::array<double, 8U> angles{
        0.0, 22.5, 45.0, 67.5, 90.0, 112.5, 135.0, 157.5,
    };
    const float scratch_balance_limit = static_cast<float>(
        0.10 - protect_detail * 0.04);
    bool used_gpu_stack = false;
    if (const KernelAccelerator* const table = kernel_accelerator();
        table != nullptr && table->scratch_angle_stack != nullptr) {
        std::array<negaflow::imaging::ScratchAngleTaps, 8> tap_sets{};
        for (std::size_t angle = 0U; angle < angles.size(); ++angle) {
            fill_scratch_angle_taps(angles[angle], labeled_detection, tap_sets[angle]);
        }
        used_gpu_stack = table->scratch_angle_stack(
            image.brightest_channel.data(),
            valid.data(),
            local_ridge.data(),
            best.data(),
            image.width,
            image.height,
            tap_sets.data(),
            static_cast<int>(angles.size()),
            scratch_balance_limit);
    }
    if (!used_gpu_stack) {
    const unsigned int hardware_threads = std::thread::hardware_concurrency();
    const std::size_t worker_count = std::clamp<std::size_t>(
        hardware_threads == 0U ? 2U : hardware_threads,
        1U,
        2U);
    std::vector<ScratchAngleMaps> workspaces(worker_count);
    for (ScratchAngleMaps& workspace : workspaces) {
        workspace.ridge.resize(count);
        workspace.integrated.resize(count);
    }
    for (std::size_t first = 0U; first < angles.size(); first += worker_count) {
        // Between angle batches rather than inside one: a batch already in flight has to
        // be joined before its workspace can be reused, so stopping here is the earliest
        // point that leaves nothing running.
        if (cancel.requested()) {
            return;
        }
        const std::size_t last = std::min(angles.size(), first + worker_count);
        std::vector<std::future<void>> futures{};
        futures.reserve(last - first);
        for (std::size_t angle = first; angle < last; ++angle) {
            ScratchAngleMaps& workspace = workspaces[angle - first];
            futures.push_back(std::async(
                std::launch::async,
                [&image, &valid, &workspace, value = angles[angle], scratch_balance_limit,
                 labeled_detection] {
                    make_scratch_angle_maps(
                        image,
                        value,
                        valid,
                        scratch_balance_limit,
                        labeled_detection,
                        workspace);
                }));
        }
        for (std::size_t slot = 0U; slot < futures.size(); ++slot) {
            futures[slot].get();
            const ScratchAngleMaps& maps = workspaces[slot];
            for (std::size_t index = 0U; index < count; ++index) {
                best[index] = std::max(best[index], maps.integrated[index]);
                local_ridge[index] = std::max(local_ridge[index], maps.ridge[index]);
            }
        }
    }
    }
    const std::vector<float> scratch_floor =
        box_mean(best, image.width, image.height, 12U);
    const float scratch_absolute = static_cast<float>(
        0.034 - scratch_sensitivity * 0.014);
    const float scratch_floor_multiplier = static_cast<float>(
        4.0 - scratch_sensitivity * 0.8);
    const float scratch_short_floor = scratch_absolute * 0.6F;
    const float scratch_weak_absolute = scratch_absolute * 0.5F;
    const float scratch_weak_short_floor = scratch_weak_absolute * 0.6F;
    for (std::size_t index = 0U; index < count; ++index) {
        const bool strong = valid[index] != 0U &&
            local_ridge[index] > scratch_short_floor &&
            best[index] > scratch_absolute &&
            best[index] > scratch_floor_multiplier * scratch_floor[index];
        if (strong) {
            result.weak[index] |= 2U;
            result.strong[index] |= 2U;
            continue;
        }
        if (labeled_detection && valid[index] != 0U &&
            local_ridge[index] > scratch_weak_short_floor &&
            best[index] > scratch_weak_absolute &&
            best[index] > scratch_floor_multiplier * scratch_floor[index]) {
            result.weak[index] |= 2U;
        }
    }
    result.scratch_angles_microseconds =
        static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now() - scratch_started).count());
}

}  // namespace negaflow::imaging::grain_mend_detail
