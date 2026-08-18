#include "negaflow/gpu/gpu_neighborhood.h"

#include <d3d11.h>

#include <cstring>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/finite_check_FiniteCheckMain.h"

namespace negaflow::gpu {
namespace {

constexpr std::uint32_t finite_group = 8U;

// HLSL `cbuffer FiniteCheckConstants` 와 같은 배치여야 합니다.
struct alignas(16) FiniteCheckConstants final {
    GpuPointwiseExtent extent{};
};

static_assert(sizeof(FiniteCheckConstants) == 16U, "one constant register");

[[nodiscard]] std::uint32_t group_count(const std::uint32_t extent) noexcept {
    return (extent + finite_group - 1U) / finite_group;
}

}  // namespace

GpuFiniteCheck::~GpuFiniteCheck() { reset(); }

GpuFiniteCheck::GpuFiniteCheck(GpuFiniteCheck&& other) noexcept
    : shader_(other.shader_),
      constants_(other.constants_),
      flag_(other.flag_),
      flag_view_(other.flag_view_),
      readback_(other.readback_) {
    other.shader_ = nullptr;
    other.constants_ = nullptr;
    other.flag_ = nullptr;
    other.flag_view_ = nullptr;
    other.readback_ = nullptr;
}

GpuFiniteCheck& GpuFiniteCheck::operator=(GpuFiniteCheck&& other) noexcept {
    if (this != &other) {
        reset();
        shader_ = other.shader_;
        constants_ = other.constants_;
        flag_ = other.flag_;
        flag_view_ = other.flag_view_;
        readback_ = other.readback_;
        other.shader_ = nullptr;
        other.constants_ = nullptr;
        other.flag_ = nullptr;
        other.flag_view_ = nullptr;
        other.readback_ = nullptr;
    }
    return *this;
}

void GpuFiniteCheck::reset() noexcept {
    if (readback_ != nullptr) {
        readback_->Release();
        readback_ = nullptr;
    }
    if (flag_view_ != nullptr) {
        flag_view_->Release();
        flag_view_ = nullptr;
    }
    if (flag_ != nullptr) {
        flag_->Release();
        flag_ = nullptr;
    }
    if (constants_ != nullptr) {
        constants_->Release();
        constants_ = nullptr;
    }
    if (shader_ != nullptr) {
        shader_->Release();
        shader_ = nullptr;
    }
}

GpuKernelStatus GpuFiniteCheck::create(
    const GpuDevice& device,
    GpuFiniteCheck& kernel) noexcept {
    kernel.reset();
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }

    if (FAILED(device.device()->CreateComputeShader(
            negaflow_finite_check_cs,
            sizeof(negaflow_finite_check_cs),
            nullptr,
            &kernel.shader_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }

    D3D11_BUFFER_DESC constants{};
    constants.ByteWidth = sizeof(FiniteCheckConstants);
    constants.Usage = D3D11_USAGE_DYNAMIC;
    constants.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    constants.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    if (FAILED(device.device()->CreateBuffer(&constants, nullptr, &kernel.constants_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }

    // 플래그 하나짜리 구조화 버퍼. `InterlockedOr` 이 여기에 씁니다.
    D3D11_BUFFER_DESC flag{};
    flag.ByteWidth = sizeof(std::uint32_t);
    flag.Usage = D3D11_USAGE_DEFAULT;
    flag.BindFlags = D3D11_BIND_UNORDERED_ACCESS;
    flag.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    flag.StructureByteStride = sizeof(std::uint32_t);
    if (FAILED(device.device()->CreateBuffer(&flag, nullptr, &kernel.flag_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }

    D3D11_UNORDERED_ACCESS_VIEW_DESC view{};
    view.Format = DXGI_FORMAT_UNKNOWN;  // 구조화 버퍼는 UNKNOWN 이어야 합니다.
    view.ViewDimension = D3D11_UAV_DIMENSION_BUFFER;
    view.Buffer.NumElements = 1U;
    if (FAILED(device.device()->CreateUnorderedAccessView(
            kernel.flag_, &view, &kernel.flag_view_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }

    // 4바이트만 내립니다. 전 화소를 내리는 것과 비교가 안 되게 쌉니다.
    D3D11_BUFFER_DESC readback{};
    readback.ByteWidth = sizeof(std::uint32_t);
    readback.Usage = D3D11_USAGE_STAGING;
    readback.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    if (FAILED(device.device()->CreateBuffer(&readback, nullptr, &kernel.readback_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }
    return GpuKernelStatus::ok;
}

GpuKernelStatus GpuFiniteCheck::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    bool& all_finite) const noexcept {
    all_finite = false;
    if (!device.is_usable() || shader_ == nullptr) {
        return GpuKernelStatus::device_unavailable;
    }
    if (!source.is_valid()) {
        return GpuKernelStatus::invalid_arguments;
    }

    ID3D11DeviceContext* context = device.context();

    FiniteCheckConstants payload{};
    payload.extent.width = source.width();
    payload.extent.height = source.height();
    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context->Map(constants_, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    std::memcpy(mapped.pData, &payload, sizeof(payload));
    context->Unmap(constants_, 0U);

    // 앞 실행의 플래그가 남아 있으면 거짓 양성이 됩니다. 매번 0 으로 시작합니다.
    const UINT clear[4] = {0U, 0U, 0U, 0U};
    context->ClearUnorderedAccessViewUint(flag_view_, clear);

    ID3D11ShaderResourceView* source_view = source.srv();
    context->CSSetShader(shader_, nullptr, 0U);
    context->CSSetShaderResources(0U, 1U, &source_view);
    context->CSSetUnorderedAccessViews(0U, 1U, &flag_view_, nullptr);
    context->CSSetConstantBuffers(0U, 1U, &constants_);
    context->Dispatch(group_count(source.width()), group_count(source.height()), 1U);

    ID3D11ShaderResourceView* const no_srv[1] = {nullptr};
    ID3D11UnorderedAccessView* const no_uav[1] = {nullptr};
    context->CSSetShaderResources(0U, 1U, no_srv);
    context->CSSetUnorderedAccessViews(0U, 1U, no_uav, nullptr);
    context->CSSetShader(nullptr, nullptr, 0U);

    context->CopyResource(readback_, flag_);
    D3D11_MAPPED_SUBRESOURCE read{};
    if (FAILED(context->Map(readback_, 0U, D3D11_MAP_READ, 0U, &read))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    std::uint32_t flagged = 1U;
    std::memcpy(&flagged, read.pData, sizeof(flagged));
    context->Unmap(readback_, 0U);

    all_finite = flagged == 0U;
    return GpuKernelStatus::ok;
}

}  // namespace negaflow::gpu
