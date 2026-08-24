#pragma once

/* WIC TIFF 디코드가 쓰는 COM·스트림 받침과 배치 판정입니다. 디코드 순서는
   wic_tiff_decoder.cpp 가 소유합니다. */

#include "negaflow/imageio/wic_tiff_decoder.h"

#include "negaflow/core/tiff_probe.h"

#include <Windows.h>
#include <wincodec.h>

#include <array>
#include <cstddef>
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
    explicit IStreamTiffReader(IStream* const stream) noexcept : stream_(stream) {
        STATSTG statistics{};
        if (stream_ != nullptr && SUCCEEDED(stream_->Stat(&statistics, STATFLAG_NONAME)) &&
            statistics.type == STGTY_STREAM) {
            size_ = statistics.cbSize.QuadPart;
            valid_ = true;
        }
    }

    [[nodiscard]] bool valid() const noexcept {
        return valid_;
    }

    [[nodiscard]] std::uint64_t size() const noexcept override {
        return size_;
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
    IStream* stream_{nullptr};
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
