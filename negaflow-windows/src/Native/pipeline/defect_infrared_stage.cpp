#include "negaflow/pipeline/defect_infrared_stage.h"

#include "defect_patch_quantization.h"
#include "negaflow/core/pixel.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <utility>
#include <vector>

namespace negaflow::pipeline {
namespace {

using negaflow::core::Rgba32F;
using negaflow::imaging::WorkingImage;

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<Rgba32F>{}.swap(image.pixels);
}

[[nodiscard]] bool valid_image_layout(const WorkingImage& image) noexcept {
    if (image.width == 0U || image.height == 0U ||
        image.stride_pixels < image.width) {
        return false;
    }
    const std::size_t height_minus_one = image.height - 1U;
    return height_minus_one == 0U ||
           image.stride_pixels <=
               (std::numeric_limits<std::size_t>::max() - image.width) /
                   height_minus_one
        ? image.pixels.size() >=
              height_minus_one * image.stride_pixels + image.width
        : false;
}

[[nodiscard]] bool valid_byte_layout(
    const std::span<const std::uint8_t> bytes,
    const std::size_t stride,
    const std::size_t row_bytes,
    const std::uint32_t height) noexcept {
    if (height == 0U || stride < row_bytes) {
        return false;
    }
    const std::size_t height_minus_one = height - 1U;
    if (height_minus_one != 0U &&
        stride > (std::numeric_limits<std::size_t>::max() - row_bytes) /
                     height_minus_one) {
        return false;
    }
    return bytes.size() == height_minus_one * stride + row_bytes;
}

[[nodiscard]] bool valid_edit(
    const DefectInfraredEdit& edit,
    const WorkingImage& image) noexcept {
    if (edit.width == 0U || edit.height == 0U ||
        edit.roi_x > image.width || edit.width > image.width - edit.roi_x ||
        edit.roi_y > image.height || edit.height > image.height - edit.roi_y ||
        !valid_byte_layout(
            edit.core_mask,
            edit.core_mask_stride_bytes,
            edit.width,
            edit.height)) {
        return false;
    }
    if (edit.attenuation_r16.empty()) {
        return edit.attenuation_stride_bytes == 0U;
    }
    if (edit.width > std::numeric_limits<std::size_t>::max() / 2U) {
        return false;
    }
    return valid_byte_layout(
        edit.attenuation_r16,
        edit.attenuation_stride_bytes,
        static_cast<std::size_t>(edit.width) * 2U,
        edit.height);
}

struct CorrectionBounds final {
    bool has_pixels{false};
    std::uint32_t left{0U};
    std::uint32_t top{0U};
    std::uint32_t right{0U};
    std::uint32_t bottom{0U};

    void include(const std::uint32_t x, const std::uint32_t y) noexcept {
        if (!has_pixels) {
            has_pixels = true;
            left = x;
            top = y;
            right = x + 1U;
            bottom = y + 1U;
            return;
        }
        left = std::min(left, x);
        top = std::min(top, y);
        right = std::max(right, x + 1U);
        bottom = std::max(bottom, y + 1U);
    }
};

struct InfraredPatch final {
    std::vector<std::uint16_t> rgb16{};
    std::uint32_t image_left{0U};
    std::uint32_t image_top{0U};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
};

[[nodiscard]] float safe_restore(
    const float source,
    const double divisor) noexcept {
    const double restored = static_cast<double>(source) / divisor;
    if (!std::isfinite(restored)) {
        return source > 0.0F ? 1.0F : 0.0F;
    }
    return static_cast<float>(std::clamp(restored, 0.0, 1.0));
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

}  // namespace

DefectInfraredStageResult apply_defect_infrared_edit(
    WorkingImage image,
    const DefectInfraredEdit& edit) noexcept {
    DefectInfraredItem item{};
    item.enabled = edit.enabled;
    item.strength = edit.strength;
    try {
        item.clusters.push_back(edit);
    } catch (...) {
        DefectInfraredStageResult result{};
        result.status = DefectInfraredStageStatus::allocation_failed;
        return result;
    }
    return apply_defect_infrared_item(std::move(image), item);
}

DefectInfraredStageResult apply_defect_infrared_item(
    WorkingImage image,
    const DefectInfraredItem& item) noexcept {
    DefectInfraredStageResult result{};
    result.image = std::move(image);
    if (!valid_image_layout(result.image) || item.clusters.empty() ||
        !std::isfinite(item.strength) || item.strength < 0.0 ||
        item.strength > 1.0 ||
        !std::all_of(
            item.clusters.begin(),
            item.clusters.end(),
            [&result](const DefectInfraredEdit& edit) {
                return valid_edit(edit, result.image);
            })) {
        discard_pixels(result.image);
        return result;
    }
    if (!item.enabled || item.strength <= 1.0e-3) {
        result.status = DefectInfraredStageStatus::ok;
        return result;
    }

    try {
        std::vector<InfraredPatch> patches{};
        patches.reserve(item.clusters.size());
        for (const DefectInfraredEdit& edit : item.clusters) {
            const std::uint32_t image_top =
                result.image.height - edit.roi_y - edit.height;
            WorkingImage roi{};
            roi.width = edit.width;
            roi.height = edit.height;
            roi.stride_pixels = edit.width;
            roi.pixels.resize(
                static_cast<std::size_t>(edit.width) * edit.height);
            for (std::uint32_t y = 0U; y < edit.height; ++y) {
                const auto source = result.image.pixels.begin() +
                    static_cast<std::ptrdiff_t>(
                        static_cast<std::size_t>(image_top + y) *
                            result.image.stride_pixels +
                        edit.roi_x);
                std::copy_n(
                    source,
                    edit.width,
                    roi.pixels.begin() +
                        static_cast<std::ptrdiff_t>(
                            static_cast<std::size_t>(y) * edit.width));
            }
            if (negaflow::core::validate_finite_pixels(
                    const_view(roi)) !=
                negaflow::core::KernelStatus::ok) {
                result.status = DefectInfraredStageStatus::kernel_failed;
                discard_pixels(result.image);
                return result;
            }
            CorrectionBounds bounds{};
            bool has_core = false;

            if (!edit.attenuation_r16.empty()) {
                for (std::uint32_t y = 0U; y < edit.height; ++y) {
                    const std::size_t attenuation_row =
                        static_cast<std::size_t>(y) *
                        edit.attenuation_stride_bytes;
                    const std::size_t pixel_row =
                        static_cast<std::size_t>(y) * roi.stride_pixels;
                    for (std::uint32_t x = 0U; x < edit.width; ++x) {
                        const std::size_t offset = attenuation_row +
                            static_cast<std::size_t>(x) * 2U;
                        const std::uint16_t attenuation =
                            static_cast<std::uint16_t>(
                                edit.attenuation_r16[offset]) |
                            static_cast<std::uint16_t>(
                                static_cast<std::uint16_t>(
                                    edit.attenuation_r16[offset + 1U])
                                << 8U);
                        if (attenuation == 0U) {
                            continue;
                        }
                        bounds.include(x, y);
                        const double transmittance = std::max(
                            1.0 - static_cast<double>(attenuation) / 65535.0,
                            0.5);
                        Rgba32F& pixel = roi.pixels[pixel_row + x];
                        pixel.red = safe_restore(pixel.red, transmittance);
                        pixel.green = safe_restore(pixel.green, transmittance);
                        pixel.blue = safe_restore(pixel.blue, transmittance);
                        ++result.info.attenuated_pixels;
                    }
                }
            }

            for (std::uint32_t y = 0U; y < edit.height; ++y) {
                const std::size_t row =
                    static_cast<std::size_t>(y) * edit.core_mask_stride_bytes;
                for (std::uint32_t x = 0U; x < edit.width; ++x) {
                    if (edit.core_mask[row + x] > 8U) {
                        has_core = true;
                        bounds.include(x, y);
                    }
                }
            }
            if (has_core) {
                auto repaired = negaflow::imaging::repair_defect_components(
                    std::move(roi),
                    edit.core_mask,
                    edit.core_mask_stride_bytes,
                    {});
                result.info.repair_status = repaired.status;
                if (repaired.status !=
                    negaflow::imaging::DefectComponentRepairStatus::ok) {
                    result.status = DefectInfraredStageStatus::repair_failed;
                    discard_pixels(result.image);
                    return result;
                }
                result.info.repaired_pixels += repaired.info.repaired_pixels;
                roi = std::move(repaired.image);
            }

            if (!bounds.has_pixels) {
                continue;
            }
            InfraredPatch patch{};
            patch.image_left = edit.roi_x + bounds.left;
            patch.image_top = image_top + bounds.top;
            patch.width = bounds.right - bounds.left;
            patch.height = bounds.bottom - bounds.top;
            if (patch.width > std::numeric_limits<std::size_t>::max() /
                                  patch.height) {
                result.status = DefectInfraredStageStatus::allocation_failed;
                discard_pixels(result.image);
                return result;
            }
            const std::size_t patch_pixels =
                static_cast<std::size_t>(patch.width) * patch.height;
            if (patch_pixels > std::numeric_limits<std::size_t>::max() /
                                   (3U * sizeof(std::uint16_t))) {
                result.status = DefectInfraredStageStatus::allocation_failed;
                discard_pixels(result.image);
                return result;
            }
            patch.rgb16.resize(patch_pixels * 3U);
            for (std::uint32_t y = 0U; y < patch.height; ++y) {
                const auto source = roi.pixels.begin() +
                    static_cast<std::ptrdiff_t>(
                        static_cast<std::size_t>(bounds.top + y) *
                            roi.stride_pixels +
                        bounds.left);
                auto destination = patch.rgb16.begin() +
                    static_cast<std::ptrdiff_t>(
                        static_cast<std::size_t>(y) * patch.width * 3U);
                for (std::uint32_t x = 0U; x < patch.width; ++x) {
                    destination[static_cast<std::size_t>(x) * 3U] =
                        defect_patch_detail::encode_linear16(source[x].red);
                    destination[static_cast<std::size_t>(x) * 3U + 1U] =
                        defect_patch_detail::encode_linear16(source[x].green);
                    destination[static_cast<std::size_t>(x) * 3U + 2U] =
                        defect_patch_detail::encode_linear16(source[x].blue);
                }
            }
            patches.push_back(std::move(patch));
        }

        const float strength =
            defect_patch_detail::composited_patch_strength(item.strength);
        for (const InfraredPatch& patch : patches) {
            for (std::uint32_t y = 0U; y < patch.height; ++y) {
                const std::size_t patch_row =
                    static_cast<std::size_t>(y) * patch.width * 3U;
                const std::size_t image_row =
                    static_cast<std::size_t>(patch.image_top + y) *
                        result.image.stride_pixels +
                    patch.image_left;
                for (std::uint32_t x = 0U; x < patch.width; ++x) {
                    const std::size_t source = patch_row +
                        static_cast<std::size_t>(x) * 3U;
                    Rgba32F& destination = result.image.pixels[image_row + x];
                    destination.red = safe_restore(
                        destination.red + static_cast<float>(
                            (defect_patch_detail::decode_linear16(
                                 patch.rgb16[source]) -
                             destination.red) * strength),
                        1.0);
                    destination.green = safe_restore(
                        destination.green + static_cast<float>(
                            (defect_patch_detail::decode_linear16(
                                 patch.rgb16[source + 1U]) -
                             destination.green) * strength),
                        1.0);
                    destination.blue = safe_restore(
                        destination.blue + static_cast<float>(
                            (defect_patch_detail::decode_linear16(
                                 patch.rgb16[source + 2U]) -
                             destination.blue) * strength),
                        1.0);
                }
            }
        }
        result.info.applied = result.info.attenuated_pixels != 0U ||
                              result.info.repaired_pixels != 0U;
        result.status = DefectInfraredStageStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = DefectInfraredStageStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    } catch (...) {
        result.status = DefectInfraredStageStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }
}

const char* defect_infrared_stage_status_name(
    const DefectInfraredStageResult& result) noexcept {
    switch (result.status) {
        case DefectInfraredStageStatus::ok:
            return "ok";
        case DefectInfraredStageStatus::invalid_argument:
            return "invalid_argument";
        case DefectInfraredStageStatus::kernel_failed:
            return "kernel_failed";
        case DefectInfraredStageStatus::repair_failed:
            return negaflow::imaging::defect_component_repair_status_name(
                result.info.repair_status);
        case DefectInfraredStageStatus::allocation_failed:
            return "allocation_failed";
    }
    return "unknown";
}

}  // namespace negaflow::pipeline
