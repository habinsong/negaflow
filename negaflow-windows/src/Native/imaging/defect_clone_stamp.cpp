#include "negaflow/imaging/defect_clone_stamp.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

constexpr double stamp_spacing_fraction = 0.25;
constexpr double antialias_pixels = 1.0;
constexpr double minimum_segment_length = 1.0e-6;

struct PixelPoint final {
    double x{0.0};
    double y{0.0};
};

struct StoredPatch final {
    std::uint32_t x{0U};
    std::uint32_t y{0U};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::vector<std::uint16_t> rgba16{};
};

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
}

[[nodiscard]] negaflow::core::ConstImageView const_view(
    const WorkingImage& image) noexcept {
    return {
        image.pixels.data(),
        image.pixels.size(),
        image.width,
        image.height,
        image.stride_pixels,
    };
}

[[nodiscard]] bool valid_layout(const WorkingImage& image) noexcept {
    if (image.width == 0U || image.height == 0U ||
        image.stride_pixels < image.width) {
        return false;
    }
    const std::size_t rows = image.height - 1U;
    return rows == 0U ||
        image.stride_pixels <=
            (std::numeric_limits<std::size_t>::max() - image.width) / rows;
}

[[nodiscard]] bool finite_point(const DefectClonePoint point) noexcept {
    return std::isfinite(point.x) && std::isfinite(point.y);
}

[[nodiscard]] bool valid_parameters(
    const DefectCloneParameters& parameters) noexcept {
    if (!std::isfinite(parameters.strength) || parameters.strength < 0.0 ||
        parameters.strength > 1.0 ||
        parameters.strokes.size() > defect_clone_maximum_strokes) {
        return false;
    }
    std::size_t point_count = 0U;
    for (const DefectCloneStroke& stroke : parameters.strokes) {
        if (!std::isfinite(stroke.offset_x) ||
            !std::isfinite(stroke.offset_y) ||
            !std::isfinite(stroke.diameter_pixels) ||
            stroke.diameter_pixels <= 0.0 ||
            !std::isfinite(stroke.hardness) || stroke.hardness < 0.0 ||
            stroke.hardness > 1.0 ||
            stroke.points.size() > defect_clone_maximum_points - point_count) {
            return false;
        }
        point_count += stroke.points.size();
        if (!std::all_of(
                stroke.points.begin(), stroke.points.end(), finite_point)) {
            return false;
        }
    }
    return true;
}

[[nodiscard]] bool valid_scaled_geometry(
    const WorkingImage& image,
    const DefectCloneParameters& parameters) noexcept {
    constexpr double safe_integer =
        static_cast<double>(std::numeric_limits<long long>::max()) / 8.0;
    for (const DefectCloneStroke& stroke : parameters.strokes) {
        const double offset_x =
            stroke.offset_x * static_cast<double>(image.width);
        const double offset_y =
            stroke.offset_y * static_cast<double>(image.height);
        if (!std::isfinite(offset_x) || !std::isfinite(offset_y) ||
            std::abs(offset_x) > safe_integer ||
            std::abs(offset_y) > safe_integer ||
            stroke.diameter_pixels > safe_integer) {
            return false;
        }
        for (const DefectClonePoint point : stroke.points) {
            const double x = point.x * static_cast<double>(image.width);
            const double y = point.y * static_cast<double>(image.height);
            if (!std::isfinite(x) || !std::isfinite(y) ||
                std::abs(x) > safe_integer || std::abs(y) > safe_integer) {
                return false;
            }
        }
    }
    return true;
}

[[nodiscard]] std::uint16_t encode_linear16(const float value) noexcept {
    const double scaled = static_cast<double>(std::clamp(value, 0.0F, 1.0F)) *
        65'535.0;
    return static_cast<std::uint16_t>(std::floor(scaled + 0.5));
}

[[nodiscard]] float decode_linear16(const std::uint16_t value) noexcept {
    return static_cast<float>(value) / 65'535.0F;
}

[[nodiscard]] bool contains(
    const StoredPatch& patch,
    const std::uint32_t x,
    const std::uint32_t y) noexcept {
    return x >= patch.x && y >= patch.y &&
        x - patch.x < patch.width && y - patch.y < patch.height;
}

[[nodiscard]] negaflow::core::Rgba32F patch_pixel(
    const StoredPatch& patch,
    const std::uint32_t x,
    const std::uint32_t y) noexcept {
    const std::size_t index =
        (static_cast<std::size_t>(y - patch.y) * patch.width + (x - patch.x)) *
        4U;
    return {
        decode_linear16(patch.rgba16[index]),
        decode_linear16(patch.rgba16[index + 1U]),
        decode_linear16(patch.rgba16[index + 2U]),
        1.0F,
    };
}

[[nodiscard]] negaflow::core::Rgba32F full_strength_pixel(
    const WorkingImage& base,
    const std::vector<StoredPatch>& patches,
    const std::uint32_t x,
    const std::uint32_t y) noexcept {
    for (auto patch = patches.rbegin(); patch != patches.rend(); ++patch) {
        if (contains(*patch, x, y)) {
            return patch_pixel(*patch, x, y);
        }
    }
    return base.pixels[static_cast<std::size_t>(y) * base.stride_pixels + x];
}

[[nodiscard]] float stamp_alpha(
    const double normalized_distance,
    const double hardness,
    const double radius) noexcept {
    if (!(normalized_distance < 1.0)) {
        return 0.0F;
    }
    const double effective_hardness = std::clamp(
        hardness,
        0.0,
        std::max(0.0, 1.0 - antialias_pixels / std::max(radius, 1.0)));
    if (normalized_distance <= effective_hardness) {
        return 1.0F;
    }
    const double value = (normalized_distance - effective_hardness) /
        std::max(1.0 - effective_hardness, 1.0e-6);
    return static_cast<float>((1.0 - value) * (1.0 - value) *
                              (1.0 + 2.0 * value));
}

void paint_stamp(
    std::vector<float>& mask,
    const std::uint32_t mask_width,
    const std::uint32_t mask_height,
    const std::uint32_t origin_x,
    const std::uint32_t origin_y,
    const PixelPoint center,
    const double radius,
    const double hardness) noexcept {
    const int left = std::max(
        static_cast<int>(origin_x),
        static_cast<int>(std::floor(center.x - radius - 1.0)));
    const int top = std::max(
        static_cast<int>(origin_y),
        static_cast<int>(std::floor(center.y - radius - 1.0)));
    const int right = std::min(
        static_cast<int>(origin_x + mask_width),
        static_cast<int>(std::ceil(center.x + radius + 1.0)));
    const int bottom = std::min(
        static_cast<int>(origin_y + mask_height),
        static_cast<int>(std::ceil(center.y + radius + 1.0)));
    for (int y = top; y < bottom; ++y) {
        const double dy = static_cast<double>(y) + 0.5 - center.y;
        const std::size_t row =
            static_cast<std::size_t>(y - static_cast<int>(origin_y)) *
            mask_width;
        for (int x = left; x < right; ++x) {
            const double dx = static_cast<double>(x) + 0.5 - center.x;
            const float alpha = stamp_alpha(
                std::sqrt(dx * dx + dy * dy) / radius,
                hardness,
                radius);
            if (alpha <= 0.0F) {
                continue;
            }
            float& destination =
                mask[row + static_cast<std::size_t>(
                    x - static_cast<int>(origin_x))];
            destination += alpha * (1.0F - destination);
        }
    }
}

void rasterize_stroke(
    const std::vector<PixelPoint>& points,
    const double spacing,
    const double radius,
    const double hardness,
    const std::uint32_t origin_x,
    const std::uint32_t origin_y,
    const std::uint32_t width,
    const std::uint32_t height,
    std::vector<float>& mask) noexcept {
    if (points.empty()) {
        return;
    }
    paint_stamp(
        mask, width, height, origin_x, origin_y, points.front(), radius, hardness);
    if (points.size() == 1U) {
        return;
    }
    double distance_since_stamp = 0.0;
    PixelPoint previous = points.front();
    for (std::size_t index = 1U; index < points.size(); ++index) {
        const PixelPoint target = points[index];
        PixelPoint segment_start = previous;
        double remaining = std::hypot(
            target.x - segment_start.x,
            target.y - segment_start.y);
        while (distance_since_stamp + remaining >= spacing &&
               remaining > minimum_segment_length) {
            const double needed = spacing - distance_since_stamp;
            const double ratio = needed / remaining;
            const PixelPoint center{
                segment_start.x + (target.x - segment_start.x) * ratio,
                segment_start.y + (target.y - segment_start.y) * ratio,
            };
            paint_stamp(
                mask, width, height, origin_x, origin_y, center, radius, hardness);
            segment_start = center;
            remaining -= needed;
            distance_since_stamp = 0.0;
        }
        distance_since_stamp += remaining;
        previous = target;
    }
}

[[nodiscard]] bool make_patch(
    const WorkingImage& base,
    const std::vector<StoredPatch>& preceding,
    const DefectCloneStroke& stroke,
    StoredPatch& patch) {
    if (stroke.points.empty()) {
        return false;
    }
    const long long offset_x = std::llround(
        stroke.offset_x * static_cast<double>(base.width));
    const long long offset_y = std::llround(
        stroke.offset_y * static_cast<double>(base.height));
    if (offset_x == 0LL && offset_y == 0LL) {
        return false;
    }

    std::vector<PixelPoint> points{};
    points.reserve(stroke.points.size());
    double minimum_x = std::numeric_limits<double>::max();
    double minimum_y = std::numeric_limits<double>::max();
    double maximum_x = -std::numeric_limits<double>::max();
    double maximum_y = -std::numeric_limits<double>::max();
    for (const DefectClonePoint point : stroke.points) {
        const PixelPoint pixel{
            point.x * static_cast<double>(base.width),
            point.y * static_cast<double>(base.height),
        };
        points.push_back(pixel);
        minimum_x = std::min(minimum_x, pixel.x);
        minimum_y = std::min(minimum_y, pixel.y);
        maximum_x = std::max(maximum_x, pixel.x);
        maximum_y = std::max(maximum_y, pixel.y);
    }

    const double radius = std::max(0.5, stroke.diameter_pixels / 2.0);
    const double padding = radius + antialias_pixels + 1.0;
    const long long left = std::max(
        0LL, static_cast<long long>(std::floor(minimum_x - padding)));
    const long long top = std::max(
        0LL, static_cast<long long>(std::floor(minimum_y - padding)));
    const long long right = std::min(
        static_cast<long long>(base.width),
        static_cast<long long>(std::ceil(maximum_x + padding)));
    const long long bottom = std::min(
        static_cast<long long>(base.height),
        static_cast<long long>(std::ceil(maximum_y + padding)));
    if (left >= right || top >= bottom) {
        return false;
    }
    const auto width = static_cast<std::uint32_t>(right - left);
    const auto height = static_cast<std::uint32_t>(bottom - top);
    if (static_cast<std::size_t>(width) >
        std::numeric_limits<std::size_t>::max() / height) {
        throw std::bad_alloc{};
    }
    std::vector<float> mask(static_cast<std::size_t>(width) * height, 0.0F);
    rasterize_stroke(
        points,
        std::max(1.0, stroke.diameter_pixels * stamp_spacing_fraction),
        radius,
        stroke.hardness,
        static_cast<std::uint32_t>(left),
        static_cast<std::uint32_t>(top),
        width,
        height,
        mask);

    std::uint32_t local_left = width;
    std::uint32_t local_top = height;
    std::uint32_t local_right = 0U;
    std::uint32_t local_bottom = 0U;
    bool any = false;
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::size_t index = static_cast<std::size_t>(y) * width + x;
            if (mask[index] <= 0.0F) {
                continue;
            }
            const long long source_x = left + x + offset_x;
            const long long source_y = top + y + offset_y;
            if (source_x < 0LL || source_y < 0LL ||
                source_x >= static_cast<long long>(base.width) ||
                source_y >= static_cast<long long>(base.height)) {
                mask[index] = 0.0F;
                continue;
            }
            any = true;
            local_left = std::min(local_left, x);
            local_top = std::min(local_top, y);
            local_right = std::max(local_right, x);
            local_bottom = std::max(local_bottom, y);
        }
    }
    if (!any) {
        return false;
    }

    patch.x = static_cast<std::uint32_t>(left) + local_left;
    patch.y = static_cast<std::uint32_t>(top) + local_top;
    patch.width = local_right - local_left + 1U;
    patch.height = local_bottom - local_top + 1U;
    const std::size_t pixel_count =
        static_cast<std::size_t>(patch.width) * patch.height;
    if (pixel_count > defect_clone_maximum_patch_bytes /
                          (4U * sizeof(std::uint16_t))) {
        throw std::bad_alloc{};
    }
    patch.rgba16.resize(pixel_count * 4U);
    for (std::uint32_t y = 0U; y < patch.height; ++y) {
        for (std::uint32_t x = 0U; x < patch.width; ++x) {
            const std::uint32_t destination_x = patch.x + x;
            const std::uint32_t destination_y = patch.y + y;
            const std::size_t mask_index =
                static_cast<std::size_t>(local_top + y) * width +
                local_left + x;
            const float alpha = mask[mask_index];
            const auto destination = full_strength_pixel(
                base, preceding, destination_x, destination_y);
            const auto source = full_strength_pixel(
                base,
                preceding,
                static_cast<std::uint32_t>(
                    static_cast<long long>(destination_x) + offset_x),
                static_cast<std::uint32_t>(
                    static_cast<long long>(destination_y) + offset_y));
            const float inverse = 1.0F - alpha;
            const std::size_t output =
                (static_cast<std::size_t>(y) * patch.width + x) * 4U;
            patch.rgba16[output] = encode_linear16(
                alpha > 0.0F
                    ? source.red * alpha + destination.red * inverse
                    : destination.red);
            patch.rgba16[output + 1U] = encode_linear16(
                alpha > 0.0F
                    ? source.green * alpha + destination.green * inverse
                    : destination.green);
            patch.rgba16[output + 2U] = encode_linear16(
                alpha > 0.0F
                    ? source.blue * alpha + destination.blue * inverse
                    : destination.blue);
            patch.rgba16[output + 3U] = 65'535U;
        }
    }
    return true;
}

void composite_patch(
    WorkingImage& image,
    const StoredPatch& patch,
    const float strength) noexcept {
    const float inverse = 1.0F - strength;
    for (std::uint32_t y = 0U; y < patch.height; ++y) {
        for (std::uint32_t x = 0U; x < patch.width; ++x) {
            const std::size_t patch_index =
                (static_cast<std::size_t>(y) * patch.width + x) * 4U;
            auto& destination = image.pixels[
                static_cast<std::size_t>(patch.y + y) * image.stride_pixels +
                patch.x + x];
            destination.red =
                decode_linear16(patch.rgba16[patch_index]) * strength +
                destination.red * inverse;
            destination.green =
                decode_linear16(patch.rgba16[patch_index + 1U]) * strength +
                destination.green * inverse;
            destination.blue =
                decode_linear16(patch.rgba16[patch_index + 2U]) * strength +
                destination.blue * inverse;
            destination.alpha = strength + destination.alpha * inverse;
        }
    }
}

}  // namespace

DefectCloneResult apply_defect_clone_stamps(
    WorkingImage image,
    const DefectCloneParameters& parameters) noexcept {
    DefectCloneResult result{};
    result.image = std::move(image);
    if (!valid_layout(result.image) || !valid_parameters(parameters) ||
        !valid_scaled_geometry(result.image, parameters)) {
        discard_pixels(result.image);
        return result;
    }
    result.info.kernel_status =
        negaflow::core::validate_finite_pixels(const_view(result.image));
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = DefectCloneStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }
    if (parameters.strength <= 1.0e-3 || parameters.strokes.empty()) {
        result.status = DefectCloneStatus::ok;
        return result;
    }

    try {
        const WorkingImage& item_base = result.image;
        std::vector<StoredPatch> full_strength_patches{};
        full_strength_patches.reserve(parameters.strokes.size());
        std::size_t stored_patch_bytes = 0U;
        for (const DefectCloneStroke& stroke : parameters.strokes) {
            StoredPatch patch{};
            if (!make_patch(item_base, full_strength_patches, stroke, patch)) {
                continue;
            }
            const std::size_t patch_bytes =
                patch.rgba16.size() * sizeof(std::uint16_t);
            if (patch_bytes > defect_clone_maximum_patch_bytes -
                                  stored_patch_bytes) {
                throw std::bad_alloc{};
            }
            stored_patch_bytes += patch_bytes;
            composite_patch(
                result.image,
                patch,
                static_cast<float>(parameters.strength));
            result.info.applied = true;
            ++result.info.applied_strokes;
            result.info.patched_pixels +=
                static_cast<std::size_t>(patch.width) * patch.height;
            result.info.peak_patch_bytes = stored_patch_bytes;
            full_strength_patches.push_back(std::move(patch));
        }
        result.status = DefectCloneStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = DefectCloneStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    } catch (...) {
        result.status = DefectCloneStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }
}

const char* defect_clone_status_name(const DefectCloneStatus status) noexcept {
    switch (status) {
        case DefectCloneStatus::ok:
            return "ok";
        case DefectCloneStatus::invalid_argument:
            return "invalid_argument";
        case DefectCloneStatus::kernel_failed:
            return "kernel_failed";
        case DefectCloneStatus::allocation_failed:
            return "allocation_failed";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
