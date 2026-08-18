#include "negaflow/gpu/gpu_neighborhood.h"

#include <d3d11.h>

#include <cstring>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/guided_filter_GuidedApplyMain.h"
#include "negaflow/gpu/shaders/guided_filter_GuidedCoefficientsMain.h"
#include "negaflow/gpu/shaders/guided_filter_GuidedPrepareMain.h"

namespace negaflow::gpu {
namespace {

constexpr std::uint32_t guided_group = 8U;

// HLSL `cbuffer GuidedFilterConstants` 와 같은 배치여야 합니다.
struct alignas(16) GuidedFilterConstants final {
    GpuPointwiseExtent extent{};
    float epsilon{0.0F};
    float padding[3]{0.0F, 0.0F, 0.0F};
};

static_assert(sizeof(GuidedFilterConstants) == 32U, "extent register + epsilon register");

[[nodiscard]] std::uint32_t group_count(const std::uint32_t extent) noexcept {
    return (extent + guided_group - 1U) / guided_group;
}

// SRV 를 최대 셋, UAV 를 최대 둘 묶습니다. 끝나면 반드시 풀어야 합니다 — 다음 패스가
// 같은 텍스처를 반대 역할로 묶기 때문입니다.
void run_pass(
    ID3D11DeviceContext* context,
    ID3D11ComputeShader* shader,
    ID3D11Buffer* constants,
    ID3D11ShaderResourceView* const* sources,
    const UINT source_count,
    ID3D11UnorderedAccessView* const* destinations,
    const UINT destination_count,
    const std::uint32_t groups_x,
    const std::uint32_t groups_y) noexcept {
    context->CSSetShader(shader, nullptr, 0U);
    context->CSSetShaderResources(0U, source_count, sources);
    context->CSSetUnorderedAccessViews(0U, destination_count, destinations, nullptr);
    context->CSSetConstantBuffers(0U, 1U, &constants);
    context->Dispatch(groups_x, groups_y, 1U);

    ID3D11ShaderResourceView* const no_srv[3] = {nullptr, nullptr, nullptr};
    ID3D11UnorderedAccessView* const no_uav[2] = {nullptr, nullptr};
    context->CSSetShaderResources(0U, 3U, no_srv);
    context->CSSetUnorderedAccessViews(0U, 2U, no_uav, nullptr);
    context->CSSetShader(nullptr, nullptr, 0U);
}

}  // namespace

GpuGuidedFilter::~GpuGuidedFilter() { reset(); }

GpuGuidedFilter::GpuGuidedFilter(GpuGuidedFilter&& other) noexcept
    : prepare_(other.prepare_),
      coefficients_(other.coefficients_),
      apply_(other.apply_),
      constants_(other.constants_) {
    other.prepare_ = nullptr;
    other.coefficients_ = nullptr;
    other.apply_ = nullptr;
    other.constants_ = nullptr;
}

GpuGuidedFilter& GpuGuidedFilter::operator=(GpuGuidedFilter&& other) noexcept {
    if (this != &other) {
        reset();
        prepare_ = other.prepare_;
        coefficients_ = other.coefficients_;
        apply_ = other.apply_;
        constants_ = other.constants_;
        other.prepare_ = nullptr;
        other.coefficients_ = nullptr;
        other.apply_ = nullptr;
        other.constants_ = nullptr;
    }
    return *this;
}

void GpuGuidedFilter::reset() noexcept {
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
    if (prepare_ != nullptr) {
        prepare_->Release();
        prepare_ = nullptr;
    }
}

GpuKernelStatus GpuGuidedFilter::create(
    const GpuDevice& device,
    GpuGuidedFilter& kernel) noexcept {
    kernel.reset();
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }

    ID3D11ComputeShader* prepare = nullptr;
    ID3D11ComputeShader* coefficients = nullptr;
    ID3D11ComputeShader* apply = nullptr;
    ID3D11Buffer* constants = nullptr;

    const auto fail = [&]() noexcept {
        if (apply != nullptr) {
            apply->Release();
        }
        if (coefficients != nullptr) {
            coefficients->Release();
        }
        if (prepare != nullptr) {
            prepare->Release();
        }
        return GpuKernelStatus::resource_creation_failed;
    };

    if (FAILED(device.device()->CreateComputeShader(
            negaflow_guided_prepare_cs, sizeof(negaflow_guided_prepare_cs), nullptr, &prepare))) {
        return fail();
    }
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_guided_coefficients_cs,
            sizeof(negaflow_guided_coefficients_cs),
            nullptr,
            &coefficients))) {
        return fail();
    }
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_guided_apply_cs, sizeof(negaflow_guided_apply_cs), nullptr, &apply))) {
        return fail();
    }

    D3D11_BUFFER_DESC description{};
    description.ByteWidth = sizeof(GuidedFilterConstants);
    description.Usage = D3D11_USAGE_DYNAMIC;
    description.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    description.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    if (FAILED(device.device()->CreateBuffer(&description, nullptr, &constants))) {
        return fail();
    }

    kernel.prepare_ = prepare;
    kernel.coefficients_ = coefficients;
    kernel.apply_ = apply;
    kernel.constants_ = constants;
    return GpuKernelStatus::ok;
}

GpuKernelStatus GpuGuidedFilter::dispatch(
    const GpuDevice& device,
    const GpuBoxBlur& blur,
    const GpuWorkingImage& packed,
    GpuWorkingImage* const scratch,
    GpuWorkingImage& destination,
    const std::int32_t radius,
    const float epsilon) const noexcept {
    if (!device.is_usable() || prepare_ == nullptr || !blur.is_valid()) {
        return GpuKernelStatus::device_unavailable;
    }
    if (scratch == nullptr || !packed.is_valid() || !destination.is_valid()) {
        return GpuKernelStatus::invalid_arguments;
    }
    for (int index = 0; index < scratch_count; ++index) {
        if (!scratch[index].is_valid() || scratch[index].width() != packed.width() ||
            scratch[index].height() != packed.height()) {
            return GpuKernelStatus::invalid_arguments;
        }
    }
    if (destination.width() != packed.width() || destination.height() != packed.height()) {
        return GpuKernelStatus::invalid_arguments;
    }

    ID3D11DeviceContext* context = device.context();

    GuidedFilterConstants payload{};
    payload.extent.width = packed.width();
    payload.extent.height = packed.height();
    payload.epsilon = epsilon;

    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context->Map(constants_, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    std::memcpy(mapped.pData, &payload, sizeof(payload));
    context->Unmap(constants_, 0U);

    const std::uint32_t groups_x = group_count(packed.width());
    const std::uint32_t groups_y = group_count(packed.height());

    // 중간 텍스처 이름표. 순서를 바꾸면 아래 패스가 전부 어긋납니다.
    GpuWorkingImage& product = scratch[0];
    GpuWorkingImage& mean_first = scratch[1];
    GpuWorkingImage& mean_second = scratch[2];
    GpuWorkingImage& coefficient_a = scratch[3];
    GpuWorkingImage& coefficient_b = scratch[4];
    GpuWorkingImage& work = scratch[5];

    // 1. guide 제곱과 source×guide.
    {
        ID3D11ShaderResourceView* const sources[1] = {packed.srv()};
        ID3D11UnorderedAccessView* const destinations[1] = {product.uav()};
        run_pass(
            context, prepare_, constants_, sources, 1U, destinations, 1U, groups_x, groups_y);
    }

    // 2. 네 스칼라의 박스 평균. **알파까지 흘려야** 가이드와 guide 제곱이 함께 평균됩니다.
    if (blur.dispatch(device, packed, work, mean_first, radius, true) != GpuKernelStatus::ok) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (blur.dispatch(device, product, work, mean_second, radius, true) != GpuKernelStatus::ok) {
        return GpuKernelStatus::invalid_arguments;
    }

    // 3. a 와 b.
    {
        ID3D11ShaderResourceView* const sources[2] = {mean_first.srv(), mean_second.srv()};
        ID3D11UnorderedAccessView* const destinations[2] = {
            coefficient_a.uav(), coefficient_b.uav()};
        run_pass(
            context,
            coefficients_,
            constants_,
            sources,
            2U,
            destinations,
            2U,
            groups_x,
            groups_y);
    }

    // 4. a 와 b 의 박스 평균. 앞의 평균 두 장을 재사용합니다.
    if (blur.dispatch(device, coefficient_a, work, mean_first, radius, true) !=
        GpuKernelStatus::ok) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (blur.dispatch(device, coefficient_b, work, mean_second, radius, true) !=
        GpuKernelStatus::ok) {
        return GpuKernelStatus::invalid_arguments;
    }

    // 5. 적용.
    {
        ID3D11ShaderResourceView* const sources[3] = {
            mean_first.srv(), mean_second.srv(), packed.srv()};
        ID3D11UnorderedAccessView* const destinations[1] = {destination.uav()};
        run_pass(
            context, apply_, constants_, sources, 3U, destinations, 1U, groups_x, groups_y);
    }
    return GpuKernelStatus::ok;
}

}  // namespace negaflow::gpu
