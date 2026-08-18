#include "negaflow/gpu/gpu_scratch_angle.h"

#include <d3d11.h>

#include <algorithm>
#include <cstring>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/scratch_angle_RidgeMain.h"
#include "negaflow/gpu/shaders/scratch_angle_IntegrateMain.h"
#include "negaflow/gpu/shaders/scratch_angle_MaxMain.h"

namespace negaflow::gpu {
namespace {

struct alignas(16) ScratchTap final {
    std::int32_t x{0};
    std::int32_t y{0};
    std::int32_t z{0};
    std::int32_t w{0};
};

struct alignas(16) ScratchAngleConstants final {
    GpuPointwiseExtent extent{};
    std::int32_t tap_count{0};
    float balance_limit{0.0F};
    std::int32_t accumulate{0};
    std::int32_t padding{0};
    ScratchTap center[5]{};
    ScratchTap positive[5]{};
    ScratchTap negative[5]{};
    ScratchTap along[25]{};
};

static_assert(sizeof(ScratchAngleConstants) == 16U + 16U + 80U + 80U + 80U + 400U,
    "extent + header + 5+5+5+25 int4 taps");

[[nodiscard]] std::uint32_t group_count(const std::uint32_t extent) noexcept {
    return (extent + gpu_thread_group_width - 1U) / gpu_thread_group_width;
}

void fill_taps(ScratchTap* const destination, const std::int32_t (*source)[2], const int count) {
    for (int index = 0; index < count; ++index) {
        destination[index].x = source[index][0];
        destination[index].y = source[index][1];
    }
}

GpuKernelStatus bind_and_dispatch(
    const GpuDevice& device,
    ID3D11ComputeShader* const shader,
    ID3D11Buffer* const constants,
    const ScratchAngleConstants& payload,
    const GpuWorkingImage& source,
    const GpuWorkingImage* const other,
    GpuWorkingImage& destination) noexcept {
    ID3D11DeviceContext* context = device.context();
    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context->Map(constants, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    std::memcpy(mapped.pData, &payload, sizeof(payload));
    context->Unmap(constants, 0U);

    ID3D11ShaderResourceView* views[2] = {
        source.srv(),
        other != nullptr ? other->srv() : nullptr,
    };
    ID3D11UnorderedAccessView* destination_view = destination.uav();
    context->CSSetShader(shader, nullptr, 0U);
    context->CSSetShaderResources(0U, 2U, views);
    context->CSSetUnorderedAccessViews(0U, 1U, &destination_view, nullptr);
    context->CSSetConstantBuffers(0U, 1U, &constants);
    context->Dispatch(group_count(source.width()), group_count(source.height()), 1U);

    ID3D11ShaderResourceView* const no_srv[2] = {nullptr, nullptr};
    ID3D11UnorderedAccessView* const no_uav[1] = {nullptr};
    context->CSSetShaderResources(0U, 2U, no_srv);
    context->CSSetUnorderedAccessViews(0U, 1U, no_uav, nullptr);
    context->CSSetShader(nullptr, nullptr, 0U);
    return GpuKernelStatus::ok;
}

}  // namespace

GpuScratchAngle::~GpuScratchAngle() { reset(); }

GpuScratchAngle::GpuScratchAngle(GpuScratchAngle&& other) noexcept
    : ridge_(other.ridge_),
      integrate_(other.integrate_),
      max_(other.max_),
      constants_(other.constants_) {
    other.ridge_ = nullptr;
    other.integrate_ = nullptr;
    other.max_ = nullptr;
    other.constants_ = nullptr;
}

GpuScratchAngle& GpuScratchAngle::operator=(GpuScratchAngle&& other) noexcept {
    if (this != &other) {
        reset();
        ridge_ = other.ridge_;
        integrate_ = other.integrate_;
        max_ = other.max_;
        constants_ = other.constants_;
        other.ridge_ = nullptr;
        other.integrate_ = nullptr;
        other.max_ = nullptr;
        other.constants_ = nullptr;
    }
    return *this;
}

void GpuScratchAngle::reset() noexcept {
    if (constants_ != nullptr) {
        constants_->Release();
        constants_ = nullptr;
    }
    if (max_ != nullptr) {
        max_->Release();
        max_ = nullptr;
    }
    if (integrate_ != nullptr) {
        integrate_->Release();
        integrate_ = nullptr;
    }
    if (ridge_ != nullptr) {
        ridge_->Release();
        ridge_ = nullptr;
    }
}

GpuKernelStatus GpuScratchAngle::create(
    const GpuDevice& device,
    GpuScratchAngle& kernel) noexcept {
    kernel.reset();
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }
    ID3D11ComputeShader* ridge = nullptr;
    ID3D11ComputeShader* integrate = nullptr;
    ID3D11ComputeShader* max_shader = nullptr;
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_scratch_angle_ridge_cs,
            sizeof(negaflow_scratch_angle_ridge_cs),
            nullptr,
            &ridge))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_scratch_angle_integrate_cs,
            sizeof(negaflow_scratch_angle_integrate_cs),
            nullptr,
            &integrate))) {
        ridge->Release();
        return GpuKernelStatus::resource_creation_failed;
    }
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_scratch_angle_max_cs,
            sizeof(negaflow_scratch_angle_max_cs),
            nullptr,
            &max_shader))) {
        integrate->Release();
        ridge->Release();
        return GpuKernelStatus::resource_creation_failed;
    }
    D3D11_BUFFER_DESC description{};
    description.ByteWidth = sizeof(ScratchAngleConstants);
    description.Usage = D3D11_USAGE_DYNAMIC;
    description.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    description.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    ID3D11Buffer* constants = nullptr;
    if (FAILED(device.device()->CreateBuffer(&description, nullptr, &constants))) {
        max_shader->Release();
        integrate->Release();
        ridge->Release();
        return GpuKernelStatus::resource_creation_failed;
    }
    kernel.ridge_ = ridge;
    kernel.integrate_ = integrate;
    kernel.max_ = max_shader;
    kernel.constants_ = constants;
    return GpuKernelStatus::ok;
}

GpuKernelStatus GpuScratchAngle::dispatch_ridge(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const imaging::ScratchAngleTaps& taps,
    const float balance_limit) const noexcept {
    if (!device.is_usable() || ridge_ == nullptr || constants_ == nullptr) {
        return GpuKernelStatus::device_unavailable;
    }
    if (!source.is_valid() || !destination.is_valid() ||
        source.texture() == destination.texture()) {
        return GpuKernelStatus::invalid_arguments;
    }
    ScratchAngleConstants payload{};
    payload.extent.width = source.width();
    payload.extent.height = source.height();
    payload.tap_count = 5;
    payload.balance_limit = balance_limit;
    fill_taps(payload.center, taps.center, 5);
    fill_taps(payload.positive, taps.positive, 5);
    fill_taps(payload.negative, taps.negative, 5);
    return bind_and_dispatch(device, ridge_, constants_, payload, source, nullptr, destination);
}

GpuKernelStatus GpuScratchAngle::dispatch_integrate(
    const GpuDevice& device,
    const GpuWorkingImage& ridge,
    GpuWorkingImage& destination,
    const std::int32_t (*const along)[2],
    const int tap_count,
    const bool accumulate) const noexcept {
    if (!device.is_usable() || integrate_ == nullptr || constants_ == nullptr) {
        return GpuKernelStatus::device_unavailable;
    }
    if (!ridge.is_valid() || !destination.is_valid() ||
        ridge.texture() == destination.texture() || tap_count <= 0 || tap_count > 25) {
        return GpuKernelStatus::invalid_arguments;
    }
    ScratchAngleConstants payload{};
    payload.extent.width = ridge.width();
    payload.extent.height = ridge.height();
    payload.tap_count = tap_count;
    payload.accumulate = accumulate ? 1 : 0;
    fill_taps(payload.along, along, tap_count);
    return bind_and_dispatch(
        device, integrate_, constants_, payload, ridge, nullptr, destination);
}

GpuKernelStatus GpuScratchAngle::dispatch_max(
    const GpuDevice& device,
    const GpuWorkingImage& integrated,
    const GpuWorkingImage& ridge,
    GpuWorkingImage& best) const noexcept {
    if (!device.is_usable() || max_ == nullptr || constants_ == nullptr) {
        return GpuKernelStatus::device_unavailable;
    }
    if (!integrated.is_valid() || !ridge.is_valid() || !best.is_valid()) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (best.texture() == integrated.texture() || best.texture() == ridge.texture()) {
        return GpuKernelStatus::invalid_arguments;
    }
    ScratchAngleConstants payload{};
    payload.extent.width = best.width();
    payload.extent.height = best.height();
    return bind_and_dispatch(device, max_, constants_, payload, integrated, &ridge, best);
}

}  // namespace negaflow::gpu
