#include "wic_tiff_frame.h"

#include "wic_tiff_support.h"

namespace negaflow::imageio::wic_tiff_detail {

using Microsoft::WRL::ComPtr;

WicTiffDecodeStatus select_tiff_frame(
    const TiffPreflight& preflight,
    const WicTiffDecodeLimits& limits,
    SelectedFrame& selected,
    WicTiffDecodeResult& result) {
    ComPtr<IWICImagingFactory> factory{};
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
    if (FAILED(status)) {
        return WicTiffDecodeStatus::wic_unavailable;
    }

    ComPtr<IWICBitmapDecoder> decoder{};
    status = factory->CreateDecoder(
        GUID_ContainerFormatTiff,
        &GUID_VendorMicrosoftBuiltIn,
        &decoder);
    if (FAILED(status) ||
        FAILED(decoder->Initialize(
            preflight.stream.Get(), WICDecodeMetadataCacheOnDemand))) {
        return WicTiffDecodeStatus::decoder_initialization_failed;
    }

    ComPtr<IWICBitmapDecoderInfo> decoder_info{};
    CLSID decoder_clsid{};
    GUID container_format{};
    if (FAILED(decoder->GetDecoderInfo(&decoder_info)) ||
        FAILED(decoder_info->GetCLSID(&decoder_clsid)) ||
        FAILED(decoder->GetContainerFormat(&container_format)) ||
        IsEqualGUID(decoder_clsid, CLSID_WICTiffDecoder) == 0 ||
        IsEqualGUID(container_format, GUID_ContainerFormatTiff) == 0) {
        return WicTiffDecodeStatus::unexpected_decoder;
    }

    status = decoder->GetFrameCount(&result.info.frame_count);
    if (FAILED(status) || result.info.frame_count == 0U ||
        result.info.frame_count > limits.probe.max_directories) {
        return WicTiffDecodeStatus::frame_count_unsupported;
    }

    ComPtr<IWICBitmapFrameDecode> frame{};
    GUID source_format{};
    UINT width = 0U;
    UINT height = 0U;
    UINT matches = 0U;
    for (UINT index = 0U; index < result.info.frame_count; ++index) {
        ComPtr<IWICBitmapFrameDecode> candidate{};
        UINT candidate_width = 0U;
        UINT candidate_height = 0U;
        if (FAILED(decoder->GetFrame(index, &candidate)) ||
            FAILED(candidate->GetSize(&candidate_width, &candidate_height))) {
            return WicTiffDecodeStatus::pixel_decode_failed;
        }
        if (candidate_width != preflight.info.width ||
            candidate_height != preflight.info.height) {
            continue;
        }
        ++matches;
        if (matches > 1U) {
            return WicTiffDecodeStatus::frame_count_unsupported;
        }
        frame = candidate;
        width = candidate_width;
        height = candidate_height;
    }
    if (matches != 1U || !frame) {
        return WicTiffDecodeStatus::dimension_mismatch;
    }
    if (FAILED(frame->GetPixelFormat(&source_format))) {
        return WicTiffDecodeStatus::pixel_decode_failed;
    }
    result.info.source_pixel_format = classify_pixel_format(source_format);

    const bool grayscale = preflight.info.samples_per_pixel == 1U;
    const bool has_alpha = preflight.info.samples_per_pixel == 4U;
    const bool associated_alpha = has_alpha && preflight.info.extra_samples[0] == 1U;
    const GUID& target_format = grayscale
                                    ? GUID_WICPixelFormat16bppGray
                                : !has_alpha ? GUID_WICPixelFormat48bppRGB
                                    : associated_alpha ? GUID_WICPixelFormat64bppPRGBA
                                                       : GUID_WICPixelFormat64bppRGBA;
    result.info.output_pixel_format = classify_pixel_format(target_format);
    result.image.width = width;
    result.image.height = height;
    result.image.layout = grayscale ? DecodedPixelLayout::gray16
                          : has_alpha ? DecodedPixelLayout::rgba16
                                      : DecodedPixelLayout::rgb16;
    result.image.alpha_mode = !has_alpha
                                  ? AlphaMode::opaque
                                  : associated_alpha ? AlphaMode::associated
                                                     : AlphaMode::unassociated;

    selected.factory = factory;
    selected.frame = frame;
    selected.source_format = source_format;
    selected.target_format = target_format;
    selected.width = width;
    selected.height = height;
    return WicTiffDecodeStatus::ok;
}

WicTiffDecodeStatus open_pixel_source(
    const SelectedFrame& selected,
    const TiffPreflight& preflight,
    const WicTiffDecodeLimits& limits,
    ComPtr<IWICBitmapSource>& pixel_source,
    WicTiffDecodeResult& result) {
    HRESULT status = S_OK;
    if (IsEqualGUID(selected.source_format, selected.target_format) != 0) {
        status = selected.frame.As(&pixel_source);
    } else {
        ComPtr<IWICFormatConverter> converter{};
        BOOL can_convert = FALSE;
        status = selected.factory->CreateFormatConverter(&converter);
        if (SUCCEEDED(status)) {
            status = converter->CanConvert(
                selected.source_format, selected.target_format, &can_convert);
        }
        if (FAILED(status) || can_convert == FALSE ||
            FAILED(converter->Initialize(
                selected.frame.Get(),
                selected.target_format,
                WICBitmapDitherTypeNone,
                nullptr,
                0.0,
                WICBitmapPaletteTypeCustom))) {
            return WicTiffDecodeStatus::unsupported_pixel_format;
        }
        result.info.format_conversion_used = true;
        status = converter.As(&pixel_source);
    }
    if (FAILED(status)) {
        return WicTiffDecodeStatus::unsupported_pixel_format;
    }

    return extract_icc_profile(
        selected.factory.Get(),
        selected.frame.Get(),
        preflight.info.icc_profile_bytes,
        limits,
        result);
}

}  // namespace negaflow::imageio::wic_tiff_detail
