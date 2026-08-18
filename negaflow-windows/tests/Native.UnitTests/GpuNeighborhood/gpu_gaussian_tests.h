#pragma once

#include <vector>

#include "gpu_neighborhood_test_support.h"
#include "negaflow/gpu/gpu_neighborhood.h"

namespace negaflow::gpu {
class GpuDevice;
}

namespace gpu_neighborhood_tests {

// CPU 두 판(`film_scan_denoise_filters.cpp:13` · `texture_stage_gaussian.h:22`)을 한 벌로
// 옮긴 참조입니다. 가중치는 호출부가 `GpuGaussianBlur::weights_for_sigma` 로 만들어 넘깁니다.
[[nodiscard]] std::vector<Rgba32F> reference_gaussian(
    const std::vector<Rgba32F>& source,
    const std::vector<float>& weights,
    negaflow::gpu::GpuGaussianEdgeMode edge_mode,
    bool blur_alpha);

void gaussian_matches_reference(const negaflow::gpu::GpuDevice& device, const char* label);

}  // namespace gpu_neighborhood_tests
