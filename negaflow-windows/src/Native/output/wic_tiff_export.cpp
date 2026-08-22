#include "negaflow/output/wic_tiff_export.h"

#include "atomic_output_file.h"
#include "tiff_ifd_allowlist.h"
#include "wic_srgb16_support.h"
#include "wic_tiff_encode.h"
#include "wic_tiff_verify.h"

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
using namespace negaflow::output::wic_tiff_detail;

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
            limits.metadata_policy,
            limits.metadata,
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
                limits.metadata_policy != ExportMetadataPolicy::minimal,
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
        result.info.pixels_verified = limits.verify_pixel_readback;
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
