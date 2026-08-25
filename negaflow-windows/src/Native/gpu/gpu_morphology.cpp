#include "negaflow/gpu/gpu_morphology.h"

#include <d3d11.h>

#include <cstring>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_kernel_timing.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/morphology_BipolarTopHatMain.h"
#include "negaflow/gpu/shaders/morphology_MorphologyHorizontalMain.h"
#include "negaflow/gpu/shaders/morphology_MorphologyVerticalMain.h"

namespace negaflow::gpu {
namespace {

// HLSL `cbuffer MorphologyConstants` 와 같은 배치여야 합니다.
struct alignas(16) MorphologyConstants final {
    GpuPointwiseExtent extent{};
    std::int32_t radius{0};
    std::int32_t is_minimum{0};
    float padding[2]{0.0F, 0.0F};
};

static_assert(sizeof(MorphologyConstants) == 32U, "extent register + radius register");

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
    ID3D11ShaderResourceView* const no_srv[3] = {nullptr, nullptr, nullptr};
    ID3D11UnorderedAccessView* const no_uav[1] = {nullptr};
    context->CSSetShaderResources(0U, 3U, no_srv);
    context->CSSetUnorderedAccessViews(0U, 1U, no_uav, nullptr);
    context->CSSetShader(nullptr, nullptr, 0U);
}

[[nodiscard]] bool write_constants(
    const GpuDevice& device,
    ID3D11Buffer* constants,
    const GpuWorkingImage& reference,
    const std::uint32_t radius,
    const bool minimum) noexcept {
    MorphologyConstants payload{};
    payload.extent.width = reference.width();
    payload.extent.height = reference.height();
    payload.radius = static_cast<std::int32_t>(radius);
    payload.is_minimum = minimum ? 1 : 0;

    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(device.context()->Map(constants, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
        return false;
    }
    std::memcpy(mapped.pData, &payload, sizeof(payload));
    device.context()->Unmap(constants, 0U);
    return true;
}

// 크기가 같고 서로 다른 자원인지 봅니다. D3D11 은 한 자원을 SRV·UAV 로 동시에 못 묶습니다.
[[nodiscard]] bool distinct_and_matching(
    const GpuWorkingImage& reference,
    const GpuWorkingImage* const images,
    const int count,
    const GpuWorkingImage& destination) noexcept {
    if (!destination.is_valid() || destination.width() != reference.width() ||
        destination.height() != reference.height() ||
        destination.texture() == reference.texture()) {
        return false;
    }
    for (int index = 0; index < count; ++index) {
        if (!images[index].is_valid() || images[index].width() != reference.width() ||
            images[index].height() != reference.height() ||
            images[index].texture() == reference.texture() ||
            images[index].texture() == destination.texture()) {
            return false;
        }
    }
    return true;
}

[[nodiscard]] bool filter_images_match(
    const GpuWorkingImage& reference,
    const GpuWorkingImage* const scratch,
    const GpuWorkingImage& destination) noexcept {
    if (!destination.is_valid() || destination.width() != reference.width() ||
        destination.height() != reference.height()) {
        return false;
    }
    for (int index = 0; index < GpuMorphology::filter_scratch_count; ++index) {
        if (!scratch[index].is_valid() || scratch[index].width() != reference.width() ||
            scratch[index].height() != reference.height() ||
            scratch[index].texture() == reference.texture() ||
            scratch[index].texture() == destination.texture()) {
            return false;
        }
    }
    return scratch[0].texture() != scratch[1].texture();
}

} // namespace

GpuMorphology::~GpuMorphology() { reset(); }

GpuMorphology::GpuMorphology(GpuMorphology&& other) noexcept
    : horizontal_(other.horizontal_),
      vertical_(other.vertical_),
      top_hat_(other.top_hat_),
      constants_(other.constants_) {
    other.horizontal_ = nullptr;
    other.vertical_ = nullptr;
    other.top_hat_ = nullptr;
    other.constants_ = nullptr;
}

GpuMorphology& GpuMorphology::operator=(GpuMorphology&& other) noexcept {
    if (this != &other) {
        reset();
        horizontal_ = other.horizontal_;
        vertical_ = other.vertical_;
        top_hat_ = other.top_hat_;
        constants_ = other.constants_;
        other.horizontal_ = nullptr;
        other.vertical_ = nullptr;
        other.top_hat_ = nullptr;
        other.constants_ = nullptr;
    }
    return *this;
}

void GpuMorphology::reset() noexcept {
    if (constants_ != nullptr) {
        constants_->Release();
        constants_ = nullptr;
    }
    if (top_hat_ != nullptr) {
        top_hat_->Release();
        top_hat_ = nullptr;
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

GpuKernelStatus GpuMorphology::create(const GpuDevice& device, GpuMorphology& kernel) noexcept {
    kernel.reset();
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }

    ID3D11ComputeShader* horizontal = nullptr;
    ID3D11ComputeShader* vertical = nullptr;
    ID3D11ComputeShader* top_hat = nullptr;
    ID3D11Buffer* constants = nullptr;

    const auto fail = [&]() noexcept {
        if (top_hat != nullptr) {
            top_hat->Release();
        }
        if (vertical != nullptr) {
            vertical->Release();
        }
        if (horizontal != nullptr) {
            horizontal->Release();
        }
        return GpuKernelStatus::resource_creation_failed;
    };

    if (FAILED(device.device()->CreateComputeShader(
            negaflow_morphology_horizontal_cs,
            sizeof(negaflow_morphology_horizontal_cs),
            nullptr,
            &horizontal))) {
        return fail();
    }
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_morphology_vertical_cs,
            sizeof(negaflow_morphology_vertical_cs),
            nullptr,
            &vertical))) {
        return fail();
    }
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_bipolar_top_hat_cs,
            sizeof(negaflow_bipolar_top_hat_cs),
            nullptr,
            &top_hat))) {
        return fail();
    }

    D3D11_BUFFER_DESC description{};
    description.ByteWidth = sizeof(MorphologyConstants);
    description.Usage = D3D11_USAGE_DYNAMIC;
    description.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    description.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    if (FAILED(device.device()->CreateBuffer(&description, nullptr, &constants))) {
        return fail();
    }

    kernel.horizontal_ = horizontal;
    kernel.vertical_ = vertical;
    kernel.top_hat_ = top_hat;
    kernel.constants_ = constants;
    return GpuKernelStatus::ok;
}

GpuKernelStatus GpuMorphology::run_filter(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& scratch,
    GpuWorkingImage& destination,
    const std::uint32_t radius,
    const bool minimum) const noexcept {
    if (!write_constants(device, constants_, source, radius, minimum)) {
        return GpuKernelStatus::resource_creation_failed;
    }
    ID3D11DeviceContext* context = device.context();

    // 축 패스는 8×8 이 아니라 **한 줄에 64 스레드**입니다. 그래야 그룹이 자기 구간과
    // halo 를 groupshared 에 한 번만 올리고 거기서 창을 훑을 수 있습니다. 창 45 기준으로
    // 8×8 은 같은 화소를 6.9배 중복해서 전역에서 읽었습니다.
    // `morphology.hlsl` 의 `MORPH_AXIS_GROUP` 과 **같은 값이어야 합니다.**
    ID3D11ShaderResourceView* horizontal_source[1] = {source.srv()};
    const GpuKernelTimer horizontal_timer{device, GpuTimedKernel::morphology_horizontal};
    run_pass(
        context,
        horizontal_,
        constants_,
        horizontal_source,
        1U,
        scratch,
        group_count(source.width(), gpu_morphology_axis_group),
        source.height());
    ID3D11ShaderResourceView* vertical_source[1] = {scratch.srv()};
    const GpuKernelTimer vertical_timer{device, GpuTimedKernel::morphology_vertical};
    run_pass(
        context,
        vertical_,
        constants_,
        vertical_source,
        1U,
        destination,
        source.width(),
        group_count(source.height(), gpu_morphology_axis_group));
    return GpuKernelStatus::ok;
}

GpuKernelStatus GpuMorphology::opening(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage* const scratch,
    GpuWorkingImage& destination,
    const std::uint32_t radius) const noexcept {
    if (!device.is_usable() || horizontal_ == nullptr) {
        return GpuKernelStatus::device_unavailable;
    }
    if (scratch == nullptr || !source.is_valid() ||
        !filter_images_match(source, scratch, destination)) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (radius == 0U) {
        if (destination.texture() == source.texture()) {
            return GpuKernelStatus::ok;
        }
        // CPU 와 같이 원본을 그대로 내보냅니다.
        const GpuImageStatus copied = destination.copy_from(device, source);
        return copied == GpuImageStatus::ok ? GpuKernelStatus::ok
                                            : GpuKernelStatus::invalid_arguments;
    }
    // 침식 → 팽창. `grain_mend_morphology.cpp:155-159`.
    const GpuKernelStatus eroded =
        run_filter(device, source, scratch[0], scratch[1], radius, true);
    if (eroded != GpuKernelStatus::ok) {
        return eroded;
    }
    return run_filter(device, scratch[1], scratch[0], destination, radius, false);
}

GpuKernelStatus GpuMorphology::closing(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage* const scratch,
    GpuWorkingImage& destination,
    const std::uint32_t radius) const noexcept {
    if (!device.is_usable() || horizontal_ == nullptr) {
        return GpuKernelStatus::device_unavailable;
    }
    if (scratch == nullptr || !source.is_valid() ||
        !filter_images_match(source, scratch, destination)) {
        return GpuKernelStatus::invalid_arguments;
    }
    if (radius == 0U) {
        if (destination.texture() == source.texture()) {
            return GpuKernelStatus::ok;
        }
        const GpuImageStatus copied = destination.copy_from(device, source);
        return copied == GpuImageStatus::ok ? GpuKernelStatus::ok
                                            : GpuKernelStatus::invalid_arguments;
    }
    // 팽창 → 침식. `grain_mend_morphology.cpp:170-174`.
    const GpuKernelStatus dilated =
        run_filter(device, source, scratch[0], scratch[1], radius, false);
    if (dilated != GpuKernelStatus::ok) {
        return dilated;
    }
    return run_filter(device, scratch[1], scratch[0], destination, radius, true);
}

GpuKernelStatus GpuMorphology::bipolar_top_hat(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage* const scratch,
    GpuWorkingImage& destination,
    const std::uint32_t radius) const noexcept {
    if (!device.is_usable() || horizontal_ == nullptr || top_hat_ == nullptr) {
        return GpuKernelStatus::device_unavailable;
    }
    if (scratch == nullptr || !source.is_valid() ||
        !distinct_and_matching(source, scratch, top_hat_scratch_count, destination)) {
        return GpuKernelStatus::invalid_arguments;
    }

    GpuWorkingImage& opened = scratch[2];
    GpuWorkingImage& closed = scratch[3];

    if (radius == 0U) {
        // CPU 는 여기서 **원본이 아니라 0** 을 냅니다(`grain_mend_morphology.cpp:183`).
        // `opening`·`closing` 의 조기 반환과 다릅니다.
        // 열기·닫기가 원본과 같아지므로 톱햇이 0 이 되는 것과 값이 같습니다.
        const GpuKernelStatus copied_open = opening(device, source, scratch, opened, 0U);
        if (copied_open != GpuKernelStatus::ok) {
            return copied_open;
        }
        const GpuKernelStatus copied_close = closing(device, source, scratch, closed, 0U);
        if (copied_close != GpuKernelStatus::ok) {
            return copied_close;
        }
    } else {
        const GpuKernelStatus made_open = opening(device, source, scratch, opened, radius);
        if (made_open != GpuKernelStatus::ok) {
            return made_open;
        }
        const GpuKernelStatus made_close = closing(device, source, scratch, closed, radius);
        if (made_close != GpuKernelStatus::ok) {
            return made_close;
        }
    }

    if (!write_constants(device, constants_, source, radius, true)) {
        return GpuKernelStatus::resource_creation_failed;
    }
    ID3D11ShaderResourceView* sources[3] = {source.srv(), opened.srv(), closed.srv()};
    run_pass(
        device.context(),
        top_hat_,
        constants_,
        sources,
        3U,
        destination,
        group_count(source.width(), gpu_thread_group_width),
        group_count(source.height(), gpu_thread_group_height));
    return GpuKernelStatus::ok;
}

} // namespace negaflow::gpu
