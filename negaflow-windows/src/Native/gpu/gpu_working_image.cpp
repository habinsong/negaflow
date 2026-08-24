#include "negaflow/gpu/gpu_working_image.h"

#include <d3d11.h>

#include <atomic>
#include <cstring>
#include <utility>

#include "negaflow/core/parallel_rows.h"
#include "negaflow/gpu/gpu_device.h"

namespace negaflow::gpu {
namespace {

std::atomic<std::uint64_t> g_uploads{0};
std::atomic<std::uint64_t> g_downloads{0};
std::atomic<std::uint64_t> g_uploaded_pixels{0};
std::atomic<std::uint64_t> g_downloaded_pixels{0};
std::atomic<std::uint64_t> g_downloaded_bytes{0};

void note_upload(const std::uint32_t width, const std::uint32_t height) noexcept {
    g_uploads.fetch_add(1U, std::memory_order_relaxed);
    g_uploaded_pixels.fetch_add(
        static_cast<std::uint64_t>(width) * static_cast<std::uint64_t>(height),
        std::memory_order_relaxed);
}

void note_download(const std::uint32_t width, const std::uint32_t height) noexcept {
    g_downloads.fetch_add(1U, std::memory_order_relaxed);
    const std::uint64_t pixels =
        static_cast<std::uint64_t>(width) * static_cast<std::uint64_t>(height);
    g_downloaded_pixels.fetch_add(pixels, std::memory_order_relaxed);
    g_downloaded_bytes.fetch_add(pixels * 16ULL, std::memory_order_relaxed);
}

} // namespace

void reset_gpu_host_transfer_stats() noexcept {
    g_uploads.store(0U, std::memory_order_relaxed);
    g_downloads.store(0U, std::memory_order_relaxed);
    g_uploaded_pixels.store(0U, std::memory_order_relaxed);
    g_downloaded_pixels.store(0U, std::memory_order_relaxed);
    g_downloaded_bytes.store(0U, std::memory_order_relaxed);
}

GpuHostTransferStats gpu_host_transfer_stats() noexcept {
    GpuHostTransferStats stats{};
    stats.uploads = g_uploads.load(std::memory_order_relaxed);
    stats.downloads = g_downloads.load(std::memory_order_relaxed);
    stats.uploaded_pixels = g_uploaded_pixels.load(std::memory_order_relaxed);
    stats.downloaded_pixels = g_downloaded_pixels.load(std::memory_order_relaxed);
    stats.downloaded_bytes = g_downloaded_bytes.load(std::memory_order_relaxed);
    return stats;
}

void record_gpu_bgra_download(const std::uint32_t width, const std::uint32_t height) noexcept {
    g_downloads.fetch_add(1U, std::memory_order_relaxed);
    const std::uint64_t pixels =
        static_cast<std::uint64_t>(width) * static_cast<std::uint64_t>(height);
    g_downloaded_pixels.fetch_add(pixels, std::memory_order_relaxed);
    g_downloaded_bytes.fetch_add(pixels * 4ULL, std::memory_order_relaxed);
}

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
// 회수한 화소를 호스트 버퍼로 옮깁니다.
//
// **행 블록으로 쪼갭니다.** 24MP RGBA float32 는 264 MB 이고, 한 스레드 `memcpy` 로는
// 수십 ms 가 그대로 나갑니다. 행이 서로 독립이라 쪼개도 값이 같습니다 —
// `parallel_rows.h` 의 계약이 그것입니다.
//
// `work_units` 에 **행 수가 아니라 바이트 수**를 넘깁니다. 행 수만 넘기면 24MP 에서도
// 3,401 이라 문턱(1M)을 못 넘어 **병렬화가 조용히 꺼집니다** — 플레이북 21절이 적은
// 바로 그 함정입니다.
void copy_rows(
    std::byte* const destination,
    const std::size_t destination_pitch,
    const std::byte* const source,
    const std::size_t source_pitch,
    const std::size_t row_bytes,
    const std::uint32_t height) noexcept {
    negaflow::core::for_each_row_block(
        height,
        static_cast<std::uint64_t>(row_bytes) * height,
        [destination, destination_pitch, source, source_pitch, row_bytes](
            const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t row = first_row; row < first_row + row_count; ++row) {
                std::memcpy(
                    destination + (static_cast<std::size_t>(row) * destination_pitch),
                    source + (static_cast<std::size_t>(row) * source_pitch),
                    row_bytes);
            }
        });
}

[[nodiscard]] ID3D11Texture2D* make_staging(
    const GpuDevice& device,
    const std::uint32_t width,
    const std::uint32_t height,
    const UINT cpu_access = D3D11_CPU_ACCESS_READ) noexcept {
    D3D11_TEXTURE2D_DESC description{};
    description.Width = width;
    description.Height = height;
    description.MipLevels = 1U;
    description.ArraySize = 1U;
    description.Format = working_format;
    description.SampleDesc.Count = 1U;
    description.Usage = D3D11_USAGE_STAGING;
    description.BindFlags = 0U;
    description.CPUAccessFlags = cpu_access;

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

} // namespace

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
      staging_(other.staging_),
      upload_staging_(other.upload_staging_),
      width_(other.width_),
      height_(other.height_) {
    other.texture_ = nullptr;
    other.srv_ = nullptr;
    other.uav_ = nullptr;
    other.staging_ = nullptr;
    other.upload_staging_ = nullptr;
    other.width_ = 0U;
    other.height_ = 0U;
}

GpuWorkingImage& GpuWorkingImage::operator=(GpuWorkingImage&& other) noexcept {
    if (this != &other) {
        reset();
        texture_ = other.texture_;
        srv_ = other.srv_;
        uav_ = other.uav_;
        staging_ = other.staging_;
        upload_staging_ = other.upload_staging_;
        width_ = other.width_;
        height_ = other.height_;
        other.texture_ = nullptr;
        other.srv_ = nullptr;
        other.uav_ = nullptr;
        other.staging_ = nullptr;
        other.upload_staging_ = nullptr;
        other.width_ = 0U;
        other.height_ = 0U;
    }
    return *this;
}

void GpuWorkingImage::reset() noexcept {
    if (upload_staging_ != nullptr) {
        upload_staging_->Release();
        upload_staging_ = nullptr;
    }
    if (staging_ != nullptr) {
        staging_->Release();
        staging_ = nullptr;
    }
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
    // 옛 텍스처를 먼저 놓으면 드라이버가 같은 COM 주소를 재사용할 수 있습니다.
    // 새 자원을 잡은 뒤에 갈아끼워 포인터가 반드시 달라지게 합니다.
    GpuWorkingImage created{};
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

    created.texture_ = texture;
    created.srv_ = srv;
    created.uav_ = uav;
    created.width_ = width;
    created.height_ = height;
    image = std::move(created);
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
    // 같은 치수면 자원을 다시 만들지 않습니다. CreateTexture2D + Release 를 매
    // 렌더마다 하면 D3D11 이 옛 DEFAULT/STAGING 을 GPU 가 끝날 때까지 붙들고,
    // UpdateSubresource 는 경합 시 명령 버퍼에 한 번 더 복사합니다.
    // https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11devicecontext-updatesubresource
    // https://learn.microsoft.com/en-us/windows/win32/api/d3d11/ne-d3d11-d3d11_usage
    if (image.is_valid() && image.width() == width && image.height() == height) {
        return image.upload_into(device, pixels, stride_pixels);
    }
    const GpuImageStatus created = create(device, width, height, image);
    if (created != GpuImageStatus::ok) {
        return created;
    }
    return image.upload_into(device, pixels, stride_pixels);
}

GpuImageStatus GpuWorkingImage::upload_into(
    const GpuDevice& device,
    const core::Rgba32F* const pixels,
    const std::uint32_t stride_pixels) const noexcept {
    if (pixels == nullptr) {
        return GpuImageStatus::buffer_size_mismatch;
    }
    if (!is_valid() || !device.is_usable()) {
        return GpuImageStatus::device_unavailable;
    }
    if (stride_pixels < width_) {
        return GpuImageStatus::invalid_dimensions;
    }

    // `UpdateSubresource` 는 드라이버가 **한 스레드로** 우리 버퍼를 자기 영역에
    // 복사합니다. 24MP(264 MB)에서 실측 44 ms 였습니다. 쓰기 스테이징에 직접
    // `Map` 해서 **행 블록으로 나눠** 채우면 그 복사가 코어를 나눠 씁니다.
    // 스테이징을 못 만들면 `UpdateSubresource` 로 돌아갑니다 — 값은 같습니다.
    if (upload_staging_ == nullptr) {
        upload_staging_ = make_staging(device, width_, height_, D3D11_CPU_ACCESS_WRITE);
    }
    if (upload_staging_ != nullptr) {
        D3D11_MAPPED_SUBRESOURCE mapped{};
        if (SUCCEEDED(device.context()->Map(upload_staging_, 0U, D3D11_MAP_WRITE, 0U, &mapped))) {
            copy_rows(
                reinterpret_cast<std::byte*>(mapped.pData),
                static_cast<std::size_t>(mapped.RowPitch),
                reinterpret_cast<const std::byte*>(pixels),
                static_cast<std::size_t>(stride_pixels) * sizeof(core::Rgba32F),
                static_cast<std::size_t>(width_) * sizeof(core::Rgba32F),
                height_);
            device.context()->Unmap(upload_staging_, 0U);
            device.context()->CopyResource(texture_, upload_staging_);
            note_upload(width_, height_);
            return GpuImageStatus::ok;
        }
    }

    const UINT source_pitch =
        static_cast<UINT>(static_cast<std::size_t>(stride_pixels) * sizeof(core::Rgba32F));
    device.context()->UpdateSubresource(texture_, 0U, nullptr, pixels, source_pitch, 0U);
    note_upload(width_, height_);
    return GpuImageStatus::ok;
}

GpuImageStatus GpuWorkingImage::upload_planes_into(
    const GpuDevice& device,
    const float* const red,
    const float* const green,
    const float* const blue,
    const std::uint32_t stride_pixels) const noexcept {
    if (red == nullptr) {
        return GpuImageStatus::buffer_size_mismatch;
    }
    if (!is_valid() || !device.is_usable()) {
        return GpuImageStatus::device_unavailable;
    }
    if (stride_pixels < width_) {
        return GpuImageStatus::invalid_dimensions;
    }
    if (upload_staging_ == nullptr) {
        upload_staging_ = make_staging(device, width_, height_, D3D11_CPU_ACCESS_WRITE);
    }
    if (upload_staging_ == nullptr) {
        return GpuImageStatus::allocation_failed;
    }
    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(device.context()->Map(
            upload_staging_, 0U, D3D11_MAP_WRITE, 0U, &mapped))) {
        return GpuImageStatus::map_failed;
    }
    negaflow::core::for_each_row_block(
        height_,
        static_cast<std::uint64_t>(width_) * height_ * 7U,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                auto* destination = reinterpret_cast<core::Rgba32F*>(
                    reinterpret_cast<std::byte*>(mapped.pData) +
                    static_cast<std::size_t>(y) * mapped.RowPitch);
                const std::size_t source_base = static_cast<std::size_t>(y) * stride_pixels;
                for (std::uint32_t x = 0U; x < width_; ++x) {
                    const std::size_t source = source_base + x;
                    destination[x] = {
                        red[source],
                        green != nullptr ? green[source] : red[source],
                        blue != nullptr ? blue[source] : red[source],
                        0.0F};
                }
            }
        });
    device.context()->Unmap(upload_staging_, 0U);
    device.context()->CopyResource(texture_, upload_staging_);
    note_upload(width_, height_);
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
    if (staging_ == nullptr) {
        staging_ = make_staging(device, width_, height_);
        if (staging_ == nullptr) {
            return GpuImageStatus::allocation_failed;
        }
    }
    device.context()->CopyResource(staging_, texture_);
    const GpuImageStatus status =
        read_staging(device, staging_, pixels, width_, height_, stride_pixels);
    if (status == GpuImageStatus::ok) {
        note_download(width_, height_);
    }
    return status;
}

GpuImageStatus GpuWorkingImage::download_planes(
    const GpuDevice& device,
    float* const red,
    float* const green,
    float* const blue,
    const std::uint32_t stride_pixels) const noexcept {
    if (red == nullptr) {
        return GpuImageStatus::buffer_size_mismatch;
    }
    if (!device.is_usable() || texture_ == nullptr) {
        return GpuImageStatus::device_unavailable;
    }
    if (stride_pixels < width_) {
        return GpuImageStatus::invalid_dimensions;
    }
    if (staging_ == nullptr) {
        staging_ = make_staging(device, width_, height_);
        if (staging_ == nullptr) {
            return GpuImageStatus::allocation_failed;
        }
    }
    device.context()->CopyResource(staging_, texture_);
    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (FAILED(device.context()->Map(staging_, 0U, D3D11_MAP_READ, 0U, &mapped))) {
        return GpuImageStatus::map_failed;
    }
    negaflow::core::for_each_row_block(
        height_,
        static_cast<std::uint64_t>(width_) * height_ *
            (green != nullptr || blue != nullptr ? 7U : 2U),
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                const auto* source = reinterpret_cast<const core::Rgba32F*>(
                    reinterpret_cast<const std::byte*>(mapped.pData) +
                    static_cast<std::size_t>(y) * mapped.RowPitch);
                const std::size_t destination_base = static_cast<std::size_t>(y) * stride_pixels;
                for (std::uint32_t x = 0U; x < width_; ++x) {
                    const std::size_t destination = destination_base + x;
                    red[destination] = source[x].red;
                    if (green != nullptr) green[destination] = source[x].green;
                    if (blue != nullptr) blue[destination] = source[x].blue;
                }
            }
        });
    device.context()->Unmap(staging_, 0U);
    note_download(width_, height_);
    return GpuImageStatus::ok;
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

} // namespace negaflow::gpu
