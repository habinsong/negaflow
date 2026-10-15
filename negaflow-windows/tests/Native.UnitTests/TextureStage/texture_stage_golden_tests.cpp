#include "texture_stage_test_support.h"

#include "negaflow/imaging/coreimage_gaussian.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <utility>
#include <vector>

namespace texture_stage_tests {

void test_coreimage_filter_goldens(const std::filesystem::path& golden_root) {
    const auto input = load_rgba_f32(golden_root / L"coreimage-filter-input-256x256.f32");
    struct GaussianCase final {
        float radius;
        const wchar_t* file;
    };
    constexpr GaussianCase gaussian_cases[]{
        {1.00F, L"cigaussianblur-radius1.0-256x256.f32"},
        {1.30F, L"cigaussianblur-radius1.3-256x256.f32"},
        {2.40F, L"cigaussianblur-radius2.4-256x256.f32"},
        {4.00F, L"cigaussianblur-clarity-0.00-radius4.0-256x256.f32"},
        {7.00F, L"cigaussianblur-clarity-0.50-radius7.0-256x256.f32"},
        {10.00F, L"cigaussianblur-clarity-1.00-radius10.0-256x256.f32"},
    };
    for (const GaussianCase& entry : gaussian_cases) {
        expect_coreimage_close(
            direct_coreimage_gaussian(input, entry.radius),
            load_rgba_f32(golden_root / entry.file),
            "Core Image Gaussian radius follows the macOS golden");
    }

    // 부분 대비는 2026-10-15 부터 감마 휘도 가이디드 필터(detail_enhancement)라 Core Image 언샤프·
    // 흐림 섞기 기준값이 없습니다 — 동작 계약은 macOS `DetailEnhancementTests` 와 같은 픽스처의
    // `detail_enhancement_tests.cpp` 가 묶습니다.

    struct OutputCase final {
        negaflow::imaging::OutputSharpeningMedium medium;
        std::uint32_t dpi;
        const wchar_t* file;
    };
    constexpr OutputCase output_cases[]{
        {negaflow::imaging::OutputSharpeningMedium::screen, 144U,
         L"ciunsharpmask-export-screen-dpi144-strength1-256x256.f32"},
        {negaflow::imaging::OutputSharpeningMedium::matte_paper, 300U,
         L"ciunsharpmask-export-matte-dpi300-strength1-256x256.f32"},
        {negaflow::imaging::OutputSharpeningMedium::glossy_paper, 300U,
         L"ciunsharpmask-export-glossy-dpi300-strength1-256x256.f32"},
    };
    for (const OutputCase& entry : output_cases) {
        negaflow::imaging::OutputSharpeningParameters parameters{};
        parameters.medium = entry.medium;
        parameters.dpi = entry.dpi;
        parameters.strength = 1.0F;
        const auto actual = negaflow::imaging::apply_output_sharpening(input, parameters);
        const auto expected = load_rgba_f32(golden_root / entry.file);
        expect(actual.status == negaflow::imaging::TextureStageStatus::ok,
               "output sharpening execution succeeds");
        expect_coreimage_close(
            actual.image,
            expected,
            "output sharpening follows the Core Image unsharp golden");
    }
}

}  // namespace texture_stage_tests
