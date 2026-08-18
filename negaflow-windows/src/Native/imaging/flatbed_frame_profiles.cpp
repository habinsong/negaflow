#include "flatbed_frame_profiles.h"

#include "flatbed_frame_signal.h"

#include <algorithm>
#include <cmath>
#include <cstddef>

namespace negaflow::imaging::flatbed_detail {

[[nodiscard]] std::optional<Geometry> make_geometry(
    const FlatbedFramePreview& preview,
    const FlatbedFrameFormat format) noexcept {
    Geometry geometry{};
    switch (format) {
        case FlatbedFrameFormat::full_frame_35mm: geometry.along_mm = 36.0; geometry.across_mm = 24.0; break;
        case FlatbedFrameFormat::square_35mm: geometry.along_mm = 24.0; geometry.across_mm = 24.0; break;
        case FlatbedFrameFormat::half_frame_35mm: geometry.along_mm = 18.0; geometry.across_mm = 24.0; break;
        case FlatbedFrameFormat::medium_645: geometry.along_mm = 41.5; geometry.across_mm = 56.0; break;
        case FlatbedFrameFormat::medium_66: geometry.along_mm = 56.0; geometry.across_mm = 56.0; break;
        case FlatbedFrameFormat::medium_67: geometry.along_mm = 69.0; geometry.across_mm = 55.0; break;
        case FlatbedFrameFormat::medium_68: geometry.along_mm = 76.0; geometry.across_mm = 56.0; break;
        case FlatbedFrameFormat::medium_69: geometry.along_mm = 84.0; geometry.across_mm = 56.0; break;
        case FlatbedFrameFormat::medium_612: geometry.along_mm = 112.0; geometry.across_mm = 56.0; break;
        case FlatbedFrameFormat::medium_617: geometry.along_mm = 168.0; geometry.across_mm = 56.0; break;
        default: return std::nullopt;
    }
    geometry.rigid_pitch = format <= FlatbedFrameFormat::half_frame_35mm;
    geometry.gap_min_mm = geometry.rigid_pitch ? 1.0 : 2.0;
    geometry.gap_max_mm = geometry.rigid_pitch ? 3.5 : 9.0;
    geometry.pixels_per_mm_x = static_cast<double>(preview.width) / preview.physical_width_mm;
    geometry.pixels_per_mm_y = static_cast<double>(preview.height) / preview.physical_height_mm;
    return geometry;
}

[[nodiscard]] ColumnProfiles column_profiles(const FlatbedFramePreview& preview) {
    ColumnProfiles profiles{};
    profiles.detail.assign(preview.width, 0.0);
    profiles.mean.assign(preview.width, 0.0);
    for (int y = 0; y < static_cast<int>(preview.height); ++y) {
        for (int x = 0; x < static_cast<int>(preview.width); ++x) {
            const double value = pixel_at(preview, x, y);
            profiles.mean[static_cast<std::size_t>(x)] += value;
            if (y + 1 < static_cast<int>(preview.height)) {
                profiles.detail[static_cast<std::size_t>(x)] +=
                    std::abs(pixel_at(preview, x, y + 1) - value);
            }
        }
    }
    const double rows = static_cast<double>(preview.height);
    const double steps = static_cast<double>(std::max(1U, preview.height - 1U));
    for (std::size_t index = 0U; index < profiles.mean.size(); ++index) {
        profiles.mean[index] /= rows;
        profiles.detail[index] /= steps;
    }
    return profiles;
}

[[nodiscard]] std::vector<double> side_means(
    const FlatbedFramePreview& preview,
    const IntRange slot,
    const std::vector<double>& fallback) {
    const int guard_width = std::max(2, slot.count() / 6);
    const int sample = std::max(3, slot.count() / 2);
    const IntRange left{slot.first - guard_width - sample, slot.first - guard_width};
    const IntRange right{slot.last + guard_width, slot.last + guard_width + sample};
    std::vector<IntRange> sides{};
    if (left.first >= 0 && left.last <= static_cast<int>(preview.width)) sides.push_back(left);
    if (right.first >= 0 && right.last <= static_cast<int>(preview.width)) sides.push_back(right);
    if (sides.empty()) {
        return fallback;
    }
    double best_texture = std::numeric_limits<double>::infinity();
    std::vector<double> result = fallback;
    for (const IntRange side : sides) {
        std::vector<double> means(preview.height, 0.0);
        double texture = 0.0;
        for (int y = 0; y < static_cast<int>(preview.height); ++y) {
            double sum = 0.0;
            double previous = pixel_at(preview, side.first, y);
            for (int x = side.first; x < side.last; ++x) {
                const double value = pixel_at(preview, x, y);
                sum += value;
                texture += std::abs(value - previous);
                previous = value;
            }
            means[static_cast<std::size_t>(y)] = sum / static_cast<double>(side.count());
        }
        texture /= static_cast<double>(preview.height * static_cast<std::uint32_t>(side.count()));
        if (texture < best_texture) {
            best_texture = texture;
            result = std::move(means);
        }
    }
    return result;
}

[[nodiscard]] RowProfiles row_profiles(
    const FlatbedFramePreview& preview,
    const IntRange slot) {
    const int inset = std::max(1, slot.count() / 10);
    const int first = slot.first + inset;
    const int last = std::max(first + 1, slot.last - inset);
    RowProfiles profiles{};
    profiles.mean.assign(preview.height, 0.0);
    profiles.detail.assign(preview.height, 0.0);
    profiles.grain.assign(preview.height, 0.0);
    for (int y = 0; y < static_cast<int>(preview.height); ++y) {
        double sum = 0.0;
        double horizontal = 0.0;
        double vertical = 0.0;
        double previous = pixel_at(preview, first, y);
        for (int x = first; x < last; ++x) {
            const double value = pixel_at(preview, x, y);
            sum += value;
            horizontal += std::abs(value - previous);
            previous = value;
            if (y + 1 < static_cast<int>(preview.height)) {
                vertical += std::abs(pixel_at(preview, x, y + 1) - value);
            }
        }
        profiles.mean[static_cast<std::size_t>(y)] = sum / static_cast<double>(last - first);
        profiles.detail[static_cast<std::size_t>(y)] = horizontal /
            static_cast<double>(std::max(1, last - first - 1));
        profiles.grain[static_cast<std::size_t>(y)] = vertical /
            static_cast<double>(last - first);
    }
    profiles.surround = side_means(preview, slot, profiles.mean);
    return profiles;
}

}  // namespace negaflow::imaging::flatbed_detail
