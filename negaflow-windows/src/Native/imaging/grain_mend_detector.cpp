#include "grain_mend_detector.h"

#include "grain_mend_detection_image.h"
#include "grain_mend_morphology.h"
#include "grain_mend_scratch_angles.h"

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

}  // namespace

CandidateMaps find_candidates(
    const DetectionImage& image,
    const double dust_sensitivity,
    const double scratch_sensitivity,
    const double protect_detail,
    const bool labeled_detection,
    const negaflow::core::CancelFlag cancel) {
    CandidateMaps result{};
    find_candidates(
        image,
        dust_sensitivity,
        scratch_sensitivity,
        protect_detail,
        labeled_detection,
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
        for (const auto& channel : image.channels) {
            for (const std::uint32_t radius : dust_radii) {
                if (cancel.requested()) {
                    return;
                }
                const std::vector<float> magnitude = bipolar_top_hat(
                    channel, image.width, image.height, radius);
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

        const double dust_s = std::clamp(dust_sensitivity, 0.0, 1.0);
        const float dust_absolute = static_cast<float>(
            0.14 - dust_s * 0.08);
        const float dust_weak_absolute = dust_absolute * 0.5F;
        const float dust_noise_multiplier = static_cast<float>(
            4.5 - dust_s * 1.5);
        const float dust_strong_magnitude =
            dust_absolute * static_cast<float>(
                5.0 - dust_s * 3.0);
        for (std::size_t index = 0U; index < count; ++index) {
            if (valid[index] == 0U) {
                continue;
            }
            ++result.valid_pixels;
            const float magnitude = dust_magnitude[index];
            result.dust_magnitude_sum += static_cast<double>(magnitude);
            result.dust_noise_sum += static_cast<double>(noise_scale[index]);
            if (magnitude > dust_weak_absolute) {
                ++result.dust_pixels_above_weak_abs;
            }
            if (magnitude > dust_absolute) {
                ++result.dust_pixels_above_abs;
            }
            const bool soft =
                magnitude > dust_noise_multiplier * noise_scale[index] ||
                magnitude > dust_strong_magnitude;
            if (magnitude > dust_weak_absolute && soft) {
                result.weak[index] |= 1U;
            }
            const bool hard =
                magnitude > dust_noise_multiplier * noise_scale[index] ||
                (magnitude > dust_strong_magnitude &&
                 magnitude > dust_far_context_multiplier * far_texture[index]);
            if (magnitude > dust_absolute && hard) {
                result.strong[index] |= 1U;
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
                [&image, &valid, &workspace, value = angles[angle], scratch_balance_limit] {
                    make_scratch_angle_maps(
                        image,
                        value,
                        valid,
                        scratch_balance_limit,
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
