// CPU/GPU 동치 시험 — 색 커널.
//
// macOS  : `ChromabaseMetalKernels.swift:101` `colorGrade`
// CPU 판 : `imaging/color_grading.cpp` `apply_color_grading`
// GPU 판 : `gpu/shaders/color_grade.hlsl` + `gpu/gpu_color_kernels.cpp`
//
// 허용 오차 `1e-5` 는 float32 반올림 범위입니다. 이보다 벌어지면 반올림이 아니라 이식 실수입니다 —
// 오차를 늘리지 말고 커널을 고치십시오.

#include "negaflow/gpu/gpu_color_kernels.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>
#include <string_view>
#include <utility>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/imaging/color_grading.h"
#include "negaflow/imaging/color_mixer.h"
#include "negaflow/imaging/bw_toning.h"
#include "negaflow/imaging/primary_calibration.h"

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

using negaflow::core::Rgba32F;
using negaflow::gpu::GpuColorGrade;
using negaflow::gpu::GpuColorGradeSetup;
using negaflow::gpu::GpuColorMixer;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuWorkingImage;

constexpr float tolerance = 1.0e-5F;
constexpr std::uint32_t width = 64U;
constexpr std::uint32_t height = 48U;

[[nodiscard]] std::vector<Rgba32F> make_ramp() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float u = static_cast<float>(x) / static_cast<float>(width - 1U);
            const float v = static_cast<float>(y) / static_cast<float>(height - 1U);
            pixels[(static_cast<std::size_t>(y) * width) + x] =
                Rgba32F{(u * 1.20F) - 0.10F, v, (1.0F - u) * (0.20F + (0.80F * v)), 1.0F};
        }
    }
    return pixels;
}

struct Case final {
    const char* name;
    negaflow::imaging::ColorGradingParameters parameters;
};

// 세 영역과 blending/balance 를 따로따로 밀어 각 가중치 가지를 지나게 합니다.
const Case cases[] = {
    {"grade_shadows", {{35.0F, 0.6F, 0.2F}, {}, {}, 0.5F, 0.0F}},
    {"grade_midtones", {{}, {210.0F, 0.5F, -0.3F}, {}, 0.5F, 0.0F}},
    {"grade_highlights", {{}, {}, {120.0F, 0.7F, 0.25F}, 0.5F, 0.0F}},
    {"grade_narrow_blend", {{35.0F, 0.4F, 0.1F}, {210.0F, 0.4F, 0.0F}, {120.0F, 0.4F, -0.1F}, 0.0F, 0.0F}},
    {"grade_wide_blend", {{35.0F, 0.4F, 0.1F}, {210.0F, 0.4F, 0.0F}, {120.0F, 0.4F, -0.1F}, 1.0F, 0.0F}},
    {"grade_balance_low", {{35.0F, 0.5F, 0.2F}, {}, {120.0F, 0.5F, -0.2F}, 0.5F, -1.0F}},
    {"grade_balance_high", {{35.0F, 0.5F, 0.2F}, {}, {120.0F, 0.5F, -0.2F}, 0.5F, 1.0F}},
    {"grade_all", {{20.0F, 0.8F, 0.3F}, {180.0F, 0.6F, -0.25F}, {300.0F, 0.7F, 0.15F}, 0.35F, 0.4F}},
};

void grade_matches_cpu(const GpuDevice& device, const char* const label) {
    GpuColorGrade kernel{};
    if (GpuColorGrade::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "grade kernel must be creatable");
        return;
    }

    const std::vector<Rgba32F> source = make_ramp();
    GpuWorkingImage input{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
        GpuImageStatus::ok) {
        expect(false, "grade source upload must succeed");
        return;
    }
    GpuWorkingImage output{};
    if (GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "grade destination must be creatable");
        return;
    }

    for (const Case& scenario : cases) {
        // ☠️ 준비 계산을 시험에서 다시 구현하지 않습니다 — CPU 와 같은 함수를 씁니다.
        //    여기서 베껴 쓰면 셰이더가 틀려도 시험이 같이 틀려 통과합니다.
        const negaflow::imaging::ColorGradingSetup cpu_setup =
            negaflow::imaging::prepare_color_grading(scenario.parameters);
        GpuColorGradeSetup gpu_setup{};
        for (int index = 0; index < 3; ++index) {
            gpu_setup.shadow_offset[index] = cpu_setup.shadow_offset[index];
            gpu_setup.midtone_offset[index] = cpu_setup.midtone_offset[index];
            gpu_setup.highlight_offset[index] = cpu_setup.highlight_offset[index];
        }
        gpu_setup.pivot = cpu_setup.pivot;
        gpu_setup.width = cpu_setup.width;

        if (kernel.dispatch(device, input, output, gpu_setup) != GpuKernelStatus::ok) {
            expect(false, "grade dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "grade download must succeed");
            continue;
        }

        std::vector<Rgba32F> cpu_pixels(source.size());
        const negaflow::core::ConstImageView view{
            source.data(), source.size(), width, height, width};
        const negaflow::core::ImageView out{
            cpu_pixels.data(), cpu_pixels.size(), width, height, width};
        (void)negaflow::imaging::apply_color_grading(view, out, scenario.parameters);

        float worst = 0.0F;
        for (std::size_t index = 0U; index < cpu_pixels.size(); ++index) {
            worst = std::max(worst, std::abs(cpu_pixels[index].red - gpu_pixels[index].red));
            worst = std::max(worst, std::abs(cpu_pixels[index].green - gpu_pixels[index].green));
            worst = std::max(worst, std::abs(cpu_pixels[index].blue - gpu_pixels[index].blue));
            worst = std::max(worst, std::abs(cpu_pixels[index].alpha - gpu_pixels[index].alpha));
        }
        if (worst > tolerance) {
            std::cerr << "FAIL: " << label << ' ' << scenario.name << " max delta " << worst
                      << '\n';
            ++failures;
        } else {
            std::cout << "[gpu] " << label << ' ' << scenario.name << " max delta " << worst
                      << '\n';
        }
    }

    GpuColorGradeSetup bad{};
    bad.pivot = std::numeric_limits<float>::quiet_NaN();
    expect(
        kernel.dispatch(device, input, output, bad) == GpuKernelStatus::non_finite_parameter,
        "NaN pivot is rejected");

    // 폭 0 은 CPU 판에서 0 나누기입니다. 조용히 값을 끼워 넣지 말고 거절해야 합니다.
    GpuColorGradeSetup zero_width{};
    zero_width.width = 0.0F;
    expect(
        kernel.dispatch(device, input, output, zero_width) == GpuKernelStatus::non_finite_parameter,
        "zero width is rejected rather than patched");
}

// 컬러 믹서 — macOS `colorMixerHSL`. 밴드 8개마다 색상/채도/광도.
struct MixerCase final {
    const char* name;
    int band;          // -1 이면 전 밴드
    float hue;
    float saturation;
    float luminance;
};

const MixerCase mixer_cases[] = {
    {"mixer_neutral", -1, 0.0F, 0.0F, 0.0F},
    {"mixer_red_hue", 0, 0.8F, 0.0F, 0.0F},
    {"mixer_orange_sat", 1, 0.0F, 0.7F, 0.0F},
    {"mixer_yellow_lum", 2, 0.0F, 0.0F, 0.6F},
    {"mixer_green_all", 3, -0.5F, -0.4F, 0.3F},
    {"mixer_aqua", 4, 0.4F, 0.5F, -0.5F},
    {"mixer_blue", 5, -0.9F, 0.9F, 0.0F},
    {"mixer_purple", 6, 0.3F, -0.8F, 0.4F},
    {"mixer_magenta_wrap", 7, 0.95F, 0.2F, -0.2F},
    {"mixer_every_band", -1, 0.35F, -0.25F, 0.2F},
};

void mixer_matches_cpu(const GpuDevice& device, const char* const label) {
    GpuColorMixer kernel{};
    if (GpuColorMixer::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "mixer kernel must be creatable");
        return;
    }

    const std::vector<Rgba32F> source = make_ramp();
    GpuWorkingImage input{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
        GpuImageStatus::ok) {
        expect(false, "mixer source upload must succeed");
        return;
    }
    GpuWorkingImage output{};
    if (GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "mixer destination must be creatable");
        return;
    }

    for (const MixerCase& scenario : mixer_cases) {
        negaflow::imaging::ColorMixerParameters cpu_parameters{};
        negaflow::gpu::GpuColorMixerParameters gpu_parameters{};
        for (std::size_t band = 0U; band < negaflow::imaging::color_mixer_band_count; ++band) {
            const bool touched =
                scenario.band < 0 || static_cast<std::size_t>(scenario.band) == band;
            if (!touched) {
                continue;
            }
            cpu_parameters.hue[band] = scenario.hue;
            cpu_parameters.saturation[band] = scenario.saturation;
            cpu_parameters.luminance[band] = scenario.luminance;
            gpu_parameters.hue[band] = scenario.hue;
            gpu_parameters.saturation[band] = scenario.saturation;
            gpu_parameters.luminance[band] = scenario.luminance;
        }

        if (kernel.dispatch(device, input, output, gpu_parameters) != GpuKernelStatus::ok) {
            expect(false, "mixer dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "mixer download must succeed");
            continue;
        }

        std::vector<Rgba32F> cpu_pixels(source.size());
        const negaflow::core::ConstImageView view{
            source.data(), source.size(), width, height, width};
        const negaflow::core::ImageView out{
            cpu_pixels.data(), cpu_pixels.size(), width, height, width};
        (void)negaflow::imaging::apply_color_mixer(view, out, cpu_parameters);

        float worst = 0.0F;
        for (std::size_t index = 0U; index < cpu_pixels.size(); ++index) {
            worst = std::max(worst, std::abs(cpu_pixels[index].red - gpu_pixels[index].red));
            worst = std::max(worst, std::abs(cpu_pixels[index].green - gpu_pixels[index].green));
            worst = std::max(worst, std::abs(cpu_pixels[index].blue - gpu_pixels[index].blue));
            worst = std::max(worst, std::abs(cpu_pixels[index].alpha - gpu_pixels[index].alpha));
        }
        if (worst > tolerance) {
            std::cerr << "FAIL: " << label << ' ' << scenario.name << " max delta " << worst
                      << '\n';
            ++failures;
        } else {
            std::cout << "[gpu] " << label << ' ' << scenario.name << " max delta " << worst
                      << '\n';
        }
    }

    negaflow::gpu::GpuColorMixerParameters bad{};
    bad.saturation[3] = std::numeric_limits<float>::quiet_NaN();
    expect(
        kernel.dispatch(device, input, output, bad) == GpuKernelStatus::non_finite_parameter,
        "NaN mixer band is rejected");
}

// 원색 보정 — macOS `calibrationPrimaries`. 믹서와 모양은 같지만 상수가 다르고 광도가 없습니다.
struct PrimaryCase final {
    const char* name;
    negaflow::imaging::PrimaryCalibrationParameters parameters;
};

const PrimaryCase primary_cases[] = {
    {"primary_neutral", {}},
    {"primary_red_hue", {0.9F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F}},
    {"primary_red_sat", {0.0F, 0.8F, 0.0F, 0.0F, 0.0F, 0.0F}},
    {"primary_green", {0.0F, 0.0F, -0.7F, 0.5F, 0.0F, 0.0F}},
    {"primary_blue", {0.0F, 0.0F, 0.0F, 0.0F, 0.6F, -0.9F}},
    {"primary_all", {0.4F, -0.3F, -0.5F, 0.35F, 0.25F, 0.45F}},
};

void primary_matches_cpu(const GpuDevice& device, const char* const label) {
    negaflow::gpu::GpuPrimaryCalibration kernel{};
    if (negaflow::gpu::GpuPrimaryCalibration::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "primary kernel must be creatable");
        return;
    }

    const std::vector<Rgba32F> source = make_ramp();
    GpuWorkingImage input{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
        GpuImageStatus::ok) {
        expect(false, "primary source upload must succeed");
        return;
    }
    GpuWorkingImage output{};
    if (GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "primary destination must be creatable");
        return;
    }

    for (const PrimaryCase& scenario : primary_cases) {
        const negaflow::gpu::GpuPrimaryCalibrationParameters gpu_parameters{
            scenario.parameters.red_hue,
            scenario.parameters.red_saturation,
            scenario.parameters.green_hue,
            scenario.parameters.green_saturation,
            scenario.parameters.blue_hue,
            scenario.parameters.blue_saturation};

        if (kernel.dispatch(device, input, output, gpu_parameters) != GpuKernelStatus::ok) {
            expect(false, "primary dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "primary download must succeed");
            continue;
        }

        std::vector<Rgba32F> cpu_pixels(source.size());
        const negaflow::core::ConstImageView view{
            source.data(), source.size(), width, height, width};
        const negaflow::core::ImageView out{
            cpu_pixels.data(), cpu_pixels.size(), width, height, width};
        (void)negaflow::imaging::apply_primary_calibration(view, out, scenario.parameters);

        float worst = 0.0F;
        for (std::size_t index = 0U; index < cpu_pixels.size(); ++index) {
            worst = std::max(worst, std::abs(cpu_pixels[index].red - gpu_pixels[index].red));
            worst = std::max(worst, std::abs(cpu_pixels[index].green - gpu_pixels[index].green));
            worst = std::max(worst, std::abs(cpu_pixels[index].blue - gpu_pixels[index].blue));
            worst = std::max(worst, std::abs(cpu_pixels[index].alpha - gpu_pixels[index].alpha));
        }
        if (worst > tolerance) {
            std::cerr << "FAIL: " << label << ' ' << scenario.name << " max delta " << worst
                      << '\n';
            ++failures;
        } else {
            std::cout << "[gpu] " << label << ' ' << scenario.name << " max delta " << worst
                      << '\n';
        }
    }

    negaflow::gpu::GpuPrimaryCalibrationParameters bad{};
    bad.green_hue = std::numeric_limits<float>::quiet_NaN();
    expect(
        kernel.dispatch(device, input, output, bad) == GpuKernelStatus::non_finite_parameter,
        "NaN primary control is rejected");
}

// 흑백 조색 — macOS `bwToning`. CPU 판은 조색을 꺼도 **먼저 중성화**하므로 그 경우까지 봅니다.
struct BwCase final {
    const char* name;
    negaflow::imaging::BwToningParameters parameters;
};

const BwCase bw_cases[] = {
    {"bw_none", {negaflow::imaging::BwToningMode::none, 285.0, 34.0, 0.0}},
    // 모드는 켰지만 강도가 임계(1e-4) 아래 — CPU 는 중성화만 합니다.
    {"bw_below_threshold", {negaflow::imaging::BwToningMode::sepia, 285.0, 34.0, 5.0e-5}},
    {"bw_selenium_half", {negaflow::imaging::BwToningMode::selenium, 285.0, 34.0, 0.5}},
    {"bw_selenium_full", {negaflow::imaging::BwToningMode::selenium, 285.0, 34.0, 1.0}},
    {"bw_sepia_half", {negaflow::imaging::BwToningMode::sepia, 285.0, 34.0, 0.5}},
    {"bw_sepia_full", {negaflow::imaging::BwToningMode::sepia, 285.0, 34.0, 1.0}},
    {"bw_custom_hues", {negaflow::imaging::BwToningMode::sepia, 200.0, 90.0, 0.8}},
};

void bw_matches_cpu(const GpuDevice& device, const char* const label) {
    negaflow::gpu::GpuBwToning kernel{};
    if (negaflow::gpu::GpuBwToning::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "bw kernel must be creatable");
        return;
    }

    const std::vector<Rgba32F> source = make_ramp();
    GpuWorkingImage input{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
        GpuImageStatus::ok) {
        expect(false, "bw source upload must succeed");
        return;
    }
    GpuWorkingImage output{};
    if (GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "bw destination must be creatable");
        return;
    }

    for (const BwCase& scenario : bw_cases) {
        // ☠️ 색조 계산을 시험에서 다시 구현하지 않습니다 — CPU 와 같은 함수를 씁니다.
        const negaflow::imaging::BwToningSetup cpu_setup =
            negaflow::imaging::prepare_bw_toning(scenario.parameters);
        negaflow::gpu::GpuBwToningSetup gpu_setup{};
        for (int index = 0; index < 3; ++index) {
            gpu_setup.shadow_tint[index] = cpu_setup.shadow_tint[index];
            gpu_setup.highlight_tint[index] = cpu_setup.highlight_tint[index];
        }
        gpu_setup.strength = cpu_setup.strength;
        gpu_setup.mode = cpu_setup.mode;
        gpu_setup.tone = cpu_setup.tone;

        if (kernel.dispatch(device, input, output, gpu_setup) != GpuKernelStatus::ok) {
            expect(false, "bw dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "bw download must succeed");
            continue;
        }

        // CPU 판은 이미지를 값으로 받아 제자리에서 바꿉니다.
        negaflow::imaging::WorkingImage cpu_image{};
        cpu_image.width = width;
        cpu_image.height = height;
        cpu_image.stride_pixels = width;
        cpu_image.pixels = source;
        const negaflow::imaging::BwToningResult cpu_result = negaflow::imaging::apply_bw_toning(
            std::move(cpu_image),
            negaflow::imaging::NegativeFilmType::black_and_white,
            scenario.parameters);
        if (cpu_result.status != negaflow::imaging::BwToningStatus::ok) {
            expect(false, "cpu bw reference must succeed");
            continue;
        }

        float worst = 0.0F;
        for (std::size_t index = 0U; index < gpu_pixels.size(); ++index) {
            const Rgba32F& cpu = cpu_result.image.pixels[index];
            worst = std::max(worst, std::abs(cpu.red - gpu_pixels[index].red));
            worst = std::max(worst, std::abs(cpu.green - gpu_pixels[index].green));
            worst = std::max(worst, std::abs(cpu.blue - gpu_pixels[index].blue));
            worst = std::max(worst, std::abs(cpu.alpha - gpu_pixels[index].alpha));
        }
        if (worst > tolerance) {
            std::cerr << "FAIL: " << label << ' ' << scenario.name << " max delta " << worst
                      << '\n';
            ++failures;
        } else {
            std::cout << "[gpu] " << label << ' ' << scenario.name << " max delta " << worst
                      << '\n';
        }
    }
}

}  // namespace

int main() {
    const GpuDevice warp = GpuDevice::create(GpuDevicePreference::warp_only);
    if (!warp.is_usable()) {
        std::cerr << "FAIL: WARP device is required for these checks\n";
        return 1;
    }
    grade_matches_cpu(warp, "warp");
    mixer_matches_cpu(warp, "warp");
    primary_matches_cpu(warp, "warp");
    bw_matches_cpu(warp, "warp");

    const GpuDevice hardware = GpuDevice::create(GpuDevicePreference::hardware_only);
    if (hardware.is_usable()) {
        std::cout << "[gpu] hardware: " << hardware.capability().adapter.description.data() << '\n';
        grade_matches_cpu(hardware, "hardware");
        mixer_matches_cpu(hardware, "hardware");
        primary_matches_cpu(hardware, "hardware");
        bw_matches_cpu(hardware, "hardware");
    } else {
        std::cout << "[gpu] hardware absent, WARP only\n";
    }

    if (failures != 0) {
        std::cerr << failures << " gpu color kernel check(s) failed\n";
        return 1;
    }
    std::cout << "gpu color kernel checks passed\n";
    return 0;
}
