#include "negaflow/gpu/gpu_neighborhood.h"

#include <d3d11.h>

#include <algorithm>
#include <cmath>
#include <cstring>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/mip_halve_MipHalveMain.h"

namespace negaflow::gpu {
namespace {

constexpr std::uint32_t mip_group = 8U;

// HLSL `cbuffer MipHalveConstants` 와 같은 배치여야 합니다.
struct alignas(16) MipHalveConstants final {
    GpuPointwiseExtent extent{};
    std::uint32_t child_width{0};
    std::uint32_t child_height{0};
    float padding[2]{0.0F, 0.0F};
};

static_assert(sizeof(MipHalveConstants) == 32U, "parent register + child register");

[[nodiscard]] std::uint32_t group_count(const std::uint32_t extent) noexcept {
    return (extent + mip_group - 1U) / mip_group;
}

}  // namespace

GpuMipHalve::~GpuMipHalve() { reset(); }

GpuMipHalve::GpuMipHalve(GpuMipHalve&& other) noexcept
    : shader_(other.shader_), constants_(other.constants_) {
    other.shader_ = nullptr;
    other.constants_ = nullptr;
}

GpuMipHalve& GpuMipHalve::operator=(GpuMipHalve&& other) noexcept {
    if (this != &other) {
        reset();
        shader_ = other.shader_;
        constants_ = other.constants_;
        other.shader_ = nullptr;
        other.constants_ = nullptr;
    }
    return *this;
}

void GpuMipHalve::reset() noexcept {
    if (constants_ != nullptr) {
        constants_->Release();
        constants_ = nullptr;
    }
    if (shader_ != nullptr) {
        shader_->Release();
        shader_ = nullptr;
    }
}

int GpuMipHalve::wanted_level_count(
    const std::uint32_t source_width,
    const std::uint32_t target_width) noexcept {
    // CPU 판(`downsample_for_statistics`)과 같은 셈입니다.
    if (source_width == 0U || target_width == 0U) {
        return 0;
    }
    const double ratio =
        static_cast<double>(source_width) / static_cast<double>(target_width);
    return ratio > 1.0 ? static_cast<int>(std::floor(std::log2(ratio))) : 0;
}

GpuKernelStatus GpuMipHalve::create(const GpuDevice& device, GpuMipHalve& kernel) noexcept {
    kernel.reset();
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }

    ID3D11ComputeShader* shader = nullptr;
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_mip_halve_cs, sizeof(negaflow_mip_halve_cs), nullptr, &shader))) {
        return GpuKernelStatus::resource_creation_failed;
    }

    D3D11_BUFFER_DESC description{};
    description.ByteWidth = sizeof(MipHalveConstants);
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

GpuKernelStatus GpuMipHalve::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination) const noexcept {
    if (!device.is_usable() || shader_ == nullptr || constants_ == nullptr) {
        return GpuKernelStatus::device_unavailable;
    }
    if (!source.is_valid() || !destination.is_valid()) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (source.texture() == destination.texture()) {
        return GpuKernelStatus::invalid_arguments;
    }
    const std::uint32_t child_width = std::max(1U, source.width() / 2U);
    const std::uint32_t child_height = std::max(1U, source.height() / 2U);
    if (destination.width() != child_width || destination.height() != child_height) {
        return GpuKernelStatus::invalid_arguments;
    }

    ID3D11DeviceContext* context = device.context();

    MipHalveConstants payload{};
    payload.extent.width = source.width();
    payload.extent.height = source.height();
    payload.child_width = child_width;
    payload.child_height = child_height;

    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context->Map(constants_, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    std::memcpy(mapped.pData, &payload, sizeof(payload));
    context->Unmap(constants_, 0U);

    ID3D11ShaderResourceView* source_view = source.srv();
    ID3D11UnorderedAccessView* destination_view = destination.uav();

    context->CSSetShader(shader_, nullptr, 0U);
    context->CSSetShaderResources(0U, 1U, &source_view);
    context->CSSetUnorderedAccessViews(0U, 1U, &destination_view, nullptr);
    context->CSSetConstantBuffers(0U, 1U, &constants_);
    context->Dispatch(group_count(child_width), group_count(child_height), 1U);

    ID3D11ShaderResourceView* const no_srv[1] = {nullptr};
    ID3D11UnorderedAccessView* const no_uav[1] = {nullptr};
    context->CSSetShaderResources(0U, 1U, no_srv);
    context->CSSetUnorderedAccessViews(0U, 1U, no_uav, nullptr);
    context->CSSetShader(nullptr, nullptr, 0U);
    return GpuKernelStatus::ok;
}

}  // namespace negaflow::gpu
