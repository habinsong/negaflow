#pragma once

#include "negaflow/output/working_to_srgb16.h"
#include "negaflow/color/output_color_space.h"

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

// Loads the colour context a published file carries. sRGB comes from the system profile
// so a file negaflow writes matches every other sRGB file on the machine byte for byte;
// the wider spaces are generated, because Windows does not ship them.
[[nodiscard]] StandardSrgbStatus load_output_color_context(
    IWICImagingFactory* factory,
    negaflow::color::OutputColorSpace space,
    std::uint32_t max_color_profile_bytes,
    Microsoft::WRL::ComPtr<IWICColorContext>& context,
    std::vector<std::uint8_t>& profile_bytes,
    std::uint32_t& native_error_code);

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
    working_conversion_failed,
    allocation_failed,
};

[[nodiscard]] WicSrgb16FrameStatus configure_srgb16_frame(
    IWICBitmapFrameEncode* frame,
    const Srgb16Image& image,
    IWICColorContext* color_context,
    std::uint32_t output_dpi,
    std::uint32_t& native_error_code) noexcept;

[[nodiscard]] WicSrgb16FrameStatus write_working_srgb16_pixels(
    IWICBitmapFrameEncode* frame,
    const negaflow::imaging::WorkingImage& working,
    const Srgb16Image& image,
    const WorkingToSrgb16Limits& conversion_limits,
    std::uint32_t write_buffer_bytes,
    WorkingToSrgb16Status& conversion_status,
    std::uint32_t& native_error_code) noexcept;

// 쓴 파일을 다시 열어 치수·화소형식·해상도·ICC 프로파일이 의도대로인지 봅니다.
//
// `compare_pixels` 는 그 위에 **화소 전수 대조**를 더합니다. 파일을 통째로 디코드하고,
// working 이미지를 sRGB16 으로 **한 번 더** 변환해 바이트 단위로 맞춰 봅니다. 인코더가
// 조용히 다른 것을 쓰지 않았음을 증명하지만 값이 큽니다 — 5088×3401 16bit 한 장에서
// 실측 736ms 로, 내보내기 전체의 36% 였습니다.
//
// macOS 는 이 대조를 하지 않습니다(`ExportEngine.writeTIFF` 는
// `CGImageDestinationFinalize` 의 성공 여부만 봅니다). 그래서 기본은 끔이고, 인코더가
// 맞다는 증명은 `wic_tiff_export_tests` · `wic_png_export_tests` 가 켜서 들고 있습니다.
[[nodiscard]] WicSrgb16FrameStatus verify_working_srgb16_frame(
    IWICImagingFactory* factory,
    IWICBitmapFrameDecode* frame,
    const negaflow::imaging::WorkingImage& working,
    const Srgb16Image& expected,
    const WorkingToSrgb16Limits& conversion_limits,
    const std::vector<std::uint8_t>& expected_profile,
    std::uint32_t output_dpi,
    std::uint32_t readback_buffer_bytes,
    bool compare_pixels,
    WorkingToSrgb16Status& conversion_status,
    std::uint32_t& native_error_code);

}  // namespace negaflow::output::detail
