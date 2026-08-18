#pragma once

// 기본 톤 커널의 GPU 판입니다.
//
// macOS  : `ChromabaseMetalKernels.swift:185` `[[stitchable]] float4 basicTone(...)`
// CPU 판 : `imaging/tone_mapping.cpp:79` `apply_basic_tone`
// 셰이더 : `src/Native/gpu/shaders/basic_tone.hlsl`
//
// 이 경로는 CPU 판을 **대체하지 않습니다.** 나란히 두고 상위에서 장치 가용성으로 고릅니다.
// 두 경로의 화소값은 동치 시험(`native.gpu_basic_tone`)이 허용 오차 `1e-5` 로 묶습니다.

#include <cstdint>

#include "negaflow/core/pixel.h"
#include "negaflow/gpu/gpu_working_image.h"

struct ID3D11ComputeShader;
struct ID3D11Buffer;

namespace negaflow::gpu {

class GpuDevice;

// `imaging::BasicToneParameters` 와 같은 값들입니다. gpu 라이브러리가 imaging 에 의존하지
// 않도록(의존 방향이 반대여야 합니다) 여기에 같은 모양으로 둡니다. 호출부가 옮겨 담습니다.
struct GpuBasicToneParameters final {
    float contrast{0.0F};
    float density{0.0F};
    float highlights{0.0F};
    float shadows{0.0F};
    float whites{0.0F};
    float blacks{0.0F};
};

enum class GpuKernelStatus : std::uint8_t {
    ok = 0,
    device_unavailable,
    // 셰이더·상수 버퍼를 못 만들었습니다.
    resource_creation_failed,
    // 입력이 비었거나 출력 크기가 입력과 다릅니다.
    invalid_arguments,
    // 매개변수에 NaN/Inf 가 있습니다. CPU 판의 `non_finite_parameter` 와 같은 판정입니다.
    non_finite_parameter,
};

[[nodiscard]] const char* gpu_kernel_status_name(GpuKernelStatus status) noexcept;

// 컴파일된 셰이더와 상수 버퍼를 들고 있습니다. **한 번 만들어 재사용하십시오** —
// 슬라이더를 끄는 동안 프레임마다 만들면 그 비용이 커널보다 큽니다.
class GpuBasicTone final {
public:
    GpuBasicTone() noexcept = default;
    ~GpuBasicTone();

    GpuBasicTone(const GpuBasicTone&) = delete;
    GpuBasicTone& operator=(const GpuBasicTone&) = delete;
    GpuBasicTone(GpuBasicTone&& other) noexcept;
    GpuBasicTone& operator=(GpuBasicTone&& other) noexcept;

    [[nodiscard]] static GpuKernelStatus create(const GpuDevice& device, GpuBasicTone& kernel) noexcept;

    // `source` 를 읽어 `destination` 에 씁니다. 같은 자원을 넘기면 안 됩니다 —
    // D3D11 은 한 자원을 SRV 와 UAV 로 동시에 묶을 수 없어 핑퐁 두 장이 필요합니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        const GpuBasicToneParameters& parameters) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return shader_ != nullptr; }

private:
    void reset() noexcept;

    ID3D11ComputeShader* shader_{nullptr};
    ID3D11Buffer* constants_{nullptr};
};

}  // namespace negaflow::gpu
