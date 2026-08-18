#pragma once

namespace negaflow::gpu {
class GpuDevice;
}

namespace gpu_neighborhood_tests {

// 밉맵 한 단계 축소가 CPU 판(`imaging/mipmap_downsampler.cpp` `halve`)과
// **비트 단위로** 같은지. 허용 오차가 아니라 완전 일치를 봅니다 — 이 값이
// 파라메트릭 톤 커브의 밴드 백분위로 가기 때문입니다.
void mip_halve_matches_reference(const negaflow::gpu::GpuDevice& device, const char* label);

}  // namespace gpu_neighborhood_tests
