#include "wic_srgb16_support.h"

#include "negaflow/color/icc_profile.h"

#include <icm.h>

#include <algorithm>
#include <cstddef>
#include <cmath>
#include <limits>
#include <new>

namespace negaflow::output::detail {
namespace {

using Microsoft::WRL::ComPtr;

[[nodiscard]] WicSrgb16FrameStatus verify_profile(
    IWICImagingFactory* const factory,
    IWICBitmapFrameDecode* const frame,
    const std::vector<std::uint8_t>& expected_profile,
    std::uint32_t& native_error_code) {
    UINT context_count = 0U;
    HRESULT status = frame->GetColorContexts(0U, nullptr, &context_count);
    if (FAILED(status) || context_count != 1U) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicSrgb16FrameStatus::profile_verification_failed;
    }
    ComPtr<IWICColorContext> context{};
    status = factory->CreateColorContext(&context);
    IWICColorContext* raw_context = context.Get();
    UINT actual_context_count = 0U;
    if (SUCCEEDED(status)) {
        status = frame->GetColorContexts(1U, &raw_context, &actual_context_count);
    }
    WICColorContextType context_type = WICColorContextUninitialized;
    if (SUCCEEDED(status)) {
        status = context->GetType(&context_type);
    }
    UINT profile_size = 0U;
    if (SUCCEEDED(status)) {
        status = context->GetProfileBytes(0U, nullptr, &profile_size);
    }
    if (FAILED(status) || actual_context_count != 1U ||
        context_type != WICColorContextProfile ||
        profile_size != expected_profile.size()) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicSrgb16FrameStatus::profile_verification_failed;
    }
    std::vector<std::uint8_t> actual_profile(profile_size);
    UINT actual_profile_size = 0U;
    status = context->GetProfileBytes(
        profile_size,
        actual_profile.data(),
        &actual_profile_size);
    if (FAILED(status) || actual_profile_size != profile_size ||
        actual_profile != expected_profile) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicSrgb16FrameStatus::profile_verification_failed;
    }
    return WicSrgb16FrameStatus::ok;
}

}  // namespace

ComApartment::ComApartment() noexcept
    : status_(CoInitializeEx(nullptr, COINIT_MULTITHREADED)) {}

ComApartment::~ComApartment() noexcept {
    if (status_ == S_OK || status_ == S_FALSE) {
        CoUninitialize();
    }
}

HRESULT ComApartment::status() const noexcept {
    return status_;
}

bool create_wic_factory(
    ComPtr<IWICImagingFactory2>& factory,
    std::uint32_t& native_error_code) noexcept {
    const HRESULT status = CoCreateInstance(
        CLSID_WICImagingFactory2,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&factory));
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return false;
    }
    return true;
}

StandardSrgbStatus load_standard_srgb_context(
    IWICImagingFactory* const factory,
    const std::uint32_t max_color_profile_bytes,
    ComPtr<IWICColorContext>& context,
    std::vector<std::uint8_t>& profile_bytes,
    std::uint32_t& native_error_code) {
    DWORD path_bytes = 0U;
    SetLastError(ERROR_SUCCESS);
    const BOOL size_status =
        GetStandardColorSpaceProfileW(nullptr, LCS_sRGB, nullptr, &path_bytes);
    const DWORD size_error = GetLastError();
    if ((size_status == FALSE && size_error != ERROR_INSUFFICIENT_BUFFER) ||
        path_bytes < sizeof(wchar_t) || path_bytes > 32U * 1024U) {
        native_error_code = static_cast<std::uint32_t>(size_error);
        return StandardSrgbStatus::unavailable;
    }
    std::vector<wchar_t> path(
        (static_cast<std::size_t>(path_bytes) + sizeof(wchar_t) - 1U) /
        sizeof(wchar_t));
    if (GetStandardColorSpaceProfileW(nullptr, LCS_sRGB, path.data(), &path_bytes) == FALSE) {
        native_error_code = static_cast<std::uint32_t>(GetLastError());
        return StandardSrgbStatus::unavailable;
    }

    HRESULT status = factory->CreateColorContext(&context);
    if (SUCCEEDED(status)) {
        status = context->InitializeFromFilename(path.data());
    }
    UINT profile_size = 0U;
    if (SUCCEEDED(status)) {
        status = context->GetProfileBytes(0U, nullptr, &profile_size);
    }
    if (FAILED(status) || profile_size == 0U ||
        profile_size > max_color_profile_bytes) {
        native_error_code = static_cast<std::uint32_t>(status);
        return StandardSrgbStatus::unavailable;
    }
    profile_bytes.resize(profile_size);
    UINT actual_profile_size = 0U;
    status = context->GetProfileBytes(
        profile_size,
        profile_bytes.data(),
        &actual_profile_size);
    if (FAILED(status) || actual_profile_size != profile_size) {
        native_error_code = static_cast<std::uint32_t>(status);
        return StandardSrgbStatus::unavailable;
    }
    const negaflow::color::IccProfileValidationResult validation =
        negaflow::color::validate_icc_profile(profile_bytes);
    if (validation.status != negaflow::color::IccProfileStatus::ok ||
        validation.info.data_color_space != 0x52474220U) {
        return StandardSrgbStatus::invalid;
    }
    return StandardSrgbStatus::ok;
}

namespace {

// RGB 로 만든 바이트를 WIC 의 24bppBGR 순서로 맞바꿉니다.
void swap_red_and_blue(std::uint8_t* const bytes, const std::size_t byte_count) noexcept {
    for (std::size_t index = 0U; index + 2U < byte_count; index += 3U) {
        const std::uint8_t red = bytes[index];
        bytes[index] = bytes[index + 2U];
        bytes[index + 2U] = red;
    }
}

}  // namespace

WicSrgb16FrameStatus configure_srgb16_frame(
    IWICBitmapFrameEncode* const frame,
    const Srgb16Image& image,
    IWICColorContext* const color_context,
    const std::uint32_t output_dpi,
    std::uint32_t& native_error_code) noexcept {
    HRESULT status = frame->SetSize(image.width, image.height);
    if (SUCCEEDED(status) && output_dpi != 0U) {
        status = frame->SetResolution(
            static_cast<double>(output_dpi),
            static_cast<double>(output_dpi));
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicSrgb16FrameStatus::configuration_failed;
    }
    // 8-bit 출력의 WIC 원형 형식은 BGR 순서입니다. 우리 변환기는 RGB 로 내므로 쓰기 직전에
    // 픽셀마다 두 바이트를 맞바꿉니다.
    const WICPixelFormatGUID requested = image.bits_per_sample == 8U
        ? GUID_WICPixelFormat24bppBGR
        : GUID_WICPixelFormat48bppRGB;
    WICPixelFormatGUID pixel_format = requested;
    status = frame->SetPixelFormat(&pixel_format);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicSrgb16FrameStatus::configuration_failed;
    }
    if (IsEqualGUID(pixel_format, requested) == FALSE) {
        return WicSrgb16FrameStatus::pixel_format_coerced;
    }
    IWICColorContext* contexts[]{color_context};
    status = frame->SetColorContexts(1U, contexts);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicSrgb16FrameStatus::configuration_failed;
    }
    return WicSrgb16FrameStatus::ok;
}

WicSrgb16FrameStatus write_working_srgb16_pixels(
    IWICBitmapFrameEncode* const frame,
    const negaflow::imaging::WorkingImage& working,
    const Srgb16Image& image,
    const WorkingToSrgb16Limits& conversion_limits,
    const std::uint32_t write_buffer_bytes,
    WorkingToSrgb16Status& conversion_status,
    std::uint32_t& native_error_code) noexcept {
    if (image.width == 0U || image.height == 0U || image.stride_bytes == 0U ||
        write_buffer_bytes < image.stride_bytes) {
        return WicSrgb16FrameStatus::write_failed;
    }
    const std::uint64_t rows_per_write = std::min<std::uint64_t>(
        write_buffer_bytes / image.stride_bytes,
        std::numeric_limits<UINT>::max() / image.stride_bytes);
    if (rows_per_write == 0U) {
        return WicSrgb16FrameStatus::write_failed;
    }
    const std::uint32_t allocated_rows = static_cast<std::uint32_t>(
        std::min<std::uint64_t>(rows_per_write, image.height));
    const std::uint64_t buffer_bytes_64 =
        static_cast<std::uint64_t>(allocated_rows) * image.stride_bytes;
    try {
        std::vector<std::uint8_t> buffer(static_cast<std::size_t>(buffer_bytes_64));
        for (std::uint32_t row = 0U; row < image.height;) {
            const std::uint32_t row_count = static_cast<std::uint32_t>(
                std::min<std::uint64_t>(rows_per_write, image.height - row));
            std::uint64_t ignored_clipped_components = 0U;
            conversion_status = convert_working_to_srgb_rows(
                working,
                image.bits_per_sample,
                row,
                row_count,
                buffer.data(),
                buffer.size(),
                ignored_clipped_components,
                conversion_limits);
            if (conversion_status != WorkingToSrgb16Status::ok) {
                return WicSrgb16FrameStatus::working_conversion_failed;
            }
            const UINT buffer_bytes = row_count * image.stride_bytes;
            if (image.bits_per_sample == 8U) {
                swap_red_and_blue(buffer.data(), buffer_bytes);
            }
            const HRESULT status = frame->WritePixels(
                row_count,
                image.stride_bytes,
                buffer_bytes,
                buffer.data());
            if (FAILED(status)) {
                native_error_code = static_cast<std::uint32_t>(status);
                return WicSrgb16FrameStatus::write_failed;
            }
            row += row_count;
        }
    } catch (const std::bad_alloc&) {
        return WicSrgb16FrameStatus::allocation_failed;
    }
    return WicSrgb16FrameStatus::ok;
}

WicSrgb16FrameStatus verify_working_srgb16_frame(
    IWICImagingFactory* const factory,
    IWICBitmapFrameDecode* const frame,
    const negaflow::imaging::WorkingImage& working,
    const Srgb16Image& expected,
    const WorkingToSrgb16Limits& conversion_limits,
    const std::vector<std::uint8_t>& expected_profile,
    const std::uint32_t output_dpi,
    const std::uint32_t readback_buffer_bytes,
    WorkingToSrgb16Status& conversion_status,
    std::uint32_t& native_error_code) {
    UINT width = 0U;
    UINT height = 0U;
    WICPixelFormatGUID format{};
    HRESULT status = frame->GetSize(&width, &height);
    if (SUCCEEDED(status)) {
        status = frame->GetPixelFormat(&format);
    }
    const WICPixelFormatGUID expected_format = expected.bits_per_sample == 8U
        ? GUID_WICPixelFormat24bppBGR
        : GUID_WICPixelFormat48bppRGB;
    if (FAILED(status) || width != expected.width || height != expected.height ||
        IsEqualGUID(format, expected_format) == FALSE) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicSrgb16FrameStatus::readback_failed;
    }
    if (output_dpi != 0U) {
        double horizontal_dpi = 0.0;
        double vertical_dpi = 0.0;
        status = frame->GetResolution(&horizontal_dpi, &vertical_dpi);
        constexpr double tolerance = 0.01;
        if (FAILED(status) ||
            std::abs(horizontal_dpi - static_cast<double>(output_dpi)) > tolerance ||
            std::abs(vertical_dpi - static_cast<double>(output_dpi)) > tolerance) {
            native_error_code = static_cast<std::uint32_t>(status);
            return WicSrgb16FrameStatus::readback_failed;
        }
    }
    if (expected.width == 0U || expected.height == 0U || expected.stride_bytes == 0U ||
        readback_buffer_bytes < expected.stride_bytes) {
        return WicSrgb16FrameStatus::readback_failed;
    }
    const std::uint32_t rows_per_copy =
        readback_buffer_bytes / expected.stride_bytes;
    const std::uint32_t allocated_rows = std::min(rows_per_copy, expected.height);
    const std::uint64_t buffer_bytes_64 =
        static_cast<std::uint64_t>(allocated_rows) * expected.stride_bytes;
    if (buffer_bytes_64 > std::numeric_limits<UINT>::max()) {
        return WicSrgb16FrameStatus::readback_failed;
    }
    std::vector<std::uint8_t> readback_buffer(static_cast<std::size_t>(buffer_bytes_64));
    std::vector<std::uint8_t> expected_buffer(static_cast<std::size_t>(buffer_bytes_64));
    for (std::uint32_t row = 0U; row < expected.height;) {
        const std::uint32_t row_count = std::min(rows_per_copy, expected.height - row);
        const UINT buffer_bytes = row_count * expected.stride_bytes;
        WICRect rectangle{
            0,
            static_cast<INT>(row),
            static_cast<INT>(expected.width),
            static_cast<INT>(row_count),
        };
        status = frame->CopyPixels(
            &rectangle,
            expected.stride_bytes,
            buffer_bytes,
            readback_buffer.data());
        if (FAILED(status)) {
            native_error_code = static_cast<std::uint32_t>(status);
            return WicSrgb16FrameStatus::readback_failed;
        }
        std::uint64_t ignored_clipped_components = 0U;
        conversion_status = convert_working_to_srgb_rows(
            working,
            expected.bits_per_sample,
            row,
            row_count,
            expected_buffer.data(),
            expected_buffer.size(),
            ignored_clipped_components,
            conversion_limits);
        if (conversion_status != WorkingToSrgb16Status::ok) {
            return WicSrgb16FrameStatus::working_conversion_failed;
        }
        if (expected.bits_per_sample == 8U) {
            swap_red_and_blue(expected_buffer.data(), buffer_bytes);
        }
        const std::size_t sample_count = static_cast<std::size_t>(buffer_bytes);
        if (!std::equal(
                readback_buffer.begin(),
                readback_buffer.begin() + static_cast<std::ptrdiff_t>(sample_count),
                expected_buffer.begin())) {
            return WicSrgb16FrameStatus::pixel_verification_failed;
        }
        row += row_count;
    }
    return verify_profile(factory, frame, expected_profile, native_error_code);
}

}  // namespace negaflow::output::detail
