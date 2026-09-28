#include "negaflow/imaging/scanner_to_working.h"

#include "negaflow/color/srgb_transfer.h"
#include "negaflow/core/parallel_rows.h"
#include "scanner_to_working_detail.h"
#include "input_gamma_preparation.h"

#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>

namespace negaflow::imaging {
namespace {

constexpr std::uint32_t rgb_color_space_signature = 0x52474220U;
constexpr std::uint32_t scanner_profile_signature = 0x73636e72U;
constexpr std::uint32_t display_profile_signature = 0x6d6e7472U;
constexpr std::uint32_t color_space_profile_signature = 0x73706163U;

[[nodiscard]] bool is_supported_source_profile_class(
    const std::uint32_t signature) noexcept {
    return signature == scanner_profile_signature || signature == display_profile_signature ||
           signature == color_space_profile_signature;
}

[[nodiscard]] ScannerToWorkingStatus validate_decoded_image(
    const negaflow::imageio::DecodedImage& decoded,
    const ScannerToWorkingLimits& limits) noexcept {
    if (decoded.width == 0U || decoded.height == 0U) {
        return ScannerToWorkingStatus::invalid_dimensions;
    }

    // rgb16·rgba16 과 함께 스캐너 Gray 의 1채널 `gray16` 도 받습니다. macOS 는
    // `CIImage(cgImage:)` 가 회색 CGImage 를 그대로 받으므로, 여기서 거부하면 Windows 만
    // Gray 스캔을 통째로 못 읽습니다. `channel_count` 는 아는 layout 만 양수를 돌려주므로
    // 알 수 없는 값은 그대로 걸립니다.
    const std::uint64_t channels = negaflow::imageio::channel_count(decoded.layout);
    if (channels == 0U) {
        return ScannerToWorkingStatus::invalid_argument;
    }
    const std::uint64_t minimum_stride =
        static_cast<std::uint64_t>(decoded.width) * channels * sizeof(std::uint16_t);
    if (decoded.stride_bytes < minimum_stride ||
        decoded.stride_bytes % sizeof(std::uint16_t) != 0U) {
        return ScannerToWorkingStatus::invalid_stride;
    }
    const std::uint64_t required_source_bytes =
        static_cast<std::uint64_t>(decoded.stride_bytes) * decoded.height;
    if (required_source_bytes / decoded.height != decoded.stride_bytes ||
        required_source_bytes % sizeof(std::uint16_t) != 0U ||
        required_source_bytes / sizeof(std::uint16_t) != decoded.samples.size()) {
        return ScannerToWorkingStatus::buffer_size_mismatch;
    }

    const std::uint64_t pixel_count =
        static_cast<std::uint64_t>(decoded.width) * decoded.height;
    if (pixel_count > std::numeric_limits<std::uint64_t>::max() /
                          sizeof(negaflow::core::Rgba32F) ||
        pixel_count > std::numeric_limits<std::size_t>::max() /
                          sizeof(negaflow::core::Rgba32F)) {
        return ScannerToWorkingStatus::size_overflow;
    }
    const std::uint64_t working_bytes =
        pixel_count * sizeof(negaflow::core::Rgba32F);
    if (working_bytes > limits.max_working_pixel_bytes) {
        return ScannerToWorkingStatus::memory_limit_exceeded;
    }

    if (decoded.layout != negaflow::imageio::DecodedPixelLayout::rgba16) {
        return decoded.alpha_mode == negaflow::imageio::AlphaMode::opaque
                   ? ScannerToWorkingStatus::ok
                   : ScannerToWorkingStatus::unsupported_alpha;
    }
    if (decoded.alpha_mode != negaflow::imageio::AlphaMode::associated &&
        decoded.alpha_mode != negaflow::imageio::AlphaMode::unassociated) {
        return ScannerToWorkingStatus::unsupported_alpha;
    }

    return ScannerToWorkingStatus::ok;
}

[[nodiscard]] float decoded_alpha(
    const negaflow::imageio::DecodedImage& decoded,
    const std::uint16_t* const source,
    const std::size_t offset) noexcept {
    constexpr float u16_scale = 1.0F / 65'535.0F;
    return decoded.layout == negaflow::imageio::DecodedPixelLayout::rgba16
        ? static_cast<float>(source[offset + 3U]) * u16_scale
        : 1.0F;
}

[[nodiscard]] std::uint16_t unassociate_component(
    const std::uint16_t component,
    const std::uint16_t alpha) noexcept {
    if (alpha == 0U) {
        return 0U;
    }
    const std::uint64_t restored =
        (static_cast<std::uint64_t>(component) * 65'535U + alpha / 2U) / alpha;
    return static_cast<std::uint16_t>(std::min<std::uint64_t>(restored, 65'535U));
}

[[nodiscard]] ScannerToWorkingStatus decode_srgb16_to_working(
    const std::vector<std::uint16_t>& encoded,
    const std::uint32_t width,
    const std::uint32_t height,
    WorkingImage& output) {
    const std::uint64_t expected_samples =
        static_cast<std::uint64_t>(width) * height * 3ULL;
    if (expected_samples != encoded.size()) {
        return ScannerToWorkingStatus::buffer_size_mismatch;
    }
    output.width = width;
    output.height = height;
    output.stride_pixels = width;
    output.pixels.resize(
        static_cast<std::size_t>(width) * static_cast<std::size_t>(height));
    const auto linear = negaflow::color::srgb16_to_linear_table();
    negaflow::core::for_each_row_block(
        height,
        static_cast<std::uint64_t>(width) * height,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            const std::size_t first = static_cast<std::size_t>(first_row) * width;
            const std::size_t last = static_cast<std::size_t>(first_row + row_count) * width;
            for (std::size_t index = first; index < last; ++index) {
                const std::size_t source = index * 3U;
                output.pixels[index] = {
                    linear[encoded[source]], linear[encoded[source + 1U]],
                    linear[encoded[source + 2U]], 1.0F};
            }
        });
    return ScannerToWorkingStatus::ok;
}

// 16-bit 표본은 65536 가지뿐이라 표를 한 번 만들어 씁니다. 표는 이 함수가 화소마다 하던
// `srgb_encoded_to_linear(x / 65535)` 와 같은 식으로 채워져 값이 같습니다. RAW 한 장을
// 한 스레드에서 화소마다 pow 로 풀던 것이 305 ms 였습니다.
[[nodiscard]] ScannerToWorkingStatus decode_untagged_srgb_to_working(
    const negaflow::imageio::DecodedImage& decoded,
    WorkingImage& output) {
    const std::size_t channels = negaflow::imageio::channel_count(decoded.layout);
    const negaflow::imageio::RgbSampleOffsets rgb =
        negaflow::imageio::rgb_sample_offsets(decoded.layout);
    const std::size_t source_stride = decoded.stride_bytes / sizeof(std::uint16_t);
    const bool associated = decoded.alpha_mode == negaflow::imageio::AlphaMode::associated;
    const auto linear = negaflow::color::srgb16_to_linear_table();
    output.width = decoded.width;
    output.height = decoded.height;
    output.stride_pixels = decoded.width;
    output.pixels.resize(
        static_cast<std::size_t>(decoded.width) * static_cast<std::size_t>(decoded.height));
    negaflow::core::for_each_row_block(
        decoded.height,
        static_cast<std::uint64_t>(decoded.width) * decoded.height * channels,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t row = first_row; row < first_row + row_count; ++row) {
                const std::uint16_t* const source =
                    decoded.samples.data() + static_cast<std::size_t>(row) * source_stride;
                negaflow::core::Rgba32F* const destination =
                    output.pixels.data() + static_cast<std::size_t>(row) * output.stride_pixels;
                for (std::uint32_t column = 0U; column < decoded.width; ++column) {
                    const std::size_t offset = static_cast<std::size_t>(column) * channels;
                    const auto sample = [&](const std::size_t channel) noexcept {
                        return linear[associated
                            ? unassociate_component(source[offset + channel], source[offset + 3U])
                            : source[offset + channel]];
                    };
                    destination[column] = {
                        sample(rgb.red),
                        sample(rgb.green),
                        sample(rgb.blue),
                        decoded_alpha(decoded, source, offset),
                    };
                }
            }
        });
    return ScannerToWorkingStatus::ok;
}

}  // namespace

ScannerToWorkingStatus detail::validate_scanner_icc_profile(
    const std::span<const std::uint8_t> profile_bytes,
    const ScannerToWorkingLimits& limits,
    negaflow::color::IccProfileStatus& icc_status,
    ScannerToWorkingInfo& info) noexcept {
    const negaflow::color::IccProfileValidationResult icc =
        negaflow::color::validate_icc_profile(profile_bytes, limits.icc);
    icc_status = icc.status;
    info.icc = icc.info;
    if (icc.status != negaflow::color::IccProfileStatus::ok) {
        return ScannerToWorkingStatus::invalid_icc_profile;
    }
    if (icc.info.data_color_space != rgb_color_space_signature) {
        return ScannerToWorkingStatus::unsupported_icc_color_space;
    }
    if (!is_supported_source_profile_class(icc.info.device_class)) {
        return ScannerToWorkingStatus::unsupported_icc_profile_class;
    }
    return ScannerToWorkingStatus::ok;
}

ScannerToWorkingResult convert_scanner_to_working(
    const negaflow::imageio::DecodedImage& decoded,
    const ScannerToWorkingLimits& limits,
    const negaflow::color::InputGammaInterpretation input_gamma) noexcept {
    ScannerToWorkingResult result{};
    result.info.input_gamma = input_gamma;
    try {
        const ScannerToWorkingStatus validation = validate_decoded_image(decoded, limits);
        if (validation != ScannerToWorkingStatus::ok) {
            result.status = validation;
            return result;
        }

        if (input_gamma.mode != 0U && decoded.layout != negaflow::imageio::DecodedPixelLayout::rgb16) {
            result.status = ScannerToWorkingStatus::unsupported_input_gamma;
            return result;
        }
        const detail::InputGammaPreparation gamma(decoded.icc_profile, input_gamma);
        if (gamma.status != ScannerToWorkingStatus::ok) { result.status = gamma.status; return result; }
        if (!gamma.linear_samples.empty()) {
            result.image.width = decoded.width;
            result.image.height = decoded.height;
            result.image.stride_pixels = decoded.width;
            result.image.pixels.resize(static_cast<std::size_t>(decoded.width) * decoded.height);
            const auto stride = decoded.stride_bytes / sizeof(std::uint16_t);
            negaflow::core::for_each_row_block(
                decoded.height,
                static_cast<std::uint64_t>(decoded.width) * decoded.height * 3U,
                [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
                    for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                        const auto* row = decoded.samples.data() + static_cast<std::size_t>(y) * stride;
                        for (std::uint32_t x = 0; x < decoded.width; ++x) {
                            const auto offset = static_cast<std::size_t>(x) * 3U;
                            result.image.pixels[static_cast<std::size_t>(y) * decoded.width + x] = {
                                gamma.linear_samples[row[offset]], gamma.linear_samples[row[offset + 1U]],
                                gamma.linear_samples[row[offset + 2U]], 1.0F};
                        }
                    }
                });
            result.status = ScannerToWorkingStatus::ok;
            result.info.transform = ScannerWorkingTransform::explicit_input_gamma;
            return result;
        }

        if (decoded.icc_profile.empty()) {
            result.status = decoded.untagged_rgb_transfer ==
                    negaflow::imageio::UntaggedRgbTransfer::srgb_encoded
                ? decode_untagged_srgb_to_working(decoded, result.image)
                : detail::convert_linear_scanner_raw(decoded, result.image);
            if (result.status == ScannerToWorkingStatus::ok) {
                result.info.transform = decoded.untagged_rgb_transfer ==
                        negaflow::imageio::UntaggedRgbTransfer::srgb_encoded
                    ? ScannerWorkingTransform::untagged_srgb_to_linear
                    : ScannerWorkingTransform::linear_scanner_raw;
            }
            return result;
        }

        result.status = detail::validate_scanner_icc_profile(
            decoded.icc_profile,
            limits,
            result.icc_status,
            result.info);
        if (result.status != ScannerToWorkingStatus::ok) {
            return result;
        }

        detail::EncodedSrgb16Result encoded =
            detail::convert_embedded_icc_to_srgb16(decoded, limits, gamma.profile, gamma.encoded_samples);
        result.info.native_error_code = encoded.native_error_code;
        if (encoded.status != ScannerToWorkingStatus::ok) {
            result.status = encoded.status;
            return result;
        }
        result.status = decode_srgb16_to_working(
            encoded.samples,
            decoded.width,
            decoded.height,
            result.image);
        if (result.status == ScannerToWorkingStatus::ok &&
            decoded.layout == negaflow::imageio::DecodedPixelLayout::rgba16) {
            const std::size_t source_stride = decoded.stride_bytes / sizeof(std::uint16_t);
            constexpr float u16_scale = 1.0F / 65'535.0F;
            for (std::uint32_t row = 0U; row < decoded.height; ++row) {
                const std::uint16_t* const source = decoded.samples.data() +
                    static_cast<std::size_t>(row) * source_stride;
                for (std::uint32_t column = 0U; column < decoded.width; ++column) {
                    result.image.pixels[static_cast<std::size_t>(row) * decoded.width + column]
                        .alpha = static_cast<float>(source[static_cast<std::size_t>(column) * 4U + 3U]) *
                            u16_scale;
                }
            }
        }
        if (result.status == ScannerToWorkingStatus::ok) {
            result.info.transform = ScannerWorkingTransform::embedded_icc_windows_icm_srgb16;
            result.info.intermediate_bits_per_color_channel = 16U;
        }
        return result;
    } catch (const std::bad_alloc&) {
        result.status = ScannerToWorkingStatus::allocation_failed;
        return result;
    } catch (...) {
        result.status = ScannerToWorkingStatus::invalid_argument;
        return result;
    }
}

const char* scanner_to_working_status_name(const ScannerToWorkingStatus status) noexcept {
    switch (status) {
        case ScannerToWorkingStatus::invalid_input_gamma:
            return "invalid_input_gamma";
        case ScannerToWorkingStatus::unsupported_input_gamma:
            return "unsupported_input_gamma";
        case ScannerToWorkingStatus::ok:
            return "ok";
        case ScannerToWorkingStatus::invalid_argument:
            return "invalid_argument";
        case ScannerToWorkingStatus::invalid_dimensions:
            return "invalid_dimensions";
        case ScannerToWorkingStatus::invalid_stride:
            return "invalid_stride";
        case ScannerToWorkingStatus::size_overflow:
            return "size_overflow";
        case ScannerToWorkingStatus::buffer_size_mismatch:
            return "buffer_size_mismatch";
        case ScannerToWorkingStatus::memory_limit_exceeded:
            return "memory_limit_exceeded";
        case ScannerToWorkingStatus::unsupported_alpha:
            return "unsupported_alpha";
        case ScannerToWorkingStatus::non_opaque_alpha:
            return "non_opaque_alpha";
        case ScannerToWorkingStatus::invalid_icc_profile:
            return "invalid_icc_profile";
        case ScannerToWorkingStatus::unsupported_icc_color_space:
            return "unsupported_icc_color_space";
        case ScannerToWorkingStatus::unsupported_icc_profile_class:
            return "unsupported_icc_profile_class";
        case ScannerToWorkingStatus::color_profile_open_failed:
            return "windows_color_profile_open_failed";
        case ScannerToWorkingStatus::color_transform_initialization_failed:
            return "windows_color_transform_initialization_failed";
        case ScannerToWorkingStatus::color_transform_failed:
            return "windows_color_transform_failed";
        case ScannerToWorkingStatus::allocation_failed:
            return "allocation_failed";
        case ScannerToWorkingStatus::cancelled:
            return "cancelled";
    }
    return "unknown_scanner_to_working_status";
}

const char* scanner_working_transform_name(const ScannerWorkingTransform transform) noexcept {
    switch (transform) {
        case ScannerWorkingTransform::explicit_input_gamma:
            return "explicit_input_gamma_to_linear_srgb_f32";
        case ScannerWorkingTransform::none:
            return "none";
        case ScannerWorkingTransform::linear_scanner_raw:
            return "linear_scanner_raw_to_linear_srgb_f32";
        case ScannerWorkingTransform::untagged_srgb_to_linear:
            return "untagged_srgb_to_linear_srgb_f32";
        case ScannerWorkingTransform::embedded_icc_windows_icm_srgb16:
            return "embedded_icc_via_windows_icm_srgb16_to_linear_srgb_f32";
    }
    return "unknown_scanner_working_transform";
}

}  // namespace negaflow::imaging
