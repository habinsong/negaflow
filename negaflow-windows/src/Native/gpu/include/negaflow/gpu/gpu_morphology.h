#pragma once

// 형태학(침식·팽창·열기·닫기·양극 톱햇)입니다.
// Windows CPU 는 `imaging/grain_mend_morphology.cpp` 이고, **GrainMend 검출 CPU 시간의
// 82%** 가 여기 있습니다 — 먼지 형태학 47% + 미세 입자 35%(`04-gpu-plan.md` 6.2절).
//
// macOS 대응은 `[[stitchable]]` 커널이 아닙니다. 검출은 macOS 도 다른 경로로 돌고,
// 우리는 **Windows CPU 판을 그대로** 옮깁니다.
//
// min/max 는 **선택 연산**이라 부동소수 산술이 없습니다 — CPU 의 단조 덱과 GPU 의 직접
// 훑기가 **비트 단위로 같은 값**을 냅니다. 그래서 알고리즘을 바꿔도 값이 안 변합니다.
// 바로 그 이유로 **성능 개선은 값 위험 없이** 나중에 할 수 있습니다(vHGW O(1)).
// 다만 **재고 나서** 하십시오 — `13-performance-playbook.md` 0절.
//
// 네 채널을 각각 독립으로 처리합니다. 검출이 채널 셋 + 휘도를 다루므로 한 텍스처에 담아
// 한 번에 돌릴 수 있습니다.

#include <cstdint>

#include "negaflow/gpu/gpu_pointwise.h"

struct ID3D11ComputeShader;
struct ID3D11Buffer;

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

class GpuMorphology final {
public:
    // `opening`·`closing` 이 쓰는 중간 텍스처 수.
    static constexpr int filter_scratch_count = 2;
    // `bipolar_top_hat` 이 쓰는 중간 텍스처 수(위 둘 + 열린 것 + 닫힌 것).
    static constexpr int top_hat_scratch_count = 4;

    GpuMorphology() noexcept = default;
    ~GpuMorphology();

    GpuMorphology(const GpuMorphology&) = delete;
    GpuMorphology& operator=(const GpuMorphology&) = delete;
    GpuMorphology(GpuMorphology&& other) noexcept;
    GpuMorphology& operator=(GpuMorphology&& other) noexcept;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuMorphology& kernel) noexcept;

    // 침식 → 팽창. `scratch` 는 `filter_scratch_count` 장이어야 합니다.
    // `radius` 가 0 이면 CPU 와 같이 원본을 그대로 내보냅니다.
    [[nodiscard]] GpuKernelStatus opening(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage* scratch,
        GpuWorkingImage& destination,
        std::uint32_t radius) const noexcept;

    // 팽창 → 침식.
    [[nodiscard]] GpuKernelStatus closing(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage* scratch,
        GpuWorkingImage& destination,
        std::uint32_t radius) const noexcept;

    // `max(max(0, source - opened), max(0, closed - source))`.
    // `scratch` 는 `top_hat_scratch_count` 장이어야 합니다.
    // `radius` 가 0 이면 CPU 와 같이 **전부 0** 입니다(원본이 아닙니다).
    [[nodiscard]] GpuKernelStatus bipolar_top_hat(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage* scratch,
        GpuWorkingImage& destination,
        std::uint32_t radius) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return horizontal_ != nullptr; }

private:
    void reset() noexcept;

    // 침식·팽창 한 벌(수평 → 수직)을 겁니다. `minimum` 이 참이면 침식입니다.
    [[nodiscard]] GpuKernelStatus run_filter(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& scratch,
        GpuWorkingImage& destination,
        std::uint32_t radius,
        bool minimum) const noexcept;

    ID3D11ComputeShader* horizontal_{nullptr};
    ID3D11ComputeShader* vertical_{nullptr};
    ID3D11ComputeShader* top_hat_{nullptr};
    ID3D11Buffer* constants_{nullptr};
};

} // namespace negaflow::gpu
