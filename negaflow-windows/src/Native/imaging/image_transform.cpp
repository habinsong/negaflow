#include "negaflow/imaging/image_transform.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <limits>
#include <new>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

[[nodiscard]] bool valid_image(const WorkingImage& image) noexcept {
    return image.width != 0U && image.height != 0U &&
           image.stride_pixels >= image.width &&
           image.pixels.size() >=
               static_cast<std::size_t>(image.stride_pixels) * image.height;
}

[[nodiscard]] std::size_t checked_count(
    const std::uint32_t width,
    const std::uint32_t height) {
    if (width == 0U || height == 0U ||
        static_cast<std::size_t>(width) >
            std::numeric_limits<std::size_t>::max() /
                static_cast<std::size_t>(height)) {
        throw std::bad_alloc{};
    }
    return static_cast<std::size_t>(width) * height;
}

[[nodiscard]] WorkingImage packed_image(
    const std::uint32_t width,
    const std::uint32_t height) {
    WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(checked_count(width, height));
    return image;
}

[[nodiscard]] negaflow::core::Rgba32F sample_bilinear_clamped(
    const WorkingImage& image,
    const double x,
    const double y) noexcept {
    const double cx = std::clamp(x, 0.0, static_cast<double>(image.width - 1U));
    const double cy = std::clamp(y, 0.0, static_cast<double>(image.height - 1U));
    const std::uint32_t x0 = static_cast<std::uint32_t>(std::floor(cx));
    const std::uint32_t y0 = static_cast<std::uint32_t>(std::floor(cy));
    const std::uint32_t x1 = std::min(x0 + 1U, image.width - 1U);
    const std::uint32_t y1 = std::min(y0 + 1U, image.height - 1U);
    const float tx = static_cast<float>(cx - x0);
    const float ty = static_cast<float>(cy - y0);
    const auto at = [&](const std::uint32_t sx, const std::uint32_t sy) {
        return image.pixels[
            static_cast<std::size_t>(sy) * image.stride_pixels + sx];
    };
    const auto p00 = at(x0, y0);
    const auto p10 = at(x1, y0);
    const auto p01 = at(x0, y1);
    const auto p11 = at(x1, y1);
    const auto interpolate = [&](const float a, const float b,
                                 const float c, const float d) {
        const float top = a + (b - a) * tx;
        const float bottom = c + (d - c) * tx;
        return top + (bottom - top) * ty;
    };
    return {
        interpolate(p00.red, p10.red, p01.red, p11.red),
        interpolate(p00.green, p10.green, p01.green, p11.green),
        interpolate(p00.blue, p10.blue, p01.blue, p11.blue),
        interpolate(p00.alpha, p10.alpha, p01.alpha, p11.alpha),
    };
}

[[nodiscard]] WorkingImage orient(
    const WorkingImage& source,
    const ImageTransformParameters& parameters) {
    const bool swap_dimensions =
        parameters.rotation == ImageRotation::degrees_90 ||
        parameters.rotation == ImageRotation::degrees_270;
    WorkingImage output = packed_image(
        swap_dimensions ? source.height : source.width,
        swap_dimensions ? source.width : source.height);
    for (std::uint32_t y = 0U; y < output.height; ++y) {
        for (std::uint32_t x = 0U; x < output.width; ++x) {
            std::uint32_t ox = x;
            std::uint32_t oy = y;
            switch (parameters.rotation) {
                case ImageRotation::degrees_0:
                    break;
                case ImageRotation::degrees_90:
                    ox = y;
                    oy = source.height - 1U - x;
                    break;
                case ImageRotation::degrees_180:
                    ox = source.width - 1U - x;
                    oy = source.height - 1U - y;
                    break;
                case ImageRotation::degrees_270:
                    ox = source.width - 1U - y;
                    oy = x;
                    break;
            }
            if (parameters.flip_horizontal) {
                ox = source.width - 1U - ox;
            }
            if (parameters.flip_vertical) {
                oy = source.height - 1U - oy;
            }
            output.pixels[static_cast<std::size_t>(y) * output.width + x] =
                source.pixels[
                    static_cast<std::size_t>(oy) * source.stride_pixels + ox];
        }
    }
    return output;
}

[[nodiscard]] WorkingImage straighten(
    const WorkingImage& source,
    const double degrees) {
    const double width = source.width;
    const double height = source.height;
    const double theta = degrees * 3.14159265358979323846 / 180.0;
    const double cosine = std::abs(std::cos(theta));
    const double sine = std::abs(std::sin(theta));
    const double output_height = std::min(
        width * height / (width * cosine + height * sine),
        height * height / (width * sine + height * cosine));
    const double output_width = width / height * output_height;
    const auto out_width = std::max(1U, static_cast<std::uint32_t>(std::floor(output_width)));
    const auto out_height = std::max(1U, static_cast<std::uint32_t>(std::floor(output_height)));
    WorkingImage output = packed_image(out_width, out_height);
    const double source_cx = (width - 1.0) * 0.5;
    const double source_cy = (height - 1.0) * 0.5;
    const double output_cx = (out_width - 1.0) * 0.5;
    const double output_cy = (out_height - 1.0) * 0.5;
    const double cos_theta = std::cos(theta);
    const double sin_theta = std::sin(theta);
    for (std::uint32_t y = 0U; y < out_height; ++y) {
        for (std::uint32_t x = 0U; x < out_width; ++x) {
            const double dx = static_cast<double>(x) - output_cx;
            const double dy = static_cast<double>(y) - output_cy;
            // macOS forward transform is clockwise for positive degrees. Map the
            // destination back through the inverse counter-clockwise rotation.
            const double source_x = source_cx + dx * cos_theta + dy * sin_theta;
            const double source_y = source_cy - dx * sin_theta + dy * cos_theta;
            output.pixels[static_cast<std::size_t>(y) * out_width + x] =
                sample_bilinear_clamped(source, source_x, source_y);
        }
    }
    return output;
}

[[nodiscard]] WorkingImage crop_image(
    const WorkingImage& source,
    const NormalizedCropRect& crop) {
    const double width = source.width;
    const double height = source.height;
    const auto left = static_cast<std::uint32_t>(std::floor(crop.x * width));
    const auto right = static_cast<std::uint32_t>(std::ceil(
        (crop.x + crop.width) * width));
    // Persisted crop uses Core Image y-up coordinates; WorkingImage rows are y-down.
    const auto top = static_cast<std::uint32_t>(std::floor(
        (1.0 - crop.y - crop.height) * height));
    const auto bottom = static_cast<std::uint32_t>(std::ceil(
        (1.0 - crop.y) * height));
    const std::uint32_t clamped_left = std::min(left, source.width - 1U);
    const std::uint32_t clamped_top = std::min(top, source.height - 1U);
    const std::uint32_t clamped_right = std::clamp(right, clamped_left + 1U, source.width);
    const std::uint32_t clamped_bottom = std::clamp(bottom, clamped_top + 1U, source.height);
    WorkingImage output = packed_image(
        clamped_right - clamped_left,
        clamped_bottom - clamped_top);
    for (std::uint32_t y = 0U; y < output.height; ++y) {
        for (std::uint32_t x = 0U; x < output.width; ++x) {
            output.pixels[static_cast<std::size_t>(y) * output.width + x] =
                source.pixels[
                    static_cast<std::size_t>(y + clamped_top) *
                        source.stride_pixels +
                    x + clamped_left];
        }
    }
    return output;
}

}  // namespace

bool valid_image_transform_parameters(
    const ImageTransformParameters& parameters) noexcept {
    const bool valid_rotation =
        parameters.rotation == ImageRotation::degrees_0 ||
        parameters.rotation == ImageRotation::degrees_90 ||
        parameters.rotation == ImageRotation::degrees_180 ||
        parameters.rotation == ImageRotation::degrees_270;
    if (!valid_rotation || !std::isfinite(parameters.straighten_angle) ||
        parameters.straighten_angle < -45.0 ||
        parameters.straighten_angle > 45.0) {
        return false;
    }
    if (!parameters.has_crop) {
        return true;
    }
    return std::isfinite(parameters.crop.x) &&
           std::isfinite(parameters.crop.y) &&
           std::isfinite(parameters.crop.width) &&
           std::isfinite(parameters.crop.height) &&
           parameters.crop.x >= 0.0 && parameters.crop.y >= 0.0 &&
           parameters.crop.width > 0.0 && parameters.crop.height > 0.0 &&
           parameters.crop.x + parameters.crop.width <= 1.0 &&
           parameters.crop.y + parameters.crop.height <= 1.0;
}

ImageTransformResult apply_image_transform(
    WorkingImage image,
    const ImageTransformParameters& parameters) noexcept {
    ImageTransformResult result{};
    if (!valid_image_transform_parameters(parameters)) {
        std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
        result.status = ImageTransformStatus::invalid_parameter;
        return result;
    }
    if (!valid_image(image)) {
        std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
        result.status = ImageTransformStatus::invalid_image;
        return result;
    }
    const bool oriented = parameters.rotation != ImageRotation::degrees_0 ||
                          parameters.flip_horizontal || parameters.flip_vertical;
    const bool straightened = std::abs(parameters.straighten_angle) > 1.0e-4;
    if (!oriented && !straightened && !parameters.has_crop) {
        result.status = ImageTransformStatus::ok;
        result.image = std::move(image);
        return result;
    }
    try {
        if (oriented) {
            image = orient(image, parameters);
        }
        if (straightened && image.width > 1U && image.height > 1U) {
            image = straighten(image, parameters.straighten_angle);
        }
        if (parameters.has_crop) {
            image = crop_image(image, parameters.crop);
        }
    } catch (const std::bad_alloc&) {
        std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
        result.status = ImageTransformStatus::allocation_failed;
        return result;
    }
    result.status = ImageTransformStatus::ok;
    result.info.applied = true;
    result.info.resampled = straightened;
    result.image = std::move(image);
    return result;
}

const char* image_transform_status_name(
    const ImageTransformStatus status) noexcept {
    switch (status) {
        case ImageTransformStatus::ok: return "ok";
        case ImageTransformStatus::invalid_parameter: return "invalid_parameter";
        case ImageTransformStatus::invalid_image: return "invalid_image";
        case ImageTransformStatus::allocation_failed: return "allocation_failed";
    }
    return "unknown_status";
}

}  // namespace negaflow::imaging
