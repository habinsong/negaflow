#pragma once

#include <vector>

#include "gpu_neighborhood_test_support.h"

namespace negaflow::gpu {
class GpuDevice;
}

namespace gpu_neighborhood_tests {

// `film_scan_denoise_filters.cpp:175` `box_blur(std::vector<Rgb>&)` 를 그대로 옮긴 참조입니다.
// 누적은 `(sum + a) - b` — `Rgb` 이항 연산자가 왼쪽부터 묶이기 때문입니다. 알파는 원본을
// 그대로 씁니다(CPU 의 `Rgb` 는 알파를 들고 다니지 않습니다).
[[nodiscard]] std::vector<Rgba32F> reference_box_blur(
    const std::vector<Rgba32F>& source,
    int radius);

// 알파에 담긴 스칼라까지 흐리는 참조입니다(GPU 의 `blur_alpha = true` 에 해당).
//
// ☠️ RGB 와 알파의 괄호가 다릅니다. `guided_base` 가 RGB 자리에는 `Rgb` 판을, 알파 자리
//    (guide·guide²)에는 `float` 판을 쓰기 때문입니다. 통일하면 가이드 필터 결과가 반경 1 에서
//    3.8e-05 까지 벌어집니다 — 실측입니다.
[[nodiscard]] std::vector<Rgba32F> reference_box_blur_four(
    const std::vector<Rgba32F>& source,
    int radius);

void box_blur_matches_reference(const negaflow::gpu::GpuDevice& device, const char* label);
void box_blur_alpha_matches_reference(const negaflow::gpu::GpuDevice& device, const char* label);

}  // namespace gpu_neighborhood_tests
