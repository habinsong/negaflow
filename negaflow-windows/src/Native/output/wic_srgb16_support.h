#pragma once

#include "negaflow/output/working_to_srgb16.h"

#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <cstdint>
#include <vector>

namespace negaflow::output::detail {

class ComApartment final {
public:
    ComApartment() noexcept;
    ComApartment(const ComApartment&) = delete;
    ComApartment& operator=(const ComApartment&) = delete;
    ~ComApartment() noexcept;

    [[nodiscard]] HRESULT status() const noexcept;

private:
    HRESULT status_{E_UNEXPECTED};
};

[[nodiscard]] bool create_wic_factory(
    Microsoft::WRL::ComPtr<IWICImagingFactory2>& factory,
    std::uint32_t& native_error_code) noexcept;

enum class StandardSrgbStatus : std::uint8_t {
    ok = 0,
    unavailable,
    invalid,
};

[[nodiscard]] StandardSrgbStatus load_standard_srgb_context(
    IWICImagingFactory* factory,
    std::uint32_t max_color_profile_bytes,
    Microsoft::WRL::ComPtr<IWICColorContext>& context,
    std::vector<std::uint8_t>& profile_bytes,
    std::uint32_t& native_error_code);

enum class WicSrgb16FrameStatus : std::uint8_t {
    ok = 0,
    configuration_failed,
    pixel_format_coerced,
    write_failed,
    readback_failed,
    pixel_verification_failed,
    profile_verification_failed,
};

[[nodiscard]] WicSrgb16FrameStatus configure_srgb16_frame(
    IWICBitmapFrameEncode* frame,
    const Srgb16Image& image,
    IWICColorContext* color_context,
    std::uint32_t output_dpi,
    std::uint32_t& native_error_code) noexcept;

[[nodiscard]] WicSrgb16FrameStatus write_srgb16_pixels(
    IWICBitmapFrameEncode* frame,
    const Srgb16Image& image,
    std::uint32_t& native_error_code) noexcept;

[[nodiscard]] WicSrgb16FrameStatus verify_srgb16_frame(
    IWICImagingFactory* factory,
    IWICBitmapFrameDecode* frame,
    const Srgb16Image& expected,
    const std::vector<std::uint8_t>& expected_profile,
    std::uint32_t output_dpi,
    std::uint32_t readback_buffer_bytes,
    std::uint32_t& native_error_code);

}  // namespace negaflow::output::detail
