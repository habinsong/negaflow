#include "negaflow/gpu/gpu_area_average.h"

#include <windows.h>
#include <d3d11.h>

#include <algorithm>
#include <cstring>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/area_average_ReduceImageMain.h"
#include "negaflow/gpu/shaders/area_average_ReducePartialsMain.h"

namespace negaflow::gpu {
namespace {

constexpr std::uint32_t group_size = 16U;
constexpr std::uint32_t group_threads = 256U;

struct alignas(16) Partial final {
    float sum[4]{};
};

static_assert(sizeof(Partial) == 16U, "float4");

struct alignas(16) AreaAverageConstants final {
    GpuPointwiseExtent extent{};
    std::uint32_t origin_x{0};
    std::uint32_t origin_y{0};
    std::uint32_t region_width{0};
    std::uint32_t region_height{0};
    std::uint32_t partial_count{0};
    std::uint32_t padding{0};
    float pad[2]{};
};

static_assert(sizeof(AreaAverageConstants) == 48U, "three constant registers");

[[nodiscard]] std::uint32_t groups_1d(const std::uint32_t extent, const std::uint32_t size) noexcept {
    return (extent + size - 1U) / size;
}

[[nodiscard]] bool make_partial_buffer(
    ID3D11Device* const device,
    const std::uint32_t count,
    ID3D11Buffer*& buffer,
    ID3D11UnorderedAccessView*& uav,
    ID3D11ShaderResourceView*& srv) noexcept {
    D3D11_BUFFER_DESC description{};
    description.ByteWidth = count * sizeof(Partial);
    description.Usage = D3D11_USAGE_DEFAULT;
    description.BindFlags = D3D11_BIND_UNORDERED_ACCESS | D3D11_BIND_SHADER_RESOURCE;
    description.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    description.StructureByteStride = sizeof(Partial);
    if (FAILED(device->CreateBuffer(&description, nullptr, &buffer))) {
        return false;
    }
    D3D11_UNORDERED_ACCESS_VIEW_DESC uav_desc{};
    uav_desc.Format = DXGI_FORMAT_UNKNOWN;
    uav_desc.ViewDimension = D3D11_UAV_DIMENSION_BUFFER;
    uav_desc.Buffer.NumElements = count;
    if (FAILED(device->CreateUnorderedAccessView(buffer, &uav_desc, &uav))) {
        return false;
    }
    D3D11_SHADER_RESOURCE_VIEW_DESC srv_desc{};
    srv_desc.Format = DXGI_FORMAT_UNKNOWN;
    srv_desc.ViewDimension = D3D11_SRV_DIMENSION_BUFFER;
    srv_desc.Buffer.NumElements = count;
    return SUCCEEDED(device->CreateShaderResourceView(buffer, &srv_desc, &srv));
}

void release_view(ID3D11UnorderedAccessView*& view) noexcept {
    if (view != nullptr) {
        view->Release();
        view = nullptr;
    }
}

void release_srv(ID3D11ShaderResourceView*& view) noexcept {
    if (view != nullptr) {
        view->Release();
        view = nullptr;
    }
}

void release_buffer(ID3D11Buffer*& buffer) noexcept {
    if (buffer != nullptr) {
        buffer->Release();
        buffer = nullptr;
    }
}

}  // namespace

GpuAreaAverage::~GpuAreaAverage() { reset(); }

GpuAreaAverage::GpuAreaAverage(GpuAreaAverage&& other) noexcept
    : image_(other.image_),
      partials_(other.partials_),
      constants_(other.constants_),
      buffer_a_(other.buffer_a_),
      buffer_b_(other.buffer_b_),
      uav_a_(other.uav_a_),
      uav_b_(other.uav_b_),
      srv_a_(other.srv_a_),
      srv_b_(other.srv_b_),
      readback_(other.readback_),
      capacity_(other.capacity_) {
    other.image_ = nullptr;
    other.partials_ = nullptr;
    other.constants_ = nullptr;
    other.buffer_a_ = nullptr;
    other.buffer_b_ = nullptr;
    other.uav_a_ = nullptr;
    other.uav_b_ = nullptr;
    other.srv_a_ = nullptr;
    other.srv_b_ = nullptr;
    other.readback_ = nullptr;
    other.capacity_ = 0;
}

GpuAreaAverage& GpuAreaAverage::operator=(GpuAreaAverage&& other) noexcept {
    if (this != &other) {
        reset();
        image_ = other.image_;
        partials_ = other.partials_;
        constants_ = other.constants_;
        buffer_a_ = other.buffer_a_;
        buffer_b_ = other.buffer_b_;
        uav_a_ = other.uav_a_;
        uav_b_ = other.uav_b_;
        srv_a_ = other.srv_a_;
        srv_b_ = other.srv_b_;
        readback_ = other.readback_;
        capacity_ = other.capacity_;
        other.image_ = nullptr;
        other.partials_ = nullptr;
        other.constants_ = nullptr;
        other.buffer_a_ = nullptr;
        other.buffer_b_ = nullptr;
        other.uav_a_ = nullptr;
        other.uav_b_ = nullptr;
        other.srv_a_ = nullptr;
        other.srv_b_ = nullptr;
        other.readback_ = nullptr;
        other.capacity_ = 0;
    }
    return *this;
}

void GpuAreaAverage::reset() noexcept {
    release_view(uav_a_);
    release_view(uav_b_);
    release_srv(srv_a_);
    release_srv(srv_b_);
    release_buffer(buffer_a_);
    release_buffer(buffer_b_);
    release_buffer(readback_);
    release_buffer(constants_);
    if (partials_ != nullptr) {
        partials_->Release();
        partials_ = nullptr;
    }
    if (image_ != nullptr) {
        image_->Release();
        image_ = nullptr;
    }
    capacity_ = 0;
}

GpuKernelStatus GpuAreaAverage::create(
    const GpuDevice& device,
    GpuAreaAverage& kernel) noexcept {
    kernel.reset();
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_area_average_image_cs,
            sizeof(negaflow_area_average_image_cs),
            nullptr,
            &kernel.image_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_area_average_partials_cs,
            sizeof(negaflow_area_average_partials_cs),
            nullptr,
            &kernel.partials_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }
    D3D11_BUFFER_DESC constants{};
    constants.ByteWidth = sizeof(AreaAverageConstants);
    constants.Usage = D3D11_USAGE_DYNAMIC;
    constants.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    constants.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    if (FAILED(device.device()->CreateBuffer(&constants, nullptr, &kernel.constants_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }
    D3D11_BUFFER_DESC readback{};
    readback.ByteWidth = sizeof(Partial);
    readback.Usage = D3D11_USAGE_STAGING;
    readback.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    if (FAILED(device.device()->CreateBuffer(&readback, nullptr, &kernel.readback_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }
    // 8192² 까지 한 변 그룹. 24MP 는 이 안에 들어갑니다.
    constexpr std::uint32_t starting_capacity = 512U * 512U;
    if (!make_partial_buffer(
            device.device(),
            starting_capacity,
            kernel.buffer_a_,
            kernel.uav_a_,
            kernel.srv_a_) ||
        !make_partial_buffer(
            device.device(),
            starting_capacity,
            kernel.buffer_b_,
            kernel.uav_b_,
            kernel.srv_b_)) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }
    kernel.capacity_ = starting_capacity;
    return GpuKernelStatus::ok;
}

namespace {

[[nodiscard]] bool write_constants(
    ID3D11DeviceContext* const context,
    ID3D11Buffer* const constants,
    const AreaAverageConstants& payload) noexcept {
    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context->Map(constants, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
        return false;
    }
    std::memcpy(mapped.pData, &payload, sizeof(payload));
    context->Unmap(constants, 0U);
    return true;
}

}  // namespace

GpuKernelStatus GpuAreaAverage::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    const std::uint32_t origin_x,
    const std::uint32_t origin_y,
    const std::uint32_t extent_width,
    const std::uint32_t extent_height,
    float mean[4],
    std::uint64_t& count) const noexcept {
    count = 0U;
    if (mean == nullptr || !device.is_usable() || image_ == nullptr) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (!source.is_valid() || extent_width == 0U || extent_height == 0U) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (origin_x >= source.width() || origin_y >= source.height()) {
        return GpuKernelStatus::invalid_arguments;
    }
    const std::uint32_t region_width = std::min(extent_width, source.width() - origin_x);
    const std::uint32_t region_height = std::min(extent_height, source.height() - origin_y);
    const std::uint32_t groups_x = groups_1d(region_width, group_size);
    const std::uint32_t groups_y = groups_1d(region_height, group_size);
    const std::uint32_t first_partials = groups_x * groups_y;
    if (first_partials == 0U) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (first_partials > capacity_) {
        // const dispatch — grow via const_cast of mutable resources is ugly.
        // Recreate on the non-const this through a local copy of pointers is worse.
        return GpuKernelStatus::resource_creation_failed;
    }

    ID3D11DeviceContext* const context = device.context();
    AreaAverageConstants payload{};
    payload.extent.width = source.width();
    payload.extent.height = source.height();
    payload.origin_x = origin_x;
    payload.origin_y = origin_y;
    payload.region_width = region_width;
    payload.region_height = region_height;
    payload.partial_count = first_partials;
    if (!write_constants(context, constants_, payload)) {
        return GpuKernelStatus::resource_creation_failed;
    }

    ID3D11ShaderResourceView* const source_srv = source.srv();
    context->CSSetShader(image_, nullptr, 0U);
    context->CSSetConstantBuffers(0U, 1U, &constants_);
    context->CSSetShaderResources(0U, 1U, &source_srv);
    context->CSSetUnorderedAccessViews(0U, 1U, &uav_a_, nullptr);
    context->Dispatch(groups_x, groups_y, 1U);

    ID3D11UnorderedAccessView* none_uav = nullptr;
    ID3D11ShaderResourceView* none_srv = nullptr;
    context->CSSetUnorderedAccessViews(0U, 1U, &none_uav, nullptr);
    context->CSSetShaderResources(0U, 1U, &none_srv);

    std::uint32_t remaining = first_partials;
    bool output_is_a = true;
    context->CSSetShader(partials_, nullptr, 0U);
    while (remaining > 1U) {
        const std::uint32_t next_groups = groups_1d(remaining, group_threads);
        payload.partial_count = remaining;
        if (!write_constants(context, constants_, payload)) {
            return GpuKernelStatus::resource_creation_failed;
        }
        ID3D11ShaderResourceView* const input_srv = output_is_a ? srv_a_ : srv_b_;
        ID3D11UnorderedAccessView* const output_uav = output_is_a ? uav_b_ : uav_a_;
        context->CSSetShaderResources(1U, 1U, &input_srv);
        context->CSSetUnorderedAccessViews(0U, 1U, &output_uav, nullptr);
        context->Dispatch(next_groups, 1U, 1U);
        context->CSSetUnorderedAccessViews(0U, 1U, &none_uav, nullptr);
        context->CSSetShaderResources(1U, 1U, &none_srv);
        remaining = next_groups;
        output_is_a = !output_is_a;
    }

    ID3D11Buffer* const result_buffer = output_is_a ? buffer_a_ : buffer_b_;
    D3D11_BOX box{};
    box.right = sizeof(Partial);
    box.bottom = 1U;
    box.back = 1U;
    context->CopySubresourceRegion(readback_, 0U, 0U, 0U, 0U, result_buffer, 0U, &box);
    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context->Map(readback_, 0U, D3D11_MAP_READ, 0U, &mapped))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    Partial result{};
    std::memcpy(&result, mapped.pData, sizeof(result));
    context->Unmap(readback_, 0U);
    if (!(result.sum[3] > 0.0F)) {
        return GpuKernelStatus::invalid_arguments;
    }
    const float inverse = 1.0F / result.sum[3];
    mean[0] = result.sum[0] * inverse;
    mean[1] = result.sum[1] * inverse;
    mean[2] = result.sum[2] * inverse;
    mean[3] = 1.0F;
    count = static_cast<std::uint64_t>(result.sum[3] + 0.5F);
    return GpuKernelStatus::ok;
}

}  // namespace negaflow::gpu
