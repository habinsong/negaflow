// CPU/GPU 동치 시험 — 노출 · 포인트 커브.
//
// 이 둘이 있어야 우측 인스펙터의 톤 경로 전체가 GPU 에 머문 채로 돕니다.
//
// CPU 판 : `core/pointwise.cpp` `apply_exposure` · `imaging/point_curve.cpp` `apply_point_curves`
// GPU 판 : `gpu/shaders/exposure.hlsl` · `point_curve.hlsl` + `gpu/gpu_stage_kernels.cpp`

#include "negaflow/gpu/gpu_stage_kernels.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>
#include <vector>

#include "negaflow/core/pointwise.h"
#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/imaging/point_curve.h"

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

using negaflow::core::Rgba32F;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;
using negaflow::gpu::GpuExposure;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuPointCurve;
using negaflow::gpu::GpuPointCurveLuts;
using negaflow::gpu::GpuWorkingImage;

constexpr float tolerance = 1.0e-5F;
constexpr std::uint32_t width = 64U;
constexpr std::uint32_t height = 48U;

// 노출은 장면 선형이라 [0,1] 밖 값이 정상입니다. 그것을 일부러 넣습니다.
[[nodiscard]] std::vector<Rgba32F> make_scene() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float u = static_cast<float>(x) / static_cast<float>(width - 1U);
            const float v = static_cast<float>(y) / static_cast<float>(height - 1U);
            pixels[(static_cast<std::size_t>(y) * width) + x] =
                Rgba32F{(u * 1.60F) - 0.20F, v * 1.10F, (1.0F - u) * 0.90F, 1.0F};
        }
    }
    return pixels;
}

[[nodiscard]] float worst_delta(
    const std::vector<Rgba32F>& left,
    const std::vector<Rgba32F>& right) noexcept {
    float worst = 0.0F;
    for (std::size_t index = 0U; index < left.size(); ++index) {
        worst = std::max(worst, std::abs(left[index].red - right[index].red));
        worst = std::max(worst, std::abs(left[index].green - right[index].green));
        worst = std::max(worst, std::abs(left[index].blue - right[index].blue));
        worst = std::max(worst, std::abs(left[index].alpha - right[index].alpha));
    }
    return worst;
}

void exposure_matches_cpu(const GpuDevice& device, const char* const label) {
    GpuExposure kernel{};
    if (GpuExposure::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "exposure kernel must be creatable");
        return;
    }

    const std::vector<Rgba32F> source = make_scene();
    GpuWorkingImage input{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
        GpuImageStatus::ok) {
        expect(false, "exposure source upload must succeed");
        return;
    }
    GpuWorkingImage output{};
    if (GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "exposure destination must be creatable");
        return;
    }

    // macOS `DevelopToneRange.exposure` 는 ±5 입니다. 양 끝과 0 을 봅니다.
    const float stop_cases[] = {0.0F, 0.5F, -0.5F, 2.75F, -3.25F, 5.0F, -5.0F};
    for (const float stops : stop_cases) {
        if (kernel.dispatch(device, input, output, stops) != GpuKernelStatus::ok) {
            expect(false, "exposure dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "exposure download must succeed");
            continue;
        }

        std::vector<Rgba32F> cpu_pixels(source.size());
        const negaflow::core::ConstImageView view{
            source.data(), source.size(), width, height, width};
        const negaflow::core::ImageView out{
            cpu_pixels.data(), cpu_pixels.size(), width, height, width};
        (void)negaflow::core::apply_exposure(view, out, stops);

        const float worst = worst_delta(cpu_pixels, gpu_pixels);
        if (worst > tolerance) {
            std::cerr << "FAIL: " << label << " exposure " << stops << " max delta " << worst
                      << '\n';
            ++failures;
        } else {
            std::cout << "[gpu] " << label << " exposure " << stops << " max delta " << worst
                      << '\n';
        }
    }

    expect(
        kernel.dispatch(
            device, input, output, std::numeric_limits<float>::quiet_NaN()) ==
            GpuKernelStatus::non_finite_parameter,
        "NaN stops are rejected like the CPU path");
    // 큰 스톱은 `exp2` 에서 무한이 됩니다. CPU 판이 거부하므로 GPU 도 거부해야 합니다.
    expect(
        kernel.dispatch(device, input, output, 4000.0F) == GpuKernelStatus::non_finite_parameter,
        "an infinite multiplier is rejected");
}

// 커브 하나를 만듭니다. 끝점 두 개는 항등이라 `has_point_curve_change` 가 거짓이 되므로
// 가운데 점을 넣어 실제로 휘게 합니다.
[[nodiscard]] negaflow::imaging::PointCurve make_curve(const double mid_y) {
    negaflow::imaging::PointCurve curve{};
    curve.points[0] = {0.0, 0.0};
    curve.points[1] = {0.5, mid_y};
    curve.points[2] = {1.0, 1.0};
    curve.point_count = 3U;
    return curve;
}

[[nodiscard]] negaflow::imaging::PointCurve identity_curve() {
    negaflow::imaging::PointCurve curve{};
    curve.points[0] = {0.0, 0.0};
    curve.points[1] = {1.0, 1.0};
    curve.point_count = 2U;
    return curve;
}

struct CurveCase final {
    const char* name;
    negaflow::imaging::PointCurves curves;
};

void point_curve_matches_cpu(const GpuDevice& device, const char* const label) {
    GpuPointCurve kernel{};
    if (GpuPointCurve::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "point curve kernel must be creatable");
        return;
    }

    CurveCase scenarios[4]{};
    scenarios[0].name = "curve_rgb_lift";
    scenarios[0].curves.rgb = make_curve(0.62);
    scenarios[0].curves.red = identity_curve();
    scenarios[0].curves.green = identity_curve();
    scenarios[0].curves.blue = identity_curve();

    scenarios[1].name = "curve_rgb_drop";
    scenarios[1].curves.rgb = make_curve(0.38);
    scenarios[1].curves.red = identity_curve();
    scenarios[1].curves.green = identity_curve();
    scenarios[1].curves.blue = identity_curve();

    scenarios[2].name = "curve_per_channel";
    scenarios[2].curves.rgb = identity_curve();
    scenarios[2].curves.red = make_curve(0.58);
    scenarios[2].curves.green = make_curve(0.50);
    scenarios[2].curves.blue = make_curve(0.42);

    scenarios[3].name = "curve_rgb_and_channels";
    scenarios[3].curves.rgb = make_curve(0.55);
    scenarios[3].curves.red = make_curve(0.60);
    scenarios[3].curves.green = identity_curve();
    scenarios[3].curves.blue = make_curve(0.44);

    const std::vector<Rgba32F> source = make_scene();
    GpuWorkingImage input{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
        GpuImageStatus::ok) {
        expect(false, "curve source upload must succeed");
        return;
    }
    GpuWorkingImage output{};
    if (GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "curve destination must be creatable");
        return;
    }

    for (const CurveCase& scenario : scenarios) {
        // ☠️ LUT 를 시험에서 다시 만들지 않습니다 — CPU 와 같은 함수를 씁니다.
        //    여기서 베껴 쓰면 셰이더가 틀려도 시험이 같이 틀려 통과합니다.
        negaflow::imaging::PointCurveLuts cpu_luts{};
        if (negaflow::imaging::build_point_curve_luts(scenario.curves, cpu_luts) !=
            negaflow::core::KernelStatus::ok) {
            expect(false, "cpu must build the luts for these curves");
            continue;
        }
        GpuPointCurveLuts gpu_luts{};
        for (std::size_t index = 0U; index < GpuPointCurveLuts::lut_size; ++index) {
            gpu_luts.red[index] = cpu_luts.red[index];
            gpu_luts.green[index] = cpu_luts.green[index];
            gpu_luts.blue[index] = cpu_luts.blue[index];
        }

        if (kernel.dispatch(device, input, output, gpu_luts) != GpuKernelStatus::ok) {
            expect(false, "curve dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "curve download must succeed");
            continue;
        }

        std::vector<Rgba32F> cpu_pixels(source.size());
        const negaflow::core::ConstImageView view{
            source.data(), source.size(), width, height, width};
        const negaflow::core::ImageView out{
            cpu_pixels.data(), cpu_pixels.size(), width, height, width};
        if (negaflow::imaging::apply_point_curves(view, out, scenario.curves) !=
            negaflow::core::KernelStatus::ok) {
            expect(false, "cpu point curve reference must succeed");
            continue;
        }

        const float worst = worst_delta(cpu_pixels, gpu_pixels);
        if (worst > tolerance) {
            std::cerr << "FAIL: " << label << ' ' << scenario.name << " max delta " << worst
                      << '\n';
            ++failures;
        } else {
            std::cout << "[gpu] " << label << ' ' << scenario.name << " max delta " << worst
                      << '\n';
        }
    }

    GpuPointCurveLuts bad{};
    bad.green[17] = std::numeric_limits<float>::quiet_NaN();
    expect(
        kernel.dispatch(device, input, output, bad) == GpuKernelStatus::non_finite_parameter,
        "a NaN lut sample is rejected");
}

}  // namespace

int main() {
    const GpuDevice warp = GpuDevice::create(GpuDevicePreference::warp_only);
    if (!warp.is_usable()) {
        std::cerr << "FAIL: WARP device is required for these checks\n";
        return 1;
    }
    exposure_matches_cpu(warp, "warp");
    point_curve_matches_cpu(warp, "warp");

    const GpuDevice hardware = GpuDevice::create(GpuDevicePreference::hardware_only);
    if (hardware.is_usable()) {
        std::cout << "[gpu] hardware: " << hardware.capability().adapter.description.data() << '\n';
        exposure_matches_cpu(hardware, "hardware");
        point_curve_matches_cpu(hardware, "hardware");
    } else {
        std::cout << "[gpu] hardware absent, WARP only\n";
    }

    if (failures != 0) {
        std::cerr << failures << " gpu stage kernel check(s) failed\n";
        return 1;
    }
    std::cout << "gpu stage kernel checks passed\n";
    return 0;
}
