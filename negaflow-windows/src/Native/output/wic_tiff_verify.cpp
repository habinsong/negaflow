#include "wic_tiff_verify.h"

#include <Shlwapi.h>
#include <wrl/client.h>

#include <limits>
#include <new>

namespace negaflow::output::wic_tiff_detail {

using Microsoft::WRL::ComPtr;

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

[[nodiscard]] bool validate_tiff_structure(
    const negaflow::core::TiffProbeResult& probe,
    const Srgb16Image& expected,
    const std::uint16_t expected_compression,
    const std::uint32_t expected_profile_bytes) noexcept {
    if (probe.status != negaflow::core::TiffProbeStatus::ok ||
        probe.info.variant != negaflow::core::TiffVariant::classic ||
        probe.info.organization != negaflow::core::TiffOrganization::stripped ||
        probe.info.width != expected.width || probe.info.height != expected.height ||
        probe.info.samples_per_pixel != expected.channels ||
        probe.info.compression != expected_compression ||
        probe.info.photometric_interpretation != 2U ||
        probe.info.planar_configuration != 1U || probe.info.orientation != 1U ||
        probe.info.bits_per_sample_count != expected.channels ||
        probe.info.bits_per_sample[0] != expected.bits_per_sample ||
        probe.info.bits_per_sample[1] != expected.bits_per_sample ||
        probe.info.bits_per_sample[2] != expected.bits_per_sample ||
        (expected.channels == 4U &&
             (probe.info.bits_per_sample[3] != expected.bits_per_sample ||
              probe.info.extra_samples_count != 1U || probe.info.extra_samples[0] != 2U)) ||
        (expected.channels == 3U && probe.info.extra_samples_count != 0U) ||
        probe.info.icc_profile_bytes != expected_profile_bytes ||
        probe.info.packed_raster_bytes !=
            static_cast<std::uint64_t>(expected.stride_bytes) * expected.height) {
        return false;
    }
    if (probe.info.sample_format_count == 1U) {
        return probe.info.sample_format[0] == 1U;
    }
    return probe.info.sample_format_count == expected.channels &&
           probe.info.sample_format[0] == 1U &&
           probe.info.sample_format[1] == 1U &&
           probe.info.sample_format[2] == 1U &&
           (expected.channels == 3U || probe.info.sample_format[3] == 1U);
}

}  // namespace negaflow::output::wic_tiff_detail
