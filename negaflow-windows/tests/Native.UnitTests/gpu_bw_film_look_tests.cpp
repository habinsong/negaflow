// 제품 경로 — 흑백 디지털 룩 사슬 오케스트레이터.
// CPU 는 스코프 밖 `apply_digital_bw_film_look`, GPU 는
// `GpuAccelerator::apply_digital_bw_film_look` 가 true 여야 한다.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

#include "negaflow/imaging/digital_bw_film_look.h"
#include "negaflow/imaging/digital_bw_film_profile.h"
#include "negaflow/imaging/film_emulation_acutance.h"
#include "negaflow/imaging/kernel_accelerator.h"
#include "negaflow/pipeline/gpu_accelerator.h"

namespace {

using negaflow::core::Rgba32F;
using negaflow::imaging::DigitalBwFilmLookParameters;
using negaflow::imaging::DigitalBwFilmLookStatus;
using negaflow::imaging::FilmEmulation;
using negaflow::imaging::WorkingImage;
using negaflow::pipeline::GpuAccelerator;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

constexpr float tolerance = 1.0e-5F;
constexpr std::uint32_t width = 64U;
constexpr std::uint32_t height = 48U;

[[nodiscard]] WorkingImage make_pattern() {
    WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float fx = static_cast<float>(x) / 63.0F;
            const float fy = static_cast<float>(y) / 47.0F;
            image.pixels[(static_cast<std::size_t>(y) * width) + x] = Rgba32F{
                0.18F + fx * 0.55F,
                0.12F + fy * 0.40F,
                0.08F + (1.0F - fx) * 0.30F,
                1.0F};
        }
    }
    return image;
}

void compare_images(
    const char* const label,
    const WorkingImage& cpu,
    const WorkingImage& other) {
    expect(cpu.pixels.size() == other.pixels.size(), "pixel count");
    float worst = 0.0F;
    for (std::size_t index = 0U; index < cpu.pixels.size(); ++index) {
        const float dr = std::abs(cpu.pixels[index].red - other.pixels[index].red);
        const float dg = std::abs(cpu.pixels[index].green - other.pixels[index].green);
        const float db = std::abs(cpu.pixels[index].blue - other.pixels[index].blue);
        worst = std::max({worst, dr, dg, db});
    }
    if (worst > tolerance) {
        std::cerr << "FAIL: " << label << " bw look delta " << worst << '\n';
        ++failures;
    } else {
        std::cout << label << " bw look max delta " << worst << '\n';
    }
}

}  // namespace

int main() {
    negaflow::pipeline::install_gpu_kernel_accelerator();
    if (!GpuAccelerator::shared().available()) {
        std::cout << "GPU unavailable — bw film look test skipped\n";
        return 0;
    }
    std::cout << "adapter: " << GpuAccelerator::shared().adapter_description() << '\n';

    const DigitalBwFilmLookParameters parameters{
        FilmEmulation::tri_x_400, 0.80, 0.0, 0.0};
    std::vector<negaflow::imaging::FilmEmulationAcutanceScratchPixel> scratch(
        negaflow::imaging::film_emulation_acutance_scratch_pixel_count(width));
    const negaflow::imaging::FilmEmulationAcutanceScratch scratch_view{
        scratch.data(), scratch.size()};

    WorkingImage cpu_source = make_pattern();
    auto cpu = negaflow::imaging::apply_digital_bw_film_look(
        std::move(cpu_source), parameters, scratch_view);
    expect(cpu.status == DigitalBwFilmLookStatus::ok, "CPU bw look must succeed");
    expect(cpu.info.emulsion_response_applied, "CPU emulsion must apply");

    WorkingImage orchestrated = make_pattern();
    negaflow::imaging::DigitalBwFilmLookPlan plan{};
    const auto* const profile =
        negaflow::imaging::digital_bw_film_profile(parameters.emulation);
    expect(profile != nullptr, "tri-x profile");
    if (profile == nullptr) {
        return 1;
    }
    plan.halation_material = {
        {profile->scatter_strength, profile->scatter_strength, profile->scatter_strength},
        {profile->halation_strength, profile->halation_strength, profile->halation_strength},
        profile->halation_radius_ratio};
    plan.halation_strength = 0.80;
    plan.halation_requested = true;
    plan.emulsion = negaflow::imaging::prepare_digital_bw_emulsion_response(
        {parameters.emulation, 0.80});
    const negaflow::imaging::FilmEmulationAcutanceParameters acutance{
        parameters.emulation, 0.80};
    plan.acutance = negaflow::imaging::has_film_emulation_acutance_change(acutance)
        ? negaflow::imaging::prepare_film_emulation_acutance(acutance)
        : negaflow::imaging::FilmEmulationAcutanceSetup{};
    plan.grain = {profile->grain_amplitude, 0.0, profile->grain_size};
    plan.grain_strength = 0.80;
    plan.grain_requested = true;
    negaflow::imaging::DigitalBwFilmLookApplied applied{};
    const bool ran = GpuAccelerator::shared().apply_digital_bw_film_look(
        reinterpret_cast<float*>(orchestrated.pixels.data()),
        width,
        height,
        width,
        &plan,
        &applied);
    expect(ran, "GPU bw look orchestrator must run — fallback would make this test vacuous");
    if (!ran) {
        return 1;
    }
    compare_images("direct", cpu.image, orchestrated);

    WorkingImage product_source = make_pattern();
    negaflow::imaging::DigitalBwFilmLookResult product{};
    {
        const negaflow::imaging::ApproximateAcceleratorScope scope{};
        product = negaflow::imaging::apply_digital_bw_film_look(
            std::move(product_source), parameters, scratch_view);
    }
    expect(product.status == DigitalBwFilmLookStatus::ok, "product bw look must succeed");
    compare_images("product", cpu.image, product.image);

    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return 1;
    }
    std::cout << "gpu bw film look tests passed\n";
    return 0;
}
