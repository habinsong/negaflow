#include "wic_multiframe_tiff_fixture.h"

#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <limits>

namespace negaflow::test_fixtures {
namespace {

class ComApartment final {
public:
    ComApartment() noexcept : status_(CoInitializeEx(nullptr, COINIT_MULTITHREADED)) {}
    ~ComApartment() {
        if (status_ == S_OK || status_ == S_FALSE) CoUninitialize();
    }

    [[nodiscard]] bool available() const noexcept {
        return SUCCEEDED(status_) || status_ == RPC_E_CHANGED_MODE;
    }

private:
    HRESULT status_{E_FAIL};
};

[[nodiscard]] HRESULT write_frame(
    IWICBitmapEncoder* const encoder,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint8_t channels,
    const std::span<const std::uint16_t> pixels) noexcept {
    Microsoft::WRL::ComPtr<IWICBitmapFrameEncode> frame{};
    Microsoft::WRL::ComPtr<IPropertyBag2> options{};
    HRESULT status = encoder->CreateNewFrame(&frame, &options);
    if (SUCCEEDED(status)) status = frame->Initialize(options.Get());
    if (SUCCEEDED(status)) status = frame->SetSize(width, height);
    WICPixelFormatGUID format = channels == 1U
        ? GUID_WICPixelFormat16bppGray
        : GUID_WICPixelFormat48bppRGB;
    if (SUCCEEDED(status)) status = frame->SetPixelFormat(&format);
    const WICPixelFormatGUID expected = channels == 1U
        ? GUID_WICPixelFormat16bppGray
        : GUID_WICPixelFormat48bppRGB;
    if (SUCCEEDED(status) && IsEqualGUID(format, expected) == FALSE) status = E_FAIL;
    const std::uint64_t stride =
        static_cast<std::uint64_t>(width) * channels * sizeof(std::uint16_t);
    const std::uint64_t byte_count = stride * height;
    if (stride > std::numeric_limits<UINT>::max() ||
        byte_count > std::numeric_limits<UINT>::max()) {
        return E_INVALIDARG;
    }
    if (SUCCEEDED(status)) {
        status = frame->WritePixels(
            height,
            static_cast<UINT>(stride),
            static_cast<UINT>(byte_count),
            reinterpret_cast<BYTE*>(const_cast<std::uint16_t*>(pixels.data())));
    }
    if (SUCCEEDED(status)) status = frame->Commit();
    return status;
}

[[nodiscard]] bool write_tiff16(
    const std::filesystem::path& path,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint8_t channels,
    const std::span<const std::uint16_t> first,
    const std::span<const std::uint16_t> second,
    const bool write_second) noexcept {
    const std::uint64_t required =
        static_cast<std::uint64_t>(width) * height * channels;
    if (path.empty() || width == 0U || height == 0U ||
        (channels != 1U && channels != 3U) ||
        required > std::numeric_limits<std::size_t>::max() ||
        first.size() != required || (write_second && second.size() != required)) {
        return false;
    }
    const ComApartment apartment{};
    if (!apartment.available()) return false;

    std::error_code error{};
    static_cast<void>(std::filesystem::remove(path, error));
    Microsoft::WRL::ComPtr<IWICImagingFactory> factory{};
    HRESULT status = CoCreateInstance(
        CLSID_WICImagingFactory2,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&factory));
    if (FAILED(status)) {
        status = CoCreateInstance(
            CLSID_WICImagingFactory,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&factory));
    }
    Microsoft::WRL::ComPtr<IWICStream> stream{};
    if (SUCCEEDED(status)) status = factory->CreateStream(&stream);
    if (SUCCEEDED(status)) {
        status = stream->InitializeFromFilename(path.c_str(), GENERIC_WRITE);
    }
    Microsoft::WRL::ComPtr<IWICBitmapEncoder> encoder{};
    if (SUCCEEDED(status)) {
        status = factory->CreateEncoder(GUID_ContainerFormatTiff, nullptr, &encoder);
    }
    if (SUCCEEDED(status)) {
        status = encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache);
    }
    if (SUCCEEDED(status)) {
        status = write_frame(encoder.Get(), width, height, channels, first);
    }
    if (SUCCEEDED(status) && write_second) {
        status = write_frame(encoder.Get(), width, height, channels, second);
    }
    if (SUCCEEDED(status)) status = encoder->Commit();
    return SUCCEEDED(status);
}

}  // namespace

bool write_single_frame_tiff16(
    const std::filesystem::path& path,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint8_t channels,
    const std::span<const std::uint16_t> pixels) noexcept {
    return write_tiff16(path, width, height, channels, pixels, {}, false);
}

bool write_two_frame_tiff16(
    const std::filesystem::path& path,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint8_t channels,
    const std::span<const std::uint16_t> first,
    const std::span<const std::uint16_t> second) noexcept {
    return write_tiff16(path, width, height, channels, first, second, true);
}

}  // namespace negaflow::test_fixtures
