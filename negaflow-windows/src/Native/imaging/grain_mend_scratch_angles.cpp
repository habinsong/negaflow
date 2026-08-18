#include "grain_mend_scratch_angles.h"

#include "grain_mend_detection_image.h"
#include "negaflow/imaging/kernel_accelerator.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {
namespace {

constexpr int scratch_short_half = 2;
constexpr double scratch_side_offset = 2.0;
constexpr int scratch_long_half = 12;
constexpr int scratch_curve_half = 6;

struct Offset final {
    int x{0};
    int y{0};
};

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


void copy_offsets(
    const std::vector<Offset>& offsets,
    std::int32_t (*destination)[2],
    const int capacity) {
    const int count = std::min(capacity, static_cast<int>(offsets.size()));
    for (int index = 0; index < count; ++index) {
        destination[index][0] = offsets[static_cast<std::size_t>(index)].x;
        destination[index][1] = offsets[static_cast<std::size_t>(index)].y;
    }
}

}  // namespace

void fill_scratch_angle_taps(
    const double degrees,
    const bool multi_scale,
    negaflow::imaging::ScratchAngleTaps& taps) {
    const double radians = degrees * 3.14159265358979323846 / 180.0;
    const double dx = std::cos(radians);
    const double dy = std::sin(radians);
    const double perpendicular_x = -dy;
    const double perpendicular_y = dx;
    copy_offsets(make_offsets(scratch_short_half, dx, dy), taps.center, 5);
    copy_offsets(
        make_offsets(
            scratch_short_half, dx, dy, scratch_side_offset, perpendicular_x, perpendicular_y),
        taps.positive,
        5);
    copy_offsets(
        make_offsets(
            scratch_short_half, dx, dy, -scratch_side_offset, perpendicular_x, perpendicular_y),
        taps.negative,
        5);
    const auto along = make_offsets(scratch_long_half, dx, dy);
    copy_offsets(along, taps.along, 25);
    taps.along_count = static_cast<std::int32_t>(along.size());
    if (multi_scale) {
        const auto curve = make_offsets(scratch_curve_half, dx, dy);
        copy_offsets(curve, taps.curve, 13);
        taps.curve_count = static_cast<std::int32_t>(curve.size());
    } else {
        taps.curve_count = 0;
    }
}

void make_scratch_angle_maps(
    const DetectionImage& image,
    const double angle_degrees,
    const std::vector<std::uint8_t>& valid,
    const float balance_limit,
    const bool multi_scale,
    ScratchAngleMaps& result) {
    const std::size_t count = checked_pixel_count(image.width, image.height);
    if (result.ridge.size() != count) {
        result.ridge.resize(count);
    }
    if (result.integrated.size() != count) {
        result.integrated.resize(count);
    }
    std::fill(result.ridge.begin(), result.ridge.end(), 0.0F);
    std::fill(result.integrated.begin(), result.integrated.end(), 0.0F);

    negaflow::imaging::ScratchAngleTaps taps{};
    fill_scratch_angle_taps(angle_degrees, multi_scale, taps);
    if (const KernelAccelerator* const table = kernel_accelerator();
        table != nullptr && table->scratch_angle_maps != nullptr) {
        if (table->scratch_angle_maps(
                image.brightest_channel.data(),
                valid.data(),
                result.ridge.data(),
                result.integrated.data(),
                image.width,
                image.height,
                &taps,
                balance_limit)) {
            return;
        }
    }

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
    if (multi_scale) {
        // macOS `computeMaps(multiScale: true)` — 급곡 결함의 짧은 적분을 픽셀별 max 로 합친다.
        integrate_ridge(
            result.ridge,
            valid,
            image.width,
            image.height,
            dx,
            dy,
            scratch_curve_half,
            result.integrated);
    }
}

}  // namespace negaflow::imaging::grain_mend_detail
