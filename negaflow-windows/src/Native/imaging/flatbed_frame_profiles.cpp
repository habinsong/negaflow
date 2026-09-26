#include "flatbed_frame_profiles.h"

#include "flatbed_frame_signal.h"

#include <algorithm>
#include <cmath>
#include <cstddef>

namespace negaflow::imaging {

// 규격 치수표는 여기 하나입니다. 격자 검출과 가장자리 검출이 같은 표를 읽어야 두 검출이 다른
// 크기를 쓰지 않습니다. 값은 macOS `FilmFrameFormat` 의 stripWidthMM · stripHeightMM · is35mm
// 그대로이고, 35mm 여부는 enum 차례가 아니라 여기서 명시합니다 — 끝에 붙인 파노라마 두
// 규격이 enum 차례로는 120 뒤에 옵니다.
std::optional<FlatbedFrameDimensions> flatbed_frame_dimensions(
    const FlatbedFrameFormat format) noexcept {
    switch (format) {
        case FlatbedFrameFormat::full_frame_35mm: return FlatbedFrameDimensions{36.0, 24.0, true};
        case FlatbedFrameFormat::square_35mm: return FlatbedFrameDimensions{24.0, 24.0, true};
        case FlatbedFrameFormat::half_frame_35mm: return FlatbedFrameDimensions{18.0, 24.0, true};
        case FlatbedFrameFormat::panorama_35mm_56x24: return FlatbedFrameDimensions{56.0, 24.0, true};
        case FlatbedFrameFormat::panorama_35mm_65x24: return FlatbedFrameDimensions{65.0, 24.0, true};
        case FlatbedFrameFormat::medium_645: return FlatbedFrameDimensions{41.5, 56.0, false};
        case FlatbedFrameFormat::medium_66: return FlatbedFrameDimensions{56.0, 56.0, false};
        case FlatbedFrameFormat::medium_67: return FlatbedFrameDimensions{69.0, 55.0, false};
        case FlatbedFrameFormat::medium_68: return FlatbedFrameDimensions{76.0, 56.0, false};
        case FlatbedFrameFormat::medium_69: return FlatbedFrameDimensions{84.0, 56.0, false};
        case FlatbedFrameFormat::medium_612: return FlatbedFrameDimensions{112.0, 56.0, false};
        case FlatbedFrameFormat::medium_617: return FlatbedFrameDimensions{168.0, 56.0, false};
    }
    return std::nullopt;
}

}  // namespace negaflow::imaging

namespace negaflow::imaging::flatbed_detail {

bool valid_dimensions(const FlatbedFrameDimensions& dimensions) noexcept {
    return std::isfinite(dimensions.along_mm) && std::isfinite(dimensions.across_mm) &&
        dimensions.along_mm > 0.0 && dimensions.across_mm > 0.0;
}

[[nodiscard]] std::optional<Geometry> make_geometry(
    const FlatbedFramePreview& preview,
    const FlatbedFrameDimensions& dimensions) noexcept {
    if (!valid_dimensions(dimensions)) return std::nullopt;
    Geometry geometry{};
    geometry.along_mm = dimensions.along_mm;
    geometry.across_mm = dimensions.across_mm;
    // macOS `gapRangeMM(for:)` — 35mm 는 퍼포레이션 이송이 정하므로 사실상 고정이고, 120 은
    // 카메라 이송 기구에 달려 있어 넓게 잡습니다.
    geometry.rigid_pitch = dimensions.is_35mm;
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
