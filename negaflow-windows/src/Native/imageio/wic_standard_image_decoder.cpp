#include "negaflow/imageio/wic_standard_image_decoder.h"

#include "wic_orientation.h"

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
           IsEqualGUID(format, GUID_ContainerFormatPng) != 0 ||
           IsEqualGUID(format, GUID_ContainerFormatRaw) != 0;
}

[[nodiscard]] WicStandardImageDecodeStatus configure_raw_development(
    IWICImagingFactory* const factory,
    IWICBitmapFrameDecode* const frame) noexcept {
    ComPtr<IWICDevelopRaw> raw{};
    if (FAILED(frame->QueryInterface(IID_PPV_ARGS(&raw))) ||
        FAILED(raw->LoadParameterSet(WICAsShotParameterSet)) ||
        FAILED(raw->SetRenderMode(WICRawRenderModeBestQuality))) {
        return WicStandardImageDecodeStatus::raw_development_failed;
    }
    ComPtr<IWICColorContext> srgb{};
    if (FAILED(factory->CreateColorContext(&srgb)) ||
        FAILED(srgb->InitializeFromExifColorSpace(1U)) ||
        FAILED(raw->SetDestinationColorContext(srgb.Get()))) {
        return WicStandardImageDecodeStatus::raw_development_failed;
    }
    return WicStandardImageDecodeStatus::ok;
}

[[nodiscard]] std::uint16_t exif_orientation(
    IWICBitmapFrameDecode* const frame) noexcept {
    ComPtr<IWICMetadataQueryReader> reader{};
    if (FAILED(frame->GetMetadataQueryReader(&reader))) {
        return 1U;
    }
    PROPVARIANT value{};
    PropVariantInit(&value);
    const HRESULT status = reader->GetMetadataByName(
        L"/app1/ifd/{ushort=274}", &value);
    std::uint32_t orientation = 1U;
    if (SUCCEEDED(status)) {
        switch (value.vt) {
            case VT_UI2: orientation = value.uiVal; break;
            case VT_UI4: orientation = value.ulVal; break;
            case VT_I2: orientation = static_cast<std::uint16_t>(value.iVal); break;
            case VT_I4: orientation = static_cast<std::uint32_t>(value.lVal); break;
            default: break;
        }
    }
    PropVariantClear(&value);
    return orientation >= 1U && orientation <= 8U
        ? static_cast<std::uint16_t>(orientation)
        : 1U;
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
        const bool is_raw = IsEqualGUID(format, GUID_ContainerFormatRaw) != 0;
        if (FAILED(decoder->GetFrameCount(&result.info.frame_count)) ||
            result.info.frame_count != 1U) {
            result.status = WicStandardImageDecodeStatus::frame_count_unsupported;
            return result;
        }
        ComPtr<IWICBitmapFrameDecode> frame{};
        UINT width = 0U;
        UINT height = 0U;
        if (FAILED(decoder->GetFrame(0U, &frame))) {
            result.status = WicStandardImageDecodeStatus::pixel_decode_failed;
            return result;
        }
        if (is_raw) {
            const WicStandardImageDecodeStatus raw_status =
                configure_raw_development(factory.Get(), frame.Get());
            if (raw_status != WicStandardImageDecodeStatus::ok) {
                result.status = raw_status;
                return result;
            }
            result.info.raw_development_used = true;
        }
        if (FAILED(frame->GetSize(&width, &height)) || width == 0U || height == 0U) {
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
        // WIC RAW codecs apply their as-shot rotation through IWICDevelopRaw. Standard
        // containers retain the EXIF transform here, matching ImageIO's separate path.
        result.info.exif_orientation = is_raw ? 1U : exif_orientation(frame.Get());
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
        ComPtr<IWICBitmapSource> oriented{};
        if (!wic_detail::apply_exif_orientation(
                factory.Get(), source.Get(), result.info.exif_orientation, oriented)) {
            result.status = WicStandardImageDecodeStatus::pixel_decode_failed;
            return result;
        }
        if (FAILED(oriented->GetSize(&width, &height)) || width == 0U || height == 0U) {
            result.status = WicStandardImageDecodeStatus::pixel_decode_failed;
            return result;
        }
        const std::uint64_t oriented_stride = static_cast<std::uint64_t>(width) * 8ULL;
        const std::uint64_t oriented_bytes = oriented_stride * height;
        if (oriented_stride > std::numeric_limits<UINT>::max() ||
            oriented_bytes > limits.max_decoded_pixel_bytes ||
            oriented_bytes > std::numeric_limits<UINT>::max() ||
            oriented_bytes / sizeof(std::uint16_t) > std::numeric_limits<std::size_t>::max()) {
            result.status = WicStandardImageDecodeStatus::memory_limit_exceeded;
            return result;
        }
        result.image.width = width;
        result.image.height = height;
        result.image.stride_bytes = static_cast<std::uint32_t>(oriented_stride);
        result.image.layout = DecodedPixelLayout::rgba16;
        result.image.alpha_mode = AlphaMode::unassociated;
        result.image.untagged_rgb_transfer = UntaggedRgbTransfer::srgb_encoded;
        result.image.samples.resize(static_cast<std::size_t>(oriented_bytes / sizeof(std::uint16_t)));
        if (FAILED(oriented->CopyPixels(
                nullptr,
                static_cast<UINT>(oriented_stride),
                static_cast<UINT>(oriented_bytes),
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
        result.info.decoded_pixel_bytes = oriented_bytes;
        result.info.orientation_applied = result.info.exif_orientation != 1U;
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
        case WicStandardImageDecodeStatus::raw_development_failed:
            return "raw_development_failed";
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
