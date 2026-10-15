#include "negaflow/gpu/gpu_local_contrast.h"

#include <d3d11.h>

#include <cmath>
#include <cstring>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_neighborhood.h"
#include "negaflow/gpu/shaders/local_contrast_LocalContrastApplyMain.h"
#include "negaflow/gpu/shaders/local_contrast_LocalContrastCoefficientsMain.h"
#include "negaflow/gpu/shaders/local_contrast_LocalContrastGuideMain.h"
#include "negaflow/imaging/texture_stage.h"

namespace negaflow::gpu {
namespace {

constexpr std::uint32_t local_contrast_group = 8U;

// HLSL `cbuffer LocalContrastConstants` 와 같은 배치여야 합니다.
struct alignas(16) LocalContrastConstants final {
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::uint32_t low_width{0U};
    std::uint32_t low_height{0U};
    std::uint32_t factor{1U};
    float inverse_factor{1.0F};
    float epsilon{0.0F};
    float amount{0.0F};
    float halo{0.0F};
    float padding[3]{0.0F, 0.0F, 0.0F};
};

static_assert(sizeof(LocalContrastConstants) == 48U, "three constant registers");

[[nodiscard]] std::uint32_t group_count(const std::uint32_t extent) noexcept {
    return (extent + local_contrast_group - 1U) / local_contrast_group;
}

void run(
    ID3D11DeviceContext* const context,
    ID3D11ComputeShader* const shader,
    ID3D11Buffer* const constants,
    ID3D11ShaderResourceView* const first,
    ID3D11ShaderResourceView* const second,
    ID3D11UnorderedAccessView* const destination,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    ID3D11ShaderResourceView* const views[2] = {first, second};
    context->CSSetShader(shader, nullptr, 0U);
    context->CSSetShaderResources(0U, 2U, views);
    context->CSSetUnorderedAccessViews(0U, 1U, &destination, nullptr);
    context->CSSetConstantBuffers(0U, 1U, &constants);
    context->Dispatch(group_count(width), group_count(height), 1U);

    ID3D11ShaderResourceView* const no_srv[2] = {nullptr, nullptr};
    ID3D11UnorderedAccessView* const no_uav[1] = {nullptr};
    context->CSSetShaderResources(0U, 2U, no_srv);
    context->CSSetUnorderedAccessViews(0U, 1U, no_uav, nullptr);
    context->CSSetShader(nullptr, nullptr, 0U);
}

} // namespace

GpuLocalContrast::~GpuLocalContrast() { reset(); }

void GpuLocalContrast::reset() noexcept {
    release_scratch();
    if (constants_ != nullptr) {
        constants_->Release();
        constants_ = nullptr;
    }
    if (apply_ != nullptr) {
        apply_->Release();
        apply_ = nullptr;
    }
    if (coefficients_ != nullptr) {
        coefficients_->Release();
        coefficients_ = nullptr;
    }
    if (guide_ != nullptr) {
        guide_->Release();
        guide_ = nullptr;
    }
}

void GpuLocalContrast::release_scratch() noexcept {
    for (GpuWorkingImage& image : low_) {
        image = GpuWorkingImage{};
    }
}

GpuKernelStatus GpuLocalContrast::create(const GpuDevice& device, GpuLocalContrast& kernel) noexcept {
    kernel.reset();
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }

    ID3D11Device* const d3d = device.device();
    if (FAILED(d3d->CreateComputeShader(
            negaflow_local_contrast_guide_cs, sizeof(negaflow_local_contrast_guide_cs), nullptr,
            &kernel.guide_)) ||
        FAILED(d3d->CreateComputeShader(
            negaflow_local_contrast_coefficients_cs, sizeof(negaflow_local_contrast_coefficients_cs),
            nullptr, &kernel.coefficients_)) ||
        FAILED(d3d->CreateComputeShader(
            negaflow_local_contrast_apply_cs, sizeof(negaflow_local_contrast_apply_cs), nullptr,
            &kernel.apply_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }

    D3D11_BUFFER_DESC description{};
    description.ByteWidth = sizeof(LocalContrastConstants);
    description.Usage = D3D11_USAGE_DYNAMIC;
    description.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    description.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    if (FAILED(d3d->CreateBuffer(&description, nullptr, &kernel.constants_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }
    return GpuKernelStatus::ok;
}

bool GpuLocalContrast::ensure_low(
    const GpuDevice& device,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    for (GpuWorkingImage& image : low_) {
        if (image.is_valid() && image.width() == width && image.height() == height) {
            continue;
        }
        if (GpuWorkingImage::create(device, width, height, image) != GpuImageStatus::ok) {
            release_scratch();
            return false;
        }
    }
    return true;
}

GpuKernelStatus GpuLocalContrast::dispatch(
    const GpuDevice& device,
    const GpuGaussianBlur& blur,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const float clarity) noexcept {
    if (!device.is_usable() || !is_valid() || constants_ == nullptr || !blur.is_valid()) {
        return GpuKernelStatus::device_unavailable;
    }
    if (!std::isfinite(clarity)) {
        return GpuKernelStatus::non_finite_parameter;
    }
    if (!source.is_valid() || !destination.is_valid() ||
        source.texture() == destination.texture() ||
        source.width() != destination.width() || source.height() != destination.height()) {
        return GpuKernelStatus::invalid_arguments;
    }

    const std::uint32_t width = source.width();
    const std::uint32_t height = source.height();
    const imaging::LocalContrastPlan plan = imaging::plan_local_contrast(width, height, clarity);
    if (plan.low_width == 0U || plan.low_height == 0U) {
        return GpuKernelStatus::invalid_arguments;
    }
    // CPU `blurred_plane` 과 같은 가중치입니다(지원 반경 하한 1 — `texture_stage` 판).
    std::vector<float> weights{};
    try {
        weights = GpuGaussianBlur::weights_for_sigma(plan.low_sigma, 1);
    } catch (...) {
        return GpuKernelStatus::resource_creation_failed;
    }
    if (!ensure_low(device, plan.low_width, plan.low_height)) {
        return GpuKernelStatus::resource_creation_failed;
    }

    LocalContrastConstants payload{};
    payload.width = width;
    payload.height = height;
    payload.low_width = plan.low_width;
    payload.low_height = plan.low_height;
    payload.factor = plan.factor;
    payload.inverse_factor = 1.0F / static_cast<float>(plan.factor);
    payload.epsilon = imaging::local_contrast_epsilon;
    payload.amount = plan.amount;
    payload.halo = imaging::local_contrast_halo;

    ID3D11DeviceContext* const context = device.context();
    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context->Map(constants_, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    std::memcpy(mapped.pData, &payload, sizeof(payload));
    context->Unmap(constants_, 0U);

    // low_[0] 안내 → (low_[1]) → low_[2] 평균 → low_[0] 계수 → (low_[1]) → low_[2] 평균 계수.
    run(context, guide_, constants_, source.srv(), nullptr, low_[0].uav(), plan.low_width,
        plan.low_height);
    GpuKernelStatus status = blur.dispatch(
        device, low_[0], low_[1], low_[2], weights, GpuGaussianEdgeMode::clamp, false);
    if (status != GpuKernelStatus::ok) {
        return status;
    }
    run(context, coefficients_, constants_, low_[2].srv(), nullptr, low_[0].uav(),
        plan.low_width, plan.low_height);
    status = blur.dispatch(
        device, low_[0], low_[1], low_[2], weights, GpuGaussianEdgeMode::clamp, false);
    if (status != GpuKernelStatus::ok) {
        return status;
    }
    run(context, apply_, constants_, source.srv(), low_[2].srv(), destination.uav(), width,
        height);
    return GpuKernelStatus::ok;
}

} // namespace negaflow::gpu
