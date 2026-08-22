#include "preview.h"

#include "outcome.h"

#include "negaflow/color/srgb_transfer.h"
#include "negaflow/core/parallel_rows.h"
#include "negaflow/core/pixel.h"
#include "negaflow/core/pointwise.h"
#include "negaflow/imaging/channel_clipping_overlay.h"
#include "negaflow/imaging/display_gamut_map.h"
#include "negaflow/pipeline/gpu_accelerator.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>

namespace negaflow::pipeline::develop_export_detail {
namespace {

[[nodiscard]] std::uint32_t preview_extent(
    const std::uint32_t source,
    const std::uint32_t maximum) noexcept {
    return source <= maximum ? source : maximum;
}

} // namespace

void preview_fit_size(
    const std::uint32_t source_width,
    const std::uint32_t source_height,
    const std::uint32_t maximum_width,
    const std::uint32_t maximum_height,
    std::uint32_t& width,
    std::uint32_t& height) noexcept {
    width = preview_extent(source_width, maximum_width);
    height = source_width == 0U
        ? 0U
        : static_cast<std::uint32_t>(
              (static_cast<std::uint64_t>(source_height) * width) / source_width);
    if (height == 0U) {
        height = 1U;
    }
    if (height > maximum_height) {
        height = maximum_height;
        width = source_height == 0U
            ? 0U
            : static_cast<std::uint32_t>(
                  (static_cast<std::uint64_t>(source_width) * height) / source_height);
        if (width == 0U) {
            width = 1U;
        }
    }
}

namespace {

// `deferred` 가 이미 정수 경계로 풀어 둔 자르기입니다. 정규화 사각형을 다시 풀면 식이
// 두 벌이 되므로 그 경계를 그대로 씁니다. 실패하면 폭 0 을 돌려줍니다.
[[nodiscard]] negaflow::imaging::WorkingImage crop_working_image(
    const negaflow::imaging::WorkingImage& source,
    const std::uint32_t left,
    const std::uint32_t top,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    negaflow::imaging::WorkingImage output{};
    if (width == 0U || height == 0U || left + width > source.width ||
        top + height > source.height) {
        return output;
    }
    try {
        output.width = width;
        output.height = height;
        output.stride_pixels = width;
        output.pixels.resize(static_cast<std::size_t>(width) * height);
    } catch (...) {
        return negaflow::imaging::WorkingImage{};
    }
    for (std::uint32_t y = 0U; y < height; ++y) {
        const negaflow::core::Rgba32F* const row =
            source.pixels.data() +
            (static_cast<std::size_t>(y + top) * source.stride_pixels) + left;
        std::copy_n(
            row, width, output.pixels.data() + (static_cast<std::size_t>(y) * width));
    }
    return output;
}

} // namespace

DevelopExportOutcome write_preview(
    const negaflow::imaging::WorkingImage& image,
    const PreviewTarget& target,
    DevelopExportOutcome outcome,
    const negaflow::imaging::ImageTransformGather* const deferred) noexcept {
    if (target.pixels == nullptr || target.maximum_width == 0U ||
        target.maximum_height == 0U) {
        return fail(DevelopExportStage::output, "invalid_preview_target");
    }

    // 미룬 기하 변환이 있으면 상자 맞춤은 **변환 뒤 크기**로 합니다.
    const std::uint32_t source_width =
        deferred != nullptr ? deferred->output_width : image.width;
    const std::uint32_t source_height =
        deferred != nullptr ? deferred->output_height : image.height;
    if (source_width == 0U || source_height == 0U || image.width == 0U ||
        image.height == 0U || image.stride_pixels < image.width) {
        return fail(DevelopExportStage::output, "empty_preview_source");
    }

    // Fit inside the box without changing the aspect ratio. Integer arithmetic on the
    // larger side first so a very wide frame does not round its short side to zero.
    std::uint32_t width = 0U;
    std::uint32_t height = 0U;
    preview_fit_size(
        source_width,
        source_height,
        target.maximum_width,
        target.maximum_height,
        width,
        height);

    const std::uint64_t required =
        static_cast<std::uint64_t>(width) * static_cast<std::uint64_t>(height) * 4ULL;
    if (required > target.capacity_bytes) {
        return fail(DevelopExportStage::output, "preview_buffer_too_small");
    }

    // Soft proof is an affine in linear light and the sRGB encode below is not, so it has
    // to run per source pixel before the encode - averaging encoded samples and proofing
    // afterwards would not be the same picture. When proofing is off the factors are
    // exactly 1 and 0, so the arithmetic is an identity rather than a second code path
    // that could drift from this one.
    const negaflow::color::SoftProofTransfer proof = target.proof;

    // macOS `renderDisplayCGImage` 는 `createCGImage(..., format: .RGBA8)` 한 번으로
    // 평가합니다. 상주 화상이 이미 상자 크기이면 GPU 에서 BGRA8 로 내립니다.
    if (width == source_width && height == source_height && !target.clipping_overlay) {
        if (GpuAccelerator::shared().try_encode_preview_bgra(
                reinterpret_cast<const float*>(image.pixels.data()),
                image.width,
                image.height,
                target.pixels,
                width * 4U,
                proof.scale.data(),
                proof.bias.data(),
                deferred)) {
            outcome.image_width = width;
            outcome.image_height = height;
            outcome.output_file_bytes = required;
            outcome.succeeded = true;
            outcome.failure_name = "ok";
            return outcome;
        }
    }
    // GPU 경로가 아니면 호스트가 최신이어야 CPU 상자 평균이 옛 화소를 쓰지 않습니다.
    GpuAccelerator::shared().flush_resident();

    // 미룬 변환을 GPU 가 못 받았습니다. 여기서 CPU 로 걸어 줘야 자른 자리가 화면에
    // 나옵니다 — 안 걸면 자르기가 통째로 사라집니다. 드문 갈래이므로 사본 한 장을
    // 감수합니다.
    if (deferred != nullptr) {
        negaflow::imaging::ImageTransformParameters parameters{};
        parameters.rotation = deferred->rotation;
        parameters.flip_horizontal = deferred->flip_horizontal;
        parameters.flip_vertical = deferred->flip_vertical;
        parameters.has_crop = false;
        auto transformed = negaflow::imaging::apply_image_transform(image, parameters);
        if (transformed.status != negaflow::imaging::ImageTransformStatus::ok) {
            return fail(
                DevelopExportStage::output,
                negaflow::imaging::image_transform_status_name(transformed.status));
        }
        negaflow::imaging::WorkingImage cropped = crop_working_image(
            transformed.image,
            deferred->crop_left,
            deferred->crop_top,
            deferred->output_width,
            deferred->output_height);
        if (cropped.width == 0U) {
            return fail(DevelopExportStage::output, "empty_preview_source");
        }
        return write_preview(cropped, target, outcome, nullptr);
    }

    // Converted straight from the working image rather than through a full-resolution
    // 16-bit copy. On a 17 MP scan that copy was about 104 MB allocated only to be
    // averaged away, and dropping it also removes a whole pass over the frame.
    std::atomic<std::uint64_t> first_failure{negaflow::core::no_row_failure};
    negaflow::core::for_each_row_block(
        height,
        static_cast<std::uint64_t>(source_width) * source_height,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
      for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
        const std::uint32_t source_y0 =
            static_cast<std::uint32_t>((static_cast<std::uint64_t>(y) * source_height) / height);
        std::uint32_t source_y1 = static_cast<std::uint32_t>(
            (static_cast<std::uint64_t>(y + 1U) * source_height) / height);
        if (source_y1 <= source_y0) {
            source_y1 = source_y0 + 1U;
        }

        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::uint32_t source_x0 =
                static_cast<std::uint32_t>((static_cast<std::uint64_t>(x) * source_width) / width);
            std::uint32_t source_x1 = static_cast<std::uint32_t>(
                (static_cast<std::uint64_t>(x + 1U) * source_width) / width);
            if (source_x1 <= source_x0) {
                source_x1 = source_x0 + 1U;
            }

            float red = 0.0F;
            float green = 0.0F;
            float blue = 0.0F;
            float overlay_red = 0.0F;
            float overlay_green = 0.0F;
            float overlay_blue = 0.0F;
            float overlay_alpha = 0.0F;
            std::uint32_t count = 0U;
            bool finite = true;
            for (std::uint32_t sy = source_y0; sy < source_y1; ++sy) {
                const negaflow::core::Rgba32F* const row =
                    image.pixels.data() +
                    (static_cast<std::size_t>(sy) * image.stride_pixels);
                for (std::uint32_t sx = source_x0; sx < source_x1; ++sx) {
                    const negaflow::core::Rgba32F source = row[sx];
                    if (!negaflow::core::finite_rgb(source)) {
                        finite = false;
                        break;
                    }
                    // Hue-preserving fold instead of a per-channel clamp, then the paper
                    // and ink range, then the sRGB encode the 8-bit step quantises in.
                    const negaflow::core::Rgba32F folded =
                        negaflow::imaging::tone_safe_unit_rgb(source);
                    red += negaflow::color::linear_to_srgb_encoded(
                        (folded.red * proof.scale[0]) + proof.bias[0]);
                    green += negaflow::color::linear_to_srgb_encoded(
                        (folded.green * proof.scale[1]) + proof.bias[1]);
                    blue += negaflow::color::linear_to_srgb_encoded(
                        (folded.blue * proof.scale[2]) + proof.bias[2]);
                    if (target.clipping_overlay) {
                        const auto overlay =
                            negaflow::imaging::channel_clipping_overlay_pixel(source);
                        overlay_red += overlay.red;
                        overlay_green += overlay.green;
                        overlay_blue += overlay.blue;
                        overlay_alpha += overlay.alpha;
                    }
                    ++count;
                }
                if (!finite) {
                    break;
                }
            }
            if (!finite || count == 0U) {
                negaflow::core::record_row_failure_value(first_failure, y, 1U);
                return;
            }

            const float inverse_count = 1.0F / static_cast<float>(count);
            // Under one 8-bit step of noise, added in the space the quantisation happens
            // in. Without it a smooth sky bands here even though the working image is
            // perfectly smooth.
            const auto quantise = [&](const float sum,
                                      const std::uint32_t channel) noexcept {
                const float encoded = (sum * inverse_count) +
                    negaflow::imaging::display_dither_offset(x, y, channel);
                return static_cast<std::uint8_t>(
                    std::clamp(encoded, 0.0F, 1.0F) * 255.0F + 0.5F);
            };

            std::uint8_t* const destination =
                target.pixels + ((static_cast<std::size_t>(y) * width + x) * 4U);
            // BGRA8 with opaque alpha, which is what a XAML Image accepts.
            destination[0] = quantise(blue, 2U);
            destination[1] = quantise(green, 1U);
            destination[2] = quantise(red, 0U);
            destination[3] = 0xFFU;
            if (target.clipping_overlay) {
                const float oa = overlay_alpha * inverse_count;
                if (oa > 0.0F) {
                    const float keep = 1.0F - oa;
                    const auto blend = [oa, keep, inverse_count](
                                           const std::uint8_t dest,
                                           const float overlay_sum) noexcept {
                        const float mixed =
                            (overlay_sum * inverse_count) +
                            ((static_cast<float>(dest) / 255.0F) * keep);
                        return static_cast<std::uint8_t>(
                            std::clamp(mixed, 0.0F, 1.0F) * 255.0F + 0.5F);
                    };
                    destination[0] = blend(destination[0], overlay_blue);
                    destination[1] = blend(destination[1], overlay_green);
                    destination[2] = blend(destination[2], overlay_red);
                }
            }
        }
      }
        });

    if (negaflow::core::has_row_failure(
            first_failure.load(std::memory_order_relaxed))) {
        return fail(DevelopExportStage::output, "non_finite_preview_pixel");
    }

    outcome.image_width = width;
    outcome.image_height = height;
    outcome.output_file_bytes = required;
    outcome.succeeded = true;
    outcome.failure_name = "ok";
    return outcome;
}

} // namespace negaflow::pipeline::develop_export_detail
