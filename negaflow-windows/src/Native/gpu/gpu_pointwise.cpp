#include "negaflow/gpu/gpu_pointwise.h"

#include <d3d11.h>

#include <cstring>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"

namespace negaflow::gpu {
namespace {

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

GpuPointwiseKernel::~GpuPointwiseKernel() { reset(); }

GpuPointwiseKernel::GpuPointwiseKernel(GpuPointwiseKernel&& other) noexcept
    : shader_(other.shader_), constants_(other.constants_), constant_bytes_(other.constant_bytes_) {
    other.shader_ = nullptr;
    other.constants_ = nullptr;
    other.constant_bytes_ = 0U;
}

GpuPointwiseKernel& GpuPointwiseKernel::operator=(GpuPointwiseKernel&& other) noexcept {
    if (this != &other) {
        reset();
        shader_ = other.shader_;
        constants_ = other.constants_;
        constant_bytes_ = other.constant_bytes_;
        other.shader_ = nullptr;
        other.constants_ = nullptr;
        other.constant_bytes_ = 0U;
    }
    return *this;
}

void GpuPointwiseKernel::reset() noexcept {
    if (constants_ != nullptr) {
        constants_->Release();
        constants_ = nullptr;
    }
    if (shader_ != nullptr) {
        shader_->Release();
        shader_ = nullptr;
    }
    constant_bytes_ = 0U;
}

GpuKernelStatus GpuPointwiseKernel::create(
    const GpuDevice& device,
    const void* const bytecode,
    const std::size_t bytecode_bytes,
    const std::size_t constant_bytes,
    GpuPointwiseKernel& kernel) noexcept {
    kernel.reset();
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }
    if (bytecode == nullptr || bytecode_bytes == 0U) {
        return GpuKernelStatus::invalid_arguments;
    }
    // D3D11 상수 버퍼는 16의 배수만 받습니다. 여기서 조용히 올려 주면 셰이더 구조체와
    // 어긋난 채로 돌아 값이 틀립니다 — 그래서 거절합니다.
    if (constant_bytes == 0U || (constant_bytes % 16U) != 0U) {
        return GpuKernelStatus::invalid_arguments;
    }

    ID3D11ComputeShader* shader = nullptr;
    if (FAILED(device.device()->CreateComputeShader(bytecode, bytecode_bytes, nullptr, &shader))) {
        return GpuKernelStatus::resource_creation_failed;
    }

    D3D11_BUFFER_DESC description{};
    description.ByteWidth = static_cast<UINT>(constant_bytes);
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
    kernel.constant_bytes_ = constant_bytes;
    return GpuKernelStatus::ok;
}

GpuKernelStatus GpuPointwiseKernel::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    void* const constants,
    const std::size_t constant_bytes) const noexcept {
    if (!device.is_usable() || shader_ == nullptr || constants_ == nullptr) {
        return GpuKernelStatus::device_unavailable;
    }
    if (constants == nullptr || constant_bytes != constant_bytes_) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (!source.is_valid() || !destination.is_valid()) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (source.width() != destination.width() || source.height() != destination.height()) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (source.texture() == destination.texture()) {
        // 한 자원을 SRV 와 UAV 로 동시에 묶을 수 없습니다. 핑퐁 두 장을 쓰십시오.
        return GpuKernelStatus::invalid_arguments;
    }

    // 크기는 여기서 채웁니다. 커널마다 채우게 두면 한 곳만 빠뜨려도 조용히 어긋납니다.
    GpuPointwiseExtent extent{};
    extent.width = source.width();
    extent.height = source.height();
    std::memcpy(constants, &extent, sizeof(extent));

    ID3D11DeviceContext* context = device.context();

    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context->Map(constants_, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    std::memcpy(mapped.pData, constants, constant_bytes);
    context->Unmap(constants_, 0U);

    ID3D11ShaderResourceView* source_view = source.srv();
    ID3D11UnorderedAccessView* destination_view = destination.uav();
    ID3D11Buffer* constant_view = constants_;

    context->CSSetShader(shader_, nullptr, 0U);
    context->CSSetShaderResources(0U, 1U, &source_view);
    context->CSSetUnorderedAccessViews(0U, 1U, &destination_view, nullptr);
    context->CSSetConstantBuffers(0U, 1U, &constant_view);

    context->Dispatch(
        group_count(source.width(), gpu_thread_group_width),
        group_count(source.height(), gpu_thread_group_height),
        1U);

    // 바인딩을 풀어 둡니다. 다음 패스가 같은 텍스처를 SRV 로 읽을 때 D3D11 이
    // "이미 UAV 로 묶여 있다" 며 바인딩을 조용히 무시하는 것을 막습니다.
    ID3D11ShaderResourceView* const no_srv[1] = {nullptr};
    ID3D11UnorderedAccessView* const no_uav[1] = {nullptr};
    context->CSSetShaderResources(0U, 1U, no_srv);
    context->CSSetUnorderedAccessViews(0U, 1U, no_uav, nullptr);
    context->CSSetShader(nullptr, nullptr, 0U);
    return GpuKernelStatus::ok;
}

}  // namespace negaflow::gpu
