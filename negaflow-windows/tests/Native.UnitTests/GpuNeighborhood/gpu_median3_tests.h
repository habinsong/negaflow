#pragma once

#include "gpu_neighborhood_test_support.h"

namespace negaflow::gpu {
class GpuDevice;
}

namespace gpu_neighborhood_tests {

void median3_matches_reference(const negaflow::gpu::GpuDevice& device, const char* label);

}  // namespace gpu_neighborhood_tests
