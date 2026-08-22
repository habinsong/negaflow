// CPU/GPU 동치 시험 — `filmScanShrink` 와 그 앞의 이웃 원시연산 사슬.
//
// **참조를 옮겨 적지 않습니다.** 진짜 CPU 함수 `apply_film_scan_denoise` 를 그대로
// 부르고 그 결과와 겨룹니다. 이웃 원시연산 시험에서 옮겨 적은 참조가 틀려 있었고
// GPU 가 그 틀린 참조에 맞아 통과했던 일이 있었습니다 — 부를 수 있으면 부릅니다.
//
// GPU 사슬은 `film_scan_denoise_tile.cpp:72-83` 과 같은 순서입니다:
// 리프트 → 가우시안(fine) → 휘도(guide) → 가이드 r3(middle) · r7(coarse)
// → 중앙값(med3) → 중앙값 한 번 더(med5) → 수축 + 되돌리기
//
// 이 시험은 **두 축을 따로** 봅니다. 하나로 합치면 무엇이 틀렸는지 다시 못 가립니다.
//
// ① 타일 — GPU 가 CPU 와 같은 512/18 타일로 도는가, 전체를 한 번에 도는가.
// ② 감마 리프트 — CPU `std::pow` 결과를 올리는가, GPU `pow` 를 쓰는가.
//
// 왜 둘 다 필요한가:
//
// ① 박스 블러는 러닝 섬이라 **수학적으로는 창 안만 보지만 수치적으로는 그 행의 0번
// 화소부터 누적한 반올림을 들고 옵니다.** 에이프런 18 은 필터 지원(가우시안 4 +
// 가이드 7 + 7)으로는 충분하지만 **누적 이력까지 맞추지는 못합니다.**
// 그래서 GPU 도 타일을 나눠야 하고, 이것은 성능 선택이 아니라 값의 조건입니다.
//
// ② HLSL `pow` 는 `exp2(y * log2(x))` 이고 D3D11 은 그 둘에 각각 상대오차 2^-21 을
// 허용합니다. `std::pow` 와 마지막 비트까지 같게 만들 방법이 표준 안에 없습니다.
// 리프트 자체의 차이는 **1~2 ulp** 인데, 사슬 안의 `1 / (variance + 0.001)` 이
// — `variance` 가 `mean(guide²) − mean(guide)²` 라 평탄한 곳에서 자리수가 거의 다
// 상쇄됩니다 — 그것을 수백 배로 키웁니다. macOS 도 같은 식이므로 이것은 이식이
// 만든 문제가 아니라 **알고리즘의 조건수**입니다.
// 출처: https://learn.microsoft.com/en-us/windows/win32/direct3d11/floating-point-rules

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <utility>
#include <vector>

#include "GpuFilmScan/gpu_film_scan_chain.h"
#include "negaflow/gpu/gpu_device.h"
#include "negaflow/imaging/film_scan_denoise.h"

namespace {

using gpu_film_scan_tests::expect;
using gpu_film_scan_tests::LiftSource;
using negaflow::core::Rgba32F;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;
using negaflow::imaging::FilmScanDenoiseFilmProfile;
using negaflow::imaging::FilmScanDenoiseParameters;
using negaflow::imaging::WorkingImage;

// 이식이 맞았는지의 기준입니다 — `04-gpu-plan.md` 7절.
constexpr float ported_tolerance = 1.0e-5F;
// GPU `pow` 로 리프트했을 때의 상한입니다. **목표가 아니라 실측을 담는 그릇**이고, 넘으면
// 무언가 새로 틀어진 것입니다.
constexpr float gpu_lift_tolerance = 1.0e-4F;

// 타일 한 변이 512 입니다. 폭을 그보다 크게 잡아 **타일 경계를 실제로 지나가게** 합니다.
constexpr std::uint32_t width = 600U;
constexpr std::uint32_t height = 130U;

[[nodiscard]] std::size_t index_of(const std::uint32_t x, const std::uint32_t y) noexcept {
    return (static_cast<std::size_t>(y) * width) + x;
}

// 잡음 제거가 실제로 무언가를 하도록 잡음·임펄스·평탄한 면·경계를 모두 담습니다.
[[nodiscard]] std::vector<Rgba32F> make_scan_like_pattern() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::uint32_t seed = (x * 73856093U) ^ (y * 19349663U);
            const std::uint32_t mixed = (seed ^ (seed >> 13U)) * 1274126177U;
            const float noise = static_cast<float>(mixed >> 8U) / 16777216.0F;
            // 넓은 톤 경사 + 세로 경계 + 알갱이 잡음 + 드문 임펄스.
            const float ramp = static_cast<float>(x) / static_cast<float>(width - 1U);
            const float step = (x % 97U) < 48U ? 0.12F : -0.08F;
            const bool impulse = ((x * 7U) + (y * 13U)) % 211U == 0U;
            const float grain = (noise - 0.5F) * 0.06F;
            const float base = std::clamp(ramp + step + grain, 0.0F, 1.0F);
            pixels[index_of(x, y)] = Rgba32F{
                impulse ? 1.0F : base,
                std::clamp(base * 0.85F + (noise - 0.5F) * 0.05F, 0.0F, 1.0F),
                impulse ? 0.0F : std::clamp(0.9F - base + grain, 0.0F, 1.0F),
                // 알파는 CPU 가 손대지 않습니다. 상수가 아닌 값을 넣어 보존을 시험합니다.
                0.25F + 0.5F * ramp};
        }
    }
    return pixels;
}

struct Comparison final {
    float worst{0.0F};
    float worst_alpha{0.0F};
    std::size_t worst_index{0U};
};

[[nodiscard]] Comparison compare(
    const std::vector<Rgba32F>& reference,
    const std::vector<Rgba32F>& measured) noexcept {
    Comparison result{};
    if (measured.size() != reference.size()) {
        // 사슬이 실패해 빈 결과가 온 경우입니다. 이미 `failures` 가 올라가 있습니다.
        result.worst = 1.0F;
        return result;
    }
    for (std::size_t index = 0U; index < reference.size(); ++index) {
        const float largest = std::max(
            std::abs(reference[index].red - measured[index].red),
            std::max(
                std::abs(reference[index].green - measured[index].green),
                std::abs(reference[index].blue - measured[index].blue)));
        if (largest > result.worst) {
            result.worst = largest;
            result.worst_index = index;
        }
        result.worst_alpha =
            std::max(result.worst_alpha, std::abs(reference[index].alpha - measured[index].alpha));
    }
    return result;
}

void report(
    const char* const label,
    const char* const what,
    const char* const note,
    const Comparison& comparison,
    const float limit) {
    if (comparison.worst > limit) {
        std::cerr << "FAIL: " << label << ' ' << what << ' ' << note << " max delta "
                  << comparison.worst << " at (" << (comparison.worst_index % width) << ','
                  << (comparison.worst_index / width) << ") limit " << limit << '\n';
        ++gpu_film_scan_tests::failures;
        return;
    }
    std::cout << "[gpu] " << label << ' ' << what << ' ' << note << " max delta "
              << comparison.worst << '\n';
}

void film_scan_matches_cpu(const GpuDevice& device, const char* const label) {
    const std::vector<Rgba32F> source = make_scan_like_pattern();

    struct Case final {
        FilmScanDenoiseFilmProfile profile;
        float strength;
        float grain_protect;
        const char* what;
    };
    const Case cases[] = {
        {FilmScanDenoiseFilmProfile::color_negative, 0.6F, 0.0F, "color-negative"},
        {FilmScanDenoiseFilmProfile::color_positive, 1.0F, 0.4F, "color-positive"},
        {FilmScanDenoiseFilmProfile::black_and_white_negative, 0.35F, 0.0F, "bw-negative"},
    };

    for (const Case& item : cases) {
        FilmScanDenoiseParameters parameters{};
        parameters.strength = item.strength;
        parameters.film_profile = item.profile;
        parameters.axes.grain_protect = item.grain_protect;

        WorkingImage cpu_image{};
        cpu_image.width = width;
        cpu_image.height = height;
        cpu_image.stride_pixels = width;
        cpu_image.pixels = source;
        const auto cpu =
            negaflow::imaging::apply_film_scan_denoise(std::move(cpu_image), parameters);
        if (cpu.status != negaflow::imaging::FilmScanDenoiseStatus::ok || !cpu.info.applied) {
            expect(false, "the CPU oracle must apply the denoise");
            continue;
        }

        // ① CPU 와 같은 타일 + CPU 리프트 — **이식이 맞았는지**를 재는 자리입니다.
        const Comparison tiled_cpu_lift = compare(
            cpu.image.pixels,
            gpu_film_scan_tests::run_chain(
                device, source, width, height, parameters, LiftSource::cpu));
        report(label, item.what, "tiled cpu-lift", tiled_cpu_lift, ported_tolerance);
        expect(tiled_cpu_lift.worst_alpha == 0.0F, "alpha is preserved exactly");

        // ② CPU 와 같은 타일 + GPU 리프트 — **실제 파이프라인이 쓸 경로**입니다.
        const Comparison tiled_gpu_lift = compare(
            cpu.image.pixels,
            gpu_film_scan_tests::run_chain(
                device, source, width, height, parameters, LiftSource::gpu));
        report(label, item.what, "tiled gpu-lift", tiled_gpu_lift, gpu_lift_tolerance);

        // ③ 타일을 안 나누면 얼마나 벌어지는지. **제품 경로가 아니고**, 타일이 값의
        // 조건이라는 주장을 수치로 남기기 위한 것입니다.
        const Comparison whole_cpu_lift = compare(
            cpu.image.pixels,
            gpu_film_scan_tests::run_chain_whole_image(
                device, source, width, height, parameters, LiftSource::cpu));
        std::cout << "[gpu] " << label << ' ' << item.what << " untiled cpu-lift max delta "
                  << whole_cpu_lift.worst << " at (" << (whole_cpu_lift.worst_index % width) << ','
                  << (whole_cpu_lift.worst_index / width) << ")\n";
        // 타일을 나눈 쪽이 **반드시 더 좋아야** 합니다. 아니면 위 설명이 틀린 것입니다.
        expect(
            tiled_cpu_lift.worst < whole_cpu_lift.worst,
            "tiling like the CPU must beat processing the whole image at once");
    }
}

} // namespace

int main() {
    const GpuDevice warp = GpuDevice::create(GpuDevicePreference::warp_only);
    if (!warp.is_usable()) {
        std::cerr << "FAIL: WARP device is required for these checks\n";
        return 1;
    }
    film_scan_matches_cpu(warp, "warp");

    const GpuDevice hardware = GpuDevice::create(GpuDevicePreference::hardware_only);
    if (hardware.is_usable()) {
        std::cout << "[gpu] hardware: " << hardware.capability().adapter.description.data() << '\n';
        film_scan_matches_cpu(hardware, "hardware");
    } else {
        std::cout << "[gpu] hardware absent, WARP only\n";
    }

    if (gpu_film_scan_tests::failures != 0) {
        std::cerr << gpu_film_scan_tests::failures << " gpu film scan check(s) failed\n";
        return 1;
    }
    std::cout << "gpu film scan checks passed\n";
    return 0;
}
