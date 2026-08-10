#include "grain_mend_detector.h"

#include "grain_mend_morphology.h"
#include "grain_mend_resample.h"
#include "negaflow/color/srgb_transfer.h"
#include "negaflow/imaging/grain_mend.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <future>
#include <limits>
#include <new>
#include <thread>
#include <utility>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {
namespace {

constexpr float clip_high = 0.985F;
constexpr float clip_low = 0.020F;
constexpr float dust_far_context_multiplier = 6.0F;
constexpr int scratch_short_half = 2;
constexpr double scratch_side_offset = 2.0;
constexpr int scratch_long_half = 12;

struct Offset final {
    int x{0};
    int y{0};
};

struct ScratchAngleMaps final {
    std::vector<float> ridge{};
    std::vector<float> integrated{};
};

[[nodiscard]] std::size_t checked_pixel_count(
    const std::uint32_t width,
    const std::uint32_t height) {
    if (width == 0U || height == 0U ||
        static_cast<std::size_t>(width) >
            std::numeric_limits<std::size_t>::max() /
                static_cast<std::size_t>(height)) {
        throw std::bad_alloc{};
    }
    return static_cast<std::size_t>(width) * static_cast<std::size_t>(height);
}

[[nodiscard]] std::uint32_t scaled_dimension(
    const std::uint32_t value,
    const std::uint32_t long_side) noexcept {
    if (long_side <= grain_mend_maximum_detection_dimension) {
        return value;
    }
    const double scaled =
        static_cast<double>(value) *
        static_cast<double>(grain_mend_maximum_detection_dimension) /
        static_cast<double>(long_side);
    return std::max(1U, static_cast<std::uint32_t>(std::lround(scaled)));
}

void finish_detection_channels(DetectionImage& image) {
    const std::size_t count = checked_pixel_count(image.width, image.height);
    image.luminance.resize(count);
    image.brightest_channel.resize(count);
    for (std::size_t index = 0U; index < count; ++index) {
        const float red = image.channels[0][index];
        const float green = image.channels[1][index];
        const float blue = image.channels[2][index];
        image.luminance[index] =
            red * 0.2126F + green * 0.7152F + blue * 0.0722F;
        image.brightest_channel[index] = std::max({red, green, blue});
    }
}

[[nodiscard]] float sample_clamped(
    const std::vector<float>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const int x,
    const int y) noexcept {
    const int sample_x = std::clamp(x, 0, static_cast<int>(width) - 1);
    const int sample_y = std::clamp(y, 0, static_cast<int>(height) - 1);
    return source[static_cast<std::size_t>(sample_y) * width +
                  static_cast<std::size_t>(sample_x)];
}

[[nodiscard]] std::vector<Offset> make_offsets(
    const int half,
    const double dx,
    const double dy,
    const double perpendicular_scale = 0.0,
    const double perpendicular_x = 0.0,
    const double perpendicular_y = 0.0) {
    std::vector<Offset> offsets{};
    offsets.reserve(static_cast<std::size_t>(half * 2 + 1));
    for (int t = -half; t <= half; ++t) {
        const double along = static_cast<double>(t);
        offsets.push_back({
            static_cast<int>(std::lround(
                along * dx + perpendicular_scale * perpendicular_x)),
            static_cast<int>(std::lround(
                along * dy + perpendicular_scale * perpendicular_y)),
        });
    }
    return offsets;
}

[[nodiscard]] int offset_margin(
    const std::vector<Offset>& first,
    const std::vector<Offset>& second = {},
    const std::vector<Offset>& third = {}) noexcept {
    int margin = 0;
    const auto accumulate = [&](const std::vector<Offset>& offsets) {
        for (const Offset offset : offsets) {
            margin = std::max(margin, std::max(std::abs(offset.x), std::abs(offset.y)));
        }
    };
    accumulate(first);
    accumulate(second);
    accumulate(third);
    return margin;
}

[[nodiscard]] std::vector<std::ptrdiff_t> make_linear_offsets(
    const std::vector<Offset>& offsets,
    const std::uint32_t width) {
    std::vector<std::ptrdiff_t> result{};
    result.reserve(offsets.size());
    for (const Offset offset : offsets) {
        result.push_back(
            static_cast<std::ptrdiff_t>(offset.y) *
                static_cast<std::ptrdiff_t>(width) +
            static_cast<std::ptrdiff_t>(offset.x));
    }
    return result;
}

void integrate_ridge(
    const std::vector<float>& ridge,
    const std::vector<std::uint8_t>& valid,
    const std::uint32_t width,
    const std::uint32_t height,
    const double dx,
    const double dy,
    const int half,
    std::vector<float>& integrated) {
    const auto offsets = make_offsets(half, dx, dy);
    const auto linear_offsets = make_linear_offsets(offsets, width);
    const int margin = offset_margin(offsets);
    const float inverse_taps =
        1.0F / static_cast<float>(half * 2 + 1);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::size_t index = static_cast<std::size_t>(y) * width + x;
            if (valid[index] == 0U) {
                continue;
            }
            float sum = 0.0F;
            const bool interior =
                static_cast<int>(x) >= margin &&
                static_cast<int>(y) >= margin &&
                static_cast<int>(x) + margin < static_cast<int>(width) &&
                static_cast<int>(y) + margin < static_cast<int>(height);
            float response = 0.0F;
            if (interior) {
                const auto center = static_cast<std::ptrdiff_t>(index);
                for (const std::ptrdiff_t offset : linear_offsets) {
                    sum += ridge[static_cast<std::size_t>(center + offset)];
                }
                response = sum * inverse_taps;
            } else {
                std::uint32_t samples = 0U;
                for (const Offset offset : offsets) {
                    const int sample_x = static_cast<int>(x) + offset.x;
                    const int sample_y = static_cast<int>(y) + offset.y;
                    if (sample_x >= 0 && sample_y >= 0 &&
                        sample_x < static_cast<int>(width) &&
                        sample_y < static_cast<int>(height)) {
                        sum += ridge[
                            static_cast<std::size_t>(sample_y) * width +
                            static_cast<std::size_t>(sample_x)];
                        ++samples;
                    }
                }
                response = samples == 0U
                    ? 0.0F
                    : sum / static_cast<float>(samples);
            }
            integrated[index] = std::max(integrated[index], response);
        }
    }
}

void make_scratch_angle_maps(
    const DetectionImage& image,
    const double angle_degrees,
    const std::vector<std::uint8_t>& valid,
    const float balance_limit,
    ScratchAngleMaps& result) {
    const std::size_t count = checked_pixel_count(image.width, image.height);
    const double radians = angle_degrees * 3.14159265358979323846 / 180.0;
    const double dx = std::cos(radians);
    const double dy = std::sin(radians);
    const double perpendicular_x = -dy;
    const double perpendicular_y = dx;
    const auto center_offsets = make_offsets(scratch_short_half, dx, dy);
    const auto positive_offsets = make_offsets(
        scratch_short_half,
        dx,
        dy,
        scratch_side_offset,
        perpendicular_x,
        perpendicular_y);
    const auto negative_offsets = make_offsets(
        scratch_short_half,
        dx,
        dy,
        -scratch_side_offset,
        perpendicular_x,
        perpendicular_y);
    const auto center_linear = make_linear_offsets(center_offsets, image.width);
    const auto positive_linear = make_linear_offsets(positive_offsets, image.width);
    const auto negative_linear = make_linear_offsets(negative_offsets, image.width);
    const int ridge_margin = offset_margin(
        center_offsets,
        positive_offsets,
        negative_offsets);

    if (result.ridge.size() != count) {
        result.ridge.resize(count);
    }
    if (result.integrated.size() != count) {
        result.integrated.resize(count);
    }
    std::fill(result.ridge.begin(), result.ridge.end(), 0.0F);
    std::fill(result.integrated.begin(), result.integrated.end(), 0.0F);
    constexpr float short_taps =
        static_cast<float>(scratch_short_half * 2 + 1);
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const std::size_t index = static_cast<std::size_t>(y) * image.width + x;
            if (valid[index] == 0U) {
                continue;
            }
            float center = 0.0F;
            float positive = 0.0F;
            float negative = 0.0F;
            const bool interior =
                static_cast<int>(x) >= ridge_margin &&
                static_cast<int>(y) >= ridge_margin &&
                static_cast<int>(x) + ridge_margin < static_cast<int>(image.width) &&
                static_cast<int>(y) + ridge_margin < static_cast<int>(image.height);
            if (interior) {
                const auto center_index = static_cast<std::ptrdiff_t>(index);
                for (std::size_t tap = 0U; tap < center_offsets.size(); ++tap) {
                    center += image.brightest_channel[static_cast<std::size_t>(
                        center_index + center_linear[tap])];
                    positive += image.brightest_channel[static_cast<std::size_t>(
                        center_index + positive_linear[tap])];
                    negative += image.brightest_channel[static_cast<std::size_t>(
                        center_index + negative_linear[tap])];
                }
            } else {
                for (std::size_t tap = 0U; tap < center_offsets.size(); ++tap) {
                    center += sample_clamped(
                        image.brightest_channel,
                        image.width,
                        image.height,
                        static_cast<int>(x) + center_offsets[tap].x,
                        static_cast<int>(y) + center_offsets[tap].y);
                    positive += sample_clamped(
                        image.brightest_channel,
                        image.width,
                        image.height,
                        static_cast<int>(x) + positive_offsets[tap].x,
                        static_cast<int>(y) + positive_offsets[tap].y);
                    negative += sample_clamped(
                        image.brightest_channel,
                        image.width,
                        image.height,
                        static_cast<int>(x) + negative_offsets[tap].x,
                        static_cast<int>(y) + negative_offsets[tap].y);
                }
            }
            center /= short_taps;
            positive /= short_taps;
            negative /= short_taps;
            if (std::abs(positive - negative) >= balance_limit) {
                continue;
            }
            result.ridge[index] = std::max(
                0.0F,
                std::max(
                    std::min(center - positive, center - negative),
                    std::min(positive - center, negative - center)));
        }
    }

    integrate_ridge(
        result.ridge,
        valid,
        image.width,
        image.height,
        dx,
        dy,
        scratch_long_half,
        result.integrated);
}

}  // namespace

DetectionImage make_detection_image(const WorkingImage& image) {
    DetectionImage result{};
    const std::uint32_t long_side = std::max(image.width, image.height);
    result.width = scaled_dimension(image.width, long_side);
    result.height = scaled_dimension(image.height, long_side);
    render_detection_rgb(
        image, result.width, result.height, result.channels);
    finish_detection_channels(result);
    return result;
}

DetectionImage make_detection_image_region(
    const WorkingImage& image,
    const std::uint32_t origin_x,
    const std::uint32_t origin_y,
    const std::uint32_t width,
    const std::uint32_t height) {
    DetectionImage result{};
    make_detection_image_region(
        image, origin_x, origin_y, width, height, result);
    return result;
}

void make_detection_image_region(
    const WorkingImage& image,
    const std::uint32_t origin_x,
    const std::uint32_t origin_y,
    const std::uint32_t width,
    const std::uint32_t height,
    DetectionImage& result) {
    if (width == 0U || height == 0U || origin_x > image.width ||
        origin_y > image.height || width > image.width - origin_x ||
        height > image.height - origin_y) {
        throw std::bad_alloc{};
    }
    result.width = width;
    result.height = height;
    const std::size_t count = checked_pixel_count(width, height);
    for (auto& channel : result.channels) {
        channel.resize(count);
    }
    for (std::uint32_t y = 0U; y < height; ++y) {
        const auto* const source = image.pixels.data() +
            static_cast<std::size_t>(origin_y + y) * image.stride_pixels +
            origin_x;
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::size_t index = static_cast<std::size_t>(y) * width + x;
            result.channels[0][index] =
                negaflow::color::linear_to_srgb_encoded(source[x].red);
            result.channels[1][index] =
                negaflow::color::linear_to_srgb_encoded(source[x].green);
            result.channels[2][index] =
                negaflow::color::linear_to_srgb_encoded(source[x].blue);
        }
    }
    finish_detection_channels(result);
}

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

    std::vector<std::uint8_t> valid(count, 0U);
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

        const float dust_absolute = static_cast<float>(
            0.14 - dust_sensitivity * 0.08);
        const float dust_weak_absolute = dust_absolute * 0.5F;
        const float dust_noise_multiplier = static_cast<float>(
            4.5 - dust_sensitivity * 1.5);
        const float dust_strong_magnitude =
            dust_absolute * static_cast<float>(
                5.0 - dust_sensitivity * 3.0);
        for (std::size_t index = 0U; index < count; ++index) {
            if (valid[index] == 0U) {
                continue;
            }
            const float magnitude = dust_magnitude[index];
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
    }
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
}

}  // namespace negaflow::imaging::grain_mend_detail
