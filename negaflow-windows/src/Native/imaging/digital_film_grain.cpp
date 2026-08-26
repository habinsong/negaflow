#include "negaflow/imaging/digital_film_grain.h"

#include "negaflow/core/parallel_rows.h"
#include "negaflow/imaging/kernel_accelerator.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
}

[[nodiscard]] negaflow::core::ConstImageView const_view(
    const WorkingImage& image) noexcept {
    return {
        image.pixels.data(), image.pixels.size(), image.width, image.height,
        image.stride_pixels};
}

[[nodiscard]] std::uint32_t coordinate_hash(
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t channel) noexcept {
    std::uint32_t value = x * 0x9e3779b9U ^ y * 0x85ebca6bU ^
                          channel * 0xc2b2ae35U ^ 0x27d4eb2fU;
    value ^= value >> 16U;
    value *= 0x7feb352dU;
    value ^= value >> 15U;
    value *= 0x846ca68bU;
    value ^= value >> 16U;
    return value;
}

[[nodiscard]] float unit_noise(
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t channel) noexcept {
    return static_cast<float>(coordinate_hash(x, y, channel) >> 8U) /
           static_cast<float>(0x00ffffffU);
}

[[nodiscard]] float scaled_noise(
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t channel,
    const double size) noexcept {
    if (size <= 1.01) {
        return unit_noise(x, y, channel);
    }
    const double source_x = (static_cast<double>(x) + 0.5) / size;
    const double source_y = (static_cast<double>(y) + 0.5) / size;
    const auto x0 = static_cast<std::uint32_t>(std::floor(source_x));
    const auto y0 = static_cast<std::uint32_t>(std::floor(source_y));
    const float tx = static_cast<float>(source_x - x0);
    const float ty = static_cast<float>(source_y - y0);
    const float n00 = unit_noise(x0, y0, channel);
    const float n10 = unit_noise(x0 + 1U, y0, channel);
    const float n01 = unit_noise(x0, y0 + 1U, channel);
    const float n11 = unit_noise(x0 + 1U, y0 + 1U, channel);
    const float top = n00 + (n10 - n00) * tx;
    const float bottom = n01 + (n11 - n01) * tx;
    return top + (bottom - top) * ty;
}

[[nodiscard]] float apply_channel(
    const float source,
    const float noise,
    const double amplitude) noexcept {
    const float value = std::max(source, 1.0e-5F);
    const float density = -std::log10(value / 0.18F);
    const float physical = std::sqrt(std::max(density, 0.0F) + 0.02F);
    const float t = (density - 1.0F) / 1.15F;
    const float perceptual = std::exp(-(t * t));
    const float amount = static_cast<float>(amplitude) * physical * perceptual;
    return 0.18F * std::pow(10.0F, -(density + noise * amount));
}

} // namespace

bool valid_digital_film_grain_parameters(
    const DigitalFilmGrainParameters& parameters) noexcept {
    return std::isfinite(parameters.strength) &&
           (parameters.emulation == FilmEmulation::none ||
            digital_film_physics(parameters.emulation) != nullptr);
}

DigitalFilmGrainResult apply_digital_film_grain(
    WorkingImage image,
    const DigitalFilmGrainParameters& parameters) noexcept {
    if (!valid_digital_film_grain_parameters(parameters)) {
        DigitalFilmGrainResult result{};
        result.image = std::move(image);
        discard_pixels(result.image);
        return result;
    }
    const DigitalFilmPhysics* const physics =
        digital_film_physics(parameters.emulation);
    const DigitalFilmGrainProfile profile = physics == nullptr
        ? DigitalFilmGrainProfile{0.0, 0.0, 1.0}
        : physics->grain;
    return apply_digital_film_grain_material(
        std::move(image), profile, parameters.strength);
}

DigitalFilmGrainResult apply_digital_film_grain_material(
    WorkingImage image,
    const DigitalFilmGrainProfile& profile,
    const double strength) noexcept {
    DigitalFilmGrainResult result{};
    result.image = std::move(image);
    if (!std::isfinite(strength) || !std::isfinite(profile.amplitude) ||
        !std::isfinite(profile.chroma_ratio) || !std::isfinite(profile.size) ||
        profile.amplitude < 0.0 || profile.chroma_ratio < 0.0 ||
        profile.chroma_ratio > 1.0 || profile.size <= 0.0) {
        discard_pixels(result.image);
        return result;
    }
    result.info.kernel_status =
        negaflow::core::validate_finite_pixels(const_view(result.image));
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = DigitalFilmGrainStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }
    const double bounded_strength = std::clamp(strength, 0.0, 1.0);
    if (profile.amplitude <= 0.0 || bounded_strength <= 1.0e-3) {
        result.status = DigitalFilmGrainStatus::ok;
        return result;
    }
    const double amplitude = profile.amplitude * bounded_strength;
    const float chroma = static_cast<float>(profile.chroma_ratio);
    // **근사입니다**(밀도 응답이 `log10`·`sqrt`·`exp`·`pow`). 좌표 해시 자체는
    // uint32 라 GPU 와 비트 단위로 같고, 사슬 전체 실측 오차는 4.2e-07 입니다.
    // `ApproximateAcceleratorScope` 안에서만 돕니다 — 내보내기·골든은 CPU 그대로입니다.
    if (approximate_acceleration_allowed()) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->digital_film_grain != nullptr) {
            if (table->digital_film_grain(
                    reinterpret_cast<float*>(result.image.pixels.data()),
                    result.image.width,
                    result.image.height,
                    result.image.stride_pixels,
                    static_cast<float>(amplitude),
                    chroma,
                    static_cast<float>(profile.size))) {
                result.info.kernel_status =
                    negaflow::core::validate_finite_pixels(const_view(result.image));
                if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
                    result.status = DigitalFilmGrainStatus::kernel_failed;
                    discard_pixels(result.image);
                    return result;
                }
                result.info.applied = true;
                result.status = DigitalFilmGrainStatus::ok;
                return result;
            }
        }
    }
    // 알갱이는 **좌표 해시**라 이웃을 보지 않습니다. 행끼리 독립이므로 코어로 나눠도
    // 값이 그대로입니다. 화소마다 잡음 셋과 밀도 응답(`log10`·`sqrt`·`exp`·`pow`)이
    // 도므로, 넘기는 몫도 그만큼 세어 문턱을 넘깁니다(`parallel_rows.h`).
    negaflow::core::for_each_row_block(
        result.image.height,
        static_cast<std::uint64_t>(result.image.width) * result.image.height * 12U,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                for (std::uint32_t x = 0U; x < result.image.width; ++x) {
                    auto& pixel = result.image.pixels[
                        static_cast<std::size_t>(y) * result.image.stride_pixels + x];
                    std::array<float, 3> noise{
                        scaled_noise(x, y, 0U, profile.size) - 0.5F,
                        scaled_noise(x, y, 1U, profile.size) - 0.5F,
                        scaled_noise(x, y, 2U, profile.size) - 0.5F,
                    };
                    const float luma = (noise[0] + noise[1] + noise[2]) / 3.0F;
                    for (float& value : noise) {
                        value = luma + (value - luma) * chroma;
                    }
                    pixel.red = apply_channel(pixel.red, noise[0], amplitude);
                    pixel.green = apply_channel(pixel.green, noise[1], amplitude);
                    pixel.blue = apply_channel(pixel.blue, noise[2], amplitude);
                }
            }
        });
    result.info.kernel_status =
        negaflow::core::validate_finite_pixels(const_view(result.image));
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = DigitalFilmGrainStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }
    result.info.applied = true;
    result.status = DigitalFilmGrainStatus::ok;
    return result;
}

const char* digital_film_grain_status_name(
    const DigitalFilmGrainStatus status) noexcept {
    switch (status) {
        case DigitalFilmGrainStatus::ok: return "ok";
        case DigitalFilmGrainStatus::invalid_parameter: return "invalid_parameter";
        case DigitalFilmGrainStatus::kernel_failed: return "kernel_failed";
    }
    return "unknown_status";
}

} // namespace negaflow::imaging
