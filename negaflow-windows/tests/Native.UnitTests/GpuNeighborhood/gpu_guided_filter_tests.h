#pragma once

#include <vector>

#include "gpu_neighborhood_test_support.h"

namespace negaflow::gpu {
class GpuDevice;
}

namespace gpu_neighborhood_tests {

// `film_scan_denoise_types.h:14` 의 `guided_epsilon` 입니다.
inline constexpr float reference_guided_epsilon = 0.001F;

// `guided_base` 를 그대로 옮긴 참조입니다. 입력은 GPU 와 같은 묶음
// `(source.r, source.g, source.b, guide)` 를 씁니다.
[[nodiscard]] std::vector<Rgba32F> reference_guided(
    const std::vector<Rgba32F>& packed,
    int radius);

void guided_filter_matches_reference(const negaflow::gpu::GpuDevice& device, const char* label);

}  // namespace gpu_neighborhood_tests
