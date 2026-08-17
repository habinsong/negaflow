#include "develop_export_abi_test_support.h"

#include <Windows.h>
#include <bcrypt.h>
#include <wincodec.h>
#include <wrl/client.h>

#ifdef small
#undef small
#endif

#include <algorithm>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>

#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "windowscodecs.lib")

namespace negaflow::develop_export_abi_tests {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] bool sha256(
    const std::vector<std::uint8_t>& bytes,
    std::array<std::uint8_t, 32U>& digest) noexcept {
    if (bytes.size() >
        static_cast<std::size_t>(std::numeric_limits<ULONG>::max())) {
        return false;
    }
    return BCryptHash(
               BCRYPT_SHA256_ALG_HANDLE,
               nullptr,
               0U,
               const_cast<PUCHAR>(bytes.data()),
               static_cast<ULONG>(bytes.size()),
               digest.data(),
               static_cast<ULONG>(digest.size())) >= 0;
}

[[nodiscard]] bool write_file(
    const std::filesystem::path& path,
    const std::vector<std::uint8_t>& bytes) {
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    output.write(
        reinterpret_cast<const char*>(bytes.data()),
        static_cast<std::streamsize>(bytes.size()));
    return output.good();
}

[[nodiscard]] std::vector<std::uint8_t> read_file(
    const std::filesystem::path& path) {
    std::ifstream input(path, std::ios::binary);
    return std::vector<std::uint8_t>(
        std::istreambuf_iterator<char>(input),
        std::istreambuf_iterator<char>());
}

[[nodiscard]] std::vector<std::uint8_t> decode_png_bgra8(
    const std::filesystem::path& path,
    const std::uint32_t expected_width,
    const std::uint32_t expected_height) {
    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(initialized) && initialized != RPC_E_CHANGED_MODE) {
        return {};
    }
    const bool uninitialize = SUCCEEDED(initialized);
    Microsoft::WRL::ComPtr<IWICImagingFactory> factory{};
    Microsoft::WRL::ComPtr<IWICBitmapDecoder> decoder{};
    Microsoft::WRL::ComPtr<IWICBitmapFrameDecode> frame{};
    Microsoft::WRL::ComPtr<IWICFormatConverter> converter{};
    HRESULT status = CoCreateInstance(
        CLSID_WICImagingFactory2,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&factory));
    if (SUCCEEDED(status)) {
        status = factory->CreateDecoderFromFilename(
            path.c_str(),
            nullptr,
            GENERIC_READ,
            WICDecodeMetadataCacheOnLoad,
            &decoder);
    }
    if (SUCCEEDED(status)) {
        status = decoder->GetFrame(0U, &frame);
    }
    UINT width = 0U;
    UINT height = 0U;
    if (SUCCEEDED(status)) {
        status = frame->GetSize(&width, &height);
    }
    if (SUCCEEDED(status) &&
        (width != expected_width || height != expected_height)) {
        status = E_FAIL;
    }
    if (SUCCEEDED(status)) {
        status = factory->CreateFormatConverter(&converter);
    }
    if (SUCCEEDED(status)) {
        status = converter->Initialize(
            frame.Get(),
            GUID_WICPixelFormat32bppBGRA,
            WICBitmapDitherTypeNone,
            nullptr,
            0.0,
            WICBitmapPaletteTypeCustom);
    }
    std::vector<std::uint8_t> pixels{};
    if (SUCCEEDED(status)) {
        pixels.resize(static_cast<std::size_t>(width) * height * 4U);
        status = converter->CopyPixels(
            nullptr,
            width * 4U,
            static_cast<UINT>(pixels.size()),
            pixels.data());
    }
    if (FAILED(status)) {
        pixels.clear();
    }
    converter.Reset();
    frame.Reset();
    decoder.Reset();
    factory.Reset();
    if (uninitialize) {
        CoUninitialize();
    }
    return pixels;
}

// Neutrality of a monochrome develop is a property of the working image. The 8-bit
// preview adds under one code value of dither per channel — as the macOS display path
// does — so the check is "no visible tint", not "identical bytes". A real tint from the
// B&W graph would be far larger than one step.
[[nodiscard]] bool preview_is_neutral(
    const std::vector<std::uint8_t>& pixels) noexcept {
    for (std::size_t offset = 0U; offset + 3U < pixels.size(); offset += 4U) {
        const int blue = pixels[offset];
        const int green = pixels[offset + 1U];
        const int red = pixels[offset + 2U];
        const int highest = std::max(red, std::max(green, blue));
        const int lowest = std::min(red, std::min(green, blue));
        if (highest - lowest > 1) {
            return false;
        }
    }
    return true;
}

}  // namespace negaflow::develop_export_abi_tests
