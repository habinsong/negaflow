#include "icm_rgb16_transform.h"
#include "scanner_to_working_detail.h"

#include <Windows.h>
#include <icm.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <span>
#include <vector>

namespace negaflow::imaging::detail {
namespace {

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

[[nodiscard]] HPROFILE open_standard_srgb_profile(std::uint32_t& native_error_code) {
    DWORD path_bytes = 0U;
    SetLastError(ERROR_SUCCESS);
    GetStandardColorSpaceProfileW(nullptr, LCS_sRGB, nullptr, &path_bytes);
    if (path_bytes < sizeof(wchar_t) || path_bytes > 32U * 1024U) {
        native_error_code = GetLastError();
        return nullptr;
    }

    std::vector<wchar_t> path(
        (static_cast<std::size_t>(path_bytes) + sizeof(wchar_t) - 1U) /
        sizeof(wchar_t));
    if (GetStandardColorSpaceProfileW(nullptr, LCS_sRGB, path.data(), &path_bytes) == FALSE) {
        native_error_code = GetLastError();
        return nullptr;
    }

    PROFILE description{};
    description.dwType = PROFILE_FILENAME;
    description.pProfileData = path.data();
    description.cbDataSize = path_bytes;
    HPROFILE profile =
        OpenColorProfileW(&description, PROFILE_READ, FILE_SHARE_READ, OPEN_EXISTING);
    if (profile == nullptr) {
        native_error_code = GetLastError();
    }
    return profile;
}

}  // namespace

IcmRgb16Transform::~IcmRgb16Transform() noexcept {
    reset();
}

void IcmRgb16Transform::reset() noexcept {
    if (transform_ != nullptr) {
        DeleteColorTransform(transform_);
        transform_ = nullptr;
    }
    if (destination_profile_ != nullptr) {
        CloseColorProfile(destination_profile_);
        destination_profile_ = nullptr;
    }
    if (source_profile_ != nullptr) {
        CloseColorProfile(source_profile_);
        source_profile_ = nullptr;
    }
}

ScannerToWorkingStatus IcmRgb16Transform::initialize(
    const std::span<const std::uint8_t> source_profile_bytes,
    std::uint32_t& native_error_code) {
    reset();
    native_error_code = 0U;
    if (source_profile_bytes.empty() ||
        source_profile_bytes.size() > std::numeric_limits<DWORD>::max()) {
        return ScannerToWorkingStatus::invalid_icc_profile;
    }

    PROFILE source_description{};
    source_description.dwType = PROFILE_MEMBUFFER;
    source_description.pProfileData = const_cast<std::uint8_t*>(source_profile_bytes.data());
    source_description.cbDataSize = static_cast<DWORD>(source_profile_bytes.size());
    SetLastError(ERROR_SUCCESS);
    source_profile_ =
        OpenColorProfileW(&source_description, PROFILE_READ, 0U, OPEN_EXISTING);
    if (source_profile_ == nullptr) {
        native_error_code = GetLastError();
        return ScannerToWorkingStatus::color_profile_open_failed;
    }

    destination_profile_ = open_standard_srgb_profile(native_error_code);
    if (destination_profile_ == nullptr) {
        reset();
        return ScannerToWorkingStatus::color_profile_open_failed;
    }

    HPROFILE profiles[2]{source_profile_, destination_profile_};
    DWORD intent = INTENT_RELATIVE_COLORIMETRIC;
    SetLastError(ERROR_SUCCESS);
    transform_ = CreateMultiProfileTransform(
        profiles,
        2U,
        &intent,
        1U,
        BEST_MODE,
        INDEX_DONT_CARE);
    if (transform_ == nullptr) {
        native_error_code = GetLastError();
        reset();
        return ScannerToWorkingStatus::color_transform_initialization_failed;
    }
    return ScannerToWorkingStatus::ok;
}

ScannerToWorkingStatus IcmRgb16Transform::translate(
    const std::uint16_t* const source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t source_stride_bytes,
    std::uint16_t* const destination,
    const std::uint32_t destination_stride_bytes,
    std::uint32_t& native_error_code,
    const PBMCALLBACKFN progress_callback,
    const LPARAM callback_data) const noexcept {
    native_error_code = 0U;
    if (transform_ == nullptr || source == nullptr || destination == nullptr || width == 0U ||
        height == 0U || source_stride_bytes == 0U || destination_stride_bytes == 0U) {
        return ScannerToWorkingStatus::invalid_argument;
    }

    SetLastError(ERROR_SUCCESS);
    const BOOL converted = TranslateBitmapBits(
        transform_,
        const_cast<std::uint16_t*>(source),
        BM_16b_RGB,
        width,
        height,
        source_stride_bytes,
        destination,
        BM_16b_RGB,
        destination_stride_bytes,
        progress_callback,
        callback_data);
    if (converted == FALSE) {
        native_error_code = GetLastError();
        return ScannerToWorkingStatus::color_transform_failed;
    }
    return ScannerToWorkingStatus::ok;
}

EncodedSrgb16Result convert_embedded_icc_to_srgb16(
    const negaflow::imageio::DecodedImage& decoded,
    const ScannerToWorkingLimits& limits) noexcept {
    EncodedSrgb16Result result{};
    try {
        const std::uint64_t rgb_stride_bytes =
            static_cast<std::uint64_t>(decoded.width) * 3ULL * sizeof(std::uint16_t);
        const std::uint64_t rgb_pixel_bytes = rgb_stride_bytes * decoded.height;
        const std::uint64_t source_memory_bytes =
            static_cast<std::uint64_t>(decoded.stride_bytes) * decoded.height;
        const bool needs_rgb_copy =
            decoded.layout == negaflow::imageio::DecodedPixelLayout::rgba16;
        const std::uint64_t additional_temporary_bytes =
            rgb_pixel_bytes + (needs_rgb_copy ? rgb_pixel_bytes : 0ULL);
        if (rgb_stride_bytes > std::numeric_limits<DWORD>::max() ||
            rgb_pixel_bytes > std::numeric_limits<DWORD>::max() ||
            source_memory_bytes > std::numeric_limits<DWORD>::max() ||
            additional_temporary_bytes > limits.max_temporary_pixel_bytes ||
            decoded.icc_profile.size() > std::numeric_limits<DWORD>::max()) {
            result.status = ScannerToWorkingStatus::memory_limit_exceeded;
            return result;
        }

        std::vector<std::uint16_t> packed_rgb{};
        const std::uint16_t* source_samples = decoded.samples.data();
        std::uint32_t source_stride_bytes = decoded.stride_bytes;
        if (needs_rgb_copy) {
            packed_rgb.resize(
                static_cast<std::size_t>(rgb_pixel_bytes / sizeof(std::uint16_t)));
            const std::size_t decoded_stride =
                decoded.stride_bytes / sizeof(std::uint16_t);
            for (std::uint32_t row = 0U; row < decoded.height; ++row) {
                const std::uint16_t* const source =
                    decoded.samples.data() + static_cast<std::size_t>(row) * decoded_stride;
                std::uint16_t* const destination =
                    packed_rgb.data() + static_cast<std::size_t>(row) * decoded.width * 3U;
                for (std::uint32_t column = 0U; column < decoded.width; ++column) {
                    const std::size_t source_offset = static_cast<std::size_t>(column) * 4U;
                    const std::size_t destination_offset = static_cast<std::size_t>(column) * 3U;
                    const bool associated =
                        decoded.alpha_mode == negaflow::imageio::AlphaMode::associated;
                    const std::uint16_t alpha = source[source_offset + 3U];
                    destination[destination_offset] = associated
                        ? unassociate_component(source[source_offset], alpha)
                        : source[source_offset];
                    destination[destination_offset + 1U] = associated
                        ? unassociate_component(source[source_offset + 1U], alpha)
                        : source[source_offset + 1U];
                    destination[destination_offset + 2U] = associated
                        ? unassociate_component(source[source_offset + 2U], alpha)
                        : source[source_offset + 2U];
                }
            }
            source_samples = packed_rgb.data();
            source_stride_bytes = static_cast<std::uint32_t>(rgb_stride_bytes);
        }

        IcmRgb16Transform transform{};
        result.status = transform.initialize(decoded.icc_profile, result.native_error_code);
        if (result.status != ScannerToWorkingStatus::ok) {
            return result;
        }

        result.samples.resize(
            static_cast<std::size_t>(rgb_pixel_bytes / sizeof(std::uint16_t)));
        result.status = transform.translate(
            source_samples,
            decoded.width,
            decoded.height,
            source_stride_bytes,
            result.samples.data(),
            static_cast<std::uint32_t>(rgb_stride_bytes),
            result.native_error_code);
        if (result.status != ScannerToWorkingStatus::ok) {
            std::vector<std::uint16_t>{}.swap(result.samples);
            return result;
        }

        return result;
    } catch (const std::bad_alloc&) {
        result.status = ScannerToWorkingStatus::allocation_failed;
        return result;
    } catch (...) {
        result.status = ScannerToWorkingStatus::color_transform_failed;
        return result;
    }
}

}  // namespace negaflow::imaging::detail
