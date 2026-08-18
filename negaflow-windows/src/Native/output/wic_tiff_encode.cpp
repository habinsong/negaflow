#include "wic_tiff_encode.h"

#include "tiff_ifd_allowlist.h"

#include <Shlwapi.h>
#include <wrl/client.h>

#include <limits>
#include <new>
#include <vector>

namespace negaflow::output::wic_tiff_detail {

using Microsoft::WRL::ComPtr;

[[nodiscard]] bool map_wic_tiff_compression(
    const WicTiffCompression compression,
    BYTE& wic_value,
    std::uint16_t& tiff_tag_value) noexcept {
    switch (compression) {
        case WicTiffCompression::none:
            wic_value = static_cast<BYTE>(WICTiffCompressionNone);
            tiff_tag_value = 1U;
            return true;
        case WicTiffCompression::lzw:
            wic_value = static_cast<BYTE>(WICTiffCompressionLZW);
            tiff_tag_value = 5U;
            return true;
        case WicTiffCompression::deflate:
            wic_value = static_cast<BYTE>(WICTiffCompressionZIP);
            tiff_tag_value = 8U;
            return true;
    }
    return false;
}

[[nodiscard]] WicTiffExportStatus encode_tiff(
    IWICImagingFactory* const factory,
    IStream* const stream,
    const negaflow::imaging::WorkingImage& working,
    const Srgb16Image& image,
    IWICColorContext* const color_context,
    const WorkingToSrgb16Limits& conversion_limits,
    const WicTiffCompression compression,
    const std::uint32_t output_dpi,
    const std::uint32_t write_buffer_bytes,
    const ExportMetadataPolicy metadata_policy,
    const ExportMetadataFields& metadata,
    WorkingToSrgb16Status& conversion_status,
    std::uint32_t& native_error_code) noexcept {
    ComPtr<IWICBitmapEncoder> encoder{};
    HRESULT status = factory->CreateEncoder(
        GUID_ContainerFormatTiff,
        &GUID_VendorMicrosoft,
        &encoder);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicTiffExportStatus::encoder_initialization_failed;
    }
    ComPtr<IWICBitmapEncoderInfo> encoder_info{};
    CLSID encoder_class{};
    status = encoder->GetEncoderInfo(&encoder_info);
    if (SUCCEEDED(status)) {
        status = encoder_info->GetCLSID(&encoder_class);
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicTiffExportStatus::encoder_initialization_failed;
    }
    if (IsEqualGUID(encoder_class, CLSID_WICTiffEncoder) == FALSE) {
        return WicTiffExportStatus::unexpected_encoder;
    }

    status = encoder->Initialize(stream, WICBitmapEncoderNoCache);
    ComPtr<IWICBitmapFrameEncode> frame{};
    ComPtr<IPropertyBag2> options{};
    if (SUCCEEDED(status)) {
        status = encoder->CreateNewFrame(&frame, &options);
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicTiffExportStatus::encoder_initialization_failed;
    }

    PROPBAG2 compression_option{};
    compression_option.dwType = PROPBAG2_TYPE_DATA;
    compression_option.vt = VT_UI1;
    compression_option.pstrName = const_cast<wchar_t*>(L"TiffCompressionMethod");
    VARIANT compression_value{};
    compression_value.vt = VT_UI1;
    std::uint16_t ignored_tiff_tag_value = 0U;
    if (!map_wic_tiff_compression(
            compression,
            compression_value.bVal,
            ignored_tiff_tag_value)) {
        return WicTiffExportStatus::compression_configuration_failed;
    }
    status = options->Write(1U, &compression_option, &compression_value);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicTiffExportStatus::compression_configuration_failed;
    }
    status = frame->Initialize(options.Get());
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicTiffExportStatus::encoder_initialization_failed;
    }

    const detail::WicSrgb16FrameStatus configure_status =
        detail::configure_srgb16_frame(
            frame.Get(),
            image,
            color_context,
            output_dpi,
            native_error_code);
    if (configure_status == detail::WicSrgb16FrameStatus::pixel_format_coerced) {
        return WicTiffExportStatus::pixel_format_coerced;
    }
    if (configure_status != detail::WicSrgb16FrameStatus::ok) {
        return WicTiffExportStatus::encoder_initialization_failed;
    }
    const detail::WicSrgb16FrameStatus write_status =
        detail::write_working_srgb16_pixels(
            frame.Get(),
            working,
            image,
            conversion_limits,
            write_buffer_bytes,
            conversion_status,
            native_error_code);
    if (write_status == detail::WicSrgb16FrameStatus::working_conversion_failed) {
        return WicTiffExportStatus::working_conversion_failed;
    }
    if (write_status == detail::WicSrgb16FrameStatus::allocation_failed) {
        return WicTiffExportStatus::allocation_failed;
    }
    if (write_status != detail::WicSrgb16FrameStatus::ok) {
        return WicTiffExportStatus::encode_failed;
    }
    // 메타데이터는 커밋 전에만 받는다. 실패하면 게시를 접는다 — 사용자가 고른 정책이
    // 조용히 무시된 파일을 내보내지 않는다. 컨테이너가 아예 지원하지 않는 경우는 다르다.
    const ExportMetadataStatus metadata_status = write_export_metadata(
        frame.Get(),
        ExportMetadataContainer::tiff,
        metadata_policy,
        metadata,
        native_error_code);
    if (metadata_status == ExportMetadataStatus::write_failed) {
        return WicTiffExportStatus::encode_failed;
    }
    status = frame->Commit();
    if (SUCCEEDED(status)) {
        status = encoder->Commit();
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicTiffExportStatus::encode_failed;
    }
    return WicTiffExportStatus::ok;
}

}  // namespace negaflow::output::wic_tiff_detail
