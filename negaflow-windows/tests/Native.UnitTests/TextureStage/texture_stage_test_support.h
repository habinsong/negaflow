#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/texture_stage.h"

#include <cstdint>
#include <filesystem>
#include <vector>

namespace texture_stage_tests {

// 실패 개수는 suite 전체가 공유합니다. 각 번역 단위가 자기 것을 세면 main 이 합계를 낼 수
// 없습니다.
extern int failures;

void expect(bool condition, const char* message);

[[nodiscard]] negaflow::imaging::WorkingImage texture_patch(
    std::uint32_t width = 64U,
    std::uint32_t height = 48U);

[[nodiscard]] negaflow::imaging::WorkingImage halation_patch();

[[nodiscard]] float luma(negaflow::core::Rgba32F value) noexcept;

[[nodiscard]] float mean_luma(
    const negaflow::imaging::WorkingImage& image) noexcept;

// 국소 잡음 세기입니다. 그레인이 실제로 얹혔는지 보려면 전역 평균이 아니라 이것을 봅니다.
[[nodiscard]] float local_noise(
    const negaflow::imaging::WorkingImage& image) noexcept;

[[nodiscard]] float mean_edge(
    const negaflow::imaging::WorkingImage& image) noexcept;

[[nodiscard]] float mean_chroma(
    const negaflow::imaging::WorkingImage& image) noexcept;

[[nodiscard]] float region_mean(
    const negaflow::imaging::WorkingImage& image,
    std::uint32_t x0,
    std::uint32_t y0,
    std::uint32_t width,
    std::uint32_t height) noexcept;

[[nodiscard]] bool same_pixels(
    const std::vector<negaflow::core::Rgba32F>& left,
    const std::vector<negaflow::core::Rgba32F>& right) noexcept;

// golden 파일에서 RGBA float 이미지를 읽습니다.
[[nodiscard]] negaflow::imaging::WorkingImage load_rgba_f32(
    const std::filesystem::path& path);

[[nodiscard]] float max_abs_difference(
    const negaflow::imaging::WorkingImage& actual,
    const negaflow::imaging::WorkingImage& expected) noexcept;

// CoreImage 가우시안을 직접 셈해 둔 참조입니다. 우리 구현과 대조합니다.
[[nodiscard]] negaflow::imaging::WorkingImage direct_coreimage_gaussian(
    const negaflow::imaging::WorkingImage& input,
    float radius);

void expect_coreimage_close(
    const negaflow::imaging::WorkingImage& actual,
    const negaflow::imaging::WorkingImage& expected,
    const char* message);

[[nodiscard]] negaflow::imaging::WorkingImage mixed(
    const negaflow::imaging::WorkingImage& source,
    const negaflow::imaging::WorkingImage& blurred,
    float amount);

// 조작 계약: 항등·잘못된 값·그레인·디테일·헐레이션·비네트·출력 샤프닝.
void test_identity_and_invalid_controls();
void test_grain_and_detail_controls();
void test_halation_and_vignette();
void test_output_sharpening();

// golden 대조: macOS CoreImage 필터와 화소로 맞춥니다.
void test_coreimage_filter_goldens(const std::filesystem::path& golden_root);

}  // namespace texture_stage_tests
