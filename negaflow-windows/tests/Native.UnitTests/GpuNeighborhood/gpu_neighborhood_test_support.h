#pragma once

// CPU/GPU 동치 시험 — 이웃 원시연산이 함께 쓰는 것들입니다.
//
// macOS 는 이 자리를 Apple 내장 필터가 채웁니다 — `CIBoxBlur` · `CIGaussianBlur` ·
// `CIMedianFilter` · `CIAreaAverage`. Windows 에는 없어서 우리가 만들어야 하고,
// 가이드 필터 4커널과 `filmScanShrink` 가 여기 물려 있습니다.
//
// ⚠️ CPU 판(`imaging/film_scan_denoise_filters.cpp`)의 필터들은 전부 내부 함수라 여기서
//    직접 부를 수 없습니다. 그래서 **CPU 판과 같은 순서로 도는 참조 구현**을 시험 안에 두고
//    비교합니다. 두 벌이라는 것을 알고 두는 것이고, 그 파일이 바뀌면 여기도 같이 바꿔야
//    합니다. 필터가 공개되면 참조를 지우고 그것을 부르십시오.

#include <cstddef>
#include <cstdint>
#include <vector>

#include "negaflow/core/pixel.h"

namespace gpu_neighborhood_tests {

using negaflow::core::Rgba32F;

extern int failures;

void expect(bool condition, const char* message);

// 커널마다 `1e-5` 로 묶습니다. [`04-gpu-plan.md`](../../../docs/audit/04-gpu-plan.md) 7절.
inline constexpr float tolerance = 1.0e-5F;
// 스레드 그룹 크기(박스 블러 64, 나머지 8×8)의 배수가 아닌 값으로 경계를 봅니다.
inline constexpr std::uint32_t width = 61U;
inline constexpr std::uint32_t height = 37U;

[[nodiscard]] inline std::size_t index_of(
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t stride) noexcept {
    return (static_cast<std::size_t>(y) * stride) + x;
}

// 흐림이 실제로 무언가를 하도록 값이 자주 바뀌는 무늬를 씁니다. 알파는 전부 1 입니다.
[[nodiscard]] std::vector<Rgba32F> make_pattern();

// 알파에 휘도를 담은 무늬입니다. 가이드 필터의 가이드 자리이자, 알파까지 흐리는 경로를
// 의미 있게 시험하는 유일한 입력입니다 — `make_pattern` 의 알파는 상수라 흐려도 그대로입니다.
[[nodiscard]] std::vector<Rgba32F> make_guided_input();

// 채널 넷의 최대 절대 오차입니다.
[[nodiscard]] float worst_delta(
    const std::vector<Rgba32F>& reference,
    const std::vector<Rgba32F>& measured) noexcept;

// 한 줄 보고. 허용치를 넘으면 실패로 셉니다.
void report(const char* label, const char* what, int radius, float worst);

}  // namespace gpu_neighborhood_tests
