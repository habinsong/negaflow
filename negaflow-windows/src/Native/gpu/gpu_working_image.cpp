#include "negaflow/gpu/gpu_working_image.h"

#include <d3d11.h>

#include <cstring>
#include <utility>

#include "negaflow/gpu/gpu_device.h"

namespace negaflow::gpu {
namespace {

// macOS 의 Core Image 는 half float 로 돌지만, Windows CPU 파이프라인이 float32 이므로
// GPU 도 float32 로 둡니다. 자세한 이유는 헤더 주석에 있습니다.
constexpr DXGI_FORMAT working_format = DXGI_FORMAT_R32G32B32A32_FLOAT;

[[nodiscard]] GpuImageStatus validate_extent(
    const GpuDevice& device,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    if (!device.is_usable()) {
        return GpuImageStatus::device_unavailable;
    }
    if (width == 0U || height == 0U) {
        return GpuImageStatus::invalid_dimensions;
    }
    const std::uint32_t limit = device.capability().max_texture_dimension;
    if (limit != 0U && (width > limit || height > limit)) {
        // 조용히 자르지 않습니다. 호출부가 타일로 나누거나 CPU 로 가야 합니다.
        return GpuImageStatus::dimension_limit_exceeded;
    }
    return GpuImageStatus::ok;
}

// 행 피치가 다른 두 버퍼 사이에서 한 행씩 옮깁니다. GPU 쪽 피치는 드라이버가 정합니다
// (256바이트 정렬이 흔합니다) — 절대 `width * 16` 이라고 가정하지 마십시오.
void copy_rows(
    std::byte* destination,
    const std::size_t destination_pitch,
    const std::byte* source,
    const std::size_t source_pitch,
    const std::size_t row_bytes,
    const std::uint32_t height) noexcept {
    for (std::uint32_t row = 0U; row < height; ++row) {
        std::memcpy(
            destination + (static_cast<std::size_t>(row) * destination_pitch),
            source + (static_cast<std::size_t>(row) * source_pitch),
            row_bytes);
    }
}

[[nodiscard]] ID3D11Texture2D* make_staging(
    const GpuDevice& device,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    D3D11_TEXTURE2D_DESC description{};
    description.Width = width;
    description.Height = height;
    description.MipLevels = 1U;
    description.ArraySize = 1U;
    description.Format = working_format;
    description.SampleDesc.Count = 1U;
    description.Usage = D3D11_USAGE_STAGING;
    description.BindFlags = 0U;
    description.CPUAccessFlags = D3D11_CPU_ACCESS_READ;

    ID3D11Texture2D* texture = nullptr;
    if (FAILED(device.device()->CreateTexture2D(&description, nullptr, &texture))) {
        return nullptr;
    }
    return texture;
}

// 스테이징 한 장을 읽어 호스트로 옮깁니다.
[[nodiscard]] GpuImageStatus read_staging(
    const GpuDevice& device,
    ID3D11Texture2D* staging,
    core::Rgba32F* pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels) noexcept {
    if (staging == nullptr || pixels == nullptr) {
        return GpuImageStatus::map_failed;
    }
    if (stride_pixels < width) {
        return GpuImageStatus::invalid_dimensions;
    }

    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(device.context()->Map(staging, 0U, D3D11_MAP_READ, 0U, &mapped))) {
        return GpuImageStatus::map_failed;
    }
    copy_rows(
        reinterpret_cast<std::byte*>(pixels),
        static_cast<std::size_t>(stride_pixels) * sizeof(core::Rgba32F),
        reinterpret_cast<const std::byte*>(mapped.pData),
        static_cast<std::size_t>(mapped.RowPitch),
        static_cast<std::size_t>(width) * sizeof(core::Rgba32F),
        height);
    device.context()->Unmap(staging, 0U);
    return GpuImageStatus::ok;
}

}  // namespace

const char* gpu_image_status_name(const GpuImageStatus status) noexcept {
    switch (status) {
        case GpuImageStatus::ok:
            return "ok";
        case GpuImageStatus::device_unavailable:
            return "device_unavailable";
        case GpuImageStatus::invalid_dimensions:
            return "invalid_dimensions";
        case GpuImageStatus::dimension_limit_exceeded:
            return "dimension_limit_exceeded";
        case GpuImageStatus::buffer_size_mismatch:
            return "buffer_size_mismatch";
        case GpuImageStatus::allocation_failed:
            return "allocation_failed";
        case GpuImageStatus::map_failed:
            return "map_failed";
    }
    return "unknown_status";
}

GpuWorkingImage::~GpuWorkingImage() { reset(); }

GpuWorkingImage::GpuWorkingImage(GpuWorkingImage&& other) noexcept
    : texture_(other.texture_),
      srv_(other.srv_),
      uav_(other.uav_),
      width_(other.width_),
      height_(other.height_) {
    other.texture_ = nullptr;
    other.srv_ = nullptr;
    other.uav_ = nullptr;
    other.width_ = 0U;
    other.height_ = 0U;
}

GpuWorkingImage& GpuWorkingImage::operator=(GpuWorkingImage&& other) noexcept {
    if (this != &other) {
        reset();
        texture_ = other.texture_;
        srv_ = other.srv_;
        uav_ = other.uav_;
        width_ = other.width_;
        height_ = other.height_;
        other.texture_ = nullptr;
        other.srv_ = nullptr;
        other.uav_ = nullptr;
        other.width_ = 0U;
        other.height_ = 0U;
    }
    return *this;
}

void GpuWorkingImage::reset() noexcept {
    if (uav_ != nullptr) {
        uav_->Release();
        uav_ = nullptr;
    }
    if (srv_ != nullptr) {
        srv_->Release();
        srv_ = nullptr;
    }
    if (texture_ != nullptr) {
        texture_->Release();
        texture_ = nullptr;
    }
    width_ = 0U;
    height_ = 0U;
}

GpuImageStatus GpuWorkingImage::create(
    const GpuDevice& device,
    const std::uint32_t width,
    const std::uint32_t height,
    GpuWorkingImage& image) noexcept {
    image.reset();
    const GpuImageStatus extent = validate_extent(device, width, height);
    if (extent != GpuImageStatus::ok) {
        return extent;
    }

    D3D11_TEXTURE2D_DESC description{};
    description.Width = width;
    description.Height = height;
    description.MipLevels = 1U;
    description.ArraySize = 1U;
    description.Format = working_format;
    description.SampleDesc.Count = 1U;
    description.Usage = D3D11_USAGE_DEFAULT;
    description.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS;

    ID3D11Texture2D* texture = nullptr;
    if (FAILED(device.device()->CreateTexture2D(&description, nullptr, &texture))) {
        return GpuImageStatus::allocation_failed;
    }

    ID3D11ShaderResourceView* srv = nullptr;
    if (FAILED(device.device()->CreateShaderResourceView(texture, nullptr, &srv))) {
        texture->Release();
        return GpuImageStatus::allocation_failed;
    }

    ID3D11UnorderedAccessView* uav = nullptr;
    if (FAILED(device.device()->CreateUnorderedAccessView(texture, nullptr, &uav))) {
        srv->Release();
        texture->Release();
        return GpuImageStatus::allocation_failed;
    }

    image.texture_ = texture;
    image.srv_ = srv;
    image.uav_ = uav;
    image.width_ = width;
    image.height_ = height;
    return GpuImageStatus::ok;
}

GpuImageStatus GpuWorkingImage::upload(
    const GpuDevice& device,
    const core::Rgba32F* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    GpuWorkingImage& image) noexcept {
    if (pixels == nullptr) {
        return GpuImageStatus::buffer_size_mismatch;
    }
    if (stride_pixels < width) {
        return GpuImageStatus::invalid_dimensions;
    }
    const GpuImageStatus created = create(device, width, height, image);
    if (created != GpuImageStatus::ok) {
        return created;
    }

    const UINT source_pitch =
        static_cast<UINT>(static_cast<std::size_t>(stride_pixels) * sizeof(core::Rgba32F));
    device.context()->UpdateSubresource(
        image.texture_, 0U, nullptr, pixels, source_pitch, 0U);
    return GpuImageStatus::ok;
}

GpuImageStatus GpuWorkingImage::download(
    const GpuDevice& device,
    core::Rgba32F* const pixels,
    const std::uint32_t stride_pixels) const noexcept {
    if (!device.is_usable()) {
        return GpuImageStatus::device_unavailable;
    }
    if (texture_ == nullptr) {
        return GpuImageStatus::invalid_dimensions;
    }
    ID3D11Texture2D* staging = make_staging(device, width_, height_);
    if (staging == nullptr) {
        return GpuImageStatus::allocation_failed;
    }
    device.context()->CopyResource(staging, texture_);
    const GpuImageStatus read =
        read_staging(device, staging, pixels, width_, height_, stride_pixels);
    staging->Release();
    return read;
}

GpuImageStatus GpuWorkingImage::copy_from(
    const GpuDevice& device,
    const GpuWorkingImage& source) noexcept {
    if (!device.is_usable()) {
        return GpuImageStatus::device_unavailable;
    }
    if (!source.is_valid() || texture_ == nullptr) {
        return GpuImageStatus::invalid_dimensions;
    }
    if (source.width() != width_ || source.height() != height_) {
        return GpuImageStatus::invalid_dimensions;
    }
    if (source.texture() == texture_) {
        // 자기 자신으로의 복사는 D3D11 이 거부합니다. 할 일이 없으므로 성공으로 봅니다.
        return GpuImageStatus::ok;
    }
    device.context()->CopyResource(texture_, source.texture());
    return GpuImageStatus::ok;
}

GpuStagingRing::~GpuStagingRing() { reset(); }

GpuStagingRing::GpuStagingRing(GpuStagingRing&& other) noexcept
    : slots_(std::move(other.slots_)),
      pending_(std::move(other.pending_)),
      next_(other.next_),
      width_(other.width_),
      height_(other.height_) {
    other.slots_.clear();
    other.pending_.clear();
    other.next_ = 0U;
    other.width_ = 0U;
    other.height_ = 0U;
}

GpuStagingRing& GpuStagingRing::operator=(GpuStagingRing&& other) noexcept {
    if (this != &other) {
        reset();
        slots_ = std::move(other.slots_);
        pending_ = std::move(other.pending_);
        next_ = other.next_;
        width_ = other.width_;
        height_ = other.height_;
        other.slots_.clear();
        other.pending_.clear();
        other.next_ = 0U;
        other.width_ = 0U;
        other.height_ = 0U;
    }
    return *this;
}

void GpuStagingRing::reset() noexcept {
    for (ID3D11Texture2D* slot : slots_) {
        if (slot != nullptr) {
            slot->Release();
        }
    }
    slots_.clear();
    pending_.clear();
    next_ = 0U;
    width_ = 0U;
    height_ = 0U;
}

GpuImageStatus GpuStagingRing::create(
    const GpuDevice& device,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::size_t depth,
    GpuStagingRing& ring) noexcept {
    ring.reset();
    const GpuImageStatus extent = validate_extent(device, width, height);
    if (extent != GpuImageStatus::ok) {
        return extent;
    }
    // 한 장이면 링이 아닙니다 — `Map` 이 매번 GPU 를 기다리게 됩니다.
    const std::size_t effective = depth < 2U ? default_depth : depth;

    ring.slots_.reserve(effective);
    for (std::size_t index = 0U; index < effective; ++index) {
        ID3D11Texture2D* slot = make_staging(device, width, height);
        if (slot == nullptr) {
            ring.reset();
            return GpuImageStatus::allocation_failed;
        }
        ring.slots_.push_back(slot);
    }
    ring.pending_.assign(effective, false);
    ring.next_ = 0U;
    ring.width_ = width;
    ring.height_ = height;
    return GpuImageStatus::ok;
}

GpuImageStatus GpuStagingRing::rotate(
    const GpuDevice& device,
    const GpuWorkingImage& source,
    core::Rgba32F* const pixels,
    const std::uint32_t stride_pixels,
    bool& produced) noexcept {
    produced = false;
    if (!device.is_usable()) {
        return GpuImageStatus::device_unavailable;
    }
    if (slots_.empty() || !source.is_valid()) {
        return GpuImageStatus::invalid_dimensions;
    }
    if (source.width() != width_ || source.height() != height_) {
        return GpuImageStatus::invalid_dimensions;
    }

    // 이번 프레임 복사를 걸고,
    device.context()->CopyResource(slots_[next_], source.texture());
    pending_[next_] = true;

    // 가장 오래된 칸을 읽습니다. GPU 는 그 사이 앞 칸 복사를 이미 끝냈을 가능성이 큽니다.
    const std::size_t oldest = (next_ + 1U) % slots_.size();
    next_ = oldest;
    if (!pending_[oldest]) {
        // 링을 채우는 중입니다. 아직 내놓을 프레임이 없습니다.
        return GpuImageStatus::ok;
    }

    const GpuImageStatus read =
        read_staging(device, slots_[oldest], pixels, width_, height_, stride_pixels);
    if (read != GpuImageStatus::ok) {
        return read;
    }
    pending_[oldest] = false;
    produced = true;
    return GpuImageStatus::ok;
}

}  // namespace negaflow::gpu
