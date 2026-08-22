#include "negaflow/imaging/defect_component_repair.h"

#include "defect_component_repair_detail.h"

#include "negaflow/color/srgb_transfer.h"
#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <optional>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

using defect_component_repair_detail::refine_broad_damage_mask;
using defect_component_repair_detail::repair_component_structures;
using negaflow::core::Rgba32F;

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<Rgba32F>{}.swap(image.pixels);
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

[[nodiscard]] bool valid_parameters(
    const DefectComponentRepairParameters& parameters) noexcept {
    return std::isfinite(parameters.strength) &&
           parameters.strength >= 0.0 && parameters.strength <= 1.0 &&
           (!parameters.has_preferred_angle ||
            (std::isfinite(parameters.preferred_angle_degrees) &&
             parameters.preferred_angle_degrees >= 0.0 &&
             parameters.preferred_angle_degrees <= 180.0));
}

[[nodiscard]] bool valid_mask_layout(
    const WorkingImage& image,
    const std::span<const std::uint8_t> mask,
    const std::size_t stride) noexcept {
    if (image.width == 0U || image.height == 0U ||
        stride < static_cast<std::size_t>(image.width)) {
        return false;
    }
    const std::size_t height_minus_one = image.height - 1U;
    if (height_minus_one != 0U &&
        stride > (std::numeric_limits<std::size_t>::max() - image.width) /
            height_minus_one) {
        return false;
    }
    const std::size_t required =
        height_minus_one * stride + static_cast<std::size_t>(image.width);
    return mask.size() >= required;
}

[[nodiscard]] std::optional<double> make_cross_angle(
    const DefectComponentRepairParameters& parameters) noexcept {
    if (!parameters.has_preferred_angle) {
        return std::nullopt;
    }
    double cross = std::fmod(parameters.preferred_angle_degrees + 90.0, 180.0);
    if (cross < 0.0) {
        cross += 180.0;
    }
    return cross;
}

}  // namespace

DefectComponentRepairResult repair_defect_components(
    WorkingImage image,
    const std::vector<std::uint8_t>& mask,
    const std::size_t mask_stride_bytes,
    const DefectComponentRepairParameters& parameters) noexcept {
    return repair_defect_components(
        std::move(image),
        std::span<const std::uint8_t>(mask),
        mask_stride_bytes,
        parameters);
}

DefectComponentRepairResult repair_defect_components(
    WorkingImage image,
    const std::span<const std::uint8_t> mask,
    const std::size_t mask_stride_bytes,
    const DefectComponentRepairParameters& parameters) noexcept {
    DefectComponentRepairResult result{};
    result.image = std::move(image);
    if (!valid_parameters(parameters) || result.image.width <= 2U ||
        result.image.height <= 2U ||
        result.image.width > static_cast<std::uint32_t>(
            std::numeric_limits<int>::max()) ||
        result.image.height > static_cast<std::uint32_t>(
            std::numeric_limits<int>::max()) ||
        !valid_mask_layout(result.image, mask, mask_stride_bytes)) {
        discard_pixels(result.image);
        return result;
    }
    result.info.kernel_status =
        negaflow::core::validate_finite_pixels(const_view(result.image));
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = DefectComponentRepairStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }
    try {
        const int width = static_cast<int>(result.image.width);
        const int height = static_cast<int>(result.image.height);
        const std::size_t count =
            static_cast<std::size_t>(result.image.width) * result.image.height;
        result.blend_mask.resize(count);
        std::vector<std::uint8_t> damaged(count, 0U);
        std::vector<Rgba32F> encoded(count);
        // 전면 마스크 한 장이면 이 루프만으로 5088x3401 화소마다 sRGB 인코드를 세 번 돕니다.
        // 행끼리 독립이므로 화소당 계산은 그대로 두고 행 블록으로만 나눕니다. 세는 값은
        // 순서와 무관하므로 원자 누적으로 합칩니다.
        std::atomic<std::size_t> input_mask_pixels{0U};
        negaflow::core::for_each_row_block(
            result.image.height,
            static_cast<std::uint64_t>(width) * height *
                (sizeof(Rgba32F) * 2U + 3U),
            [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
                std::size_t block_mask_pixels = 0U;
                for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                    const std::size_t source_row =
                        static_cast<std::size_t>(y) * result.image.stride_pixels;
                    const std::size_t mask_row =
                        static_cast<std::size_t>(y) * mask_stride_bytes;
                    const std::size_t packed_row =
                        static_cast<std::size_t>(y) * static_cast<std::size_t>(width);
                    for (int x = 0; x < width; ++x) {
                        const std::size_t packed = packed_row + x;
                        const std::uint8_t weight = mask[mask_row + x];
                        result.blend_mask[packed] = weight;
                        if (weight > 8U) {
                            damaged[packed] = 1U;
                            ++block_mask_pixels;
                        }
                        const Rgba32F source = result.image.pixels[source_row + x];
                        encoded[packed] = {
                            negaflow::color::linear_to_srgb_encoded(source.red),
                            negaflow::color::linear_to_srgb_encoded(source.green),
                            negaflow::color::linear_to_srgb_encoded(source.blue),
                            source.alpha,
                        };
                    }
                }
                input_mask_pixels.fetch_add(
                    block_mask_pixels, std::memory_order_relaxed);
            });
        result.info.input_mask_pixels =
            input_mask_pixels.load(std::memory_order_relaxed);
        if (parameters.has_preferred_angle) {
            damaged = refine_broad_damage_mask(encoded, damaged, width, height);
            for (std::size_t pixel = 0U; pixel < count; ++pixel) {
                if (damaged[pixel] == 0U) {
                    result.blend_mask[pixel] = 0U;
                }
            }
        }
        result.info.retained_mask_pixels = static_cast<std::size_t>(std::count(
            damaged.begin(), damaged.end(), static_cast<std::uint8_t>(1U)));
        const std::vector<std::uint8_t> damaged_original = damaged;
        std::vector<Rgba32F> repaired = encoded;
        std::uint64_t seed = 0x2545F4914F6CDD1DULL;
        const auto structure_info = repair_component_structures(
            encoded,
            repaired,
            damaged,
            damaged_original,
            width,
            height,
            make_cross_angle(parameters),
            seed);
        result.info.component_count = structure_info.component_count;
        result.info.repaired_pixels = structure_info.repaired_pixels;

        negaflow::core::for_each_row_block(
            result.image.height,
            static_cast<std::uint64_t>(width) * height *
                (sizeof(Rgba32F) * 2U + 1U),
            [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
                for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                    const std::size_t output_row =
                        static_cast<std::size_t>(y) * result.image.stride_pixels;
                    const std::size_t packed_row =
                        static_cast<std::size_t>(y) * static_cast<std::size_t>(width);
                    for (int x = 0; x < width; ++x) {
                        const std::size_t packed = packed_row + x;
                        const float blend = static_cast<float>(
                            static_cast<double>(result.blend_mask[packed]) / 255.0 *
                            parameters.strength);
                        if (blend <= 0.0F) {
                            continue;
                        }
                        Rgba32F& output = result.image.pixels[output_row + x];
                        const Rgba32F source = output;
                        const Rgba32F repaired_linear{
                            negaflow::color::srgb_encoded_to_linear(repaired[packed].red),
                            negaflow::color::srgb_encoded_to_linear(repaired[packed].green),
                            negaflow::color::srgb_encoded_to_linear(repaired[packed].blue),
                            source.alpha,
                        };
                        const float keep = 1.0F - blend;
                        output.red = source.red * keep + repaired_linear.red * blend;
                        output.green = source.green * keep + repaired_linear.green * blend;
                        output.blue = source.blue * keep + repaired_linear.blue * blend;
                        output.alpha = source.alpha;
                    }
                }
            });
        result.info.applied = result.info.repaired_pixels != 0U &&
                              parameters.strength > 1.0e-3;
        result.status = DefectComponentRepairStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = DefectComponentRepairStatus::allocation_failed;
        result.blend_mask.clear();
        discard_pixels(result.image);
        return result;
    } catch (...) {
        result.status = DefectComponentRepairStatus::allocation_failed;
        result.blend_mask.clear();
        discard_pixels(result.image);
        return result;
    }
}

const char* defect_component_repair_status_name(
    const DefectComponentRepairStatus status) noexcept {
    switch (status) {
        case DefectComponentRepairStatus::ok:
            return "ok";
        case DefectComponentRepairStatus::invalid_argument:
            return "invalid_argument";
        case DefectComponentRepairStatus::kernel_failed:
            return "kernel_failed";
        case DefectComponentRepairStatus::allocation_failed:
            return "allocation_failed";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
