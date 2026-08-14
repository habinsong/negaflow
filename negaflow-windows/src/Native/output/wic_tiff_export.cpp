#include "negaflow/output/wic_tiff_export.h"

#include "atomic_output_file.h"
#include "tiff_ifd_allowlist.h"
#include "wic_srgb16_support.h"

#include "negaflow/core/tiff_probe.h"

#include <Windows.h>
#include <Shlwapi.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <cstdint>
#include <limits>
#include <new>
#include <vector>

namespace negaflow::output {
namespace {

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

[[nodiscard]] WicTiffExportStatus verify_tiff_readback(
    IWICImagingFactory* const factory,
    const std::filesystem::path& path,
    const negaflow::imaging::WorkingImage& working,
    const Srgb16Image& expected,
    const std::vector<std::uint8_t>& expected_profile,
    const WicTiffExportLimits& limits,
    WorkingToSrgb16Status& conversion_status,
    std::uint32_t& native_error_code) {
    ComPtr<IStream> stream{};
    HRESULT status = SHCreateStreamOnFileEx(
        path.c_str(),
        STGM_READ | STGM_SHARE_DENY_WRITE,
        FILE_ATTRIBUTE_NORMAL,
        FALSE,
        nullptr,
        &stream);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicTiffExportStatus::decoder_initialization_failed;
    }
    ComPtr<IWICBitmapDecoder> decoder{};
    status = factory->CreateDecoderFromStream(
        stream.Get(),
        &GUID_VendorMicrosoft,
        WICDecodeMetadataCacheOnLoad,
        &decoder);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicTiffExportStatus::decoder_initialization_failed;
    }
    ComPtr<IWICBitmapDecoderInfo> decoder_info{};
    CLSID decoder_class{};
    status = decoder->GetDecoderInfo(&decoder_info);
    if (SUCCEEDED(status)) {
        status = decoder_info->GetCLSID(&decoder_class);
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicTiffExportStatus::decoder_initialization_failed;
    }
    if (IsEqualGUID(decoder_class, CLSID_WICTiffDecoder) == FALSE) {
        return WicTiffExportStatus::unexpected_decoder;
    }

    UINT frame_count = 0U;
    status = decoder->GetFrameCount(&frame_count);
    if (FAILED(status) || frame_count != 1U) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicTiffExportStatus::readback_failed;
    }
    ComPtr<IWICBitmapFrameDecode> frame{};
    status = decoder->GetFrame(0U, &frame);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicTiffExportStatus::readback_failed;
    }
    WorkingToSrgb16Limits color_limits = limits.conversion;
    color_limits.color_space = limits.color_space;
    switch (detail::verify_working_srgb16_frame(
        factory,
        frame.Get(),
        working,
        expected,
        color_limits,
        expected_profile,
        limits.output_dpi,
        limits.readback_buffer_bytes,
        conversion_status,
        native_error_code)) {
        case detail::WicSrgb16FrameStatus::ok:
            return WicTiffExportStatus::ok;
        case detail::WicSrgb16FrameStatus::pixel_verification_failed:
            return WicTiffExportStatus::pixel_verification_failed;
        case detail::WicSrgb16FrameStatus::profile_verification_failed:
            return WicTiffExportStatus::profile_verification_failed;
        case detail::WicSrgb16FrameStatus::working_conversion_failed:
            return WicTiffExportStatus::working_conversion_failed;
        case detail::WicSrgb16FrameStatus::allocation_failed:
            return WicTiffExportStatus::allocation_failed;
        case detail::WicSrgb16FrameStatus::configuration_failed:
        case detail::WicSrgb16FrameStatus::pixel_format_coerced:
        case detail::WicSrgb16FrameStatus::write_failed:
        case detail::WicSrgb16FrameStatus::readback_failed:
            return WicTiffExportStatus::readback_failed;
    }
    return WicTiffExportStatus::readback_failed;
}

[[nodiscard]] WicTiffExportStatus map_atomic_status(
    const detail::AtomicOutputStatus status) noexcept {
    switch (status) {
        case detail::AtomicOutputStatus::ok:
            return WicTiffExportStatus::ok;
        case detail::AtomicOutputStatus::destination_exists:
            return WicTiffExportStatus::destination_exists;
        case detail::AtomicOutputStatus::flush_failed:
            return WicTiffExportStatus::flush_failed;
        case detail::AtomicOutputStatus::published_file_invalid:
            return WicTiffExportStatus::published_file_invalid;
        case detail::AtomicOutputStatus::publish_failed:
            return WicTiffExportStatus::publish_failed;
        case detail::AtomicOutputStatus::allocation_failed:
            return WicTiffExportStatus::allocation_failed;
        case detail::AtomicOutputStatus::invalid_path:
        case detail::AtomicOutputStatus::destination_query_failed:
        case detail::AtomicOutputStatus::parent_unavailable:
        case detail::AtomicOutputStatus::staging_create_failed:
            return WicTiffExportStatus::staging_create_failed;
    }
    return WicTiffExportStatus::staging_create_failed;
}

void discard_staging(
    detail::AtomicOutputFile* const output,
    WicTiffExportResult& result) noexcept {
    if (output != nullptr) {
        output->discard(result.cleanup_error_code);
    }
}

[[nodiscard]] bool validate_tiff_structure(
    const negaflow::core::TiffProbeResult& probe,
    const Srgb16Image& expected,
    const std::uint16_t expected_compression,
    const std::uint32_t expected_profile_bytes) noexcept {
    if (probe.status != negaflow::core::TiffProbeStatus::ok ||
        probe.info.variant != negaflow::core::TiffVariant::classic ||
        probe.info.organization != negaflow::core::TiffOrganization::stripped ||
        probe.info.width != expected.width || probe.info.height != expected.height ||
        probe.info.samples_per_pixel != 3U || probe.info.compression != expected_compression ||
        probe.info.photometric_interpretation != 2U ||
        probe.info.planar_configuration != 1U || probe.info.orientation != 1U ||
        probe.info.bits_per_sample_count != 3U ||
        probe.info.bits_per_sample[0] != expected.bits_per_sample ||
        probe.info.bits_per_sample[1] != expected.bits_per_sample ||
        probe.info.bits_per_sample[2] != expected.bits_per_sample ||
        probe.info.extra_samples_count != 0U ||
        probe.info.icc_profile_bytes != expected_profile_bytes ||
        probe.info.packed_raster_bytes !=
            static_cast<std::uint64_t>(expected.stride_bytes) * expected.height) {
        return false;
    }
    if (probe.info.sample_format_count == 1U) {
        return probe.info.sample_format[0] == 1U;
    }
    return probe.info.sample_format_count == 3U &&
           probe.info.sample_format[0] == 1U &&
           probe.info.sample_format[1] == 1U &&
           probe.info.sample_format[2] == 1U;
}

}  // namespace

WicTiffExportResult export_working_to_srgb16_tiff(
    const negaflow::imaging::WorkingImage& working,
    const std::filesystem::path& destination,
    const WicTiffExportLimits& limits) noexcept {
    WicTiffExportResult result{};
    // 색공간은 변환과 프로파일 양쪽이 함께 알아야 합니다. 한쪽만 바뀌면 픽셀과 프로파일이
    // 서로 다른 공간을 가리키게 됩니다.
    WorkingToSrgb16Limits color_limits = limits.conversion;
    color_limits.color_space = limits.color_space;
    try {
        BYTE ignored_wic_value = 0U;
        std::uint16_t expected_compression = 0U;
        if (!map_wic_tiff_compression(
                limits.compression,
                ignored_wic_value,
                expected_compression)) {
            result.status = WicTiffExportStatus::compression_configuration_failed;
            return result;
        }
        WorkingToSrgb16Result converted =
            inspect_working_to_srgb(
                working,
                limits.bits_per_sample,
                color_limits);
        result.conversion_status = converted.status;
        result.info.width = working.width;
        result.info.height = working.height;
        result.info.encoded_pixel_bytes = converted.info.encoded_pixel_bytes;
        result.info.clipped_color_components = converted.info.clipped_color_components;
        result.info.output_dpi = limits.output_dpi;
        if (converted.status != WorkingToSrgb16Status::ok) {
            return result;
        }
        if (working.width > static_cast<std::uint32_t>(std::numeric_limits<INT>::max()) ||
            working.height > static_cast<std::uint32_t>(std::numeric_limits<INT>::max())) {
            result.conversion_status = WorkingToSrgb16Status::size_overflow;
            return result;
        }

        const detail::ComApartment apartment{};
        if (apartment.status() == RPC_E_CHANGED_MODE) {
            result.status = WicTiffExportStatus::com_apartment_mismatch;
            result.native_error_code = static_cast<std::uint32_t>(apartment.status());
            return result;
        }
        if (FAILED(apartment.status())) {
            result.status = WicTiffExportStatus::wic_unavailable;
            result.native_error_code = static_cast<std::uint32_t>(apartment.status());
            return result;
        }
        ComPtr<IWICImagingFactory2> factory{};
        if (!detail::create_wic_factory(factory, result.native_error_code)) {
            result.status = WicTiffExportStatus::wic_unavailable;
            return result;
        }

        ComPtr<IWICColorContext> color_context{};
        std::vector<std::uint8_t> profile_bytes{};
        switch (detail::load_output_color_context(
            factory.Get(),
            limits.color_space,
            limits.max_color_profile_bytes,
            color_context,
            profile_bytes,
            result.native_error_code)) {
            case detail::StandardSrgbStatus::ok:
                break;
            case detail::StandardSrgbStatus::unavailable:
                result.status = WicTiffExportStatus::destination_profile_unavailable;
                return result;
            case detail::StandardSrgbStatus::invalid:
                result.status = WicTiffExportStatus::destination_profile_invalid;
                return result;
        }
        result.info.color_profile_bytes = static_cast<std::uint32_t>(profile_bytes.size());

        std::unique_ptr<detail::AtomicOutputFile> output{};
        const detail::AtomicOutputStatus create_status = detail::AtomicOutputFile::create(
            destination,
            output,
            result.native_error_code);
        if (create_status != detail::AtomicOutputStatus::ok) {
            result.status = map_atomic_status(create_status);
            return result;
        }

        result.status = encode_tiff(
            factory.Get(),
            output->stream(),
            working,
            converted.image,
            color_context.Get(),
            color_limits,
            limits.compression,
            limits.output_dpi,
            limits.write_buffer_bytes,
            result.conversion_status,
            result.native_error_code);
        if (result.status != WicTiffExportStatus::ok) {
            discard_staging(output.get(), result);
            return result;
        }
        const detail::AtomicOutputStatus flush_status =
            output->close_and_flush(result.native_error_code);
        if (flush_status != detail::AtomicOutputStatus::ok) {
            result.status = map_atomic_status(flush_status);
            discard_staging(output.get(), result);
            return result;
        }

        negaflow::core::TiffProbeLimits probe_limits{};
        probe_limits.max_file_bytes = limits.max_artifact_bytes;
        probe_limits.max_ifd_entries = limits.max_ifd_entries;
        probe_limits.max_icc_profile_bytes = limits.max_color_profile_bytes;
        const negaflow::core::TiffProbeResult probe =
            negaflow::core::probe_tiff_file(output->staging_path(), probe_limits);
        result.info.artifact_bytes = probe.info.file_bytes;
        result.info.strip_count = probe.info.segment_count;
        result.info.compression = probe.info.compression;
        if (!validate_tiff_structure(
                probe,
                converted.image,
                expected_compression,
                result.info.color_profile_bytes)) {
            result.status = WicTiffExportStatus::structure_verification_failed;
            discard_staging(output.get(), result);
            return result;
        }
        result.info.structure_verified = true;

        detail::TiffIfdAllowlistInfo metadata_info{};
        const detail::TiffIfdAllowlistStatus metadata_status =
            detail::inspect_minimal_rgb_tiff_ifd(
                output->staging_path(),
                limits.max_artifact_bytes,
                limits.max_ifd_entries,
                metadata_info,
                result.native_error_code);
        result.info.ifd_entry_count = metadata_info.tag_count;
        result.info.unexpected_metadata_tag = metadata_info.unexpected_tag;
        if (metadata_status != detail::TiffIfdAllowlistStatus::ok) {
            result.status = WicTiffExportStatus::metadata_verification_failed;
            discard_staging(output.get(), result);
            return result;
        }
        result.info.metadata_verified = true;

        result.status = verify_tiff_readback(
            factory.Get(),
            output->staging_path(),
            working,
            converted.image,
            profile_bytes,
            limits,
            result.conversion_status,
            result.native_error_code);
        if (result.status != WicTiffExportStatus::ok) {
            discard_staging(output.get(), result);
            return result;
        }
        result.info.pixels_verified = true;
        result.info.profile_verified = true;
        result.info.resolution_verified = limits.output_dpi != 0U;

        const detail::AtomicOutputStatus publish_status = output->publish(
            result.info.artifact_bytes,
            result.native_error_code);
        result.info.published = publish_status == detail::AtomicOutputStatus::ok ||
                                publish_status ==
                                    detail::AtomicOutputStatus::published_file_invalid;
        result.status = map_atomic_status(publish_status);
        if (!result.info.published) {
            discard_staging(output.get(), result);
        }
        return result;
    } catch (const std::bad_alloc&) {
        result.status = WicTiffExportStatus::allocation_failed;
        return result;
    } catch (...) {
        result.status = WicTiffExportStatus::encode_failed;
        return result;
    }
}

const char* wic_tiff_export_status_name(const WicTiffExportStatus status) noexcept {
    switch (status) {
        case WicTiffExportStatus::ok:
            return "ok";
        case WicTiffExportStatus::working_conversion_failed:
            return "working_conversion_failed";
        case WicTiffExportStatus::allocation_failed:
            return "allocation_failed";
        case WicTiffExportStatus::com_apartment_mismatch:
            return "com_apartment_mismatch";
        case WicTiffExportStatus::wic_unavailable:
            return "wic_unavailable";
        case WicTiffExportStatus::destination_profile_unavailable:
            return "destination_profile_unavailable";
        case WicTiffExportStatus::destination_profile_invalid:
            return "destination_profile_invalid";
        case WicTiffExportStatus::destination_exists:
            return "destination_exists";
        case WicTiffExportStatus::staging_create_failed:
            return "staging_create_failed";
        case WicTiffExportStatus::encoder_initialization_failed:
            return "encoder_initialization_failed";
        case WicTiffExportStatus::unexpected_encoder:
            return "unexpected_encoder";
        case WicTiffExportStatus::compression_configuration_failed:
            return "compression_configuration_failed";
        case WicTiffExportStatus::pixel_format_coerced:
            return "pixel_format_coerced";
        case WicTiffExportStatus::encode_failed:
            return "encode_failed";
        case WicTiffExportStatus::flush_failed:
            return "flush_failed";
        case WicTiffExportStatus::structure_verification_failed:
            return "structure_verification_failed";
        case WicTiffExportStatus::metadata_verification_failed:
            return "metadata_verification_failed";
        case WicTiffExportStatus::decoder_initialization_failed:
            return "decoder_initialization_failed";
        case WicTiffExportStatus::unexpected_decoder:
            return "unexpected_decoder";
        case WicTiffExportStatus::readback_failed:
            return "readback_failed";
        case WicTiffExportStatus::pixel_verification_failed:
            return "pixel_verification_failed";
        case WicTiffExportStatus::profile_verification_failed:
            return "profile_verification_failed";
        case WicTiffExportStatus::publish_failed:
            return "publish_failed";
        case WicTiffExportStatus::published_file_invalid:
            return "published_file_invalid";
    }
    return "unknown";
}

}  // namespace negaflow::output
