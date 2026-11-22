#include "icm_rgb16_parallel.h"
#include "scanner_to_working_detail.h"

#include "negaflow/color/icc_profile.h"
#include "negaflow/color/icm_transform.h"

#include <Windows.h>
#include <icm.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <span>
#include <utility>
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

// ICM 의 16비트 3채널 형식 `BM_16b_RGB` 는 BMFORMAT 문서 표(R,G,B)와 달리 메모리를 **B,G,R
// 순서**로 읽고 씁니다. 2026-11-22 검증 PC 실측: sRGB→Display P3 변환에 [65535,0,0] 을 넣으면
// 파랑으로 옮겨져 [62888,89,0](= P3 파랑을 B,G,R 로 쓴 값)이 나오고, 같은 변환의
// `TranslateColors` 는 빨강을 [60126,13144,9070] 으로 맞게 옮깁니다. R,G,B 순서 16비트 형식은
// 없으므로 변환 앞뒤로 R 과 B 를 맞바꿉니다. 같은 프로파일끼리는 티가 나지 않고, 기본색이
// 다른 변환(P3·Adobe RGB·넓은 스캐너 프로파일·인화소 프로파일)에만 R/B 가 뒤바뀐 행렬이
// 걸렸습니다.
void swap_red_blue_rows(
    std::uint16_t* const rows,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_bytes) noexcept {
    auto* const base = reinterpret_cast<std::uint8_t*>(rows);
    for (std::uint32_t y = 0U; y < height; ++y) {
        auto* const row = reinterpret_cast<std::uint16_t*>(
            base + (static_cast<std::size_t>(y) * stride_bytes));
        for (std::uint32_t x = 0U; x < width; ++x) {
            std::swap(row[x * 3U], row[(x * 3U) + 2U]);
        }
    }
}

void copy_rows_swapping_red_blue(
    const std::uint16_t* const source,
    const std::uint32_t source_stride_bytes,
    std::uint16_t* const destination,
    const std::uint32_t destination_stride_bytes,
    const std::uint32_t width,
    const std::uint32_t height) noexcept {
    const auto* const from = reinterpret_cast<const std::uint8_t*>(source);
    auto* const to = reinterpret_cast<std::uint8_t*>(destination);
    for (std::uint32_t y = 0U; y < height; ++y) {
        const auto* const in = reinterpret_cast<const std::uint16_t*>(
            from + (static_cast<std::size_t>(y) * source_stride_bytes));
        auto* const out = reinterpret_cast<std::uint16_t*>(
            to + (static_cast<std::size_t>(y) * destination_stride_bytes));
        for (std::uint32_t x = 0U; x < width; ++x) {
            out[x * 3U] = in[(x * 3U) + 2U];
            out[(x * 3U) + 1U] = in[(x * 3U) + 1U];
            out[(x * 3U) + 2U] = in[x * 3U];
        }
    }
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
    std::vector<std::uint8_t>{}.swap(source_profile_storage_);
    std::vector<std::uint8_t>{}.swap(destination_profile_storage_);
}

ScannerToWorkingStatus IcmRgb16Transform::initialize(
    const std::span<const std::uint8_t> source_profile_bytes,
    std::uint32_t& native_error_code,
    const std::span<const std::uint8_t> destination_profile_bytes) {
    reset();
    native_error_code = 0U;
    if (source_profile_bytes.empty() ||
        source_profile_bytes.size() > std::numeric_limits<DWORD>::max()) {
        return ScannerToWorkingStatus::invalid_icc_profile;
    }
    const std::span<const std::uint8_t> source_trimmed =
        negaflow::color::trim_icc_padding(source_profile_bytes);
    const std::span<const std::uint8_t> destination_trimmed =
        destination_profile_bytes.empty()
            ? destination_profile_bytes
            : negaflow::color::trim_icc_padding(destination_profile_bytes);

    PROFILE source_description{};
    source_description.dwType = PROFILE_MEMBUFFER;
    source_description.pProfileData = const_cast<std::uint8_t*>(source_trimmed.data());
    source_description.cbDataSize = static_cast<DWORD>(source_trimmed.size());
    SetLastError(ERROR_SUCCESS);
    source_profile_ =
        OpenColorProfileW(&source_description, PROFILE_READ, 0U, OPEN_EXISTING);
    if (source_profile_ == nullptr) {
        native_error_code = GetLastError();
        return ScannerToWorkingStatus::color_profile_open_failed;
    }

    if (destination_trimmed.empty()) {
        destination_profile_ = open_standard_srgb_profile(native_error_code);
    } else {
        if (destination_trimmed.size() > std::numeric_limits<DWORD>::max()) {
            reset();
            return ScannerToWorkingStatus::invalid_icc_profile;
        }
        try {
            destination_profile_storage_.assign(
                destination_trimmed.begin(), destination_trimmed.end());
        } catch (const std::bad_alloc&) {
            reset();
            return ScannerToWorkingStatus::allocation_failed;
        }
        PROFILE destination_description{};
        destination_description.dwType = PROFILE_MEMBUFFER;
        destination_description.pProfileData = destination_profile_storage_.data();
        destination_description.cbDataSize =
            static_cast<DWORD>(destination_profile_storage_.size());
        SetLastError(ERROR_SUCCESS);
        destination_profile_ =
            OpenColorProfileW(&destination_description, PROFILE_READ, 0U, OPEN_EXISTING);
        if (destination_profile_ == nullptr) {
            native_error_code = GetLastError();
        }
    }
    if (destination_profile_ == nullptr) {
        reset();
        return ScannerToWorkingStatus::color_profile_open_failed;
    }

    return link(native_error_code);
}

ScannerToWorkingStatus IcmRgb16Transform::initialize_to_profile(
    const std::span<const std::uint8_t> destination_profile_bytes,
    std::uint32_t& native_error_code,
    const std::span<const std::uint8_t> source_profile_bytes) {
    reset();
    native_error_code = 0U;
    if (destination_profile_bytes.empty() ||
        destination_profile_bytes.size() > std::numeric_limits<DWORD>::max() ||
        source_profile_bytes.size() > std::numeric_limits<DWORD>::max()) {
        return ScannerToWorkingStatus::invalid_icc_profile;
    }
    const std::span<const std::uint8_t> destination_trimmed =
        negaflow::color::trim_icc_padding(destination_profile_bytes);
    const std::span<const std::uint8_t> source_trimmed =
        source_profile_bytes.empty()
            ? source_profile_bytes
            : negaflow::color::trim_icc_padding(source_profile_bytes);

    if (source_trimmed.empty()) {
        source_profile_ = open_standard_srgb_profile(native_error_code);
    } else {
        try {
            source_profile_storage_.assign(
                source_trimmed.begin(), source_trimmed.end());
        } catch (const std::bad_alloc&) {
            return ScannerToWorkingStatus::allocation_failed;
        }
        PROFILE source_description{};
        source_description.dwType = PROFILE_MEMBUFFER;
        source_description.pProfileData = source_profile_storage_.data();
        source_description.cbDataSize = static_cast<DWORD>(source_profile_storage_.size());
        SetLastError(ERROR_SUCCESS);
        source_profile_ =
            OpenColorProfileW(&source_description, PROFILE_READ, 0U, OPEN_EXISTING);
        if (source_profile_ == nullptr) {
            native_error_code = GetLastError();
        }
    }
    if (source_profile_ == nullptr) {
        reset();
        return ScannerToWorkingStatus::color_profile_open_failed;
    }

    try {
        destination_profile_storage_.assign(
            destination_trimmed.begin(), destination_trimmed.end());
    } catch (const std::bad_alloc&) {
        reset();
        return ScannerToWorkingStatus::allocation_failed;
    }
    PROFILE destination_description{};
    destination_description.dwType = PROFILE_MEMBUFFER;
    destination_description.pProfileData = destination_profile_storage_.data();
    destination_description.cbDataSize =
        static_cast<DWORD>(destination_profile_storage_.size());
    SetLastError(ERROR_SUCCESS);
    destination_profile_ =
        OpenColorProfileW(&destination_description, PROFILE_READ, 0U, OPEN_EXISTING);
    if (destination_profile_ == nullptr) {
        native_error_code = GetLastError();
        reset();
        return ScannerToWorkingStatus::color_profile_open_failed;
    }
    return link(native_error_code);
}

ScannerToWorkingStatus IcmRgb16Transform::link(std::uint32_t& native_error_code) {
    HPROFILE profiles[2]{source_profile_, destination_profile_};
    transform_ = negaflow::color::create_icm_transform(profiles, 2U, false, native_error_code);
    if (transform_ == nullptr) {
        reset();
        return ScannerToWorkingStatus::color_transform_initialization_failed;
    }
    return ScannerToWorkingStatus::ok;
}

ScannerToWorkingStatus IcmRgb16Transform::translate8(
    const std::uint8_t* const source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t source_stride_bytes,
    std::uint8_t* const destination,
    const std::uint32_t destination_stride_bytes,
    std::uint32_t& native_error_code) const noexcept {
    native_error_code = 0U;
    if (transform_ == nullptr || source == nullptr || destination == nullptr || width == 0U ||
        height == 0U || source_stride_bytes == 0U || destination_stride_bytes == 0U) {
        return ScannerToWorkingStatus::invalid_argument;
    }
    // 화소는 R,G,B 순서입니다. BMFORMAT 표대로 그 메모리 순서는 `BM_BGRTRIPLETS` 이고
    // `BM_RGBTRIPLETS` 는 B,G,R 입니다(이름이 거꾸로 붙어 있습니다, 2026-11-22 실측 확인).
    SetLastError(ERROR_SUCCESS);
    const BOOL converted = TranslateBitmapBits(
        transform_,
        const_cast<std::uint8_t*>(source),
        BM_BGRTRIPLETS,
        width,
        height,
        source_stride_bytes,
        destination,
        BM_BGRTRIPLETS,
        destination_stride_bytes,
        nullptr,
        0);
    if (converted == FALSE) {
        native_error_code = GetLastError();
        return ScannerToWorkingStatus::color_transform_failed;
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

    // ICM 이 B,G,R 로 읽으므로(위 `swap_red_blue_rows` 주석) 목적지에 R/B 를 맞바꾼 사본을
    // 두고 제자리에서 옮긴 뒤 되돌립니다. 원본은 건드리지 않습니다 — 원본과 목적지가 같은
    // 버퍼(제자리 변환)일 때만 그 버퍼가 바뀝니다.
    if (source == destination && source_stride_bytes == destination_stride_bytes) {
        swap_red_blue_rows(destination, width, height, destination_stride_bytes);
    } else {
        copy_rows_swapping_red_blue(
            source, source_stride_bytes, destination, destination_stride_bytes, width, height);
    }
    SetLastError(ERROR_SUCCESS);
    const BOOL converted = TranslateBitmapBits(
        transform_,
        destination,
        BM_16b_RGB,
        width,
        height,
        destination_stride_bytes,
        destination,
        BM_16b_RGB,
        destination_stride_bytes,
        progress_callback,
        callback_data);
    swap_red_blue_rows(destination, width, height, destination_stride_bytes);
    if (converted == FALSE) {
        native_error_code = GetLastError();
        return ScannerToWorkingStatus::color_transform_failed;
    }
    return ScannerToWorkingStatus::ok;
}

std::span<const std::uint8_t> working_intermediate_profile() noexcept {
    static const std::vector<std::uint8_t> profile = []() noexcept {
        try {
            return negaflow::color::build_working_intermediate_icc_profile();
        } catch (...) {
            return std::vector<std::uint8_t>{};
        }
    }();
    return profile;
}

EncodedSrgb16Result convert_embedded_icc_to_srgb16(
    const negaflow::imageio::DecodedImage& decoded,
    const ScannerToWorkingLimits& limits,
    const std::span<const std::uint8_t> profile_override,
    const std::span<const std::uint16_t> sample_table) noexcept {
    EncodedSrgb16Result result{};
    if (!sample_table.empty() && sample_table.size() != 65536U) {
        result.status = ScannerToWorkingStatus::invalid_input_gamma;
        return result;
    }
    try {
        const std::uint64_t rgb_stride_bytes =
            static_cast<std::uint64_t>(decoded.width) * 3ULL * sizeof(std::uint16_t);
        const std::uint64_t rgb_pixel_bytes = rgb_stride_bytes * decoded.height;
        const std::uint64_t source_memory_bytes =
            static_cast<std::uint64_t>(decoded.stride_bytes) * decoded.height;
        // ICM 변환은 RGB16 만 받습니다. rgba 는 alpha 를 떼고, gray 는 한 표본을 세 채널로
        // 펴서 같은 입력 모양으로 맞춥니다.
        const bool needs_rgb_copy =
            decoded.layout != negaflow::imageio::DecodedPixelLayout::rgb16 || !sample_table.empty();
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
            const std::size_t source_channels =
                negaflow::imageio::channel_count(decoded.layout);
            const bool source_has_alpha =
                decoded.layout == negaflow::imageio::DecodedPixelLayout::rgba16;
            const negaflow::imageio::RgbSampleOffsets rgb =
                negaflow::imageio::rgb_sample_offsets(decoded.layout);
            for (std::uint32_t row = 0U; row < decoded.height; ++row) {
                const std::uint16_t* const source =
                    decoded.samples.data() + static_cast<std::size_t>(row) * decoded_stride;
                std::uint16_t* const destination =
                    packed_rgb.data() + static_cast<std::size_t>(row) * decoded.width * 3U;
                for (std::uint32_t column = 0U; column < decoded.width; ++column) {
                    const std::size_t source_offset =
                        static_cast<std::size_t>(column) * source_channels;
                    const std::size_t destination_offset = static_cast<std::size_t>(column) * 3U;
                    const bool associated =
                        decoded.alpha_mode == negaflow::imageio::AlphaMode::associated;
                    const std::uint16_t alpha = source_has_alpha
                        ? source[source_offset + 3U]
                        : std::uint16_t{65'535U};
                    destination[destination_offset] = associated
                        ? unassociate_component(source[source_offset + rgb.red], alpha)
                        : source[source_offset + rgb.red];
                    destination[destination_offset + 1U] = associated
                        ? unassociate_component(source[source_offset + rgb.green], alpha)
                        : source[source_offset + rgb.green];
                    destination[destination_offset + 2U] = associated
                        ? unassociate_component(source[source_offset + rgb.blue], alpha)
                        : source[source_offset + rgb.blue];
                    if (!sample_table.empty()) {
                        for (std::size_t channel = 0; channel < 3U; ++channel) {
                            auto& sample = destination[destination_offset + channel];
                            sample = sample_table[sample];
                        }
                    }
                }
            }
            source_samples = packed_rgb.data();
            source_stride_bytes = static_cast<std::uint32_t>(rgb_stride_bytes);
        }

        const std::span<const std::uint8_t> intermediate = working_intermediate_profile();
        if (intermediate.empty()) {
            result.status = ScannerToWorkingStatus::allocation_failed;
            return result;
        }
        std::span<const std::uint8_t> source_profile = profile_override.empty()
            ? std::span<const std::uint8_t>(decoded.icc_profile) : profile_override;
        // Gray 프로파일은 같은 회색 축의 RGB 프로파일로 옮겨 읽습니다. 흑백 화소는 위에서 세
        // 채널로 폈습니다.
        std::vector<std::uint8_t> gray_as_rgb{};
        if (icc_is_gray(source_profile)) {
            if (decoded.layout != negaflow::imageio::DecodedPixelLayout::gray16) {
                result.status = ScannerToWorkingStatus::unsupported_icc_color_space;
                return result;
            }
            gray_as_rgb = negaflow::color::rgb_profile_for_gray_profile(source_profile);
            if (gray_as_rgb.empty()) {
                result.status = ScannerToWorkingStatus::unsupported_icc_color_space;
                return result;
            }
            source_profile = gray_as_rgb;
        }
        ParallelIcmRgb16Transform transform{};
        result.status = transform.initialize(
            source_profile,
            result.native_error_code,
            intermediate);
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
