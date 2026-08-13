#include "negaflow/output/wic_png_export.h"

#include "atomic_output_file.h"
#include "png_structure_reader.h"
#include "wic_srgb16_support.h"

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

[[nodiscard]] WicPngExportStatus encode_png(
    IWICImagingFactory* const factory,
    IStream* const stream,
    const negaflow::imaging::WorkingImage& working,
    const Srgb16Image& image,
    IWICColorContext* const color_context,
    const WorkingToSrgb16Limits& conversion_limits,
    const std::uint32_t output_dpi,
    const std::uint32_t write_buffer_bytes,
    WorkingToSrgb16Status& conversion_status,
    std::uint32_t& native_error_code) noexcept {
    ComPtr<IWICBitmapEncoder> encoder{};
    HRESULT status = factory->CreateEncoder(
        GUID_ContainerFormatPng,
        &GUID_VendorMicrosoft,
        &encoder);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::encoder_initialization_failed;
    }
    ComPtr<IWICBitmapEncoderInfo> encoder_info{};
    CLSID encoder_class{};
    status = encoder->GetEncoderInfo(&encoder_info);
    if (SUCCEEDED(status)) {
        status = encoder_info->GetCLSID(&encoder_class);
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::encoder_initialization_failed;
    }
    if (IsEqualGUID(encoder_class, CLSID_WICPngEncoder) == FALSE) {
        return WicPngExportStatus::unexpected_encoder;
    }

    status = encoder->Initialize(stream, WICBitmapEncoderNoCache);
    ComPtr<IWICBitmapFrameEncode> frame{};
    ComPtr<IPropertyBag2> options{};
    if (SUCCEEDED(status)) {
        status = encoder->CreateNewFrame(&frame, &options);
    }
    if (SUCCEEDED(status)) {
        status = frame->Initialize(options.Get());
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::encoder_initialization_failed;
    }

    const detail::WicSrgb16FrameStatus configure_status =
        detail::configure_srgb16_frame(
            frame.Get(),
            image,
            color_context,
            output_dpi,
            native_error_code);
    if (configure_status == detail::WicSrgb16FrameStatus::pixel_format_coerced) {
        return WicPngExportStatus::pixel_format_coerced;
    }
    if (configure_status != detail::WicSrgb16FrameStatus::ok) {
        return WicPngExportStatus::encoder_initialization_failed;
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
        return WicPngExportStatus::working_conversion_failed;
    }
    if (write_status == detail::WicSrgb16FrameStatus::allocation_failed) {
        return WicPngExportStatus::allocation_failed;
    }
    if (write_status != detail::WicSrgb16FrameStatus::ok) {
        return WicPngExportStatus::encode_failed;
    }
    status = frame->Commit();
    if (SUCCEEDED(status)) {
        status = encoder->Commit();
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::encode_failed;
    }
    return WicPngExportStatus::ok;
}

[[nodiscard]] WicPngExportStatus verify_png_readback(
    IWICImagingFactory* const factory,
    const std::filesystem::path& path,
    const negaflow::imaging::WorkingImage& working,
    const Srgb16Image& expected,
    const std::vector<std::uint8_t>& expected_profile,
    const WicPngExportLimits& limits,
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
        return WicPngExportStatus::decoder_initialization_failed;
    }
    ComPtr<IWICBitmapDecoder> decoder{};
    status = factory->CreateDecoderFromStream(
        stream.Get(),
        &GUID_VendorMicrosoft,
        WICDecodeMetadataCacheOnLoad,
        &decoder);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::decoder_initialization_failed;
    }
    ComPtr<IWICBitmapDecoderInfo> decoder_info{};
    CLSID decoder_class{};
    status = decoder->GetDecoderInfo(&decoder_info);
    if (SUCCEEDED(status)) {
        status = decoder_info->GetCLSID(&decoder_class);
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::decoder_initialization_failed;
    }
    if (IsEqualGUID(decoder_class, CLSID_WICPngDecoder) == FALSE) {
        return WicPngExportStatus::unexpected_decoder;
    }

    UINT frame_count = 0U;
    status = decoder->GetFrameCount(&frame_count);
    if (FAILED(status) || frame_count != 1U) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::readback_failed;
    }
    ComPtr<IWICBitmapFrameDecode> frame{};
    status = decoder->GetFrame(0U, &frame);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::readback_failed;
    }
    switch (detail::verify_working_srgb16_frame(
        factory,
        frame.Get(),
        working,
        expected,
        limits.conversion,
        expected_profile,
        limits.output_dpi,
        limits.readback_buffer_bytes,
        conversion_status,
        native_error_code)) {
        case detail::WicSrgb16FrameStatus::ok:
            return WicPngExportStatus::ok;
        case detail::WicSrgb16FrameStatus::pixel_verification_failed:
            return WicPngExportStatus::pixel_verification_failed;
        case detail::WicSrgb16FrameStatus::profile_verification_failed:
            return WicPngExportStatus::profile_verification_failed;
        case detail::WicSrgb16FrameStatus::working_conversion_failed:
            return WicPngExportStatus::working_conversion_failed;
        case detail::WicSrgb16FrameStatus::allocation_failed:
            return WicPngExportStatus::allocation_failed;
        case detail::WicSrgb16FrameStatus::configuration_failed:
        case detail::WicSrgb16FrameStatus::pixel_format_coerced:
        case detail::WicSrgb16FrameStatus::write_failed:
        case detail::WicSrgb16FrameStatus::readback_failed:
            return WicPngExportStatus::readback_failed;
    }
    return WicPngExportStatus::readback_failed;
}

[[nodiscard]] WicPngExportStatus map_atomic_status(
    const detail::AtomicOutputStatus status) noexcept {
    switch (status) {
        case detail::AtomicOutputStatus::ok:
            return WicPngExportStatus::ok;
        case detail::AtomicOutputStatus::destination_exists:
            return WicPngExportStatus::destination_exists;
        case detail::AtomicOutputStatus::flush_failed:
            return WicPngExportStatus::flush_failed;
        case detail::AtomicOutputStatus::published_file_invalid:
            return WicPngExportStatus::published_file_invalid;
        case detail::AtomicOutputStatus::publish_failed:
            return WicPngExportStatus::publish_failed;
        case detail::AtomicOutputStatus::allocation_failed:
            return WicPngExportStatus::allocation_failed;
        case detail::AtomicOutputStatus::invalid_path:
        case detail::AtomicOutputStatus::destination_query_failed:
        case detail::AtomicOutputStatus::parent_unavailable:
        case detail::AtomicOutputStatus::staging_create_failed:
            return WicPngExportStatus::staging_create_failed;
    }
    return WicPngExportStatus::staging_create_failed;
}

void discard_staging(
    detail::AtomicOutputFile* const output,
    WicPngExportResult& result) noexcept {
    if (output != nullptr) {
        output->discard(result.cleanup_error_code);
    }
}

}  // namespace

WicPngExportResult export_working_to_srgb16_png(
    const negaflow::imaging::WorkingImage& working,
    const std::filesystem::path& destination,
    const WicPngExportLimits& limits) noexcept {
    WicPngExportResult result{};
    try {
        WorkingToSrgb16Result converted =
            inspect_working_to_srgb16(working, limits.conversion);
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
            result.status = WicPngExportStatus::com_apartment_mismatch;
            result.native_error_code = static_cast<std::uint32_t>(apartment.status());
            return result;
        }
        if (FAILED(apartment.status())) {
            result.status = WicPngExportStatus::wic_unavailable;
            result.native_error_code = static_cast<std::uint32_t>(apartment.status());
            return result;
        }
        ComPtr<IWICImagingFactory2> factory{};
        if (!detail::create_wic_factory(factory, result.native_error_code)) {
            result.status = WicPngExportStatus::wic_unavailable;
            return result;
        }

        ComPtr<IWICColorContext> color_context{};
        std::vector<std::uint8_t> profile_bytes{};
        switch (detail::load_standard_srgb_context(
            factory.Get(),
            limits.max_color_profile_bytes,
            color_context,
            profile_bytes,
            result.native_error_code)) {
            case detail::StandardSrgbStatus::ok:
                break;
            case detail::StandardSrgbStatus::unavailable:
                result.status = WicPngExportStatus::destination_profile_unavailable;
                return result;
            case detail::StandardSrgbStatus::invalid:
                result.status = WicPngExportStatus::destination_profile_invalid;
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

        result.status = encode_png(
            factory.Get(),
            output->stream(),
            working,
            converted.image,
            color_context.Get(),
            limits.conversion,
            limits.output_dpi,
            limits.write_buffer_bytes,
            result.conversion_status,
            result.native_error_code);
        if (result.status != WicPngExportStatus::ok) {
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

        detail::PngStructureInfo structure{};
        const detail::PngStructureStatus structure_status = detail::inspect_png_structure(
            output->staging_path(),
            limits.max_artifact_bytes,
            structure,
            result.native_error_code);
        result.info.artifact_bytes = structure.file_bytes;
        result.info.image_data_chunks = structure.image_data_chunks;
        if (structure_status != detail::PngStructureStatus::ok ||
            structure.width != converted.image.width ||
            structure.height != converted.image.height || structure.bit_depth != 16U ||
            structure.color_type != 2U) {
            result.status = WicPngExportStatus::structure_verification_failed;
            discard_staging(output.get(), result);
            return result;
        }
        result.info.structure_verified = true;

        result.status = verify_png_readback(
            factory.Get(),
            output->staging_path(),
            working,
            converted.image,
            profile_bytes,
            limits,
            result.conversion_status,
            result.native_error_code);
        if (result.status != WicPngExportStatus::ok) {
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
        result.status = WicPngExportStatus::allocation_failed;
        return result;
    } catch (...) {
        result.status = WicPngExportStatus::encode_failed;
        return result;
    }
}

const char* wic_png_export_status_name(const WicPngExportStatus status) noexcept {
    switch (status) {
        case WicPngExportStatus::ok:
            return "ok";
        case WicPngExportStatus::working_conversion_failed:
            return "working_conversion_failed";
        case WicPngExportStatus::allocation_failed:
            return "allocation_failed";
        case WicPngExportStatus::com_apartment_mismatch:
            return "com_apartment_mismatch";
        case WicPngExportStatus::wic_unavailable:
            return "wic_unavailable";
        case WicPngExportStatus::destination_profile_unavailable:
            return "destination_profile_unavailable";
        case WicPngExportStatus::destination_profile_invalid:
            return "destination_profile_invalid";
        case WicPngExportStatus::destination_exists:
            return "destination_exists";
        case WicPngExportStatus::staging_create_failed:
            return "staging_create_failed";
        case WicPngExportStatus::encoder_initialization_failed:
            return "encoder_initialization_failed";
        case WicPngExportStatus::unexpected_encoder:
            return "unexpected_encoder";
        case WicPngExportStatus::pixel_format_coerced:
            return "pixel_format_coerced";
        case WicPngExportStatus::encode_failed:
            return "encode_failed";
        case WicPngExportStatus::flush_failed:
            return "flush_failed";
        case WicPngExportStatus::structure_verification_failed:
            return "structure_verification_failed";
        case WicPngExportStatus::decoder_initialization_failed:
            return "decoder_initialization_failed";
        case WicPngExportStatus::unexpected_decoder:
            return "unexpected_decoder";
        case WicPngExportStatus::readback_failed:
            return "readback_failed";
        case WicPngExportStatus::pixel_verification_failed:
            return "pixel_verification_failed";
        case WicPngExportStatus::profile_verification_failed:
            return "profile_verification_failed";
        case WicPngExportStatus::publish_failed:
            return "publish_failed";
        case WicPngExportStatus::published_file_invalid:
            return "published_file_invalid";
    }
    return "unknown";
}

}  // namespace negaflow::output
