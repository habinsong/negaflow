#include "wic_jpeg_encode.h"

#include <Shlwapi.h>
#include <wrl/client.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <new>

namespace negaflow::output::wic_jpeg_detail {

using Microsoft::WRL::ComPtr;

[[nodiscard]] WicJpegExportStatus map_atomic_status(
    const detail::AtomicOutputStatus status) noexcept {
    switch (status) {
        case detail::AtomicOutputStatus::ok:
            return WicJpegExportStatus::ok;
        case detail::AtomicOutputStatus::destination_exists:
            return WicJpegExportStatus::destination_exists;
        case detail::AtomicOutputStatus::flush_failed:
            return WicJpegExportStatus::flush_failed;
        case detail::AtomicOutputStatus::published_file_invalid:
            return WicJpegExportStatus::published_file_invalid;
        case detail::AtomicOutputStatus::publish_failed:
            return WicJpegExportStatus::publish_failed;
        case detail::AtomicOutputStatus::allocation_failed:
            return WicJpegExportStatus::allocation_failed;
        case detail::AtomicOutputStatus::invalid_path:
        case detail::AtomicOutputStatus::destination_query_failed:
        case detail::AtomicOutputStatus::parent_unavailable:
        case detail::AtomicOutputStatus::staging_create_failed:
            return WicJpegExportStatus::staging_create_failed;
    }
    return WicJpegExportStatus::staging_create_failed;
}

void discard_staging(
    detail::AtomicOutputFile* const output,
    WicJpegExportResult& result) noexcept {
    if (output != nullptr) {
        output->discard(result.cleanup_error_code);
    }
}

[[nodiscard]] bool write_option(
    IPropertyBag2* const options,
    const wchar_t* const name,
    const VARIANT& value,
    std::uint32_t& native_error_code) noexcept {
    PROPBAG2 option{};
    option.dwType = PROPBAG2_TYPE_DATA;
    option.vt = value.vt;
    option.pstrName = const_cast<wchar_t*>(name);
    const HRESULT status = options->Write(1U, &option, const_cast<VARIANT*>(&value));
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return false;
    }
    return true;
}

[[nodiscard]] WicJpegExportStatus encode_jpeg(
    IWICImagingFactory* const factory,
    IStream* const stream,
    const Srgb16Image& image,
    IWICColorContext* const color_context,
    const float quality,
    const std::uint32_t dpi,
    const std::uint8_t expected_subsampling,
    const ExportMetadataPolicy metadata_policy,
    const ExportMetadataFields& metadata,
    std::uint32_t& native_error_code) noexcept {
    ComPtr<IWICBitmapEncoder> encoder{};
    HRESULT status = factory->CreateEncoder(
        GUID_ContainerFormatJpeg,
        &GUID_VendorMicrosoft,
        &encoder);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::encoder_initialization_failed;
    }
    ComPtr<IWICBitmapEncoderInfo> encoder_info{};
    CLSID encoder_class{};
    status = encoder->GetEncoderInfo(&encoder_info);
    if (SUCCEEDED(status)) {
        status = encoder_info->GetCLSID(&encoder_class);
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::encoder_initialization_failed;
    }
    if (IsEqualGUID(encoder_class, CLSID_WICJpegEncoder) == FALSE) {
        return WicJpegExportStatus::unexpected_encoder;
    }

    status = encoder->Initialize(stream, WICBitmapEncoderNoCache);
    ComPtr<IWICBitmapFrameEncode> frame{};
    ComPtr<IPropertyBag2> options{};
    if (SUCCEEDED(status)) {
        status = encoder->CreateNewFrame(&frame, &options);
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::encoder_initialization_failed;
    }

    VARIANT quality_value{};
    quality_value.vt = VT_R4;
    quality_value.fltVal = quality;
    VARIANT subsampling_value{};
    subsampling_value.vt = VT_UI1;
    subsampling_value.bVal = expected_subsampling;
    if (!write_option(options.Get(), L"ImageQuality", quality_value, native_error_code) ||
        !write_option(
            options.Get(), L"JpegYCrCbSubsampling", subsampling_value, native_error_code)) {
        return WicJpegExportStatus::encoder_initialization_failed;
    }
    status = frame->Initialize(options.Get());
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::encoder_initialization_failed;
    }
    status = frame->SetSize(image.width, image.height);
    if (SUCCEEDED(status) && dpi != 0U) {
        status = frame->SetResolution(static_cast<double>(dpi), static_cast<double>(dpi));
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::resolution_configuration_failed;
    }
    WICPixelFormatGUID pixel_format = GUID_WICPixelFormat24bppBGR;
    status = frame->SetPixelFormat(&pixel_format);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::encoder_initialization_failed;
    }
    if (IsEqualGUID(pixel_format, GUID_WICPixelFormat24bppBGR) == FALSE) {
        return WicJpegExportStatus::pixel_format_coerced;
    }
    // **픽셀보다 먼저** 쓴다. WIC 의 JPEG 인코더는 WriteSource 뒤에 들어온 메타데이터를
    // 조용히 버린다 — TIFF 는 받아들여서 이 차이를 실파일로 확인하기 전에는 보이지 않았다.
    // 실패하면 게시를 접는다: 고른 정책이 무시된 파일을 내보내지 않는다.
    const ExportMetadataStatus metadata_status = write_export_metadata(
        frame.Get(),
        ExportMetadataContainer::jpeg,
        metadata_policy,
        metadata,
        native_error_code);
    if (metadata_status == ExportMetadataStatus::write_failed) {
        return WicJpegExportStatus::encode_failed;
    }

    IWICColorContext* contexts[]{color_context};
    status = frame->SetColorContexts(1U, contexts);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::encoder_initialization_failed;
    }

    const std::uint64_t bytes_64 =
        static_cast<std::uint64_t>(image.stride_bytes) * image.height;
    if (bytes_64 > std::numeric_limits<UINT>::max()) {
        return WicJpegExportStatus::encode_failed;
    }
    ComPtr<IWICBitmap> source{};
    status = factory->CreateBitmapFromMemory(
        image.width,
        image.height,
        GUID_WICPixelFormat48bppRGB,
        image.stride_bytes,
        static_cast<UINT>(bytes_64),
        reinterpret_cast<BYTE*>(const_cast<std::uint16_t*>(image.samples.data())),
        &source);
    ComPtr<IWICFormatConverter> dithered{};
    if (SUCCEEDED(status)) {
        status = factory->CreateFormatConverter(&dithered);
    }
    if (SUCCEEDED(status)) {
        status = dithered->Initialize(
            source.Get(),
            GUID_WICPixelFormat24bppBGR,
            WICBitmapDitherTypeErrorDiffusion,
            nullptr,
            0.0,
            WICBitmapPaletteTypeCustom);
    }
    if (SUCCEEDED(status)) {
        status = frame->WriteSource(dithered.Get(), nullptr);
    }
    if (SUCCEEDED(status)) {
        status = frame->Commit();
    }
    if (SUCCEEDED(status)) {
        status = encoder->Commit();
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::encode_failed;
    }
    return WicJpegExportStatus::ok;
}

}  // namespace negaflow::output::wic_jpeg_detail
