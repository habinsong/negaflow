#pragma once

/* 수동 네거티브 현상 suite 가 공유하는 fixture 와 선언입니다. */

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/manual_negative_developer.h"

#include <array>
#include <cstdint>
#include <vector>

namespace manual_negative_tests {

// 실패 개수는 suite 전체가 공유합니다.
extern int failures;

void expect(bool condition, const char* message);

[[nodiscard]] bool pixels_equal(
    const negaflow::core::Rgba32F& left,
    const negaflow::core::Rgba32F& right) noexcept;

[[nodiscard]] bool images_equal(
    const std::vector<negaflow::core::Rgba32F>& left,
    const std::vector<negaflow::core::Rgba32F>& right) noexcept;

// 합성 프레임들입니다. 자동 베이스 판정이 어느 경로로 가는지 보려면 서로 다른
// 가장자리·띠·장면 배치가 필요합니다.
negaflow::imaging::WorkingImage make_working_image();
negaflow::imaging::WorkingImage make_scene_working_image();

// 바랜 네거티브 - 밀도 범위가 진짜로 좁습니다.
negaflow::imaging::WorkingImage make_faded_scene_working_image();
negaflow::imaging::WorkingImage make_affine_proxy_scene_image();
negaflow::imaging::WorkingImage make_affine_auto_base_image();
negaflow::imaging::WorkingImage make_auto_base_image(const negaflow::core::Rgba32F& base);
negaflow::imaging::WorkingImage make_auto_base_component_with_luma_outliers();
negaflow::imaging::WorkingImage make_auto_base_component_order_image();
negaflow::imaging::WorkingImage make_auto_base_double_luma_boundary_image();
negaflow::imaging::WorkingImage make_auto_base_edge_fraction_image();
negaflow::imaging::WorkingImage make_scene_edge_fallback_image();
negaflow::imaging::WorkingImage make_affine_scene_edge_fallback_image();
negaflow::imaging::WorkingImage make_uniform_working_image(
    negaflow::core::Rgba32F pixel,
    std::uint32_t width = 64U,
    std::uint32_t height = 16U);

// suite: 채도, 필름 스톡 프리셋, 수동 현상, 자동 베이스 판정, 실패 경로.
void test_muted_scene_vibrance();
void test_film_stock_presets();
void test_manual_negative_development();
void test_auto_negative_base_resolution();
void test_invalid_manual_inputs_fail_closed();

}  // namespace manual_negative_tests
