// macOS `ChromabaseMetalKernels.swift:826` `digitalBWFilm` — CPU `imaging/digital_bw_emulsion_response.cpp`.
//
// 허용 오차 `1e-5` 는 float32 반올림 범위입니다 — 넘으면 커널을 고치십시오.

#include "gpu_color_kernel_test_support.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>
#include <string_view>
#include <utility>
#include <vector>

#include "negaflow/gpu/gpu_color_kernels.h"
#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/imaging/digital_bw_emulsion_response.h"

namespace gpu_color_kernel_tests {
namespace {

using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuWorkingImage;

struct DigitalBwCase final {
    const char* name;
    negaflow::imaging::DigitalBwEmulsionResponseParameters parameters;
};

const DigitalBwCase digital_bw_cases[] = {
    // 프로파일 없음 — CPU 는 원본을 그대로 복사합니다.
    {"dbw_none", {negaflow::imaging::FilmEmulation::none, 1.0}},
    {"dbw_half", {negaflow::imaging::FilmEmulation::tri_x_400, 0.5}},
    {"dbw_full", {negaflow::imaging::FilmEmulation::tri_x_400, 1.0}},
    {"dbw_hp5", {negaflow::imaging::FilmEmulation::hp5_plus, 0.8}},
    {"dbw_tmax", {negaflow::imaging::FilmEmulation::tmax_100, 0.65}},
};

} // namespace

void digital_bw_matches_cpu(const GpuDevice& device, const char* const label) {
    negaflow::gpu::GpuDigitalBwFilm kernel{};
    if (negaflow::gpu::GpuDigitalBwFilm::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "digital bw kernel must be creatable");
        return;
    }

    const std::vector<Rgba32F> source = make_ramp();
    GpuWorkingImage input{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
        GpuImageStatus::ok) {
        expect(false, "digital bw source upload must succeed");
        return;
    }
    GpuWorkingImage output{};
    if (GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "digital bw destination must be creatable");
        return;
    }

    for (const DigitalBwCase& scenario : digital_bw_cases) {
        // 응답 계수를 시험에서 다시 만들지 않습니다 — CPU 와 같은 함수를 씁니다.
        const negaflow::imaging::DigitalBwEmulsionSetup cpu_setup =
            negaflow::imaging::prepare_digital_bw_emulsion_response(scenario.parameters);
        negaflow::gpu::GpuDigitalBwFilmSetup gpu_setup{};
        for (int index = 0; index < 3; ++index) {
            gpu_setup.weights[index] = cpu_setup.weights[index];
        }
        gpu_setup.contrast = cpu_setup.contrast;
        gpu_setup.toe = cpu_setup.toe;
        gpu_setup.shoulder = cpu_setup.shoulder;
        gpu_setup.deepen = cpu_setup.deepen;
        gpu_setup.black = cpu_setup.black;
        gpu_setup.white = cpu_setup.white;
        gpu_setup.intensity = cpu_setup.intensity;
        gpu_setup.active = cpu_setup.active;

        if (kernel.dispatch(device, input, output, gpu_setup) != GpuKernelStatus::ok) {
            expect(false, "digital bw dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "digital bw download must succeed");
            continue;
        }

        std::vector<Rgba32F> cpu_pixels(source.size());
        const negaflow::core::ConstImageView view{
            source.data(), source.size(), width, height, width};
        const negaflow::core::ImageView out{
            cpu_pixels.data(), cpu_pixels.size(), width, height, width};
        const negaflow::core::KernelStatus cpu_status =
            negaflow::imaging::apply_digital_bw_emulsion_response(view, out, scenario.parameters);
        if (cpu_status != negaflow::core::KernelStatus::ok) {
            // 프로파일이 없는 경우는 CPU 가 invalid_parameter 를 냅니다. 그때 GPU 도
            // 원본 복사이므로 결과 비교는 의미가 있습니다 — 원본과 같아야 합니다.
            bool identical = true;
            for (std::size_t index = 0U; index < source.size() && identical; ++index) {
                identical = source[index].red == gpu_pixels[index].red &&
                    source[index].green == gpu_pixels[index].green &&
                    source[index].blue == gpu_pixels[index].blue;
            }
            expect(identical, "inactive digital bw must pass the source through untouched");
            std::cout << "[gpu] " << label << ' ' << scenario.name << " pass-through\n";
            continue;
        }

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
}

} // namespace gpu_color_kernel_tests
