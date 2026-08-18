#include "negaflow/gpu/gpu_film_scan.h"

#include <d3d11.h>

#include <algorithm>
#include <cmath>
#include <cstring>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/film_scan_shrink_FilmScanShrinkMain.h"
#include "negaflow/gpu/shaders/gamma_lift_GammaLiftMain.h"

namespace negaflow::gpu {
namespace {

// HLSL `cbuffer GammaLiftConstants` 와 같은 배치여야 합니다.
struct alignas(16) GammaLiftConstants final {
    GpuPointwiseExtent extent{};
    float power{0.0F};
    float padding[3]{0.0F, 0.0F, 0.0F};
};

static_assert(sizeof(GammaLiftConstants) == 32U, "extent register + power register");

// HLSL `cbuffer FilmScanShrinkConstants` 와 같은 배치여야 합니다.
struct alignas(16) FilmScanShrinkConstants final {
    GpuPointwiseExtent extent{};

    float base_luma_threshold{0.0F};
    float base_chroma_threshold{0.0F};
    float impulse_luma_threshold{0.0F};
    float impulse_chroma_threshold{0.0F};

    float shadow_boost{0.0F};
    float dark_tone_scale{0.0F};
    float highlight_chroma{0.0F};
    float highlight_luma_protect{0.0F};

    float detail_scale{0.0F};
    float grain_protect{0.0F};
    float inverse_gamma_lift_power{0.0F};
    std::int32_t monochrome{0};
};

static_assert(sizeof(FilmScanShrinkConstants) == 64U, "extent + three parameter registers");

[[nodiscard]] std::uint32_t group_count(const std::uint32_t extent, const std::uint32_t size) noexcept {
    return (extent + size - 1U) / size;
}

}  // namespace

GpuKernelStatus GpuGammaLift::create(const GpuDevice& device, GpuGammaLift& kernel) noexcept {
    return GpuPointwiseKernel::create(
        device,
        negaflow_gamma_lift_cs,
        sizeof(negaflow_gamma_lift_cs),
        sizeof(GammaLiftConstants),
        kernel.kernel_);
}

GpuKernelStatus GpuGammaLift::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const float power) const noexcept {
    if (!std::isfinite(power)) {
        return GpuKernelStatus::non_finite_parameter;
    }
    GammaLiftConstants constants{};
    constants.power = power;
    return kernel_.dispatch(device, source, destination, &constants, sizeof(constants));
}

GpuFilmScanShrink::Parameters GpuFilmScanShrink::resolve(
    const imaging::FilmScanDenoiseParameters& parameters) noexcept {
    // `film_scan_denoise_tile.cpp:85-101` 을 그대로 옮긴 것입니다. 곱하는 순서까지 같아야
    // 합니다 — `std::pow` 두 번이 여기 들어 있고, CPU 와 같은 값이 나와야 임계가 같습니다.
    const imaging::FilmScanDenoiseFilmScalars profile =
        imaging::film_scan_denoise_film_scalars(parameters.film_profile);
    const float strength = parameters.strength;
    const float luma_gate = parameters.axes.luma * 2.0F;
    const float chroma_gate = parameters.axes.chroma * 2.0F;

    Parameters resolved{};
    resolved.dark_tone_scale = parameters.axes.dark_tone * 2.0F;
    resolved.detail_scale = 1.5F - parameters.axes.detail;
    resolved.base_luma_threshold = std::max(
        0.065F * std::pow(strength, 1.25F) * profile.luma_scale * luma_gate, 1.0e-6F);
    resolved.base_chroma_threshold = std::max(
        0.14F * std::pow(strength, 1.1F) * profile.chroma_scale * chroma_gate, 1.0e-6F);
    resolved.impulse_luma_threshold = luma_gate > 1.0e-3F
        ? (0.10F - 0.055F * strength) / std::min(luma_gate, 1.0F)
        : 10.0F;
    resolved.impulse_chroma_threshold = chroma_gate > 1.0e-3F
        ? (0.09F - 0.05F * strength) / std::min(chroma_gate, 1.0F)
        : 10.0F;
    resolved.shadow_boost = profile.shadow_boost;
    resolved.highlight_chroma = profile.highlight_chroma;
    resolved.highlight_luma_protect = profile.highlight_luma_protect;
    resolved.grain_protect = parameters.axes.grain_protect;
    resolved.monochrome = profile.monochrome;
    resolved.inverse_gamma_lift_power = imaging::film_scan_denoise_inverse_gamma_lift_power;
    return resolved;
}

GpuFilmScanShrink::~GpuFilmScanShrink() { reset(); }

GpuFilmScanShrink::GpuFilmScanShrink(GpuFilmScanShrink&& other) noexcept
    : shader_(other.shader_), constants_(other.constants_) {
    other.shader_ = nullptr;
    other.constants_ = nullptr;
}

GpuFilmScanShrink& GpuFilmScanShrink::operator=(GpuFilmScanShrink&& other) noexcept {
    if (this != &other) {
        reset();
        shader_ = other.shader_;
        constants_ = other.constants_;
        other.shader_ = nullptr;
        other.constants_ = nullptr;
    }
    return *this;
}

void GpuFilmScanShrink::reset() noexcept {
    if (constants_ != nullptr) {
        constants_->Release();
        constants_ = nullptr;
    }
    if (shader_ != nullptr) {
        shader_->Release();
        shader_ = nullptr;
    }
}

GpuKernelStatus GpuFilmScanShrink::create(
    const GpuDevice& device,
    GpuFilmScanShrink& kernel) noexcept {
    kernel.reset();
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }

    ID3D11ComputeShader* shader = nullptr;
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_film_scan_shrink_cs,
            sizeof(negaflow_film_scan_shrink_cs),
            nullptr,
            &shader))) {
        return GpuKernelStatus::resource_creation_failed;
    }

    D3D11_BUFFER_DESC description{};
    description.ByteWidth = sizeof(FilmScanShrinkConstants);
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

GpuKernelStatus GpuFilmScanShrink::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    const GpuWorkingImage& median_three,
    const GpuWorkingImage& median_five,
    const GpuWorkingImage& fine,
    const GpuWorkingImage& middle,
    const GpuWorkingImage& coarse,
    GpuWorkingImage& destination,
    const Parameters& parameters) const noexcept {
    if (!device.is_usable() || shader_ == nullptr || constants_ == nullptr) {
        return GpuKernelStatus::device_unavailable;
    }

    const GpuWorkingImage* const inputs[6] = {
        &source, &median_three, &median_five, &fine, &middle, &coarse};
    if (!destination.is_valid()) {
        return GpuKernelStatus::invalid_arguments;
    }
    for (const GpuWorkingImage* const input : inputs) {
        if (!input->is_valid() || input->width() != destination.width() ||
            input->height() != destination.height() ||
            input->texture() == destination.texture()) {
            return GpuKernelStatus::invalid_arguments;
        }
    }

    FilmScanShrinkConstants payload{};
    payload.extent.width = destination.width();
    payload.extent.height = destination.height();
    payload.base_luma_threshold = parameters.base_luma_threshold;
    payload.base_chroma_threshold = parameters.base_chroma_threshold;
    payload.impulse_luma_threshold = parameters.impulse_luma_threshold;
    payload.impulse_chroma_threshold = parameters.impulse_chroma_threshold;
    payload.shadow_boost = parameters.shadow_boost;
    payload.dark_tone_scale = parameters.dark_tone_scale;
    payload.highlight_chroma = parameters.highlight_chroma;
    payload.highlight_luma_protect = parameters.highlight_luma_protect;
    payload.detail_scale = parameters.detail_scale;
    payload.grain_protect = parameters.grain_protect;
    payload.inverse_gamma_lift_power = parameters.inverse_gamma_lift_power;
    payload.monochrome = parameters.monochrome ? 1 : 0;

    const float* const scalars = &payload.base_luma_threshold;
    for (std::size_t index = 0U; index < 11U; ++index) {
        if (!std::isfinite(scalars[index])) {
            return GpuKernelStatus::non_finite_parameter;
        }
    }

    ID3D11DeviceContext* context = device.context();

    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context->Map(constants_, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    std::memcpy(mapped.pData, &payload, sizeof(payload));
    context->Unmap(constants_, 0U);

    ID3D11ShaderResourceView* views[6]{};
    for (std::size_t index = 0U; index < 6U; ++index) {
        views[index] = inputs[index]->srv();
    }
    ID3D11UnorderedAccessView* destination_view = destination.uav();
    ID3D11Buffer* constant_view = constants_;

    context->CSSetShader(shader_, nullptr, 0U);
    context->CSSetShaderResources(0U, 6U, views);
    context->CSSetUnorderedAccessViews(0U, 1U, &destination_view, nullptr);
    context->CSSetConstantBuffers(0U, 1U, &constant_view);
    context->Dispatch(
        group_count(destination.width(), gpu_thread_group_width),
        group_count(destination.height(), gpu_thread_group_height),
        1U);

    ID3D11ShaderResourceView* const no_srv[6] = {
        nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
    ID3D11UnorderedAccessView* const no_uav[1] = {nullptr};
    context->CSSetShaderResources(0U, 6U, no_srv);
    context->CSSetUnorderedAccessViews(0U, 1U, no_uav, nullptr);
    context->CSSetShader(nullptr, nullptr, 0U);
    return GpuKernelStatus::ok;
}

}  // namespace negaflow::gpu
