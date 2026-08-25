#pragma once

/* WIC TIFF 디코드가 쓰는 COM·스트림 받침과 배치 판정입니다. 디코드 순서는
   wic_tiff_decoder.cpp 가 소유합니다. */

#include "negaflow/imageio/wic_tiff_decoder.h"

#include "negaflow/core/tiff_probe.h"

#include <Windows.h>
#include <Shlwapi.h>
#include <wincodec.h>

#include <array>
#include <cstddef>
#include <filesystem>
#include <memory>
#include <new>
#include <cstdint>
#include <limits>
#include <vector>

namespace negaflow::imageio::wic_tiff_detail {

class ComApartment final {
public:
    ComApartment() noexcept : status_(CoInitializeEx(nullptr, COINIT_MULTITHREADED)) {}
    ComApartment(const ComApartment&) = delete;
    ComApartment& operator=(const ComApartment&) = delete;

    ~ComApartment() noexcept {
        if (status_ == S_OK || status_ == S_FALSE) {
            CoUninitialize();
        }
    }

    [[nodiscard]] HRESULT status() const noexcept {
        return status_;
    }

private:
    HRESULT status_;
};

class IStreamTiffReader final : public negaflow::core::TiffRandomAccessReader {
public:
    // 빌려 쓰는 판입니다. 수명은 호출부가 쥔 스트림을 따릅니다. `path` 를 주면 복제할 수
    // 있습니다 - `SHCreateStreamOnFileEx` 가 낸 스트림은 `IStream::Clone` 을 구현하지 않고
    // **E_NOTIMPL(0x80004001)** 을 냅니다(실측). 그래서 같은 파일을 다시 열어 복제합니다.
    explicit IStreamTiffReader(
        IStream* const stream,
        std::filesystem::path path = {}) noexcept
        : stream_(stream), path_(std::move(path)) {
        STATSTG statistics{};
        if (stream_ != nullptr && SUCCEEDED(stream_->Stat(&statistics, STATFLAG_NONAME)) &&
            statistics.type == STGTY_STREAM) {
            size_ = statistics.cbSize.QuadPart;
            valid_ = true;
        }
    }

    ~IStreamTiffReader() noexcept override {
        if (owned_ != nullptr) {
            owned_->Release();
        }
    }

    [[nodiscard]] bool valid() const noexcept {
        return valid_;
    }

    [[nodiscard]] std::uint64_t size() const noexcept override {
        return size_;
    }

    /// <summary>
    /// `IStream::Clone` 은 같은 바이트를 가리키되 **자체 seek 위치**를 가진 스트림을 냅니다.
    /// 그래서 복제본끼리는 동시에 읽어도 서로의 위치를 흔들지 않습니다. 스트림 구현이
    /// `Clone` 을 지원하지 않으면(선택 사항입니다) `nullptr` 을 내고 호출부가 순차로 갑니다.
    /// </summary>
    [[nodiscard]] std::unique_ptr<negaflow::core::TiffRandomAccessReader>
    clone() const noexcept override {
        if (!valid_ || stream_ == nullptr) {
            return nullptr;
        }
        IStream* copied = nullptr;
        // 규격상 `Clone` 은 선택 사항입니다. 되면 그것을 쓰고, 안 되면 경로로 다시 엽니다.
        if (FAILED(stream_->Clone(&copied)) || copied == nullptr) {
            copied = nullptr;
            if (path_.empty() ||
                FAILED(SHCreateStreamOnFileEx(
                    path_.c_str(),
                    STGM_READ | STGM_SHARE_DENY_WRITE,
                    FILE_ATTRIBUTE_NORMAL,
                    FALSE,
                    nullptr,
                    &copied)) ||
                copied == nullptr) {
                return nullptr;
            }
        }
        try {
            auto reader = std::unique_ptr<IStreamTiffReader>{
                new IStreamTiffReader{copied, OwnsStream{}, path_}};
            if (!reader->valid() || reader->size() != size_) {
                return nullptr;
            }
            return reader;
        } catch (const std::bad_alloc&) {
            copied->Release();
            return nullptr;
        }
    }

    [[nodiscard]] bool read(
        const std::uint64_t offset,
        std::uint8_t* const destination,
        const std::size_t byte_count) const noexcept override {
        if (!valid_ || destination == nullptr ||
            byte_count > static_cast<std::size_t>(std::numeric_limits<ULONG>::max()) ||
            offset > static_cast<std::uint64_t>(std::numeric_limits<LONGLONG>::max()) ||
            offset > size_ || static_cast<std::uint64_t>(byte_count) > size_ - offset) {
            return false;
        }

        LARGE_INTEGER requested_position{};
        requested_position.QuadPart = static_cast<LONGLONG>(offset);
        ULARGE_INTEGER actual_position{};
        if (FAILED(stream_->Seek(requested_position, STREAM_SEEK_SET, &actual_position)) ||
            actual_position.QuadPart != offset) {
            return false;
        }

        ULONG bytes_read = 0U;
        return SUCCEEDED(stream_->Read(
                   destination,
                   static_cast<ULONG>(byte_count),
                   &bytes_read)) &&
               bytes_read == byte_count;
    }

private:
    struct OwnsStream final {};

    IStreamTiffReader(
        IStream* const stream,
        OwnsStream,
        std::filesystem::path path) noexcept
        : IStreamTiffReader(stream, std::move(path)) {
        owned_ = stream;
    }

    IStream* stream_{nullptr};
    IStream* owned_{nullptr};
    std::filesystem::path path_{};
    std::uint64_t size_{0};
    bool valid_{false};
};

// 스트림을 처음으로 되감습니다. probe 와 디코드가 같은 스트림을 두 번 읽습니다.
[[nodiscard]] bool rewind_stream(IStream* stream) noexcept;

// 실패한 결과에서 화소를 버립니다. 반쯤 채운 버퍼를 호출부에 넘기지 않으려는 것입니다.
void discard_samples(WicTiffDecodeResult& result) noexcept;

[[nodiscard]] bool all_u16_values_equal(
    const std::array<std::uint16_t, 8>& values,
    std::uint8_t count,
    std::uint16_t expected) noexcept;

// probe 가 읽은 배치를 이 디코더가 다룰 수 있는가.
[[nodiscard]] bool is_supported_layout(
    const negaflow::core::TiffProbeInfo& info,
    bool allow_orientation) noexcept;

[[nodiscard]] WicPixelFormat classify_pixel_format(const GUID& format) noexcept;

// 프레임에 붙은 ICC 프로파일을 읽어 결과에 담습니다. 프로파일이 없고 probe 도 없다고
// 했으면 성공입니다.
[[nodiscard]] WicTiffDecodeStatus extract_icc_profile(
    IWICImagingFactory* factory,
    IWICBitmapFrameDecode* frame,
    std::uint64_t expected_profile_bytes,
    const WicTiffDecodeLimits& limits,
    WicTiffDecodeResult& result);

}  // namespace negaflow::imageio::wic_tiff_detail
