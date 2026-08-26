#include "negaflow/imaging/digital_film_color_preset.h"

#include "negaflow/core/parallel_rows.h"
#include "negaflow/imaging/kernel_accelerator.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <new>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

struct Rgb final {
    float red;
    float green;
    float blue;
};

static_assert(sizeof(Rgb) == 3U * sizeof(float));

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
}

[[nodiscard]] negaflow::core::ConstImageView const_view(
    const WorkingImage& image) noexcept {
    return {image.pixels.data(), image.pixels.size(), image.width, image.height,
            image.stride_pixels};
}

[[nodiscard]] float linear_to_srgb(const float value) noexcept {
    return value <= 0.0031308F
        ? value * 12.92F
        : 1.055F * std::pow(std::max(value, 0.0F), 1.0F / 2.4F) - 0.055F;
}

[[nodiscard]] float srgb_to_linear(const float value) noexcept {
    return value <= 0.04045F
        ? value / 12.92F
        : std::pow(std::max((value + 0.055F) / 1.055F, 0.0F), 2.4F);
}

} // namespace

bool valid_digital_film_color_preset_parameters(
    const DigitalFilmColorPresetParameters& parameters) noexcept {
    return std::isfinite(parameters.intensity) &&
           (parameters.emulation == FilmEmulation::none ||
            digital_film_color_preset(parameters.emulation) != nullptr);
}

// 화소마다 `pow` 를 세 번 부릅니다. 출력 화소 수만 넘기면 문턱을 못 넘어 병렬화가
// 조용히 꺼지므로, 실제로 드는 몫을 세어 넘깁니다(`parallel_rows.h`).
[[nodiscard]] static std::uint64_t srgb_round_trip_work_units(
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    return static_cast<std::uint64_t>(width) * height * 8U;
}

DigitalFilmColorPresetResult apply_digital_film_color_preset(
    WorkingImage image,
    const DigitalFilmColorPresetParameters& parameters) noexcept {
    DigitalFilmColorPresetResult result{};
    result.image = std::move(image);
    if (!valid_digital_film_color_preset_parameters(parameters)) {
        discard_pixels(result.image);
        return result;
    }
    result.info.kernel_status =
        negaflow::core::validate_finite_pixels(const_view(result.image));
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = DigitalFilmColorPresetStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }
    const DigitalFilmColorPreset* const preset =
        digital_film_color_preset(parameters.emulation);
    const float strength = static_cast<float>(
        std::clamp(parameters.intensity, 0.0, 1.0));
    if (preset == nullptr || strength <= 1.0e-3F) {
        result.status = DigitalFilmColorPresetStatus::ok;
        return result;
    }
    // **근사입니다**(감마 왕복의 `pow`, 색 커널 셋의 HSL 왕복).
    // `ApproximateAcceleratorScope` 안에서만 돕니다 — 내보내기·골든은 CPU 그대로입니다.
    // GPU 판은 타일을 쓰지 않으므로 `scratch_peak_bytes` 는 0 입니다. 셋 다 화소별이라
    // 타일이 값의 조건이 아니고(러닝 섬이 없습니다), 호스트 스크래치도 필요 없습니다.
    if (approximate_acceleration_allowed()) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->digital_film_color_preset != nullptr) {
            if (table->digital_film_color_preset(
                    reinterpret_cast<float*>(result.image.pixels.data()),
                    result.image.width,
                    result.image.height,
                    result.image.stride_pixels,
                    preset,
                    strength)) {
                result.info.applied = true;
                result.info.kernel_status = negaflow::core::KernelStatus::ok;
                result.status = DigitalFilmColorPresetStatus::ok;
                return result;
            }
        }
    }
    try {
        const std::size_t width = result.image.width;
        const std::uint32_t rows_per_tile = static_cast<std::uint32_t>(
            std::min<std::size_t>(
                result.image.height,
                std::max<std::size_t>(
                    1U,
                    digital_film_color_preset_scratch_target_pixels / width)));
        std::vector<Rgb> original(width * rows_per_tile);
        result.info.scratch_peak_bytes = original.size() * sizeof(Rgb);
        const auto apply = [&](const negaflow::core::KernelStatus status) {
            result.info.kernel_status = status;
            return status == negaflow::core::KernelStatus::ok;
        };
        for (std::uint32_t tile_y = 0U; tile_y < result.image.height;) {
            const std::uint32_t tile_height = std::min(
                rows_per_tile, result.image.height - tile_y);
            // 화소마다 `pow` 를 세 번 씁니다. 행끼리 독립이라 코어로 나눠도 값이
            // 그대로입니다 — 색 커널 셋은 이미 `transform_validated_pointwise` 로
            // 나뉘어 도는데 이 왕복만 한 스레드에 남아 있었습니다.
            negaflow::core::for_each_row_block(
                tile_height,
                srgb_round_trip_work_units(result.image.width, tile_height),
                [&](const std::uint32_t first, const std::uint32_t count) noexcept {
                    for (std::uint32_t local_y = first; local_y < first + count; ++local_y) {
                        const std::size_t row_offset =
                            static_cast<std::size_t>(tile_y + local_y) *
                            result.image.stride_pixels;
                        std::size_t index =
                            static_cast<std::size_t>(local_y) * result.image.width;
                        for (std::uint32_t x = 0U; x < result.image.width; ++x, ++index) {
                            auto& pixel = result.image.pixels[row_offset + x];
                            original[index] = {pixel.red, pixel.green, pixel.blue};
                            pixel.red = linear_to_srgb(pixel.red);
                            pixel.green = linear_to_srgb(pixel.green);
                            pixel.blue = linear_to_srgb(pixel.blue);
                        }
                    }
                });

            const std::size_t tile_offset =
                static_cast<std::size_t>(tile_y) * result.image.stride_pixels;
            const negaflow::core::ConstImageView input{
                result.image.pixels.data() + tile_offset,
                result.image.pixels.size() - tile_offset,
                result.image.width,
                tile_height,
                result.image.stride_pixels,
            };
            const negaflow::core::ImageView output{
                result.image.pixels.data() + tile_offset,
                result.image.pixels.size() - tile_offset,
                result.image.width,
                tile_height,
                result.image.stride_pixels,
            };
            if (!apply(apply_color_mixer(input, output, preset->mixer)) ||
                !apply(apply_color_grading(input, output, preset->grading)) ||
                !apply(apply_primary_calibration(
                    input, output, preset->calibration))) {
                result.status = DigitalFilmColorPresetStatus::kernel_failed;
                discard_pixels(result.image);
                return result;
            }

            negaflow::core::for_each_row_block(
                tile_height,
                srgb_round_trip_work_units(result.image.width, tile_height),
                [&](const std::uint32_t first, const std::uint32_t count) noexcept {
                    for (std::uint32_t local_y = first; local_y < first + count; ++local_y) {
                        const std::size_t row_offset =
                            static_cast<std::size_t>(tile_y + local_y) *
                            result.image.stride_pixels;
                        std::size_t index =
                            static_cast<std::size_t>(local_y) * result.image.width;
                        for (std::uint32_t x = 0U; x < result.image.width; ++x, ++index) {
                            auto& pixel = result.image.pixels[row_offset + x];
                            const Rgb rendered{
                                srgb_to_linear(pixel.red), srgb_to_linear(pixel.green),
                                srgb_to_linear(pixel.blue)};
                            pixel.red = original[index].red +
                                        (rendered.red - original[index].red) * strength;
                            pixel.green = original[index].green +
                                          (rendered.green - original[index].green) * strength;
                            pixel.blue = original[index].blue +
                                         (rendered.blue - original[index].blue) * strength;
                        }
                    }
                });
            tile_y += tile_height;
        }
    } catch (const std::bad_alloc&) {
        result.status = DigitalFilmColorPresetStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }
    result.info.applied = true;
    result.info.kernel_status = negaflow::core::KernelStatus::ok;
    result.status = DigitalFilmColorPresetStatus::ok;
    return result;
}

const char* digital_film_color_preset_status_name(
    const DigitalFilmColorPresetStatus status) noexcept {
    switch (status) {
        case DigitalFilmColorPresetStatus::ok: return "ok";
        case DigitalFilmColorPresetStatus::invalid_parameter: return "invalid_parameter";
        case DigitalFilmColorPresetStatus::allocation_failed: return "allocation_failed";
        case DigitalFilmColorPresetStatus::kernel_failed: return "kernel_failed";
    }
    return "unknown_status";
}

} // namespace negaflow::imaging
