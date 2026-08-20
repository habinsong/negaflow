#include "negaflow/gpu/gpu_preview_display_encode.h"

#include <d3d11.h>

#include <cstring>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/preview_display_encode_PreviewDisplayEncodeMain.h"

namespace negaflow::gpu {
namespace {

struct alignas(16) PreviewDisplayEncodeConstants final {
    GpuPointwiseExtent extent{};
    float proof_scale[3]{1.0F, 1.0F, 1.0F};
    float padding0{0.0F};
    float proof_bias[3]{0.0F, 0.0F, 0.0F};
    float padding1{0.0F};
};

static_assert(sizeof(PreviewDisplayEncodeConstants) == 48U, "three constant registers");

[[nodiscard]] std::uint32_t group_count(
    const std::uint32_t extent,
    const std::uint32_t group) noexcept {
    return (extent + group - 1U) / group;
}

}  // namespace

GpuPreviewDisplayEncode::~GpuPreviewDisplayEncode() { reset(); }

void GpuPreviewDisplayEncode::reset() noexcept {
    if (staging_ != nullptr) {
        staging_->Release();
        staging_ = nullptr;
    }
    if (target_uav_ != nullptr) {
        target_uav_->Release();
        target_uav_ = nullptr;
    }
    if (target_ != nullptr) {
        target_->Release();
        target_ = nullptr;
    }
    if (constants_ != nullptr) {
        constants_->Release();
        constants_ = nullptr;
    }
    if (shader_ != nullptr) {
        shader_->Release();
        shader_ = nullptr;
    }
    width_ = 0U;
    height_ = 0U;
}

GpuKernelStatus GpuPreviewDisplayEncode::create(
    const GpuDevice& device,
    GpuPreviewDisplayEncode& kernel) noexcept {
    kernel.reset();
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }
    ID3D11ComputeShader* shader = nullptr;
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_preview_display_encode_cs,
            sizeof(negaflow_preview_display_encode_cs),
            nullptr,
            &shader))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    D3D11_BUFFER_DESC description{};
    description.ByteWidth = sizeof(PreviewDisplayEncodeConstants);
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

bool GpuPreviewDisplayEncode::ensure_target(
    const GpuDevice& device,
    const std::uint32_t width,
    const std::uint32_t height) const noexcept {
    if (target_ != nullptr && width_ == width && height_ == height) {
        return true;
    }
    if (staging_ != nullptr) {
        staging_->Release();
        staging_ = nullptr;
    }
    if (target_uav_ != nullptr) {
        target_uav_->Release();
        target_uav_ = nullptr;
    }
    if (target_ != nullptr) {
        target_->Release();
        target_ = nullptr;
    }
    width_ = 0U;
    height_ = 0U;

    D3D11_TEXTURE2D_DESC description{};
    description.Width = width;
    description.Height = height;
    description.MipLevels = 1U;
    description.ArraySize = 1U;
    description.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    description.SampleDesc.Count = 1U;
    description.Usage = D3D11_USAGE_DEFAULT;
    description.BindFlags = D3D11_BIND_UNORDERED_ACCESS;
    ID3D11Texture2D* target = nullptr;
    if (FAILED(device.device()->CreateTexture2D(&description, nullptr, &target))) {
        return false;
    }
    ID3D11UnorderedAccessView* uav = nullptr;
    if (FAILED(device.device()->CreateUnorderedAccessView(target, nullptr, &uav))) {
        target->Release();
        return false;
    }
    D3D11_TEXTURE2D_DESC staging_description = description;
    staging_description.Usage = D3D11_USAGE_STAGING;
    staging_description.BindFlags = 0U;
    staging_description.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    ID3D11Texture2D* staging = nullptr;
    if (FAILED(device.device()->CreateTexture2D(&staging_description, nullptr, &staging))) {
        uav->Release();
        target->Release();
        return false;
    }
    target_ = target;
    target_uav_ = uav;
    staging_ = staging;
    width_ = width;
    height_ = height;
    return true;
}

GpuKernelStatus GpuPreviewDisplayEncode::encode(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    std::uint8_t* const destination,
    const std::uint32_t destination_stride_bytes,
    const float proof_scale[3],
    const float proof_bias[3]) const noexcept {
    if (!device.is_usable() || shader_ == nullptr || constants_ == nullptr) {
        return GpuKernelStatus::device_unavailable;
    }
    if (!source.is_valid() || destination == nullptr || proof_scale == nullptr ||
        proof_bias == nullptr) {
        return GpuKernelStatus::invalid_arguments;
    }
    const std::uint32_t width = source.width();
    const std::uint32_t height = source.height();
    if (destination_stride_bytes < width * 4U) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (!ensure_target(device, width, height)) {
        return GpuKernelStatus::resource_creation_failed;
    }

    PreviewDisplayEncodeConstants payload{};
    payload.extent.width = width;
    payload.extent.height = height;
    payload.proof_scale[0] = proof_scale[0];
    payload.proof_scale[1] = proof_scale[1];
    payload.proof_scale[2] = proof_scale[2];
    payload.proof_bias[0] = proof_bias[0];
    payload.proof_bias[1] = proof_bias[1];
    payload.proof_bias[2] = proof_bias[2];

    ID3D11DeviceContext* const context = device.context();
    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context->Map(constants_, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    std::memcpy(mapped.pData, &payload, sizeof(payload));
    context->Unmap(constants_, 0U);

    ID3D11ShaderResourceView* source_view = source.srv();
    ID3D11UnorderedAccessView* dest_view = target_uav_;
    ID3D11Buffer* constant_view = constants_;
    context->CSSetShader(shader_, nullptr, 0U);
    context->CSSetShaderResources(0U, 1U, &source_view);
    context->CSSetUnorderedAccessViews(0U, 1U, &dest_view, nullptr);
    context->CSSetConstantBuffers(0U, 1U, &constant_view);
    context->Dispatch(
        group_count(width, gpu_thread_group_width),
        group_count(height, gpu_thread_group_height),
        1U);
    ID3D11ShaderResourceView* const no_srv[1] = {nullptr};
    ID3D11UnorderedAccessView* const no_uav[1] = {nullptr};
    context->CSSetShaderResources(0U, 1U, no_srv);
    context->CSSetUnorderedAccessViews(0U, 1U, no_uav, nullptr);
    context->CSSetShader(nullptr, nullptr, 0U);

    context->CopyResource(staging_, target_);
    D3D11_MAPPED_SUBRESOURCE read{};
    if (FAILED(context->Map(staging_, 0U, D3D11_MAP_READ, 0U, &read))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    const auto* const src = static_cast<const std::uint8_t*>(read.pData);
    const std::uint32_t row_bytes = width * 4U;
    for (std::uint32_t y = 0U; y < height; ++y) {
        std::memcpy(
            destination + (static_cast<std::size_t>(y) * destination_stride_bytes),
            src + (static_cast<std::size_t>(y) * read.RowPitch),
            row_bytes);
    }
    context->Unmap(staging_, 0U);
    record_gpu_bgra_download(width, height);
    return GpuKernelStatus::ok;
}

}  // namespace negaflow::gpu
