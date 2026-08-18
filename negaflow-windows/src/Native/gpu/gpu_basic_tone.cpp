#include "negaflow/gpu/gpu_basic_tone.h"

#include <d3d11.h>

#include <cmath>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/shaders/basic_tone_BasicToneMain.h"

namespace negaflow::gpu {
namespace {

// 셰이더의 `[numthreads(8, 8, 1)]` 과 반드시 같아야 합니다. 8×8 = 64 로, AMD wave64 와
// NVIDIA warp32 둘 다 나눠떨어지는 값입니다. 바꾸려면 셰이더와 여기를 같이 바꾸고 다시 재십시오.
constexpr std::uint32_t thread_group_width = 8U;
constexpr std::uint32_t thread_group_height = 8U;

// HLSL `cbuffer BasicToneConstants` 와 같은 배치여야 합니다. HLSL 상수 버퍼는 16바이트
// 경계를 넘지 않게 채워지므로 padding 을 명시해 둡니다.
struct alignas(16) BasicToneConstants final {
    std::uint32_t width{0};
    std::uint32_t height{0};
    float padding0[2]{0.0F, 0.0F};
    float contrast{0.0F};
    float density{0.0F};
    float highlights{0.0F};
    float shadows{0.0F};
    float whites{0.0F};
    float blacks{0.0F};
    float padding1[2]{0.0F, 0.0F};
};

static_assert(sizeof(BasicToneConstants) % 16U == 0U, "constant buffers are 16-byte aligned");

[[nodiscard]] bool finite_parameters(const GpuBasicToneParameters& parameters) noexcept {
    return std::isfinite(parameters.contrast) && std::isfinite(parameters.density) &&
        std::isfinite(parameters.highlights) && std::isfinite(parameters.shadows) &&
        std::isfinite(parameters.whites) && std::isfinite(parameters.blacks);
}

[[nodiscard]] std::uint32_t group_count(
    const std::uint32_t extent,
    const std::uint32_t group) noexcept {
    return (extent + group - 1U) / group;
}

}  // namespace

const char* gpu_kernel_status_name(const GpuKernelStatus status) noexcept {
    switch (status) {
        case GpuKernelStatus::ok:
            return "ok";
        case GpuKernelStatus::device_unavailable:
            return "device_unavailable";
        case GpuKernelStatus::resource_creation_failed:
            return "resource_creation_failed";
        case GpuKernelStatus::invalid_arguments:
            return "invalid_arguments";
        case GpuKernelStatus::non_finite_parameter:
            return "non_finite_parameter";
    }
    return "unknown_status";
}

GpuBasicTone::~GpuBasicTone() { reset(); }

GpuBasicTone::GpuBasicTone(GpuBasicTone&& other) noexcept
    : shader_(other.shader_), constants_(other.constants_) {
    other.shader_ = nullptr;
    other.constants_ = nullptr;
}

GpuBasicTone& GpuBasicTone::operator=(GpuBasicTone&& other) noexcept {
    if (this != &other) {
        reset();
        shader_ = other.shader_;
        constants_ = other.constants_;
        other.shader_ = nullptr;
        other.constants_ = nullptr;
    }
    return *this;
}

void GpuBasicTone::reset() noexcept {
    if (constants_ != nullptr) {
        constants_->Release();
        constants_ = nullptr;
    }
    if (shader_ != nullptr) {
        shader_->Release();
        shader_ = nullptr;
    }
}

GpuKernelStatus GpuBasicTone::create(const GpuDevice& device, GpuBasicTone& kernel) noexcept {
    kernel.reset();
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }

    ID3D11ComputeShader* shader = nullptr;
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_basic_tone_cs, sizeof(negaflow_basic_tone_cs), nullptr, &shader))) {
        return GpuKernelStatus::resource_creation_failed;
    }

    D3D11_BUFFER_DESC description{};
    description.ByteWidth = sizeof(BasicToneConstants);
    description.Usage = D3D11_USAGE_DYNAMIC;
    description.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    description.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

    ID3D11Buffer* constants = nullptr;
    if (FAILED(device.device()->CreateBuffer(&description, nullptr, &constants))) {
        shader->Release();
        return GpuKernelStatus::resource_creation_failed;
    }

    kernel.shader_ = shader;
    kernel.constants_ = constants;
    return GpuKernelStatus::ok;
}

GpuKernelStatus GpuBasicTone::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const GpuBasicToneParameters& parameters) const noexcept {
    if (!device.is_usable() || shader_ == nullptr || constants_ == nullptr) {
        return GpuKernelStatus::device_unavailable;
    }
    if (!finite_parameters(parameters)) {
        // CPU 판 `apply_basic_tone` 과 같은 판정입니다. 조용히 0 으로 바꾸지 않습니다.
        return GpuKernelStatus::non_finite_parameter;
    }
    if (!source.is_valid() || !destination.is_valid()) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (source.width() != destination.width() || source.height() != destination.height()) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (source.texture() == destination.texture()) {
        // 한 자원을 SRV·UAV 로 동시에 묶을 수 없습니다. 핑퐁 두 장을 쓰십시오.
        return GpuKernelStatus::invalid_arguments;
    }

    ID3D11DeviceContext* context = device.context();

    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context->Map(constants_, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    BasicToneConstants payload{};
    payload.width = source.width();
    payload.height = source.height();
    payload.contrast = parameters.contrast;
    payload.density = parameters.density;
    payload.highlights = parameters.highlights;
    payload.shadows = parameters.shadows;
    payload.whites = parameters.whites;
    payload.blacks = parameters.blacks;
    *static_cast<BasicToneConstants*>(mapped.pData) = payload;
    context->Unmap(constants_, 0U);

    ID3D11ShaderResourceView* source_view = source.srv();
    ID3D11UnorderedAccessView* destination_view = destination.uav();
    ID3D11Buffer* constant_view = constants_;

    context->CSSetShader(shader_, nullptr, 0U);
    context->CSSetShaderResources(0U, 1U, &source_view);
    context->CSSetUnorderedAccessViews(0U, 1U, &destination_view, nullptr);
    context->CSSetConstantBuffers(0U, 1U, &constant_view);

    context->Dispatch(
        group_count(source.width(), thread_group_width),
        group_count(source.height(), thread_group_height),
        1U);

    // 바인딩을 풀어 둡니다. 다음 패스가 같은 텍스처를 SRV 로 읽을 때 D3D11 이
    // "이미 UAV 로 묶여 있다" 며 경고하고 바인딩을 조용히 무시하는 것을 막습니다.
    ID3D11ShaderResourceView* const no_srv[1] = {nullptr};
    ID3D11UnorderedAccessView* const no_uav[1] = {nullptr};
    context->CSSetShaderResources(0U, 1U, no_srv);
    context->CSSetUnorderedAccessViews(0U, 1U, no_uav, nullptr);
    context->CSSetShader(nullptr, nullptr, 0U);
    return GpuKernelStatus::ok;
}

}  // namespace negaflow::gpu
