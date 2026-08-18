#pragma once

// 화소별 컴퓨트 커널의 공통 뼈대입니다.
//
// macOS `ChromabaseMetalKernels.swift` 의 `[[stitchable]]` 커널 **32개는 전부 화소별**입니다
// (같은 파일에서 `destCoord`·`samplerCoord`·`.sample(` 히트 0). 이웃을 보는 일은 Apple 내장
// 필터(`CIGaussianBlur`·`CIBoxBlur`·`CIMedianFilter`·`CIAreaAverage`)가 대신합니다.
//
// 그래서 32개가 같은 모양을 공유합니다 — 텍스처 하나 읽고, 상수 버퍼 하나 받고, 텍스처 하나에
// 씁니다. 커널마다 이 골격을 복사하면 32벌이 되고 서로 어긋납니다. 여기 한 번만 둡니다.
//
// 커널이 달라지는 것은 **셰이더 바이트코드와 상수 구조체** 둘뿐입니다.

#include <cstddef>
#include <cstdint>

struct ID3D11ComputeShader;
struct ID3D11Buffer;

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

enum class GpuKernelStatus : std::uint8_t {
    ok = 0,
    device_unavailable,
    // 셰이더·상수 버퍼를 못 만들었습니다.
    resource_creation_failed,
    // 입력이 비었거나, 출력 크기가 입력과 다르거나, 입출력이 같은 자원입니다.
    invalid_arguments,
    // 매개변수에 NaN/Inf 가 있습니다. CPU 판의 `non_finite_parameter` 와 같은 판정입니다.
    non_finite_parameter,
};

[[nodiscard]] const char* gpu_kernel_status_name(GpuKernelStatus status) noexcept;

// 모든 화소별 셰이더의 상수 버퍼는 **이것으로 시작해야 합니다.** 커널마다 자기 값을 뒤에 붙입니다.
// HLSL 상수 버퍼는 16바이트 경계로 채워지므로 여기서 이미 16바이트를 차지하게 둡니다.
struct alignas(16) GpuPointwiseExtent final {
    std::uint32_t width{0};
    std::uint32_t height{0};
    float padding[2]{0.0F, 0.0F};
};

static_assert(sizeof(GpuPointwiseExtent) == 16U, "extent occupies one constant register");

// 셰이더의 `[numthreads(...)]` 과 반드시 같아야 합니다. 8×8 = 64 는 AMD wave64 와
// NVIDIA warp32 둘 다 나눠떨어지는 값이라 어느 벤더에서도 낭비가 없습니다.
// **바꾸려면 모든 셰이더와 여기를 같이 바꾸고 다시 재십시오.**
inline constexpr std::uint32_t gpu_thread_group_width = 8U;
inline constexpr std::uint32_t gpu_thread_group_height = 8U;

// 컴파일된 셰이더와 상수 버퍼를 들고 있습니다. **한 번 만들어 재사용하십시오** —
// 슬라이더를 끄는 동안 프레임마다 만들면 그 비용이 커널보다 큽니다.
class GpuPointwiseKernel final {
public:
    GpuPointwiseKernel() noexcept = default;
    ~GpuPointwiseKernel();

    GpuPointwiseKernel(const GpuPointwiseKernel&) = delete;
    GpuPointwiseKernel& operator=(const GpuPointwiseKernel&) = delete;
    GpuPointwiseKernel(GpuPointwiseKernel&& other) noexcept;
    GpuPointwiseKernel& operator=(GpuPointwiseKernel&& other) noexcept;

    // `bytecode` 는 빌드 시 `fxc` 가 만든 헤더의 배열입니다(`cmake/CompileShaders.cmake`).
    // `constant_bytes` 는 커널의 상수 구조체 크기이며 16의 배수여야 합니다.
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        const void* bytecode,
        std::size_t bytecode_bytes,
        std::size_t constant_bytes,
        GpuPointwiseKernel& kernel) noexcept;

    // `constants` 의 앞 16바이트는 호출부가 채우지 않아도 됩니다 — 여기서 크기를 써 넣습니다.
    // 크기를 커널마다 따로 채우게 두면 한 곳만 빠뜨려도 조용히 어긋납니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        void* constants,
        std::size_t constant_bytes) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return shader_ != nullptr; }

private:
    void reset() noexcept;

    ID3D11ComputeShader* shader_{nullptr};
    ID3D11Buffer* constants_{nullptr};
    std::size_t constant_bytes_{0};
};

}  // namespace negaflow::gpu
