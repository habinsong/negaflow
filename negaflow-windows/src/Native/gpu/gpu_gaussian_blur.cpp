#include "negaflow/gpu/gpu_neighborhood.h"

#include <d3d11.h>

#include <algorithm>
#include <cmath>
#include <cstring>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/gaussian_blur_GaussianHorizontalMain.h"
#include "negaflow/gpu/shaders/gaussian_blur_GaussianVerticalMain.h"
#include "negaflow/imaging/coreimage_gaussian.h"

namespace negaflow::gpu {
namespace {

// 셰이더의 `[numthreads(8, 8, 1)]` 과 반드시 같아야 합니다. 박스 블러와 달리 러닝 섬이
// 아니라 화소마다 독립이라 2D 로 갑니다.
constexpr std::uint32_t gaussian_group = 8U;

// HLSL `cbuffer GaussianConstants` 와 같은 배치여야 합니다.
struct alignas(16) GaussianConstants final {
    GpuPointwiseExtent extent{};
    std::int32_t radius{0};
    std::int32_t edge_mode{0};
    std::int32_t blur_alpha{0};
    float padding{0.0F};
};

static_assert(sizeof(GaussianConstants) == 32U, "extent register + radius register");

[[nodiscard]] std::uint32_t group_count(const std::uint32_t extent) noexcept {
    return (extent + gaussian_group - 1U) / gaussian_group;
}

void run_pass(
    ID3D11DeviceContext* context,
    ID3D11ComputeShader* shader,
    ID3D11Buffer* constants,
    ID3D11ShaderResourceView* weights,
    const GpuWorkingImage& input,
    GpuWorkingImage& output,
    const std::uint32_t groups_x,
    const std::uint32_t groups_y) noexcept {
    ID3D11ShaderResourceView* const sources[2] = {input.srv(), weights};
    ID3D11UnorderedAccessView* destination_view = output.uav();

    context->CSSetShader(shader, nullptr, 0U);
    context->CSSetShaderResources(0U, 2U, sources);
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

}  // namespace

GpuGaussianBlur::~GpuGaussianBlur() { reset(); }

GpuGaussianBlur::GpuGaussianBlur(GpuGaussianBlur&& other) noexcept
    : horizontal_(other.horizontal_),
      vertical_(other.vertical_),
      constants_(other.constants_),
      weights_(other.weights_),
      weights_view_(other.weights_view_),
      weight_capacity_(other.weight_capacity_) {
    other.horizontal_ = nullptr;
    other.vertical_ = nullptr;
    other.constants_ = nullptr;
    other.weights_ = nullptr;
    other.weights_view_ = nullptr;
    other.weight_capacity_ = 0U;
}

GpuGaussianBlur& GpuGaussianBlur::operator=(GpuGaussianBlur&& other) noexcept {
    if (this != &other) {
        reset();
        horizontal_ = other.horizontal_;
        vertical_ = other.vertical_;
        constants_ = other.constants_;
        weights_ = other.weights_;
        weights_view_ = other.weights_view_;
        weight_capacity_ = other.weight_capacity_;
        other.horizontal_ = nullptr;
        other.vertical_ = nullptr;
        other.constants_ = nullptr;
        other.weights_ = nullptr;
        other.weights_view_ = nullptr;
        other.weight_capacity_ = 0U;
    }
    return *this;
}

void GpuGaussianBlur::reset() noexcept {
    if (weights_view_ != nullptr) {
        weights_view_->Release();
        weights_view_ = nullptr;
    }
    if (weights_ != nullptr) {
        weights_->Release();
        weights_ = nullptr;
    }
    weight_capacity_ = 0U;
    if (constants_ != nullptr) {
        constants_->Release();
        constants_ = nullptr;
    }
    if (vertical_ != nullptr) {
        vertical_->Release();
        vertical_ = nullptr;
    }
    if (horizontal_ != nullptr) {
        horizontal_->Release();
        horizontal_ = nullptr;
    }
}

std::vector<float> GpuGaussianBlur::weights_for_sigma(
    const float sigma,
    const int minimum_support) {
    // `film_scan_denoise_filters.cpp:17-31` · `texture_stage_gaussian.h:29-42` 와 같은 계산입니다.
    // 두 판의 유일한 차이인 지원 반경 하한만 호출부가 고릅니다.
    const float effective_sigma = negaflow::imaging::coreimage_gaussian_effective_sigma(sigma);
    const int support = std::max(
        minimum_support, negaflow::imaging::coreimage_gaussian_support_radius(sigma));
    std::vector<float> weights(static_cast<std::size_t>(support * 2 + 1));
    float total = 0.0F;
    for (int offset = -support; offset <= support; ++offset) {
        const float value = std::exp(
            -static_cast<float>(offset * offset) /
            (2.0F * effective_sigma * effective_sigma));
        weights[static_cast<std::size_t>(offset + support)] = value;
        total += value;
    }
    for (float& weight : weights) {
        weight /= total;
    }
    return weights;
}

std::vector<float> GpuGaussianBlur::weights_for_halation_sigma(const float sigma) {
    // `imaging/digital_halation.cpp:51` `gaussian_weights` 를 그대로 옮긴 것입니다.
    // Core Image 분산 보정 0.08 이 **없고**, 지수와 합계를 `double` 로 굴립니다.
    const auto radius = std::max(1, static_cast<int>(std::ceil(3.0F * sigma)));
    std::vector<float> weights(static_cast<std::size_t>(radius) * 2U + 1U);
    double total = 0.0;
    for (int offset = -radius; offset <= radius; ++offset) {
        const double distance = offset;
        const float weight = static_cast<float>(std::exp(
            -(distance * distance) / (2.0 * static_cast<double>(sigma) * sigma)));
        weights[static_cast<std::size_t>(offset + radius)] = weight;
        total += weight;
    }
    for (float& weight : weights) {
        weight = static_cast<float>(weight / total);
    }
    return weights;
}

GpuKernelStatus GpuGaussianBlur::create(
    const GpuDevice& device,
    GpuGaussianBlur& kernel) noexcept {
    kernel.reset();
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }

    ID3D11ComputeShader* horizontal = nullptr;
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_gaussian_horizontal_cs,
            sizeof(negaflow_gaussian_horizontal_cs),
            nullptr,
            &horizontal))) {
        return GpuKernelStatus::resource_creation_failed;
    }

    ID3D11ComputeShader* vertical = nullptr;
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_gaussian_vertical_cs,
            sizeof(negaflow_gaussian_vertical_cs),
            nullptr,
            &vertical))) {
        horizontal->Release();
        return GpuKernelStatus::resource_creation_failed;
    }

    D3D11_BUFFER_DESC description{};
    description.ByteWidth = sizeof(GaussianConstants);
    description.Usage = D3D11_USAGE_DYNAMIC;
    description.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    description.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

    ID3D11Buffer* constants = nullptr;
    if (FAILED(device.device()->CreateBuffer(&description, nullptr, &constants))) {
        vertical->Release();
        horizontal->Release();
        return GpuKernelStatus::resource_creation_failed;
    }

    kernel.horizontal_ = horizontal;
    kernel.vertical_ = vertical;
    kernel.constants_ = constants;
    return GpuKernelStatus::ok;
}

GpuKernelStatus GpuGaussianBlur::ensure_weights(
    const GpuDevice& device,
    const std::vector<float>& weights) const noexcept {
    // 탭 수가 그대로면 버퍼를 다시 만들지 않고 내용만 덮어씁니다.
    if (weights_ != nullptr && weight_capacity_ == weights.size()) {
        D3D11_MAPPED_SUBRESOURCE mapped{};
        if (FAILED(device.context()->Map(weights_, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
            return GpuKernelStatus::resource_creation_failed;
        }
        std::memcpy(mapped.pData, weights.data(), weights.size() * sizeof(float));
        device.context()->Unmap(weights_, 0U);
        return GpuKernelStatus::ok;
    }

    if (weights_view_ != nullptr) {
        weights_view_->Release();
        weights_view_ = nullptr;
    }
    if (weights_ != nullptr) {
        weights_->Release();
        weights_ = nullptr;
    }
    weight_capacity_ = 0U;

    D3D11_BUFFER_DESC description{};
    description.ByteWidth = static_cast<UINT>(weights.size() * sizeof(float));
    description.Usage = D3D11_USAGE_DYNAMIC;
    description.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    description.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    description.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    description.StructureByteStride = sizeof(float);

    D3D11_SUBRESOURCE_DATA initial{};
    initial.pSysMem = weights.data();

    ID3D11Buffer* buffer = nullptr;
    if (FAILED(device.device()->CreateBuffer(&description, &initial, &buffer))) {
        return GpuKernelStatus::resource_creation_failed;
    }

    D3D11_SHADER_RESOURCE_VIEW_DESC view{};
    view.Format = DXGI_FORMAT_UNKNOWN;  // 구조화 버퍼는 UNKNOWN 이어야 합니다.
    view.ViewDimension = D3D11_SRV_DIMENSION_BUFFER;
    view.Buffer.FirstElement = 0U;
    view.Buffer.NumElements = static_cast<UINT>(weights.size());

    ID3D11ShaderResourceView* srv = nullptr;
    if (FAILED(device.device()->CreateShaderResourceView(buffer, &view, &srv))) {
        buffer->Release();
        return GpuKernelStatus::resource_creation_failed;
    }

    weights_ = buffer;
    weights_view_ = srv;
    weight_capacity_ = weights.size();
    return GpuKernelStatus::ok;
}

GpuKernelStatus GpuGaussianBlur::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& scratch,
    GpuWorkingImage& destination,
    const std::vector<float>& weights,
    const GpuGaussianEdgeMode edge_mode,
    const bool blur_alpha) const noexcept {
    if (!device.is_usable() || horizontal_ == nullptr || vertical_ == nullptr ||
        constants_ == nullptr) {
        return GpuKernelStatus::device_unavailable;
    }
    if (!source.is_valid() || !scratch.is_valid() || !destination.is_valid()) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (source.width() != scratch.width() || source.height() != scratch.height() ||
        source.width() != destination.width() || source.height() != destination.height()) {
        return GpuKernelStatus::invalid_arguments;
    }
    // 셋이 서로 달라야 합니다. 같으면 D3D11 이 SRV·UAV 를 동시에 못 묶습니다.
    if (source.texture() == scratch.texture() || scratch.texture() == destination.texture() ||
        source.texture() == destination.texture()) {
        return GpuKernelStatus::invalid_arguments;
    }
    // 탭 수는 홀수여야 중심이 하나입니다.
    if (weights.empty() || weights.size() % 2U == 0U) {
        return GpuKernelStatus::invalid_arguments;
    }
    for (const float weight : weights) {
        if (!std::isfinite(weight)) {
            return GpuKernelStatus::non_finite_parameter;
        }
    }
    if (weights.size() == 1U) {
        // 탭 하나 — 흐림이 없습니다. 가중치가 1 이라도 곱하면 반올림이 붙으므로 복사합니다.
        const GpuImageStatus copied = destination.copy_from(device, source);
        return copied == GpuImageStatus::ok ? GpuKernelStatus::ok
                                            : GpuKernelStatus::invalid_arguments;
    }

    const GpuKernelStatus prepared = ensure_weights(device, weights);
    if (prepared != GpuKernelStatus::ok) {
        return prepared;
    }

    ID3D11DeviceContext* context = device.context();

    GaussianConstants payload{};
    payload.extent.width = source.width();
    payload.extent.height = source.height();
    payload.radius = static_cast<std::int32_t>((weights.size() - 1U) / 2U);
    payload.edge_mode = static_cast<std::int32_t>(edge_mode);
    payload.blur_alpha = blur_alpha ? 1 : 0;

    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context->Map(constants_, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    std::memcpy(mapped.pData, &payload, sizeof(payload));
    context->Unmap(constants_, 0U);

    const std::uint32_t groups_x = group_count(source.width());
    const std::uint32_t groups_y = group_count(source.height());
    run_pass(
        context, horizontal_, constants_, weights_view_, source, scratch, groups_x, groups_y);
    run_pass(
        context, vertical_, constants_, weights_view_, scratch, destination, groups_x, groups_y);
    return GpuKernelStatus::ok;
}

}  // namespace negaflow::gpu
