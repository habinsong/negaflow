#pragma once

// CPU/GPU 동치 시험 — 색 커널이 함께 쓰는 것들입니다.
//
// 허용 오차 `1e-5` 는 float32 반올림 범위입니다. 이보다 벌어지면 반올림이 아니라 이식
// 실수입니다 — **오차를 늘리지 말고 커널을 고치십시오.**

#include <cstddef>
#include <cstdint>
#include <vector>

#include "negaflow/core/pixel.h"

namespace negaflow::gpu {
class GpuDevice;
}

namespace gpu_color_kernel_tests {

using negaflow::core::Rgba32F;

extern int failures;
void expect(bool condition, const char* message);

inline constexpr float tolerance = 1.0e-5F;
inline constexpr std::uint32_t width = 64U;
inline constexpr std::uint32_t height = 48U;

// 세 채널이 서로 다르게 움직이는 경사입니다. 한 채널만 보는 실수를 잡습니다.
[[nodiscard]] std::vector<Rgba32F> make_ramp();

void grade_matches_cpu(const negaflow::gpu::GpuDevice& device, const char* label);
void mixer_matches_cpu(const negaflow::gpu::GpuDevice& device, const char* label);
void primary_matches_cpu(const negaflow::gpu::GpuDevice& device, const char* label);
void bw_matches_cpu(const negaflow::gpu::GpuDevice& device, const char* label);
void digital_bw_matches_cpu(const negaflow::gpu::GpuDevice& device, const char* label);

}  // namespace gpu_color_kernel_tests
