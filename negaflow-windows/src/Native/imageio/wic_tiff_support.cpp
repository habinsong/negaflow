#include "wic_tiff_support.h"

#include <Shlwapi.h>
#include <wrl/client.h>

#include <algorithm>

namespace negaflow::imageio::wic_tiff_detail {

using Microsoft::WRL::ComPtr;

[[nodiscard]] bool rewind_stream(IStream* const stream) noexcept {
    if (stream == nullptr) {
        return false;
    }
    LARGE_INTEGER beginning{};
    ULARGE_INTEGER actual_position{};
    return SUCCEEDED(stream->Seek(beginning, STREAM_SEEK_SET, &actual_position)) &&
           actual_position.QuadPart == 0U;
}

void discard_samples(WicTiffDecodeResult& result) noexcept {
    std::vector<std::uint16_t>{}.swap(result.image.samples);
}

[[nodiscard]] bool all_u16_values_equal(
    const std::array<std::uint16_t, 8>& values,
    const std::uint8_t count,
    const std::uint16_t expected) noexcept {
    for (std::uint8_t index = 0U; index < count; ++index) {
        if (values[index] != expected) {
            return false;
        }
    }
    return true;
}

[[nodiscard]] bool is_supported_layout(const negaflow::core::TiffProbeInfo& info) noexcept {
    // 8 and 16 bits per channel, and nothing in between. WIC widens 8-bit samples to the
    // 16-bit target by bit replication (v * 257), which is exactly v / 255 once the
    // working conversion divides by 65535 — so the shallower file loses no accuracy on
    // the way in, only the latitude it never had. Everything downstream stays 16-bit.
    const bool eight_bit =
        all_u16_values_equal(info.bits_per_sample, info.bits_per_sample_count, 8U);
    const bool sixteen_bit =
        all_u16_values_equal(info.bits_per_sample, info.bits_per_sample_count, 16U);
    const bool grayscale =
        (info.photometric_interpretation == 0U || info.photometric_interpretation == 1U) &&
        info.samples_per_pixel == 1U && info.extra_samples_count == 0U;
    const bool rgb = info.photometric_interpretation == 2U &&
        (info.samples_per_pixel == 3U || info.samples_per_pixel == 4U);
    if (info.width > std::numeric_limits<UINT>::max() ||
        info.height > std::numeric_limits<UINT>::max() ||
        (!grayscale && !rgb) || info.planar_configuration != 1U ||
        info.orientation != 1U ||
        (!eight_bit && !sixteen_bit) ||
        !all_u16_values_equal(info.sample_format, info.sample_format_count, 1U) ||
        (info.compression != 1U && info.compression != 5U && info.compression != 8U)) {
        return false;
    }
    if (grayscale) {
        return true;
    }
    if (info.samples_per_pixel == 3U) {
        return info.extra_samples_count == 0U;
    }
    return info.extra_samples_count == 1U &&
           (info.extra_samples[0] == 1U || info.extra_samples[0] == 2U);
}

[[nodiscard]] WicPixelFormat classify_pixel_format(const GUID& format) noexcept {
    if (IsEqualGUID(format, GUID_WICPixelFormat48bppRGB) != 0) {
        return WicPixelFormat::rgb16;
    }
    if (IsEqualGUID(format, GUID_WICPixelFormat64bppRGBA) != 0) {
        return WicPixelFormat::rgba16;
    }
    if (IsEqualGUID(format, GUID_WICPixelFormat64bppPRGBA) != 0) {
        return WicPixelFormat::prgba16;
    }
    if (IsEqualGUID(format, GUID_WICPixelFormat64bppBGRA) != 0) {
        return WicPixelFormat::bgra16;
    }
    if (IsEqualGUID(format, GUID_WICPixelFormat64bppPBGRA) != 0) {
        return WicPixelFormat::pbgra16;
    }
    if (IsEqualGUID(format, GUID_WICPixelFormat16bppGray) != 0) {
        return WicPixelFormat::gray16;
    }
    return WicPixelFormat::unknown;
}

[[nodiscard]] WicTiffDecodeStatus extract_icc_profile(
    IWICImagingFactory* const factory,
    IWICBitmapFrameDecode* const frame,
    const std::uint64_t expected_profile_bytes,
    const WicTiffDecodeLimits& limits,
    WicTiffDecodeResult& result) {
    UINT context_count = 0U;
    HRESULT status = frame->GetColorContexts(0U, nullptr, &context_count);
    if (status == WINCODEC_ERR_UNSUPPORTEDOPERATION && expected_profile_bytes == 0U) {
        return WicTiffDecodeStatus::ok;
    }
    if (FAILED(status) || context_count > limits.max_color_contexts) {
        return WicTiffDecodeStatus::color_context_failed;
    }
    if (context_count == 0U) {
        return expected_profile_bytes == 0U ? WicTiffDecodeStatus::ok
                                            : WicTiffDecodeStatus::color_context_failed;
    }

    std::vector<ComPtr<IWICColorContext>> contexts(context_count);
    std::vector<IWICColorContext*> raw_contexts(context_count, nullptr);
    for (UINT index = 0U; index < context_count; ++index) {
        status = factory->CreateColorContext(&contexts[index]);
        if (FAILED(status)) {
            return WicTiffDecodeStatus::color_context_failed;
        }
        raw_contexts[index] = contexts[index].Get();
    }
    UINT actual_context_count = 0U;
    status = frame->GetColorContexts(context_count, raw_contexts.data(), &actual_context_count);
    if (FAILED(status) || actual_context_count != context_count) {
        return WicTiffDecodeStatus::color_context_failed;
    }

    bool profile_found = false;
    for (const ComPtr<IWICColorContext>& context : contexts) {
        WICColorContextType type = WICColorContextUninitialized;
        status = context->GetType(&type);
        if (FAILED(status)) {
            return WicTiffDecodeStatus::color_context_failed;
        }
        if (type != WICColorContextProfile) {
            continue;
        }
        if (profile_found) {
            return WicTiffDecodeStatus::color_context_failed;
        }
        profile_found = true;

        UINT profile_bytes = 0U;
        status = context->GetProfileBytes(0U, nullptr, &profile_bytes);
        if (FAILED(status) || profile_bytes != expected_profile_bytes ||
            profile_bytes > limits.icc.max_profile_bytes) {
            return WicTiffDecodeStatus::color_context_failed;
        }
        result.image.icc_profile.resize(profile_bytes);
        UINT actual_profile_bytes = 0U;
        status = context->GetProfileBytes(
            profile_bytes,
            result.image.icc_profile.data(),
            &actual_profile_bytes);
        if (FAILED(status) || actual_profile_bytes != profile_bytes) {
            return WicTiffDecodeStatus::color_context_failed;
        }
    }

    if (!profile_found) {
        return expected_profile_bytes == 0U ? WicTiffDecodeStatus::ok
                                            : WicTiffDecodeStatus::color_context_failed;
    }
    const negaflow::color::IccProfileValidationResult validation =
        negaflow::color::validate_icc_profile(result.image.icc_profile, limits.icc);
    result.icc_status = validation.status;
    result.info.icc = validation.info;
    return validation.status == negaflow::color::IccProfileStatus::ok
               ? WicTiffDecodeStatus::ok
               : WicTiffDecodeStatus::invalid_icc_profile;
}

}  // namespace negaflow::imageio::wic_tiff_detail
