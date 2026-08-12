#include "negaflow/imageio/wic_standard_image_decoder.h"

#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <vector>

namespace negaflow::imageio {
namespace {

using Microsoft::WRL::ComPtr;

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

void discard_samples(WicStandardImageDecodeResult& result) noexcept {
    std::vector<std::uint16_t>{}.swap(result.image.samples);
}

[[nodiscard]] bool supported_container(const GUID& format) noexcept {
    return IsEqualGUID(format, GUID_ContainerFormatJpeg) != 0 ||
           IsEqualGUID(format, GUID_ContainerFormatPng) != 0;
}

[[nodiscard]] WicStandardImageDecodeStatus extract_icc_profile(
    IWICImagingFactory* const factory,
    IWICBitmapFrameDecode* const frame,
    const WicStandardImageDecodeLimits& limits,
    WicStandardImageDecodeResult& result) {
    UINT count = 0U;
    HRESULT status = frame->GetColorContexts(0U, nullptr, &count);
    if (status == WINCODEC_ERR_UNSUPPORTEDOPERATION) {
        return WicStandardImageDecodeStatus::ok;
    }
    if (FAILED(status) || count > limits.max_color_contexts) {
        return WicStandardImageDecodeStatus::color_context_failed;
    }
    if (count == 0U) {
        return WicStandardImageDecodeStatus::ok;
    }

    std::vector<ComPtr<IWICColorContext>> contexts(count);
    std::vector<IWICColorContext*> raw_contexts(count, nullptr);
    for (UINT index = 0U; index < count; ++index) {
        if (FAILED(factory->CreateColorContext(&contexts[index]))) {
            return WicStandardImageDecodeStatus::color_context_failed;
        }
        raw_contexts[index] = contexts[index].Get();
    }
    UINT actual_count = 0U;
    if (FAILED(frame->GetColorContexts(count, raw_contexts.data(), &actual_count)) ||
        actual_count != count) {
        return WicStandardImageDecodeStatus::color_context_failed;
    }

    bool profile_found = false;
    for (const ComPtr<IWICColorContext>& context : contexts) {
        WICColorContextType type = WICColorContextUninitialized;
        if (FAILED(context->GetType(&type))) {
            return WicStandardImageDecodeStatus::color_context_failed;
        }
        if (type != WICColorContextProfile) {
            continue;
        }
        if (profile_found) {
            return WicStandardImageDecodeStatus::color_context_failed;
        }
        profile_found = true;
        UINT bytes = 0U;
        if (FAILED(context->GetProfileBytes(0U, nullptr, &bytes)) ||
            bytes == 0U || bytes > limits.icc.max_profile_bytes) {
            return WicStandardImageDecodeStatus::color_context_failed;
        }
        result.image.icc_profile.resize(bytes);
        UINT actual_bytes = 0U;
        if (FAILED(context->GetProfileBytes(
                bytes,
                result.image.icc_profile.data(),
                &actual_bytes)) ||
            actual_bytes != bytes) {
            return WicStandardImageDecodeStatus::color_context_failed;
        }
    }
    if (!profile_found) {
        return WicStandardImageDecodeStatus::ok;
    }

    const negaflow::color::IccProfileValidationResult validation =
        negaflow::color::validate_icc_profile(result.image.icc_profile, limits.icc);
    result.icc_status = validation.status;
    result.info.icc = validation.info;
    return validation.status == negaflow::color::IccProfileStatus::ok
        ? WicStandardImageDecodeStatus::ok
        : WicStandardImageDecodeStatus::invalid_icc_profile;
}

}  // namespace

WicStandardImageDecodeResult decode_standard_image_with_wic(
    const std::filesystem::path& path,
    const WicStandardImageDecodeLimits& limits,
    const std::stop_token stop_token) noexcept {
    WicStandardImageDecodeResult result{};
    try {
        if (path.empty()) {
            return result;
        }
        if (stop_token.stop_requested()) {
            result.status = WicStandardImageDecodeStatus::cancelled;
            return result;
        }
        const ComApartment apartment{};
        if (apartment.status() == RPC_E_CHANGED_MODE) {
            result.status = WicStandardImageDecodeStatus::com_apartment_mismatch;
            return result;
        }
        if (FAILED(apartment.status())) {
            result.status = WicStandardImageDecodeStatus::wic_unavailable;
            return result;
        }

        ComPtr<IWICImagingFactory> factory{};
        if (FAILED(CoCreateInstance(
                CLSID_WICImagingFactory,
                nullptr,
                CLSCTX_INPROC_SERVER,
                IID_PPV_ARGS(&factory)))) {
            result.status = WicStandardImageDecodeStatus::wic_unavailable;
            return result;
        }
        ComPtr<IWICBitmapDecoder> decoder{};
        if (FAILED(factory->CreateDecoderFromFilename(
                path.c_str(),
                nullptr,
                GENERIC_READ,
                WICDecodeMetadataCacheOnDemand,
                &decoder))) {
            result.status = WicStandardImageDecodeStatus::decoder_initialization_failed;
            return result;
        }
        GUID format{};
        if (FAILED(decoder->GetContainerFormat(&format)) || !supported_container(format)) {
            result.status = WicStandardImageDecodeStatus::unsupported_container;
            return result;
        }
        if (FAILED(decoder->GetFrameCount(&result.info.frame_count)) ||
            result.info.frame_count != 1U) {
            result.status = WicStandardImageDecodeStatus::frame_count_unsupported;
            return result;
        }
        ComPtr<IWICBitmapFrameDecode> frame{};
        UINT width = 0U;
        UINT height = 0U;
        if (FAILED(decoder->GetFrame(0U, &frame)) ||
            FAILED(frame->GetSize(&width, &height)) || width == 0U || height == 0U) {
            result.status = WicStandardImageDecodeStatus::pixel_decode_failed;
            return result;
        }
        const std::uint64_t stride = static_cast<std::uint64_t>(width) * 8ULL;
        const std::uint64_t bytes = stride * height;
        if (stride > std::numeric_limits<UINT>::max() ||
            bytes > limits.max_decoded_pixel_bytes ||
            bytes > std::numeric_limits<UINT>::max() ||
            bytes / sizeof(std::uint16_t) > std::numeric_limits<std::size_t>::max()) {
            result.status = WicStandardImageDecodeStatus::memory_limit_exceeded;
            return result;
        }
        const WicStandardImageDecodeStatus profile_status =
            extract_icc_profile(factory.Get(), frame.Get(), limits, result);
        if (profile_status != WicStandardImageDecodeStatus::ok) {
            result.status = profile_status;
            return result;
        }
        if (stop_token.stop_requested()) {
            result.status = WicStandardImageDecodeStatus::cancelled;
            return result;
        }
        GUID source_format{};
        if (FAILED(frame->GetPixelFormat(&source_format))) {
            result.status = WicStandardImageDecodeStatus::pixel_decode_failed;
            return result;
        }
        ComPtr<IWICBitmapSource> source{};
        if (IsEqualGUID(source_format, GUID_WICPixelFormat64bppRGBA) != 0) {
            if (FAILED(frame.As(&source))) {
                result.status = WicStandardImageDecodeStatus::pixel_decode_failed;
                return result;
            }
        } else {
            ComPtr<IWICFormatConverter> converter{};
            BOOL can_convert = FALSE;
            if (FAILED(factory->CreateFormatConverter(&converter)) ||
                FAILED(converter->CanConvert(source_format, GUID_WICPixelFormat64bppRGBA,
                    &can_convert)) || !can_convert ||
                FAILED(converter->Initialize(
                    frame.Get(),
                    GUID_WICPixelFormat64bppRGBA,
                    WICBitmapDitherTypeNone,
                    nullptr,
                    0.0,
                    WICBitmapPaletteTypeCustom)) ||
                FAILED(converter.As(&source))) {
                result.status = WicStandardImageDecodeStatus::unsupported_pixel_format;
                return result;
            }
            result.info.format_conversion_used = true;
        }
        result.image.width = width;
        result.image.height = height;
        result.image.stride_bytes = static_cast<std::uint32_t>(stride);
        result.image.layout = DecodedPixelLayout::rgba16;
        result.image.alpha_mode = AlphaMode::unassociated;
        result.image.untagged_rgb_transfer = UntaggedRgbTransfer::srgb_encoded;
        result.image.samples.resize(static_cast<std::size_t>(bytes / sizeof(std::uint16_t)));
        if (FAILED(source->CopyPixels(
                nullptr,
                static_cast<UINT>(stride),
                static_cast<UINT>(bytes),
                reinterpret_cast<BYTE*>(result.image.samples.data())))) {
            discard_samples(result);
            result.status = WicStandardImageDecodeStatus::pixel_decode_failed;
            return result;
        }
        if (stop_token.stop_requested()) {
            discard_samples(result);
            result.status = WicStandardImageDecodeStatus::cancelled;
            return result;
        }
        result.info.decoded_pixel_bytes = bytes;
        result.status = WicStandardImageDecodeStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        discard_samples(result);
        result.status = WicStandardImageDecodeStatus::allocation_failed;
        return result;
    } catch (...) {
        discard_samples(result);
        result.status = WicStandardImageDecodeStatus::pixel_decode_failed;
        return result;
    }
}

const char* wic_standard_image_decode_status_name(const WicStandardImageDecodeStatus status) noexcept {
    switch (status) {
        case WicStandardImageDecodeStatus::ok: return "ok";
        case WicStandardImageDecodeStatus::invalid_argument: return "invalid_argument";
        case WicStandardImageDecodeStatus::cancelled: return "cancelled";
        case WicStandardImageDecodeStatus::com_apartment_mismatch: return "com_apartment_mismatch";
        case WicStandardImageDecodeStatus::wic_unavailable: return "wic_unavailable";
        case WicStandardImageDecodeStatus::decoder_initialization_failed:
            return "decoder_initialization_failed";
        case WicStandardImageDecodeStatus::unsupported_container: return "unsupported_container";
        case WicStandardImageDecodeStatus::frame_count_unsupported:
            return "frame_count_unsupported";
        case WicStandardImageDecodeStatus::unsupported_pixel_format:
            return "unsupported_pixel_format";
        case WicStandardImageDecodeStatus::color_context_failed: return "color_context_failed";
        case WicStandardImageDecodeStatus::invalid_icc_profile: return "invalid_icc_profile";
        case WicStandardImageDecodeStatus::memory_limit_exceeded: return "memory_limit_exceeded";
        case WicStandardImageDecodeStatus::allocation_failed: return "allocation_failed";
        case WicStandardImageDecodeStatus::pixel_decode_failed: return "pixel_decode_failed";
    }
    return "unknown_standard_image_decode_status";
}

}  // namespace negaflow::imageio
