#include "wic_srgb16_support.h"

#include "negaflow/color/icc_profile.h"

#include <icm.h>

#include <algorithm>
#include <cstddef>
#include <limits>

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

WicSrgb16FrameStatus configure_srgb16_frame(
    IWICBitmapFrameEncode* const frame,
    const Srgb16Image& image,
    IWICColorContext* const color_context,
    std::uint32_t& native_error_code) noexcept {
    HRESULT status = frame->SetSize(image.width, image.height);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicSrgb16FrameStatus::configuration_failed;
    }
    WICPixelFormatGUID pixel_format = GUID_WICPixelFormat48bppRGB;
    status = frame->SetPixelFormat(&pixel_format);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicSrgb16FrameStatus::configuration_failed;
    }
    if (IsEqualGUID(pixel_format, GUID_WICPixelFormat48bppRGB) == FALSE) {
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

WicSrgb16FrameStatus write_srgb16_pixels(
    IWICBitmapFrameEncode* const frame,
    const Srgb16Image& image,
    std::uint32_t& native_error_code) noexcept {
    const std::uint64_t max_rows_per_write =
        std::numeric_limits<UINT>::max() / image.stride_bytes;
    if (max_rows_per_write == 0U) {
        return WicSrgb16FrameStatus::write_failed;
    }
    std::uint32_t completed_rows = 0U;
    while (completed_rows < image.height) {
        const UINT row_count = static_cast<UINT>(std::min<std::uint64_t>(
            image.height - completed_rows,
            max_rows_per_write));
        const UINT buffer_bytes = row_count * image.stride_bytes;
        const std::size_t sample_offset =
            static_cast<std::size_t>(completed_rows) * image.width * 3U;
        const HRESULT status = frame->WritePixels(
            row_count,
            image.stride_bytes,
            buffer_bytes,
            reinterpret_cast<BYTE*>(
                const_cast<std::uint16_t*>(image.samples.data() + sample_offset)));
        if (FAILED(status)) {
            native_error_code = static_cast<std::uint32_t>(status);
            return WicSrgb16FrameStatus::write_failed;
        }
        completed_rows += row_count;
    }
    return WicSrgb16FrameStatus::ok;
}

WicSrgb16FrameStatus verify_srgb16_frame(
    IWICImagingFactory* const factory,
    IWICBitmapFrameDecode* const frame,
    const Srgb16Image& expected,
    const std::vector<std::uint8_t>& expected_profile,
    const std::uint32_t readback_buffer_bytes,
    std::uint32_t& native_error_code) {
    UINT width = 0U;
    UINT height = 0U;
    WICPixelFormatGUID format{};
    HRESULT status = frame->GetSize(&width, &height);
    if (SUCCEEDED(status)) {
        status = frame->GetPixelFormat(&format);
    }
    if (FAILED(status) || width != expected.width || height != expected.height ||
        IsEqualGUID(format, GUID_WICPixelFormat48bppRGB) == FALSE) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicSrgb16FrameStatus::readback_failed;
    }
    if (readback_buffer_bytes < expected.stride_bytes) {
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
    std::vector<std::uint16_t> buffer(
        static_cast<std::size_t>(buffer_bytes_64 / sizeof(std::uint16_t)));
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
            reinterpret_cast<BYTE*>(buffer.data()));
        if (FAILED(status)) {
            native_error_code = static_cast<std::uint32_t>(status);
            return WicSrgb16FrameStatus::readback_failed;
        }
        const std::size_t expected_offset =
            static_cast<std::size_t>(row) * expected.width * 3U;
        const std::size_t sample_count =
            static_cast<std::size_t>(row_count) * expected.width * 3U;
        if (!std::equal(
                buffer.begin(),
                buffer.begin() + static_cast<std::ptrdiff_t>(sample_count),
                expected.samples.begin() + static_cast<std::ptrdiff_t>(expected_offset))) {
            return WicSrgb16FrameStatus::pixel_verification_failed;
        }
        row += row_count;
    }
    return verify_profile(factory, frame, expected_profile, native_error_code);
}

}  // namespace negaflow::output::detail
