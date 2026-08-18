// 파이프라인 GPU 가속 진입점 시험.
//
// 커널 동치 시험은 커널이 맞는지를 봅니다. **이 시험은 그 커널이 실제로 파이프라인에서
// 도는지**를 봅니다 — 앞 판의 가장 큰 구멍이 "커널은 정확한데 아무도 안 부른다" 였습니다.
//
// 보는 것 셋:
//  ① 정책이 `cpu_only` 면 GPU 가 **손대지 않습니다.** 내보내기·골든이 여기 걸려 있습니다.
//  ② 정책이 `allowed` 면 **실제로 처리합니다**(`handled == true`). 안 돌면 이 시험이 실패합니다.
//  ③ 처리한 결과가 CPU 판과 허용 오차 안입니다. 적용 플래그도 CPU 와 같아야 합니다 —
//     게이트를 하나라도 빠뜨리면 여기서 걸립니다.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <utility>
#include <vector>

#include "negaflow/imaging/film_scan_denoise.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "negaflow/pipeline/gpu_accelerator.h"

namespace {

using negaflow::core::Rgba32F;
using negaflow::imaging::FilmScanDenoiseParameters;
using negaflow::imaging::WorkingImage;
using negaflow::imaging::WorkingToneAdjustParameters;
using negaflow::pipeline::GpuAccelerator;
using negaflow::pipeline::GpuUsePolicy;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

// 톤 커널은 1e-5, 디노이즈 사슬은 감마 리프트의 `pow` 때문에 그보다 큽니다
// (`gpu_film_scan_stage.h` 의 설명). 두 상한을 따로 둡니다.
constexpr float tone_tolerance = 1.0e-5F;
constexpr float denoise_tolerance = 1.0e-4F;

// 타일 한 변(512)을 지나가게 잡습니다 — 디노이즈가 타일 경계를 실제로 지나야 의미가 있습니다.
constexpr std::uint32_t width = 600U;
constexpr std::uint32_t height = 96U;

[[nodiscard]] WorkingImage make_image() {
    WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::uint32_t seed = (x * 73856093U) ^ (y * 19349663U);
            const std::uint32_t mixed = (seed ^ (seed >> 13U)) * 1274126177U;
            const float noise = static_cast<float>(mixed >> 8U) / 16777216.0F;
            const float ramp = static_cast<float>(x) / static_cast<float>(width - 1U);
            const float base = std::clamp(ramp * 0.9F + (noise - 0.5F) * 0.08F, 0.0F, 1.0F);
            image.pixels[(static_cast<std::size_t>(y) * width) + x] = Rgba32F{
                base,
                std::clamp(base * 0.85F, 0.0F, 1.0F),
                std::clamp(0.9F - base, 0.0F, 1.0F),
                1.0F};
        }
    }
    return image;
}

[[nodiscard]] float worst_delta(
    const std::vector<Rgba32F>& reference,
    const std::vector<Rgba32F>& measured) noexcept {
    float worst = 0.0F;
    if (reference.size() != measured.size()) {
        return 1.0F;
    }
    for (std::size_t index = 0U; index < reference.size(); ++index) {
        worst = std::max(worst, std::abs(reference[index].red - measured[index].red));
        worst = std::max(worst, std::abs(reference[index].green - measured[index].green));
        worst = std::max(worst, std::abs(reference[index].blue - measured[index].blue));
        worst = std::max(worst, std::abs(reference[index].alpha - measured[index].alpha));
    }
    return worst;
}

void tone_path_runs_on_gpu() {
    WorkingToneAdjustParameters parameters{};
    parameters.exposure_stops = 0.6F;
    parameters.basic.contrast = 0.35F;
    parameters.basic.shadows = -0.20F;
    parameters.basic.whites = 1.4F;  // ±1 을 넘는 값 — 엔진이 받아야 합니다.
    parameters.curve.lights = 0.30F;
    parameters.curve.darks = -0.25F;
    parameters.color_mixer.saturation[2] = 0.4F;
    parameters.color_grading.shadows = {35.0F, 0.5F, 0.15F};
    parameters.color_grading.blending = 0.5F;
    parameters.primary_calibration.red_hue = 0.2F;

    // ① `cpu_only` 는 손대지 않습니다.
    {
        WorkingImage image = make_image();
        const std::vector<Rgba32F> before = image.pixels;
        const auto outcome = GpuAccelerator::shared().apply_working_tone_adjustments(
            GpuUsePolicy::cpu_only, image, parameters, {});
        expect(!outcome.handled, "cpu_only must not use the GPU");
        expect(worst_delta(before, image.pixels) == 0.0F, "cpu_only must leave pixels alone");
    }

    // CPU 기준값.
    const auto cpu = negaflow::imaging::apply_working_tone_adjustments(make_image(), parameters);
    if (cpu.status != negaflow::imaging::WorkingToneAdjustStatus::ok) {
        expect(false, "the CPU tone path must succeed");
        return;
    }

    // ② `allowed` 는 실제로 처리해야 합니다.
    WorkingImage image = make_image();
    const auto outcome = GpuAccelerator::shared().apply_working_tone_adjustments(
        GpuUsePolicy::allowed, image, parameters, {});
    if (!GpuAccelerator::shared().available()) {
        std::cout << "[gpu] accelerator unavailable — the CPU path is the only one here\n";
        expect(!outcome.handled, "an unavailable accelerator must not claim the work");
        return;
    }
    expect(outcome.handled, "the tone path must actually run on the GPU");
    if (!outcome.handled) {
        return;
    }

    // ③ 값과 적용 플래그가 CPU 와 같아야 합니다.
    const float worst = worst_delta(cpu.image.pixels, image.pixels);
    if (worst > tone_tolerance) {
        std::cerr << "FAIL: tone gpu/cpu max delta " << worst << '\n';
        ++failures;
    } else {
        std::cout << "[gpu] pipeline tone max delta " << worst << '\n';
    }
    expect(outcome.info.exposure_applied == cpu.info.exposure_applied, "exposure gate agrees");
    expect(outcome.info.basic_tone_applied == cpu.info.basic_tone_applied, "basic gate agrees");
    expect(
        outcome.info.parametric_curve_applied == cpu.info.parametric_curve_applied,
        "parametric gate agrees");
    expect(
        outcome.info.point_curve_applied == cpu.info.point_curve_applied,
        "point curve gate agrees");
    expect(outcome.info.color_mixer_applied == cpu.info.color_mixer_applied, "mixer gate agrees");
    expect(
        outcome.info.color_grading_applied == cpu.info.color_grading_applied,
        "grading gate agrees");
    expect(
        outcome.info.primary_calibration_applied == cpu.info.primary_calibration_applied,
        "primary gate agrees");
    // 측정 밴드는 **정확히 같을 수 없습니다.** 측정은 기본 톤까지 끝난 이미지의 백분위인데,
    // 그 이미지가 이미 1e-06 급으로 다르므로 정렬 순서가 한 칸 밀릴 수 있습니다.
    // 밴드가 크게 벌어지면 커브가 다른 자리에서 걸린 것이니 그것만 봅니다.
    const auto& gpu_bands = outcome.info.measurement.info.bands;
    const auto& cpu_bands = cpu.info.measurement.info.bands;
    const float band_delta = std::max(
        std::abs(gpu_bands.shadow_low - cpu_bands.shadow_low),
        std::max(
            std::abs(gpu_bands.dark_high - cpu_bands.dark_high),
            std::max(
                std::abs(gpu_bands.light_high - cpu_bands.light_high),
                std::abs(gpu_bands.highlight_high - cpu_bands.highlight_high))));
    if (band_delta > 1.0e-3F) {
        std::cerr << "FAIL: measured band delta " << band_delta << '\n';
        ++failures;
    } else {
        std::cout << "[gpu] pipeline tone band delta " << band_delta << '\n';
    }
}

void tone_no_change_is_a_pass_through() {
    // 아무것도 안 움직이면 CPU 는 원본 그대로 내보냅니다. GPU 도 올리지조차 않아야 합니다.
    const WorkingToneAdjustParameters parameters{};
    WorkingImage image = make_image();
    const std::vector<Rgba32F> before = image.pixels;
    const auto outcome = GpuAccelerator::shared().apply_working_tone_adjustments(
        GpuUsePolicy::allowed, image, parameters, {});
    if (!GpuAccelerator::shared().available()) {
        return;
    }
    expect(outcome.handled, "a no-change request is still handled");
    expect(worst_delta(before, image.pixels) == 0.0F, "a no-change request copies nothing");
}

void denoise_path_runs_on_gpu() {
    FilmScanDenoiseParameters parameters{};
    parameters.strength = 0.6F;
    parameters.film_profile = negaflow::imaging::FilmScanDenoiseFilmProfile::color_negative;

    // ① `cpu_only` 는 손대지 않습니다.
    {
        WorkingImage image = make_image();
        const std::vector<Rgba32F> before = image.pixels;
        const auto outcome = GpuAccelerator::shared().apply_film_scan_denoise(
            GpuUsePolicy::cpu_only, image, parameters);
        expect(!outcome.handled, "cpu_only must not use the GPU for denoise");
        expect(worst_delta(before, image.pixels) == 0.0F, "cpu_only leaves denoise pixels alone");
    }

    const auto cpu =
        negaflow::imaging::apply_film_scan_denoise(make_image(), parameters);
    if (cpu.status != negaflow::imaging::FilmScanDenoiseStatus::ok || !cpu.info.applied) {
        expect(false, "the CPU denoise path must succeed");
        return;
    }

    WorkingImage image = make_image();
    const auto outcome = GpuAccelerator::shared().apply_film_scan_denoise(
        GpuUsePolicy::allowed, image, parameters);
    if (!GpuAccelerator::shared().available()) {
        return;
    }
    expect(outcome.handled, "the denoise path must actually run on the GPU");
    if (!outcome.handled) {
        return;
    }
    expect(outcome.info.applied == cpu.info.applied, "the denoise applied flag agrees");
    // 타일 수가 같아야 합니다 — 다르면 GPU 가 CPU 와 다르게 나눈 것이고, 그 순간 값이 갈립니다.
    expect(
        outcome.info.tiles_processed == cpu.info.tiles_processed,
        "the GPU must split into the same tiles as the CPU");

    const float worst = worst_delta(cpu.image.pixels, image.pixels);
    if (worst > denoise_tolerance) {
        std::cerr << "FAIL: denoise gpu/cpu max delta " << worst << '\n';
        ++failures;
    } else {
        std::cout << "[gpu] pipeline denoise max delta " << worst << '\n';
    }
}

void denoise_below_threshold_is_a_pass_through() {
    FilmScanDenoiseParameters parameters{};
    parameters.strength = 0.0005F;  // 임계 1e-3 아래.
    WorkingImage image = make_image();
    const std::vector<Rgba32F> before = image.pixels;
    const auto outcome = GpuAccelerator::shared().apply_film_scan_denoise(
        GpuUsePolicy::allowed, image, parameters);
    if (!GpuAccelerator::shared().available()) {
        return;
    }
    expect(outcome.handled, "a below-threshold request is still handled");
    expect(!outcome.info.applied, "a below-threshold request is not applied");
    expect(worst_delta(before, image.pixels) == 0.0F, "a below-threshold request copies nothing");
}

}  // namespace

int main() {
    std::cout << "[gpu] accelerator: "
              << (GpuAccelerator::shared().available()
                      ? GpuAccelerator::shared().adapter_description()
                      : "unavailable")
              << '\n';
    tone_path_runs_on_gpu();
    tone_no_change_is_a_pass_through();
    denoise_path_runs_on_gpu();
    denoise_below_threshold_is_a_pass_through();

    if (failures != 0) {
        std::cerr << failures << " gpu accelerator check(s) failed\n";
        return 1;
    }
    std::cout << "gpu accelerator checks passed\n";
    return 0;
}
