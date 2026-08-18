#include "negaflow/gpu/gpu_digital_halation.h"

#include <d3d11.h>

#include <algorithm>
#include <cmath>
#include <cstring>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/digital_halation_HalationAccumulateMain.h"
#include "negaflow/gpu/shaders/digital_halation_HalationBaseMain.h"

namespace negaflow::gpu {
namespace {

// HLSL `cbuffer HalationConstants` 와 같은 배치여야 합니다.
struct alignas(16) HalationConstants final {
    GpuPointwiseExtent extent{};
    float scale[3]{0.0F, 0.0F, 0.0F};
    float padding{0.0F};
};

static_assert(sizeof(HalationConstants) == 32U, "extent register + scale register");

[[nodiscard]] std::uint32_t group_count(
    const std::uint32_t extent,
    const std::uint32_t size) noexcept {
    return (extent + size - 1U) / size;
}

void run_pass(
    ID3D11DeviceContext* context,
    ID3D11ComputeShader* shader,
    ID3D11Buffer* constants,
    ID3D11ShaderResourceView* const* sources,
    const UINT source_count,
    GpuWorkingImage& output,
    const std::uint32_t groups_x,
    const std::uint32_t groups_y) noexcept {
    ID3D11UnorderedAccessView* destination_view = output.uav();
    context->CSSetShader(shader, nullptr, 0U);
    context->CSSetShaderResources(0U, source_count, sources);
    context->CSSetUnorderedAccessViews(0U, 1U, &destination_view, nullptr);
    context->CSSetConstantBuffers(0U, 1U, &constants);
    context->Dispatch(groups_x, groups_y, 1U);

    // 다음 패스가 같은 텍스처를 반대 역할로 묶으므로 반드시 풀어 둡니다.
    ID3D11ShaderResourceView* const no_srv[2] = {nullptr, nullptr};
    ID3D11UnorderedAccessView* const no_uav[1] = {nullptr};
    context->CSSetShaderResources(0U, 2U, no_srv);
    context->CSSetUnorderedAccessViews(0U, 1U, no_uav, nullptr);
    context->CSSetShader(nullptr, nullptr, 0U);
}

[[nodiscard]] bool write_constants(
    const GpuDevice& device,
    ID3D11Buffer* constants,
    const GpuWorkingImage& reference,
    const std::array<float, 3>& scale) noexcept {
    HalationConstants payload{};
    payload.extent.width = reference.width();
    payload.extent.height = reference.height();
    payload.scale[0] = scale[0];
    payload.scale[1] = scale[1];
    payload.scale[2] = scale[2];

    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(device.context()->Map(constants, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
        return false;
    }
    std::memcpy(mapped.pData, &payload, sizeof(payload));
    device.context()->Unmap(constants, 0U);
    return true;
}

}  // namespace

GpuDigitalHalation::~GpuDigitalHalation() { reset(); }

GpuDigitalHalation::GpuDigitalHalation(GpuDigitalHalation&& other) noexcept
    : base_(other.base_), accumulate_(other.accumulate_), constants_(other.constants_) {
    other.base_ = nullptr;
    other.accumulate_ = nullptr;
    other.constants_ = nullptr;
}

GpuDigitalHalation& GpuDigitalHalation::operator=(GpuDigitalHalation&& other) noexcept {
    if (this != &other) {
        reset();
        base_ = other.base_;
        accumulate_ = other.accumulate_;
        constants_ = other.constants_;
        other.base_ = nullptr;
        other.accumulate_ = nullptr;
        other.constants_ = nullptr;
    }
    return *this;
}

void GpuDigitalHalation::reset() noexcept {
    if (constants_ != nullptr) {
        constants_->Release();
        constants_ = nullptr;
    }
    if (accumulate_ != nullptr) {
        accumulate_->Release();
        accumulate_ = nullptr;
    }
    if (base_ != nullptr) {
        base_->Release();
        base_ = nullptr;
    }
}

GpuDigitalHalation::Parameters GpuDigitalHalation::resolve(
    const imaging::DigitalHalationMaterial& material,
    const double strength,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    // `digital_halation.cpp:219-263` 을 그대로 옮긴 것입니다.
    Parameters resolved{};

    bool valid = std::isfinite(strength) && std::isfinite(material.radius_ratio) &&
                 material.radius_ratio >= 0.0;
    for (const double value : material.scatter_strength) {
        valid = valid && std::isfinite(value) && value >= 0.0;
    }
    for (const double value : material.halation_strength) {
        valid = valid && std::isfinite(value) && value >= 0.0;
    }
    if (!valid) {
        return resolved;
    }

    const auto amount = static_cast<float>(std::clamp(strength, 0.0, 1.0));
    const std::uint32_t reference = std::min(width, height);
    if (amount <= 1.0e-3F || reference <= 8U || material.radius_ratio <= 0.0) {
        // CPU 의 조기 반환과 같은 자리입니다 — 원본 그대로 나갑니다.
        return resolved;
    }

    std::array<float, 3> scatter{};
    std::array<float, 3> halation{};
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        scatter[channel] = static_cast<float>(material.scatter_strength[channel] * amount);
        halation[channel] = static_cast<float>(material.halation_strength[channel] * amount);
        resolved.keep[channel] =
            std::max(1.0F - scatter[channel] - halation[channel], 0.0F);
        resolved.far_scale[channel] = halation[channel] * 0.68F;
        resolved.wide_scale[channel] = halation[channel] * 0.32F;
    }
    resolved.scatter = scatter;

    const float far_radius =
        std::max(1.0F, static_cast<float>(reference * material.radius_ratio));
    resolved.far_sigma = far_radius;
    resolved.near_sigma = std::max(0.6F, far_radius * 0.28F);
    resolved.wide_sigma = far_radius * 1.414F;
    resolved.applied = true;
    return resolved;
}

GpuKernelStatus GpuDigitalHalation::create(
    const GpuDevice& device,
    GpuDigitalHalation& kernel) noexcept {
    kernel.reset();
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }

    ID3D11ComputeShader* base = nullptr;
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_halation_base_cs, sizeof(negaflow_halation_base_cs), nullptr, &base))) {
        return GpuKernelStatus::resource_creation_failed;
    }

    ID3D11ComputeShader* accumulate = nullptr;
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_halation_accumulate_cs,
            sizeof(negaflow_halation_accumulate_cs),
            nullptr,
            &accumulate))) {
        base->Release();
        return GpuKernelStatus::resource_creation_failed;
    }

    D3D11_BUFFER_DESC description{};
    description.ByteWidth = sizeof(HalationConstants);
    description.Usage = D3D11_USAGE_DYNAMIC;
    description.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    description.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

    ID3D11Buffer* constants = nullptr;
    if (FAILED(device.device()->CreateBuffer(&description, nullptr, &constants))) {
        accumulate->Release();
        base->Release();
        return GpuKernelStatus::resource_creation_failed;
    }

    kernel.base_ = base;
    kernel.accumulate_ = accumulate;
    kernel.constants_ = constants;
    return GpuKernelStatus::ok;
}

GpuKernelStatus GpuDigitalHalation::dispatch(
    const GpuDevice& device,
    const GpuGaussianBlur& gaussian,
    const GpuWorkingImage& source,
    GpuWorkingImage* const scratch,
    GpuWorkingImage& destination,
    const Parameters& parameters) const noexcept {
    if (!device.is_usable() || base_ == nullptr || accumulate_ == nullptr ||
        !gaussian.is_valid()) {
        return GpuKernelStatus::device_unavailable;
    }
    if (scratch == nullptr || !source.is_valid() || !destination.is_valid()) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (destination.width() != source.width() || destination.height() != source.height() ||
        destination.texture() == source.texture()) {
        return GpuKernelStatus::invalid_arguments;
    }
    for (int index = 0; index < scratch_count; ++index) {
        if (!scratch[index].is_valid() || scratch[index].width() != source.width() ||
            scratch[index].height() != source.height()) {
            return GpuKernelStatus::invalid_arguments;
        }
    }
    if (!parameters.applied) {
        // CPU 의 조기 반환과 같습니다 — 커널을 돌리면 곱셈 반올림이 붙습니다.
        const GpuImageStatus copied = destination.copy_from(device, source);
        return copied == GpuImageStatus::ok ? GpuKernelStatus::ok
                                            : GpuKernelStatus::invalid_arguments;
    }

    // 이름표. 순서를 바꾸면 아래가 전부 어긋납니다.
    GpuWorkingImage& accumulator = scratch[0];
    GpuWorkingImage& spare = scratch[1];
    GpuWorkingImage& blur_scratch = scratch[2];
    GpuWorkingImage& blurred = scratch[3];

    ID3D11DeviceContext* context = device.context();
    const std::uint32_t groups_x = group_count(source.width(), gpu_thread_group_width);
    const std::uint32_t groups_y = group_count(source.height(), gpu_thread_group_height);

    // 1. 기저 — 원본에서 덜어냅니다.
    if (!write_constants(device, constants_, source, parameters.keep)) {
        return GpuKernelStatus::resource_creation_failed;
    }
    {
        ID3D11ShaderResourceView* const sources[1] = {source.srv()};
        run_pass(context, base_, constants_, sources, 1U, accumulator, groups_x, groups_y);
    }

    // 2~4. 세 반경을 CPU 와 **같은 순서**로 누적합니다 — near → far → wide.
    //      마지막 것만 `destination` 에 씁니다.
    const struct {
        float sigma;
        const std::array<float, 3>* scale;
    } passes[3] = {
        {parameters.near_sigma, &parameters.scatter},
        {parameters.far_sigma, &parameters.far_scale},
        {parameters.wide_sigma, &parameters.wide_scale},
    };

    GpuWorkingImage* read = &accumulator;
    GpuWorkingImage* write = &spare;
    for (int index = 0; index < 3; ++index) {
        const std::vector<float> weights =
            GpuGaussianBlur::weights_for_halation_sigma(passes[index].sigma);
        // 블러는 언제나 **원본**입니다. 누적본을 흐리면 안 됩니다.
        if (gaussian.dispatch(
                device,
                source,
                blur_scratch,
                blurred,
                weights,
                GpuGaussianEdgeMode::clamp,
                false) != GpuKernelStatus::ok) {
            return GpuKernelStatus::invalid_arguments;
        }
        if (!write_constants(device, constants_, source, *passes[index].scale)) {
            return GpuKernelStatus::resource_creation_failed;
        }
        GpuWorkingImage& target = index == 2 ? destination : *write;
        ID3D11ShaderResourceView* const sources[2] = {read->srv(), blurred.srv()};
        run_pass(context, accumulate_, constants_, sources, 2U, target, groups_x, groups_y);
        std::swap(read, write);
    }
    return GpuKernelStatus::ok;
}

}  // namespace negaflow::gpu
