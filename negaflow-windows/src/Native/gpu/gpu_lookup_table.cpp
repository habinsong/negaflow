#include "negaflow/gpu/gpu_lookup_table.h"

#include <d3d11.h>

#include <cstring>

#include "negaflow/gpu/gpu_device.h"

namespace negaflow::gpu {

GpuLookupTable::~GpuLookupTable() { reset(); }

GpuLookupTable::GpuLookupTable(GpuLookupTable&& other) noexcept
    : buffer_(other.buffer_),
      srv_(other.srv_),
      element_count_(other.element_count_),
      element_bytes_(other.element_bytes_) {
    other.buffer_ = nullptr;
    other.srv_ = nullptr;
    other.element_count_ = 0U;
    other.element_bytes_ = 0U;
}

GpuLookupTable& GpuLookupTable::operator=(GpuLookupTable&& other) noexcept {
    if (this != &other) {
        reset();
        buffer_ = other.buffer_;
        srv_ = other.srv_;
        element_count_ = other.element_count_;
        element_bytes_ = other.element_bytes_;
        other.buffer_ = nullptr;
        other.srv_ = nullptr;
        other.element_count_ = 0U;
        other.element_bytes_ = 0U;
    }
    return *this;
}

void GpuLookupTable::reset() noexcept {
    if (srv_ != nullptr) {
        srv_->Release();
        srv_ = nullptr;
    }
    if (buffer_ != nullptr) {
        buffer_->Release();
        buffer_ = nullptr;
    }
    element_count_ = 0U;
    element_bytes_ = 0U;
}

GpuKernelStatus GpuLookupTable::create(
    const GpuDevice& device,
    const std::size_t element_count,
    const std::size_t element_bytes,
    GpuLookupTable& table) noexcept {
    table.reset();
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }
    if (element_count == 0U || element_bytes == 0U) {
        return GpuKernelStatus::invalid_arguments;
    }
    // 구조화 버퍼의 원소 크기는 4의 배수여야 합니다.
    if ((element_bytes % 4U) != 0U) {
        return GpuKernelStatus::invalid_arguments;
    }

    D3D11_BUFFER_DESC description{};
    description.ByteWidth = static_cast<UINT>(element_count * element_bytes);
    // 큐브는 프리셋·세기가 바뀔 때만 갱신되므로 `DYNAMIC` + `MAP_WRITE_DISCARD` 로
    // 충분합니다. `DEFAULT` + `UpdateSubresource` 보다 갱신이 쌉니다.
    description.Usage = D3D11_USAGE_DYNAMIC;
    description.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    description.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    description.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    description.StructureByteStride = static_cast<UINT>(element_bytes);

    ID3D11Buffer* buffer = nullptr;
    if (FAILED(device.device()->CreateBuffer(&description, nullptr, &buffer))) {
        return GpuKernelStatus::resource_creation_failed;
    }

    D3D11_SHADER_RESOURCE_VIEW_DESC view{};
    view.Format = DXGI_FORMAT_UNKNOWN;  // 구조화 버퍼는 형식이 없습니다.
    view.ViewDimension = D3D11_SRV_DIMENSION_BUFFER;
    view.Buffer.FirstElement = 0U;
    view.Buffer.NumElements = static_cast<UINT>(element_count);

    ID3D11ShaderResourceView* srv = nullptr;
    if (FAILED(device.device()->CreateShaderResourceView(buffer, &view, &srv))) {
        buffer->Release();
        return GpuKernelStatus::resource_creation_failed;
    }

    table.buffer_ = buffer;
    table.srv_ = srv;
    table.element_count_ = element_count;
    table.element_bytes_ = element_bytes;
    return GpuKernelStatus::ok;
}

GpuKernelStatus GpuLookupTable::upload(
    const GpuDevice& device,
    const void* const data,
    const std::size_t element_count) const noexcept {
    if (!device.is_usable() || buffer_ == nullptr) {
        return GpuKernelStatus::device_unavailable;
    }
    if (data == nullptr || element_count != element_count_) {
        return GpuKernelStatus::invalid_arguments;
    }
    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(device.context()->Map(buffer_, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    std::memcpy(mapped.pData, data, element_count_ * element_bytes_);
    device.context()->Unmap(buffer_, 0U);
    return GpuKernelStatus::ok;
}

}  // namespace negaflow::gpu
