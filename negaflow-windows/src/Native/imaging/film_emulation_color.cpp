#include "negaflow/imaging/film_emulation_color.h"

#include "negaflow/core/pointwise.h"
#include "negaflow/imaging/kernel_accelerator.h"

#include "film_emulation_profiles.h"
#include "negaflow/color/srgb_transfer.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace negaflow::imaging {
namespace {

constexpr double identity_threshold = 1.0e-3;
constexpr double intensity_steps = 20.0;
constexpr double red_luma = 0.2126;
constexpr double green_luma = 0.7152;
constexpr double blue_luma = 0.0722;

using detail::FilmEmulationColorProfile;
using detail::FilmRgb64;
using detail::FilmToneCurve;

[[nodiscard]] double clamp_unit(const double value) noexcept {
    return std::clamp(value, 0.0, 1.0);
}

[[nodiscard]] double dot(
    const FilmRgb64 left,
    const FilmRgb64 right) noexcept {
    return (left.red * right.red) + (left.green * right.green) +
           (left.blue * right.blue);
}

[[nodiscard]] double luma(const FilmRgb64 color) noexcept {
    return (color.red * red_luma) + (color.green * green_luma) +
           (color.blue * blue_luma);
}

[[nodiscard]] double smoothstep(
    const double lower,
    const double upper,
    const double value) noexcept {
    const double denominator = std::max(upper - lower, 1.0e-6);
    const double t = clamp_unit((value - lower) / denominator);
    return t * t * (3.0 - (2.0 * t));
}

[[nodiscard]] double smootherstep(const double value) noexcept {
    const double t = clamp_unit(value);
    return t * t * t * ((t * ((t * 6.0) - 15.0)) + 10.0);
}

[[nodiscard]] double s_curve_pivot(
    const double value,
    const double pivot) noexcept {
    const double bounded_pivot =
        (pivot <= 0.001 || pivot >= 0.999) ? 0.5 : pivot;
    const double exponent = std::log(0.5) / std::log(bounded_pivot);
    const double powered = std::pow(value, exponent);
    return std::pow(clamp_unit(smootherstep(powered)), 1.0 / exponent);
}

[[nodiscard]] double tone_curve(
    const double value,
    const FilmToneCurve& parameters) noexcept {
    const double source = clamp_unit(value);
    const double curved = s_curve_pivot(source, parameters.pivot);
    double result = source + ((curved - source) * parameters.contrast);
    result = (result - parameters.black) /
             std::max(parameters.white - parameters.black, 1.0e-4);
    result += parameters.lift;
    return clamp_unit(result);
}

[[nodiscard]] double hue_degrees(const FilmRgb64 color) noexcept {
    const double maximum = std::max(color.red, std::max(color.green, color.blue));
    const double minimum = std::min(color.red, std::min(color.green, color.blue));
    const double difference = maximum - minimum;
    if (difference <= 1.0e-6) {
        return 0.0;
    }

    double hue = 0.0;
    if (maximum == color.red) {
        hue = (color.green - color.blue) / difference;
    } else if (maximum == color.green) {
        hue = 2.0 + ((color.blue - color.red) / difference);
    } else {
        hue = 4.0 + ((color.red - color.green) / difference);
    }
    hue *= 60.0;
    if (hue < 0.0) {
        hue += 360.0;
    }
    return hue;
}

[[nodiscard]] double hue_saturation_weight(
    const double hue,
    const std::array<double, 6>& anchors) noexcept {
    const double segment = hue / 60.0;
    const double lower_floor = std::floor(segment);
    const std::size_t lower =
        static_cast<std::size_t>(lower_floor) % anchors.size();
    const std::size_t upper = (lower + 1U) % anchors.size();
    const double fraction = segment - lower_floor;
    return (anchors[lower] * (1.0 - fraction)) +
           (anchors[upper] * fraction);
}

[[nodiscard]] FilmRgb64 map_color(
    const FilmRgb64 source,
    const FilmEmulationColorProfile& profile) noexcept {
    FilmRgb64 result{
        tone_curve(source.red, profile.tone_red),
        tone_curve(source.green, profile.tone_green),
        tone_curve(source.blue, profile.tone_blue),
    };

    result = {
        std::max(0.0, dot(profile.matrix_red, result)),
        std::max(0.0, dot(profile.matrix_green, result)),
        std::max(0.0, dot(profile.matrix_blue, result)),
    };

    const double bounded_luma = clamp_unit(luma(result));
    const double shadow_weight = (1.0 - bounded_luma) * (1.0 - bounded_luma);
    const double highlight_weight = bounded_luma * bounded_luma;
    result.red += (profile.shadow_tint.red * shadow_weight) +
                  (profile.highlight_tint.red * highlight_weight);
    result.green += (profile.shadow_tint.green * shadow_weight) +
                    (profile.highlight_tint.green * highlight_weight);
    result.blue += (profile.shadow_tint.blue * shadow_weight) +
                   (profile.highlight_tint.blue * highlight_weight);

    const double result_luma = luma(result);
    const double maximum = std::max(result.red, std::max(result.green, result.blue));
    const double minimum = std::min(result.red, std::min(result.green, result.blue));
    const double chroma = maximum - minimum;
    const double exposure_weight = smoothstep(0.12, 0.72, result_luma);
    const double chroma_weight = smoothstep(0.02, 0.14, chroma);
    const double hue_weight = 1.0 + hue_saturation_weight(
                                        hue_degrees(result),
                                        profile.hue_saturation_weights);
    const double saturation = 1.0 +
        (profile.exposure_saturation * exposure_weight * chroma_weight *
         hue_weight);
    result.red = result_luma + ((result.red - result_luma) * saturation);
    result.green = result_luma + ((result.green - result_luma) * saturation);
    result.blue = result_luma + ((result.blue - result_luma) * saturation);

    return {
        clamp_unit(result.red),
        clamp_unit(result.green),
        clamp_unit(result.blue),
    };
}

[[nodiscard]] bool valid_emulation(const FilmEmulation emulation) noexcept {
    return emulation == FilmEmulation::none ||
           detail::film_emulation_color_profile(emulation) != nullptr;
}

[[nodiscard]] negaflow::core::KernelStatus validate_parameters(
    const FilmEmulationColorParameters& parameters) noexcept {
    if (!std::isfinite(parameters.intensity)) {
        return negaflow::core::KernelStatus::non_finite_parameter;
    }
    return valid_emulation(parameters.emulation)
               ? negaflow::core::KernelStatus::ok
               : negaflow::core::KernelStatus::invalid_parameter;
}

[[nodiscard]] std::size_t cube_index(
    const std::size_t red,
    const std::size_t green,
    const std::size_t blue) noexcept {
    const std::size_t dimension = film_emulation_cube_dimension;
    return ((blue * dimension) + green) * dimension + red;
}

[[nodiscard]] float interpolate(
    const float lower,
    const float upper,
    const float fraction) noexcept {
    return lower + ((upper - lower) * fraction);
}

[[nodiscard]] FilmEmulationCubeEntry interpolate_entry(
    const FilmEmulationCubeEntry lower,
    const FilmEmulationCubeEntry upper,
    const float fraction) noexcept {
    return {
        interpolate(lower.red, upper.red, fraction),
        interpolate(lower.green, upper.green, fraction),
        interpolate(lower.blue, upper.blue, fraction),
    };
}

[[nodiscard]] FilmEmulationCubeEntry sample_cube(
    const FilmEmulationColorCube& cube,
    const float red,
    const float green,
    const float blue) noexcept {
    const float maximum_coordinate =
        static_cast<float>(film_emulation_cube_dimension - 1U);
    const float red_coordinate = red * maximum_coordinate;
    const float green_coordinate = green * maximum_coordinate;
    const float blue_coordinate = blue * maximum_coordinate;

    const std::size_t red_low = static_cast<std::size_t>(red_coordinate);
    const std::size_t green_low = static_cast<std::size_t>(green_coordinate);
    const std::size_t blue_low = static_cast<std::size_t>(blue_coordinate);
    const std::size_t red_high = std::min(
        red_low + 1U,
        static_cast<std::size_t>(film_emulation_cube_dimension - 1U));
    const std::size_t green_high = std::min(
        green_low + 1U,
        static_cast<std::size_t>(film_emulation_cube_dimension - 1U));
    const std::size_t blue_high = std::min(
        blue_low + 1U,
        static_cast<std::size_t>(film_emulation_cube_dimension - 1U));
    const float red_fraction = red_coordinate - static_cast<float>(red_low);
    const float green_fraction =
        green_coordinate - static_cast<float>(green_low);
    const float blue_fraction = blue_coordinate - static_cast<float>(blue_low);

    const FilmEmulationCubeEntry c000 =
        cube.entries[cube_index(red_low, green_low, blue_low)];
    const FilmEmulationCubeEntry c100 =
        cube.entries[cube_index(red_high, green_low, blue_low)];
    const FilmEmulationCubeEntry c010 =
        cube.entries[cube_index(red_low, green_high, blue_low)];
    const FilmEmulationCubeEntry c110 =
        cube.entries[cube_index(red_high, green_high, blue_low)];
    const FilmEmulationCubeEntry c001 =
        cube.entries[cube_index(red_low, green_low, blue_high)];
    const FilmEmulationCubeEntry c101 =
        cube.entries[cube_index(red_high, green_low, blue_high)];
    const FilmEmulationCubeEntry c011 =
        cube.entries[cube_index(red_low, green_high, blue_high)];
    const FilmEmulationCubeEntry c111 =
        cube.entries[cube_index(red_high, green_high, blue_high)];
    const FilmEmulationCubeEntry c00 =
        interpolate_entry(c000, c100, red_fraction);
    const FilmEmulationCubeEntry c10 =
        interpolate_entry(c010, c110, red_fraction);
    const FilmEmulationCubeEntry c01 =
        interpolate_entry(c001, c101, red_fraction);
    const FilmEmulationCubeEntry c11 =
        interpolate_entry(c011, c111, red_fraction);
    const FilmEmulationCubeEntry c0 =
        interpolate_entry(c00, c10, green_fraction);
    const FilmEmulationCubeEntry c1 =
        interpolate_entry(c01, c11, green_fraction);
    return interpolate_entry(c0, c1, blue_fraction);
}

[[nodiscard]] bool valid_cube_entries(
    const FilmEmulationColorCube& cube) noexcept {
    return std::all_of(
        cube.entries.begin(),
        cube.entries.end(),
        [](const FilmEmulationCubeEntry entry) noexcept {
            return std::isfinite(entry.red) && std::isfinite(entry.green) &&
                   std::isfinite(entry.blue) && entry.red >= 0.0F &&
                   entry.red <= 1.0F && entry.green >= 0.0F &&
                   entry.green <= 1.0F && entry.blue >= 0.0F &&
                   entry.blue <= 1.0F;
        });
}

} // namespace

bool valid_film_emulation_color_parameters(
    const FilmEmulationColorParameters& parameters) noexcept {
    return validate_parameters(parameters) == negaflow::core::KernelStatus::ok;
}

std::uint32_t film_emulation_intensity_step(
    const FilmEmulationColorParameters& parameters) noexcept {
    if (!std::isfinite(parameters.intensity)) {
        return 0U;
    }
    return static_cast<std::uint32_t>(
        std::lround(clamp_unit(parameters.intensity) * intensity_steps));
}

bool has_film_emulation_color_change(
    const FilmEmulationColorParameters& parameters) noexcept {
    if (!valid_emulation(parameters.emulation) ||
        parameters.emulation == FilmEmulation::none ||
        !std::isfinite(parameters.intensity)) {
        return false;
    }
    const double strength = clamp_unit(parameters.intensity);
    return strength > identity_threshold &&
           film_emulation_intensity_step(parameters) > 0U;
}

negaflow::core::KernelStatus build_film_emulation_color_cube(
    const FilmEmulationColorParameters& parameters,
    FilmEmulationColorCube& cube) noexcept {
    cube.ready = false;
    cube.emulation = parameters.emulation;
    cube.intensity_step = film_emulation_intensity_step(parameters);

    const negaflow::core::KernelStatus parameter_status =
        validate_parameters(parameters);
    if (parameter_status != negaflow::core::KernelStatus::ok) {
        return parameter_status;
    }
    if (!has_film_emulation_color_change(parameters)) {
        return negaflow::core::KernelStatus::ok;
    }

    const FilmEmulationColorProfile* const profile =
        detail::film_emulation_color_profile(parameters.emulation);
    if (profile == nullptr) {
        return negaflow::core::KernelStatus::invalid_parameter;
    }

    const double strength =
        static_cast<double>(cube.intensity_step) / intensity_steps;
    const double denominator =
        static_cast<double>(film_emulation_cube_dimension - 1U);
    for (std::uint32_t blue = 0U; blue < film_emulation_cube_dimension; ++blue) {
        for (std::uint32_t green = 0U; green < film_emulation_cube_dimension;
             ++green) {
            for (std::uint32_t red = 0U; red < film_emulation_cube_dimension;
                 ++red) {
                const FilmRgb64 source{
                    static_cast<double>(red) / denominator,
                    static_cast<double>(green) / denominator,
                    static_cast<double>(blue) / denominator,
                };
                const FilmRgb64 mapped = map_color(source, *profile);
                const FilmRgb64 blended{
                    source.red + ((mapped.red - source.red) * strength),
                    source.green + ((mapped.green - source.green) * strength),
                    source.blue + ((mapped.blue - source.blue) * strength),
                };
                cube.entries[cube_index(red, green, blue)] = {
                    static_cast<float>(clamp_unit(blended.red)),
                    static_cast<float>(clamp_unit(blended.green)),
                    static_cast<float>(clamp_unit(blended.blue)),
                };
            }
        }
    }
    if (!valid_cube_entries(cube)) {
        return negaflow::core::KernelStatus::non_finite_output;
    }
    cube.ready = true;
    return negaflow::core::KernelStatus::ok;
}

negaflow::core::KernelStatus apply_film_emulation_color_cube(
    const negaflow::core::ConstImageView input,
    const negaflow::core::ImageView output,
    const FilmEmulationColorParameters& parameters,
    const FilmEmulationColorCube* const cube) noexcept {
    const negaflow::core::KernelStatus parameter_status =
        validate_parameters(parameters);
    if (parameter_status != negaflow::core::KernelStatus::ok) {
        return parameter_status;
    }
    const negaflow::core::KernelStatus compatibility_status =
        negaflow::core::validate_compatible_views(input, output);
    if (compatibility_status != negaflow::core::KernelStatus::ok) {
        return compatibility_status;
    }
    const negaflow::core::KernelStatus input_status =
        negaflow::core::validate_finite_pixels(input);
    if (input_status != negaflow::core::KernelStatus::ok) {
        return input_status;
    }

    if (!has_film_emulation_color_change(parameters)) {
        for (std::uint32_t row = 0U; row < input.height; ++row) {
            const std::size_t input_offset =
                static_cast<std::size_t>(row) * input.stride_pixels;
            const std::size_t output_offset =
                static_cast<std::size_t>(row) * output.stride_pixels;
            std::copy_n(
                input.pixels + input_offset,
                input.width,
                output.pixels + output_offset);
        }
        return negaflow::core::KernelStatus::ok;
    }

    if (cube == nullptr || !cube->ready ||
        cube->emulation != parameters.emulation ||
        cube->intensity_step != film_emulation_intensity_step(parameters)) {
        return negaflow::core::KernelStatus::invalid_argument;
    }
    if (!valid_cube_entries(*cube)) {
        return negaflow::core::KernelStatus::invalid_parameter;
    }

    // **근사입니다**(sRGB 왕복의 `pow`). 표와 삼선형 보간은 CPU 와 같은 float
    // 연산이라 그 자리에서는 오차가 안 생깁니다.
    // 입출력이 별칭이어도 됩니다 — GPU 판은 텍스처 두 장을 오가므로 겹침이 없습니다.
    if (approximate_acceleration_allowed()) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->film_emulation_cube != nullptr &&
            input.pixels == output.pixels && input.stride_pixels == output.stride_pixels &&
            output.stride_pixels <= 0xFFFFFFFFULL) {
            if (table->film_emulation_cube(
                    reinterpret_cast<float*>(output.pixels),
                    output.width,
                    output.height,
                    static_cast<std::uint32_t>(output.stride_pixels),
                    cube)) {
                return negaflow::core::KernelStatus::ok;
            }
        }
    }

    // 화소마다 sRGB 왕복(`pow`)과 삼선형 보간이 돕니다. 엔진의 화소별 헬퍼가 행끼리
    // 나눠 돌며 — 행이 서로를 보지 않으므로 값은 그대로이고, 첫 실패 행을 가장 작은
    // 것으로 모아 돌려주는 규칙도 그대로입니다.
    return negaflow::core::transform_validated_pointwise(
        input,
        output,
        [cube](const negaflow::core::Rgba32F source) noexcept {
            const FilmEmulationCubeEntry encoded = sample_cube(
                *cube,
                std::clamp(
                    negaflow::color::linear_to_srgb_encoded(source.red), 0.0F, 1.0F),
                std::clamp(
                    negaflow::color::linear_to_srgb_encoded(source.green), 0.0F, 1.0F),
                std::clamp(
                    negaflow::color::linear_to_srgb_encoded(source.blue), 0.0F, 1.0F));
            return negaflow::core::Rgba32F{
                negaflow::color::srgb_encoded_to_linear(encoded.red),
                negaflow::color::srgb_encoded_to_linear(encoded.green),
                negaflow::color::srgb_encoded_to_linear(encoded.blue),
                source.alpha,
            };
        });
}

} // namespace negaflow::imaging
