#include "negaflow/output/wic_jpeg_export.h"

#include "atomic_output_file.h"
#include "wic_jpeg_encode.h"
#include "wic_jpeg_verify.h"
#include "wic_srgb16_support.h"

#include <Windows.h>
#include <Shlwapi.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <new>
#include <vector>

namespace negaflow::output {
namespace {

using Microsoft::WRL::ComPtr;
using namespace negaflow::output::wic_jpeg_detail;

}  // namespace

WicJpegExportResult export_working_to_srgb8_jpeg(
    const negaflow::imaging::WorkingImage& working,
    const std::filesystem::path& destination,
    const float quality,
    const std::uint32_t dpi,
    const WicJpegExportLimits& limits) noexcept {
    WicJpegExportResult result{};
    result.info.quality = quality;
    result.info.dpi = dpi;
    if (!std::isfinite(quality) || quality < 0.0F || quality > 1.0F) {
        result.status = WicJpegExportStatus::invalid_quality;
        return result;
    }
    const std::uint8_t expected_subsampling_option = quality >= 0.95F
        ? static_cast<std::uint8_t>(WICJpegYCrCbSubsampling444)
        : static_cast<std::uint8_t>(WICJpegYCrCbSubsampling420);
    const std::uint8_t expected_sampling_factor = quality >= 0.95F ? 0x11U : 0x22U;
    result.info.chroma_subsampling = expected_sampling_factor;
    try {
        WorkingToSrgb16Result converted =
            convert_working_to_srgb16(working, limits.conversion);
        result.conversion_status = converted.status;
        result.info.width = working.width;
        result.info.height = working.height;
        result.info.encoded_pixel_bytes = converted.info.encoded_pixel_bytes;
        result.info.clipped_color_components = converted.info.clipped_color_components;
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
            result.status = WicJpegExportStatus::com_apartment_mismatch;
            result.native_error_code = static_cast<std::uint32_t>(apartment.status());
            return result;
        }
        if (FAILED(apartment.status())) {
            result.status = WicJpegExportStatus::wic_unavailable;
            result.native_error_code = static_cast<std::uint32_t>(apartment.status());
            return result;
        }
        ComPtr<IWICImagingFactory2> factory{};
        if (!detail::create_wic_factory(factory, result.native_error_code)) {
            result.status = WicJpegExportStatus::wic_unavailable;
            return result;
        }
        ComPtr<IWICColorContext> color_context{};
        std::vector<std::uint8_t> profile_bytes{};
        switch (detail::load_output_color_context(
            factory.Get(),
            negaflow::color::OutputColorSpace::srgb,
            limits.max_color_profile_bytes,
            color_context,
            profile_bytes,
            result.native_error_code,
            false,
            limits.conversion.output_icc_profile)) {
            case detail::StandardSrgbStatus::ok:
                break;
            case detail::StandardSrgbStatus::unavailable:
                result.status = WicJpegExportStatus::destination_profile_unavailable;
                return result;
            case detail::StandardSrgbStatus::invalid:
                result.status = WicJpegExportStatus::destination_profile_invalid;
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
        result.status = encode_jpeg(
            factory.Get(),
            output->stream(),
            converted.image,
            color_context.Get(),
            quality,
            dpi,
            expected_subsampling_option,
            limits.metadata_policy,
            limits.metadata,
            result.native_error_code);
        if (result.status != WicJpegExportStatus::ok) {
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
        JpegStructure structure{};
        const bool valid_structure = inspect_jpeg_structure(
            output->staging_path(), limits.max_artifact_bytes, structure);
        result.info.chroma_subsampling = structure.chroma_subsampling;
        if (!valid_structure ||
            structure.width != converted.image.width || structure.height != converted.image.height ||
            structure.components != 3U ||
            structure.chroma_subsampling != expected_sampling_factor) {
            result.status = WicJpegExportStatus::structure_verification_failed;
            discard_staging(output.get(), result);
            return result;
        }
        std::error_code size_error{};
        result.info.artifact_bytes = std::filesystem::file_size(output->staging_path(), size_error);
        if (size_error || result.info.artifact_bytes == 0U) {
            result.status = WicJpegExportStatus::structure_verification_failed;
            discard_staging(output.get(), result);
            return result;
        }
        result.info.structure_verified = true;
        result.status = verify_jpeg_readback(
            factory.Get(),
            output->staging_path(),
            converted.image,
            profile_bytes,
            dpi,
            result.info,
            result.native_error_code);
        if (result.status != WicJpegExportStatus::ok) {
            discard_staging(output.get(), result);
            return result;
        }
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
        result.status = WicJpegExportStatus::allocation_failed;
        return result;
    } catch (...) {
        result.status = WicJpegExportStatus::encode_failed;
        return result;
    }
}

const char* wic_jpeg_export_status_name(const WicJpegExportStatus status) noexcept {
    switch (status) {
        case WicJpegExportStatus::ok: return "ok";
        case WicJpegExportStatus::invalid_quality: return "invalid_quality";
        case WicJpegExportStatus::working_conversion_failed: return "working_conversion_failed";
        case WicJpegExportStatus::allocation_failed: return "allocation_failed";
        case WicJpegExportStatus::com_apartment_mismatch: return "com_apartment_mismatch";
        case WicJpegExportStatus::wic_unavailable: return "wic_unavailable";
        case WicJpegExportStatus::destination_profile_unavailable: return "destination_profile_unavailable";
        case WicJpegExportStatus::destination_profile_invalid: return "destination_profile_invalid";
        case WicJpegExportStatus::destination_exists: return "destination_exists";
        case WicJpegExportStatus::staging_create_failed: return "staging_create_failed";
        case WicJpegExportStatus::encoder_initialization_failed: return "encoder_initialization_failed";
        case WicJpegExportStatus::unexpected_encoder: return "unexpected_encoder";
        case WicJpegExportStatus::pixel_format_coerced: return "pixel_format_coerced";
        case WicJpegExportStatus::resolution_configuration_failed: return "resolution_configuration_failed";
        case WicJpegExportStatus::encode_failed: return "encode_failed";
        case WicJpegExportStatus::flush_failed: return "flush_failed";
        case WicJpegExportStatus::structure_verification_failed: return "structure_verification_failed";
        case WicJpegExportStatus::decoder_initialization_failed: return "decoder_initialization_failed";
        case WicJpegExportStatus::unexpected_decoder: return "unexpected_decoder";
        case WicJpegExportStatus::readback_failed: return "readback_failed";
        case WicJpegExportStatus::profile_verification_failed: return "profile_verification_failed";
        case WicJpegExportStatus::resolution_verification_failed: return "resolution_verification_failed";
        case WicJpegExportStatus::publish_failed: return "publish_failed";
        case WicJpegExportStatus::published_file_invalid: return "published_file_invalid";
    }
    return "unknown";
}

}  // namespace negaflow::output
