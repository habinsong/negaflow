#include "negaflow/gpu/gpu_scene_correction.h"

#include <windows.h>
#include <d3d11.h>

#include <algorithm>
#include <cstring>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/gpu/shaders/scene_sample_grid_SceneSampleGridMain.h"
#include "negaflow/gpu/shaders/scene_correction_SceneAutoLevelsMain.h"
#include "negaflow/gpu/shaders/scene_correction_SceneNeutralBalanceMain.h"

namespace negaflow::gpu {
namespace {

struct alignas(16) SampleCell final {
    float value[4]{};
};

static_assert(sizeof(SampleCell) == 16U, "float4");

struct alignas(16) SampleGridConstants final {
    GpuPointwiseExtent extent{};
    std::uint32_t sample_width{0};
    std::uint32_t sample_height{0};
    float inverse_scale{0.0F};
    float padding{0.0F};
};

static_assert(sizeof(SampleGridConstants) == 32U, "two constant registers");

// 셰이더의 `Cube[24]` 와 같은 모양입니다 — 채널마다 float4 여덟 개.
struct alignas(16) SceneCorrectionConstants final {
    GpuPointwiseExtent extent{};
    float level_scale[4]{1.0F, 1.0F, 1.0F, 1.0F};
    float level_bias[4]{0.0F, 0.0F, 0.0F, 0.0F};
    float cube[24][4]{};
};

static_assert(
    sizeof(SceneCorrectionConstants) == 16U + 16U + 16U + (24U * 16U),
    "extent + scale + bias + three 32-entry cubes");

// 가장 큰 격자는 256칸 가로입니다. 세로는 원본 비율을 따르므로 아주 긴 파노라마도
// 들어가도록 넉넉히 잡습니다. 16바이트 × 256 × 1024 = 4MB.
constexpr std::uint32_t grid_capacity = 256U * 1024U;

[[nodiscard]] std::uint32_t groups_1d(
    const std::uint32_t extent,
    const std::uint32_t size) noexcept {
    return (extent + size - 1U) / size;
}

void release_buffer(ID3D11Buffer*& buffer) noexcept {
    if (buffer != nullptr) {
        buffer->Release();
        buffer = nullptr;
    }
}

[[nodiscard]] bool write_constants(
    ID3D11DeviceContext* const context,
    ID3D11Buffer* const constants,
    const void* const payload,
    const std::size_t bytes) noexcept {
    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context->Map(constants, 0U, D3D11_MAP_WRITE_DISCARD, 0U, &mapped))) {
        return false;
    }
    std::memcpy(mapped.pData, payload, bytes);
    context->Unmap(constants, 0U);
    return true;
}

void fill_cube(
    float (&destination)[24][4],
    const std::size_t channel,
    const double (&source)[imaging::scene_cube_dimension]) noexcept {
    const std::size_t base = channel * 8U;
    for (std::size_t index = 0U; index < imaging::scene_cube_dimension; ++index) {
        destination[base + (index >> 2U)][index & 3U] =
            static_cast<float>(source[index]);
    }
}

} // namespace

GpuSceneCorrection::~GpuSceneCorrection() { reset(); }

GpuSceneCorrection::GpuSceneCorrection(GpuSceneCorrection&& other) noexcept
    : grid_(other.grid_),
      grid_constants_(other.grid_constants_),
      grid_buffer_(other.grid_buffer_),
      grid_uav_(other.grid_uav_),
      grid_readback_(other.grid_readback_),
      grid_capacity_(other.grid_capacity_),
      levels_(std::move(other.levels_)),
      balance_(std::move(other.balance_)) {
    other.grid_ = nullptr;
    other.grid_constants_ = nullptr;
    other.grid_buffer_ = nullptr;
    other.grid_uav_ = nullptr;
    other.grid_readback_ = nullptr;
    other.grid_capacity_ = 0U;
}

GpuSceneCorrection& GpuSceneCorrection::operator=(GpuSceneCorrection&& other) noexcept {
    if (this != &other) {
        reset();
        grid_ = other.grid_;
        grid_constants_ = other.grid_constants_;
        grid_buffer_ = other.grid_buffer_;
        grid_uav_ = other.grid_uav_;
        grid_readback_ = other.grid_readback_;
        grid_capacity_ = other.grid_capacity_;
        levels_ = std::move(other.levels_);
        balance_ = std::move(other.balance_);
        other.grid_ = nullptr;
        other.grid_constants_ = nullptr;
        other.grid_buffer_ = nullptr;
        other.grid_uav_ = nullptr;
        other.grid_readback_ = nullptr;
        other.grid_capacity_ = 0U;
    }
    return *this;
}

void GpuSceneCorrection::reset() noexcept {
    if (grid_uav_ != nullptr) {
        grid_uav_->Release();
        grid_uav_ = nullptr;
    }
    release_buffer(grid_buffer_);
    release_buffer(grid_readback_);
    release_buffer(grid_constants_);
    if (grid_ != nullptr) {
        grid_->Release();
        grid_ = nullptr;
    }
    grid_capacity_ = 0U;
}

GpuKernelStatus GpuSceneCorrection::create(
    const GpuDevice& device,
    GpuSceneCorrection& kernel) noexcept {
    kernel.reset();
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }
    if (FAILED(device.device()->CreateComputeShader(
            negaflow_scene_sample_grid_cs,
            sizeof(negaflow_scene_sample_grid_cs),
            nullptr,
            &kernel.grid_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }
    D3D11_BUFFER_DESC constants{};
    constants.ByteWidth = sizeof(SampleGridConstants);
    constants.Usage = D3D11_USAGE_DYNAMIC;
    constants.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    constants.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    if (FAILED(device.device()->CreateBuffer(&constants, nullptr, &kernel.grid_constants_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }
    D3D11_BUFFER_DESC grid{};
    grid.ByteWidth = grid_capacity * sizeof(SampleCell);
    grid.Usage = D3D11_USAGE_DEFAULT;
    grid.BindFlags = D3D11_BIND_UNORDERED_ACCESS;
    grid.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    grid.StructureByteStride = sizeof(SampleCell);
    if (FAILED(device.device()->CreateBuffer(&grid, nullptr, &kernel.grid_buffer_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }
    D3D11_UNORDERED_ACCESS_VIEW_DESC uav{};
    uav.Format = DXGI_FORMAT_UNKNOWN;
    uav.ViewDimension = D3D11_UAV_DIMENSION_BUFFER;
    uav.Buffer.NumElements = grid_capacity;
    if (FAILED(device.device()->CreateUnorderedAccessView(
            kernel.grid_buffer_, &uav, &kernel.grid_uav_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }
    D3D11_BUFFER_DESC readback{};
    readback.ByteWidth = grid_capacity * sizeof(SampleCell);
    readback.Usage = D3D11_USAGE_STAGING;
    readback.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    if (FAILED(device.device()->CreateBuffer(&readback, nullptr, &kernel.grid_readback_))) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }
    kernel.grid_capacity_ = grid_capacity;

    if (GpuPointwiseKernel::create(
            device,
            negaflow_scene_auto_levels_cs,
            sizeof(negaflow_scene_auto_levels_cs),
            sizeof(SceneCorrectionConstants),
            kernel.levels_) != GpuKernelStatus::ok) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }
    if (GpuPointwiseKernel::create(
            device,
            negaflow_scene_neutral_balance_cs,
            sizeof(negaflow_scene_neutral_balance_cs),
            sizeof(SceneCorrectionConstants),
            kernel.balance_) != GpuKernelStatus::ok) {
        kernel.reset();
        return GpuKernelStatus::resource_creation_failed;
    }
    return GpuKernelStatus::ok;
}

GpuKernelStatus GpuSceneCorrection::collect_samples(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    const std::uint32_t target_width,
    imaging::SceneSampleGrid& samples) const noexcept {
    if (!device.is_usable() || grid_ == nullptr || !source.is_valid()) {
        return GpuKernelStatus::invalid_arguments;
    }
    std::uint32_t target_height = 0U;
    if (!imaging::scene_sample_grid_extent(
            source.width(), source.height(), target_width, target_height)) {
        return GpuKernelStatus::invalid_arguments;
    }
    const std::uint32_t count = target_width * target_height;
    if (count == 0U || count > grid_capacity_) {
        return GpuKernelStatus::invalid_arguments;
    }

    SampleGridConstants payload{};
    payload.extent.width = source.width();
    payload.extent.height = source.height();
    payload.sample_width = target_width;
    payload.sample_height = target_height;
    // CPU 와 같은 두 단계 나눗셈입니다(`scene_correction.cpp` 주석 참고).
    const double scale =
        static_cast<double>(target_width) / static_cast<double>(source.width());
    payload.inverse_scale = static_cast<float>(1.0 / scale);

    ID3D11DeviceContext* const context = device.context();
    if (!write_constants(context, grid_constants_, &payload, sizeof(payload))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    ID3D11ShaderResourceView* const source_srv = source.srv();
    context->CSSetShader(grid_, nullptr, 0U);
    context->CSSetConstantBuffers(0U, 1U, &grid_constants_);
    context->CSSetShaderResources(0U, 1U, &source_srv);
    context->CSSetUnorderedAccessViews(0U, 1U, &grid_uav_, nullptr);
    context->Dispatch(
        groups_1d(target_width, gpu_thread_group_width),
        groups_1d(target_height, gpu_thread_group_height),
        1U);
    ID3D11UnorderedAccessView* none_uav = nullptr;
    ID3D11ShaderResourceView* none_srv = nullptr;
    context->CSSetUnorderedAccessViews(0U, 1U, &none_uav, nullptr);
    context->CSSetShaderResources(0U, 1U, &none_srv);

    D3D11_BOX box{};
    box.right = count * sizeof(SampleCell);
    box.bottom = 1U;
    box.back = 1U;
    context->CopySubresourceRegion(
        grid_readback_, 0U, 0U, 0U, 0U, grid_buffer_, 0U, &box);
    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(context->Map(grid_readback_, 0U, D3D11_MAP_READ, 0U, &mapped))) {
        return GpuKernelStatus::resource_creation_failed;
    }
    const auto* const cells = static_cast<const SampleCell*>(mapped.pData);
    GpuKernelStatus status = GpuKernelStatus::ok;
    try {
        samples.red.resize(count);
        samples.green.resize(count);
        samples.blue.resize(count);
        for (std::uint32_t index = 0U; index < count; ++index) {
            if (!(cells[index].value[3] > 0.0F)) {
                status = GpuKernelStatus::invalid_arguments;
                break;
            }
            samples.red[index] = static_cast<double>(cells[index].value[0]);
            samples.green[index] = static_cast<double>(cells[index].value[1]);
            samples.blue[index] = static_cast<double>(cells[index].value[2]);
        }
    } catch (...) {
        status = GpuKernelStatus::resource_creation_failed;
    }
    context->Unmap(grid_readback_, 0U);
    return status;
}

GpuKernelStatus GpuSceneCorrection::apply_auto_levels(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const imaging::SceneAutoLevelsPlan& plan) const noexcept {
    SceneCorrectionConstants payload{};
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        payload.level_scale[channel] = static_cast<float>(plan.scale[channel]);
        payload.level_bias[channel] = static_cast<float>(plan.bias[channel]);
    }
    return levels_.dispatch(device, source, destination, &payload, sizeof(payload));
}

GpuKernelStatus GpuSceneCorrection::apply_neutral_balance(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    GpuWorkingImage& destination,
    const imaging::SceneNeutralBalancePlan& plan) const noexcept {
    SceneCorrectionConstants payload{};
    fill_cube(payload.cube, 0U, plan.cube[0]);
    fill_cube(payload.cube, 1U, plan.cube[1]);
    fill_cube(payload.cube, 2U, plan.cube[2]);
    return balance_.dispatch(device, source, destination, &payload, sizeof(payload));
}

} // namespace negaflow::gpu
