#include "negaflow/gpu/gpu_point_sample.h"

#include <d3d11.h>

#include <cstring>
#include <new>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/point_sample_grid_PointSampleGridMain.h"

namespace negaflow::gpu {
namespace {

// HLSL `cbuffer PointSampleGridConstants` 와 같은 배치여야 합니다.
struct alignas(16) PointSampleGridConstants final {
    GpuPointwiseExtent extent{};
    std::uint32_t grid_width{0U};
    std::uint32_t grid_height{0U};
    std::uint32_t divisor_width{0U};
    std::uint32_t divisor_height{0U};
};
static_assert(sizeof(PointSampleGridConstants) == 32U, "two constant registers");

[[nodiscard]] std::uint32_t group_count(const std::uint32_t extent) noexcept {
    return (extent + gpu_thread_group_width - 1U) / gpu_thread_group_width;
}

template <typename Resource>
void release(Resource*& resource) noexcept {
    if (resource != nullptr) {
        resource->Release();
        resource = nullptr;
    }
}

}  // namespace

GpuPointSampleGrid::~GpuPointSampleGrid() { reset(); }

void GpuPointSampleGrid::release_buffers() noexcept {
    release(readback_);
    release(samples_view_);
    release(samples_);
    capacity_ = 0U;
}

void GpuPointSampleGrid::reset() noexcept {
    release_buffers();
    release(constants_);
    release(shader_);
}

GpuKernelStatus GpuPointSampleGrid::create(
    const GpuDevice& device,
    GpuPointSampleGrid& kernel) noexcept {
    kernel.reset();
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_point_sample_grid_cs,
            sizeof(negaflow_point_sample_grid_cs),
            nullptr,
            &kernel.shader_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }
    D3D11_BUFFER_DESC constants{};
    constants.ByteWidth = sizeof(PointSampleGridConstants);
    constants.Usage = D3D11_USAGE_DYNAMIC;
    constants.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    constants.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    if (FAILED(device.device()->CreateBuffer(&constants, nullptr, &kernel.constants_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }
    return GpuKernelStatus::ok;
}

bool GpuPointSampleGrid::ensure_capacity(
    const GpuDevice& device,
    const std::uint32_t count) noexcept {
    if (count <= capacity_ && samples_ != nullptr) {
        return true;
    }
    release_buffers();
    const UINT bytes = count * static_cast<UINT>(sizeof(core::Rgba32F));
    D3D11_BUFFER_DESC samples{};
    samples.ByteWidth = bytes;
    samples.Usage = D3D11_USAGE_DEFAULT;
    samples.BindFlags = D3D11_BIND_UNORDERED_ACCESS;
    samples.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    samples.StructureByteStride = sizeof(core::Rgba32F);
    if (FAILED(device.device()->CreateBuffer(&samples, nullptr, &samples_))) {
        release_buffers();
        return false;
    }
    D3D11_UNORDERED_ACCESS_VIEW_DESC view{};
    view.Format = DXGI_FORMAT_UNKNOWN;  // 구조화 버퍼는 UNKNOWN 이어야 합니다.
    view.ViewDimension = D3D11_UAV_DIMENSION_BUFFER;
    view.Buffer.NumElements = count;
    if (FAILED(device.device()->CreateUnorderedAccessView(samples_, &view, &samples_view_))) {
        release_buffers();
        return false;
    }
    D3D11_BUFFER_DESC readback{};
    readback.ByteWidth = bytes;
    readback.Usage = D3D11_USAGE_STAGING;
    readback.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    if (FAILED(device.device()->CreateBuffer(&readback, nullptr, &readback_))) {
        release_buffers();
        return false;
    }
    capacity_ = count;
    return true;
}

GpuKernelStatus GpuPointSampleGrid::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    const std::uint32_t divisor_width,
    const std::uint32_t divisor_height,
    const std::uint32_t grid_width,
    const std::uint32_t grid_height,
    std::vector<core::Rgba32F>& samples) noexcept {
    if (!device.is_usable() || shader_ == nullptr) {
        return GpuKernelStatus::device_unavailable;
    }
    const std::uint64_t count = static_cast<std::uint64_t>(grid_width) * grid_height;
    // 격자는 표본이라 작습니다. 원본보다 크거나 버퍼 한도를 넘는 요청은 표본이 아닙니다.
    if (!source.is_valid() || count == 0U || divisor_width == 0U || divisor_height == 0U ||
        divisor_width > source.width() || divisor_height > source.height() ||
        count * sizeof(core::Rgba32F) > D3D11_REQ_RESOURCE_SIZE_IN_MEGABYTES_EXPRESSION_A_TERM * 1024ULL * 1024ULL) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (!ensure_capacity(device, static_cast<std::uint32_t>(count))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    try {
        samples.resize(static_cast<std::size_t>(count));
    } catch (...) {
        return GpuKernelStatus::resource_creation_failed;
    }

    ID3D11DeviceContext* const context = device.context();
    PointSampleGridConstants payload{};
    payload.extent.width = source.width();
    payload.extent.height = source.height();
    payload.grid_width = grid_width;
    payload.grid_height = grid_height;
    payload.divisor_width = divisor_width;
    payload.divisor_height = divisor_height;
    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context->Map(constants_, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    std::memcpy(mapped.pData, &payload, sizeof(payload));
    context->Unmap(constants_, 0U);

    ID3D11ShaderResourceView* const source_view = source.srv();
    context->CSSetShader(shader_, nullptr, 0U);
    context->CSSetShaderResources(0U, 1U, &source_view);
    context->CSSetUnorderedAccessViews(0U, 1U, &samples_view_, nullptr);
    context->CSSetConstantBuffers(0U, 1U, &constants_);
    context->Dispatch(group_count(grid_width), group_count(grid_height), 1U);

    ID3D11ShaderResourceView* const no_srv[1] = {nullptr};
    ID3D11UnorderedAccessView* const no_uav[1] = {nullptr};
    context->CSSetShaderResources(0U, 1U, no_srv);
    context->CSSetUnorderedAccessViews(0U, 1U, no_uav, nullptr);
    context->CSSetShader(nullptr, nullptr, 0U);

    const D3D11_BOX box{0U, 0U, 0U, static_cast<UINT>(count * sizeof(core::Rgba32F)), 1U, 1U};
    context->CopySubresourceRegion(readback_, 0U, 0U, 0U, 0U, samples_, 0U, &box);
    D3D11_MAPPED_SUBRESOURCE read{};
    if (FAILED(context->Map(readback_, 0U, D3D11_MAP_READ, 0U, &read))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    std::memcpy(samples.data(), read.pData, static_cast<std::size_t>(count) * sizeof(core::Rgba32F));
    context->Unmap(readback_, 0U);
    return GpuKernelStatus::ok;
}

}  // namespace negaflow::gpu
