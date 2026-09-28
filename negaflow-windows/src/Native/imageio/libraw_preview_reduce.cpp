#include "negaflow/imageio/libraw_preview_reduce.h"

#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <atomic>
#include <cstring>
#include <new>
#include <cstddef>
#include <limits>
#include <thread>
#include <vector>

namespace negaflow::imageio {
namespace {

using Microsoft::WRL::ComPtr;

// wic_standard_image_decoder.cpp · wic_tiff_support.h · wic_srgb16_support.h 과 같은
// 자리입니다. WIC 를 쓰는 모듈은 저마다 자기 아파트를 엽니다 - 이 함수는 LibRaw 가 도는
// 워커 스레드에서 불리고, 그 스레드는 COM 이 열려 있다고 보장되지 않습니다.
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

    [[nodiscard]] HRESULT status() const noexcept { return status_; }

private:
    HRESULT status_;
};

struct FittedSize final {
    std::uint32_t width{0U};
    std::uint32_t height{0U};
};

/// `shrink_decoded_rgba16` 이 쓰는 것과 같은 맞춤 규칙입니다 - 긴 변을 상자에 맞추고
/// 나머지 한 변은 비율로 따라갑니다.
[[nodiscard]] FittedSize fit_within(
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t maximum_width,
    const std::uint32_t maximum_height) noexcept {
    FittedSize fitted{width, height};
    if (maximum_width == 0U || maximum_height == 0U) {
        return fitted;
    }
    if (fitted.width > maximum_width) {
        fitted.width = maximum_width;
        fitted.height = static_cast<std::uint32_t>(
            (static_cast<std::uint64_t>(height) * fitted.width) / width);
        if (fitted.height == 0U) fitted.height = 1U;
    }
    if (fitted.height > maximum_height) {
        fitted.height = maximum_height;
        fitted.width = static_cast<std::uint32_t>(
            (static_cast<std::uint64_t>(width) * fitted.height) / height);
        if (fitted.width == 0U) fitted.width = 1U;
    }
    return fitted;
}

/// 최종 크기보다 작아지지 않는 가장 큰 정수 축소배입니다.
[[nodiscard]] std::uint32_t box_average_factor(
    const std::uint32_t width,
    const std::uint32_t height,
    const FittedSize& fitted) noexcept {
    if (fitted.width == 0U || fitted.height == 0U) {
        return 1U;
    }
    const std::uint32_t by_width = width / fitted.width;
    const std::uint32_t by_height = height / fitted.height;
    const std::uint32_t factor = by_width < by_height ? by_width : by_height;
    return factor < 1U ? 1U : factor;
}

[[nodiscard]] unsigned worker_count(const std::uint32_t rows) noexcept {
    unsigned workers = std::thread::hardware_concurrency();
    if (workers == 0U) workers = 1U;
    // 한 줄에 스레드 하나씩 붙이면 만드는 값이 하는 일보다 큽니다.
    const unsigned by_rows = rows / 64U;
    if (workers > by_rows) workers = by_rows;
    return workers < 1U ? 1U : workers;
}

/// 정수배 박스 평균입니다. 가장자리의 모자란 칸은 **있는 만큼만** 평균 내므로 원본의
/// 오른쪽·아래가 잘려 나가지 않습니다.
void box_average_rows(
    const std::uint16_t* const source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t factor,
    const std::uint32_t out_width,
    const std::uint32_t y_begin,
    const std::uint32_t y_end,
    std::uint16_t* const destination) noexcept {
    for (std::uint32_t y = y_begin; y < y_end; ++y) {
        const std::uint32_t sy0 = y * factor;
        const std::uint32_t sy1 = std::min(sy0 + factor, height);
        for (std::uint32_t x = 0U; x < out_width; ++x) {
            const std::uint32_t sx0 = x * factor;
            const std::uint32_t sx1 = std::min(sx0 + factor, width);
            std::uint32_t red = 0U;
            std::uint32_t green = 0U;
            std::uint32_t blue = 0U;
            std::uint32_t taken = 0U;
            for (std::uint32_t sy = sy0; sy < sy1; ++sy) {
                const std::size_t row = static_cast<std::size_t>(sy) * width;
                for (std::uint32_t sx = sx0; sx < sx1; ++sx) {
                    const std::size_t sample = (row + sx) * 3U;
                    red += source[sample];
                    green += source[sample + 1U];
                    blue += source[sample + 2U];
                    ++taken;
                }
            }
            if (taken == 0U) taken = 1U;
            const std::size_t out = (static_cast<std::size_t>(y) * out_width + x) * 3U;
            destination[out] = static_cast<std::uint16_t>(red / taken);
            destination[out + 1U] = static_cast<std::uint16_t>(green / taken);
            destination[out + 2U] = static_cast<std::uint16_t>(blue / taken);
        }
    }
}

void box_average(
    const std::uint16_t* const source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t factor,
    const std::uint32_t out_width,
    const std::uint32_t out_height,
    std::uint16_t* const destination) {
    const unsigned workers = worker_count(out_height);
    if (workers <= 1U) {
        box_average_rows(
            source, width, height, factor, out_width, 0U, out_height, destination);
        return;
    }
    std::vector<std::thread> pool;
    pool.reserve(workers);
    const std::uint32_t band = (out_height + workers - 1U) / workers;
    for (unsigned index = 0U; index < workers; ++index) {
        const std::uint32_t begin = index * band;
        if (begin >= out_height) break;
        const std::uint32_t end = std::min(begin + band, out_height);
        pool.emplace_back([&, begin, end] {
            box_average_rows(
                source, width, height, factor, out_width, begin, end, destination);
        });
    }
    for (std::thread& worker : pool) {
        worker.join();
    }
}

/// 16bit RGB 를 화소당 8바이트 `rgba16` 으로 넓힙니다. **줄인 결과에만** 씁니다.
void widen_to_rgba16(
    const std::uint16_t* const source,
    const std::size_t pixels,
    std::uint16_t* const destination) noexcept {
    for (std::size_t pixel = 0U; pixel < pixels; ++pixel) {
        const std::size_t in = pixel * 3U;
        const std::size_t out = pixel * 4U;
        destination[out] = source[in];
        destination[out + 1U] = source[in + 1U];
        destination[out + 2U] = source[in + 2U];
        destination[out + 3U] = 65'535U;
    }
}

/// WIC 스케일러가 읽을 원본입니다. 우리 버퍼를 **그대로** 가리킵니다.
///
/// `CreateBitmapFromMemory` 는 버퍼를 통째로 복사합니다(6000x4000 이면 144 MB). 읽기만 하는
/// 원본이라 그 사본은 메모리와 시간만 씁니다. 읽기 전용이므로 여러 스케일러가 동시에 읽어도
/// 됩니다.
class MemoryRgb16Source final : public IWICBitmapSource {
public:
    MemoryRgb16Source(const std::uint16_t* const pixels, const UINT width, const UINT height) noexcept
        : pixels_(pixels), width_(width), height_(height) {}
    MemoryRgb16Source(const MemoryRgb16Source&) = delete;
    MemoryRgb16Source& operator=(const MemoryRgb16Source&) = delete;

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id, void** const out) noexcept override {
        if (out == nullptr) {
            return E_POINTER;
        }
        if (IsEqualIID(id, __uuidof(IUnknown)) != 0 ||
            IsEqualIID(id, __uuidof(IWICBitmapSource)) != 0) {
            *out = static_cast<IWICBitmapSource*>(this);
            AddRef();
            return S_OK;
        }
        *out = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() noexcept override { return ++references_; }
    ULONG STDMETHODCALLTYPE Release() noexcept override {
        const ULONG left = --references_;
        if (left == 0U) {
            delete this;
        }
        return left;
    }
    HRESULT STDMETHODCALLTYPE GetSize(UINT* const width, UINT* const height) noexcept override {
        if (width == nullptr || height == nullptr) {
            return E_INVALIDARG;
        }
        *width = width_;
        *height = height_;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetPixelFormat(WICPixelFormatGUID* const format) noexcept override {
        if (format == nullptr) {
            return E_INVALIDARG;
        }
        *format = GUID_WICPixelFormat48bppRGB;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetResolution(double* const x, double* const y) noexcept override {
        if (x == nullptr || y == nullptr) {
            return E_INVALIDARG;
        }
        *x = 96.0;
        *y = 96.0;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE CopyPalette(IWICPalette*) noexcept override {
        return WINCODEC_ERR_PALETTEUNAVAILABLE;
    }
    HRESULT STDMETHODCALLTYPE CopyPixels(
        const WICRect* const rectangle,
        const UINT stride,
        const UINT buffer_size,
        BYTE* const buffer) noexcept override {
        const WICRect area = rectangle != nullptr
            ? *rectangle
            : WICRect{0, 0, static_cast<INT>(width_), static_cast<INT>(height_)};
        if (buffer == nullptr || area.X < 0 || area.Y < 0 || area.Width <= 0 || area.Height <= 0 ||
            static_cast<UINT>(area.X) + static_cast<UINT>(area.Width) > width_ ||
            static_cast<UINT>(area.Y) + static_cast<UINT>(area.Height) > height_) {
            return E_INVALIDARG;
        }
        const std::size_t row_bytes = static_cast<std::size_t>(area.Width) * 6U;
        if (stride < row_bytes ||
            buffer_size < static_cast<std::uint64_t>(stride) * (area.Height - 1) + row_bytes) {
            return WINCODEC_ERR_INSUFFICIENTBUFFER;
        }
        for (INT row = 0; row < area.Height; ++row) {
            const std::size_t first =
                (static_cast<std::size_t>(area.Y + row) * width_ + static_cast<std::size_t>(area.X)) * 3U;
            std::memcpy(buffer + static_cast<std::size_t>(row) * stride, pixels_ + first, row_bytes);
        }
        return S_OK;
    }

private:
    ~MemoryRgb16Source() = default;

    std::atomic<ULONG> references_{1U};
    const std::uint16_t* pixels_{nullptr};
    UINT width_{0U};
    UINT height_{0U};
};

/// 48bpp 원본을 WIC 스케일러로 줄여 `rgba16` 으로 넓혀 둡니다.
///
/// 출력 행을 띠로 나눠 띠마다 스케일러를 따로 둡니다. 스케일러는 출력 행마다 같은 원본 행과
/// 같은 가중치를 쓰므로 나눠 받아도 한 번에 받은 것과 화소가 같습니다. 한 스레드로 받던
/// 10056x6792 DNG 의 축소가 이 자리의 대부분이었습니다.
[[nodiscard]] bool scale_rgb16_to_rgba16(
    const std::uint16_t* const source,
    const std::uint32_t width,
    const std::uint32_t height,
    const FittedSize& fitted,
    std::uint16_t* const destination) {
    const std::uint64_t source_stride = static_cast<std::uint64_t>(width) * 6ULL;
    const std::uint64_t stride = static_cast<std::uint64_t>(fitted.width) * 6ULL;
    if (source_stride > std::numeric_limits<UINT>::max() ||
        stride * fitted.height > std::numeric_limits<UINT>::max()) {
        return false;
    }
    const ComApartment apartment{};
    if (FAILED(apartment.status())) {
        return false;
    }
    ComPtr<IWICImagingFactory> factory{};
    if (FAILED(CoCreateInstance(
            CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) {
        return false;
    }
    ComPtr<IWICBitmapSource> memory{};
    memory.Attach(new (std::nothrow) MemoryRgb16Source(source, width, height));
    if (!memory) {
        return false;
    }
    const std::uint32_t lanes = std::min(negaflow::core::physical_cores(), fitted.height);
    const std::uint32_t rows_per_lane = (fitted.height + lanes - 1U) / lanes;
    std::vector<ComPtr<IWICBitmapScaler>> scalers(lanes);
    for (ComPtr<IWICBitmapScaler>& scaler : scalers) {
        if (FAILED(factory->CreateBitmapScaler(&scaler)) ||
            FAILED(scaler->Initialize(
                memory.Get(),
                fitted.width,
                fitted.height,
                WICBitmapInterpolationModeHighQualityCubic))) {
            return false;
        }
    }
    std::atomic<bool> failed{false};
    negaflow::core::for_each_row_block(
        lanes,
        source_stride * height,
        [&](const std::uint32_t first_lane, const std::uint32_t lane_count) noexcept {
            const ComApartment lane_apartment{};
            try {
                std::vector<std::uint16_t> band(
                    static_cast<std::size_t>(rows_per_lane) * fitted.width * 3U);
                for (std::uint32_t lane = first_lane; lane < first_lane + lane_count; ++lane) {
                    const std::uint32_t top = lane * rows_per_lane;
                    if (top >= fitted.height || failed.load(std::memory_order_relaxed)) {
                        return;
                    }
                    const std::uint32_t rows = std::min(rows_per_lane, fitted.height - top);
                    const WICRect rectangle{
                        0, static_cast<INT>(top), static_cast<INT>(fitted.width), static_cast<INT>(rows)};
                    if (FAILED(scalers[lane]->CopyPixels(
                            &rectangle,
                            static_cast<UINT>(stride),
                            static_cast<UINT>(stride * rows),
                            reinterpret_cast<BYTE*>(band.data())))) {
                        failed.store(true, std::memory_order_relaxed);
                        return;
                    }
                    widen_to_rgba16(
                        band.data(),
                        static_cast<std::size_t>(rows) * fitted.width,
                        destination + static_cast<std::size_t>(top) * fitted.width * 4U);
                }
            } catch (...) {
                failed.store(true, std::memory_order_relaxed);
            }
        });
    return !failed.load(std::memory_order_relaxed);
}

}  // namespace

LibRawPreviewReduceResult reduce_libraw_rgb16_to_preview(
    const std::uint16_t* const source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t maximum_width,
    const std::uint32_t maximum_height,
    const std::uint64_t max_decoded_pixel_bytes,
    DecodedImage& destination) noexcept {
    LibRawPreviewReduceResult result{};
    if (source == nullptr || width == 0U || height == 0U) {
        return result;
    }
    try {
        const FittedSize fitted = fit_within(width, height, maximum_width, maximum_height);
        const std::uint64_t stride = static_cast<std::uint64_t>(fitted.width) * 8ULL;
        const std::uint64_t bytes = stride * fitted.height;
        if (stride > std::numeric_limits<std::uint32_t>::max() ||
            bytes > max_decoded_pixel_bytes) {
            return result;
        }

        const std::uint16_t* pixels = source;
        std::uint32_t pixels_width = width;
        std::uint32_t pixels_height = height;
        std::vector<std::uint16_t> averaged{};
        if (fitted.width != width || fitted.height != height) {
            const std::uint32_t factor = box_average_factor(width, height, fitted);
            if (factor >= 2U) {
                pixels_width = (width + factor - 1U) / factor;
                pixels_height = (height + factor - 1U) / factor;
                averaged.resize(
                    static_cast<std::size_t>(pixels_width) * pixels_height * 3U);
                box_average(
                    source,
                    width,
                    height,
                    factor,
                    pixels_width,
                    pixels_height,
                    averaged.data());
                pixels = averaged.data();
                result.box_average_factor = factor;
            }
        }

        std::vector<std::uint16_t> samples(static_cast<std::size_t>(bytes / sizeof(std::uint16_t)));
        if (pixels_width != fitted.width || pixels_height != fitted.height) {
            if (!scale_rgb16_to_rgba16(pixels, pixels_width, pixels_height, fitted, samples.data())) {
                return result;
            }
            result.reduced = true;
        } else {
            widen_to_rgba16(
                pixels, static_cast<std::size_t>(fitted.width) * fitted.height, samples.data());
        }

        destination.width = fitted.width;
        destination.height = fitted.height;
        destination.stride_bytes = static_cast<std::uint32_t>(stride);
        destination.layout = DecodedPixelLayout::rgba16;
        destination.alpha_mode = AlphaMode::unassociated;
        destination.untagged_rgb_transfer = UntaggedRgbTransfer::srgb_encoded;
        destination.samples = std::move(samples);
        result.reduced = result.reduced || fitted.width != width || fitted.height != height;
        result.ok = true;
        return result;
    } catch (...) {
        return LibRawPreviewReduceResult{};
    }
}

}  // namespace negaflow::imageio
