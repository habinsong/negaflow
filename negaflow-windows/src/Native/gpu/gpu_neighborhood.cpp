#include "negaflow/gpu/gpu_neighborhood.h"

#include <d3d11.h>

#include <cstring>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/box_blur_BoxBlurHorizontalMain.h"
#include "negaflow/gpu/shaders/box_blur_BoxBlurVerticalMain.h"

namespace negaflow::gpu {
namespace {

// 셰이더의 `[numthreads(64, 1, 1)]` 과 반드시 같아야 합니다. 1D 인 이유는 러닝 섬이
// 줄 방향으로 순차적이기 때문입니다 — 한 줄을 스레드 하나가 통째로 맡습니다.
constexpr std::uint32_t box_blur_group = 64U;

// HLSL `cbuffer BoxBlurConstants` 와 같은 배치여야 합니다.
struct alignas(16) BoxBlurConstants final {
    GpuPointwiseExtent extent{};
    std::int32_t radius{0};
    float padding[3]{0.0F, 0.0F, 0.0F};
};

static_assert(sizeof(BoxBlurConstants) == 32U, "extent register + radius register");

[[nodiscard]] std::uint32_t group_count(const std::uint32_t extent) noexcept {
    return (extent + box_blur_group - 1U) / box_blur_group;
}

// 한 패스를 겁니다. 바인딩을 매번 풀어 두는 이유는 다음 패스가 같은 텍스처를 반대 역할로
// 묶기 때문입니다 — 안 풀면 D3D11 이 바인딩을 조용히 무시합니다.
void run_pass(
    ID3D11DeviceContext* context,
    ID3D11ComputeShader* shader,
    ID3D11Buffer* constants,
    const GpuWorkingImage& input,
    GpuWorkingImage& output,
    const std::uint32_t groups) noexcept {
    ID3D11ShaderResourceView* source_view = input.srv();
    ID3D11UnorderedAccessView* destination_view = output.uav();

    context->CSSetShader(shader, nullptr, 0U);
    context->CSSetShaderResources(0U, 1U, &source_view);
    context->CSSetUnorderedAccessViews(0U, 1U, &destination_view, nullptr);
    context->CSSetConstantBuffers(0U, 1U, &constants);
    context->Dispatch(groups, 1U, 1U);

    ID3D11ShaderResourceView* const no_srv[1] = {nullptr};
    ID3D11UnorderedAccessView* const no_uav[1] = {nullptr};
    context->CSSetShaderResources(0U, 1U, no_srv);
    context->CSSetUnorderedAccessViews(0U, 1U, no_uav, nullptr);
    context->CSSetShader(nullptr, nullptr, 0U);
}

}  // namespace

GpuBoxBlur::~GpuBoxBlur() { reset(); }

GpuBoxBlur::GpuBoxBlur(GpuBoxBlur&& other) noexcept
    : horizontal_(other.horizontal_), vertical_(other.vertical_), constants_(other.constants_) {
    other.horizontal_ = nullptr;
    other.vertical_ = nullptr;
    other.constants_ = nullptr;
}

GpuBoxBlur& GpuBoxBlur::operator=(GpuBoxBlur&& other) noexcept {
    if (this != &other) {
        reset();
        horizontal_ = other.horizontal_;
        vertical_ = other.vertical_;
        constants_ = other.constants_;
        other.horizontal_ = nullptr;
        other.vertical_ = nullptr;
        other.constants_ = nullptr;
    }
    return *this;
}

void GpuBoxBlur::reset() noexcept {
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

GpuKernelStatus GpuBoxBlur::create(const GpuDevice& device, GpuBoxBlur& kernel) noexcept {
    kernel.reset();
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }

    ID3D11ComputeShader* horizontal = nullptr;
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_box_blur_horizontal_cs,
            sizeof(negaflow_box_blur_horizontal_cs),
            nullptr,
            &horizontal))) {
        return GpuKernelStatus::resource_creation_failed;
    }

    ID3D11ComputeShader* vertical = nullptr;
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_box_blur_vertical_cs,
            sizeof(negaflow_box_blur_vertical_cs),
            nullptr,
            &vertical))) {
        horizontal->Release();
        return GpuKernelStatus::resource_creation_failed;
    }

    D3D11_BUFFER_DESC description{};
    description.ByteWidth = sizeof(BoxBlurConstants);
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

GpuKernelStatus GpuBoxBlur::dispatch(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& scratch,
    GpuWorkingImage& destination,
    const std::int32_t radius) const noexcept {
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
    if (radius < 0) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (radius == 0) {
        // 창 크기 1 — 흐림이 없습니다. CPU 판과 같이 원본을 그대로 내보냅니다.
        const GpuImageStatus copied = destination.copy_from(device, source);
        return copied == GpuImageStatus::ok ? GpuKernelStatus::ok
                                            : GpuKernelStatus::invalid_arguments;
    }

    ID3D11DeviceContext* context = device.context();

    BoxBlurConstants payload{};
    payload.extent.width = source.width();
    payload.extent.height = source.height();
    payload.radius = radius;

    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context->Map(constants_, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    std::memcpy(mapped.pData, &payload, sizeof(payload));
    context->Unmap(constants_, 0U);

    // 수평 패스는 **행마다** 스레드 하나 → 높이만큼. 수직 패스는 **열마다** → 폭만큼.
    run_pass(context, horizontal_, constants_, source, scratch, group_count(source.height()));
    run_pass(context, vertical_, constants_, scratch, destination, group_count(source.width()));
    return GpuKernelStatus::ok;
}

}  // namespace negaflow::gpu
