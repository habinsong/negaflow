#include "negaflow/imageio/wic_tiff_decoder.h"

#include "wic_tiff_frame.h"
#include "wic_tiff_preflight.h"
#include "wic_tiff_rows.h"
#include "wic_tiff_support.h"

#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <new>

namespace negaflow::imageio {
namespace {

using Microsoft::WRL::ComPtr;
using namespace negaflow::imageio::wic_tiff_detail;

// 디코드 한 번의 순서만 여기 있습니다. 준비·프레임 선택·화소 소스·행 복사는 각자
// 자기 번역 단위가 소유하며, 이 함수는 그 넷을 순서대로 부르고 실패를 그대로 전합니다.
WicTiffDecodeResult decode_tiff_with_wic_impl(
    const std::filesystem::path& path,
    const WicTiffDecodeLimits& limits,
    const WicTiffDecodeControl& control,
    WicTiffRowSink* const row_sink) noexcept {
    WicTiffDecodeResult result{};
    bool sink_started = false;
    const auto complete_sink = [&](const WicTiffDecodeStatus status) noexcept {
        if (sink_started) {
            row_sink->complete(status);
            sink_started = false;
        }
    };
    try {
        if (path.empty() || (row_sink != nullptr && control.rows_per_copy == 0U)) {
            return result;
        }
        if (control.stop_token.stop_requested()) {
            result.status = WicTiffDecodeStatus::cancelled;
            return result;
        }

        const ComApartment apartment{};
        if (apartment.status() == RPC_E_CHANGED_MODE) {
            result.status = WicTiffDecodeStatus::com_apartment_mismatch;
            return result;
        }
        if (FAILED(apartment.status())) {
            result.status = WicTiffDecodeStatus::wic_unavailable;
            return result;
        }

        TiffPreflight preflight{};
        result.status = preflight_tiff_source(
            path, limits, control, preflight, result);
        if (result.status != WicTiffDecodeStatus::ok) {
            return result;
        }

        SelectedFrame selected{};
        result.status = select_tiff_frame(preflight, limits, selected, result);
        if (result.status != WicTiffDecodeStatus::ok) {
            return result;
        }
        result.image.stride_bytes =
            static_cast<std::uint32_t>(preflight.stride_bytes);

        ComPtr<IWICBitmapSource> pixel_source{};
        result.status = open_pixel_source(
            selected, preflight, limits, pixel_source, result);
        if (result.status != WicTiffDecodeStatus::ok) {
            return result;
        }

        UINT output_width = selected.width;
        UINT output_height = selected.height;
        std::uint64_t output_stride = preflight.stride_bytes;
        std::uint64_t output_bytes = preflight.pixel_bytes;
        ComPtr<IWICBitmapScaler> scaler{};
        // 48bpp RGB 비압축(frame_1)은 스케일러+행 CopyPixels 가 invalid_argument 로
        // 끝났습니다. 이 형식은 원본 디코드가 174ms 라 스케일이 필요 없습니다.
        const bool allow_scaler =
            result.image.layout != DecodedPixelLayout::rgb16;
        if (allow_scaler &&
            control.max_output_width > 0U && control.max_output_height > 0U &&
            (selected.width > control.max_output_width ||
             selected.height > control.max_output_height) &&
            selected.factory) {
            UINT fitted_width = selected.width;
            UINT fitted_height = selected.height;
            if (fitted_width > control.max_output_width) {
                fitted_width = control.max_output_width;
                fitted_height = selected.width == 0U
                    ? 0U
                    : static_cast<UINT>(
                          (static_cast<std::uint64_t>(selected.height) * fitted_width) /
                          selected.width);
                if (fitted_height == 0U) {
                    fitted_height = 1U;
                }
            }
            if (fitted_height > control.max_output_height) {
                fitted_height = control.max_output_height;
                fitted_width = selected.height == 0U
                    ? 0U
                    : static_cast<UINT>(
                          (static_cast<std::uint64_t>(selected.width) * fitted_height) /
                          selected.height);
                if (fitted_width == 0U) {
                    fitted_width = 1U;
                }
            }
            const std::uint32_t bytes_per_pixel =
                result.image.layout == DecodedPixelLayout::rgba16 ? 8U
                : result.image.layout == DecodedPixelLayout::gray16 ? 2U
                                                                   : 6U;
            if (SUCCEEDED(selected.factory->CreateBitmapScaler(&scaler)) &&
                SUCCEEDED(scaler->Initialize(
                    pixel_source.Get(),
                    fitted_width,
                    fitted_height,
                    WICBitmapInterpolationModeHighQualityCubic))) {
                pixel_source = scaler;
                output_width = fitted_width;
                output_height = fitted_height;
                output_stride = static_cast<std::uint64_t>(fitted_width) * bytes_per_pixel;
                output_bytes = output_stride * fitted_height;
                result.image.width = fitted_width;
                result.image.height = fitted_height;
                result.image.stride_bytes = static_cast<std::uint32_t>(output_stride);
            }
        }

        if (control.stop_token.stop_requested()) {
            result.status = WicTiffDecodeStatus::cancelled;
            return result;
        }

        // 스케일러에 원본 좌표 사각형을 잘라 넣으면 48bpp RGB(frame_1) 에서
        // CopyPixels 가 실패합니다. 축소본은 한 번에 받습니다.
        WicTiffDecodeControl row_control = control;
        if (scaler) {
            row_control.rows_per_copy = output_height;
        }
        result.status = copy_tiff_rows(
            pixel_source.Get(),
            output_stride,
            output_bytes,
            output_width,
            output_height,
            row_control,
            row_sink,
            sink_started,
            result);
        return result;
    } catch (const std::bad_alloc&) {
        discard_samples(result);
        result.status = WicTiffDecodeStatus::allocation_failed;
        complete_sink(result.status);
        return result;
    } catch (...) {
        discard_samples(result);
        result.status = WicTiffDecodeStatus::pixel_decode_failed;
        complete_sink(result.status);
        return result;
    }
}

}  // namespace

WicTiffDecodeResult decode_tiff_with_wic(
    const std::filesystem::path& path,
    const WicTiffDecodeLimits& limits,
    const WicTiffDecodeControl& control) noexcept {
    return decode_tiff_with_wic_impl(path, limits, control, nullptr);
}

WicTiffDecodeResult decode_tiff_rows_with_wic(
    const std::filesystem::path& path,
    WicTiffRowSink& sink,
    const WicTiffDecodeLimits& limits,
    const WicTiffDecodeControl& control) noexcept {
    return decode_tiff_with_wic_impl(path, limits, control, &sink);
}

const char* wic_tiff_decode_status_name(const WicTiffDecodeStatus status) noexcept {
    switch (status) {
        case WicTiffDecodeStatus::ok:
            return "ok";
        case WicTiffDecodeStatus::invalid_argument:
            return "invalid_argument";
        case WicTiffDecodeStatus::preflight_failed:
            return "tiff_preflight_failed";
        case WicTiffDecodeStatus::unsupported_layout:
            return "unsupported_tiff_layout";
        case WicTiffDecodeStatus::com_apartment_mismatch:
            return "com_apartment_mismatch";
        case WicTiffDecodeStatus::wic_unavailable:
            return "wic_unavailable";
        case WicTiffDecodeStatus::stream_open_failed:
            return "wic_stream_open_failed";
        case WicTiffDecodeStatus::decoder_initialization_failed:
            return "wic_decoder_initialization_failed";
        case WicTiffDecodeStatus::unexpected_decoder:
            return "unexpected_wic_decoder";
        case WicTiffDecodeStatus::frame_count_unsupported:
            return "unsupported_frame_count";
        case WicTiffDecodeStatus::dimension_mismatch:
            return "wic_dimension_mismatch";
        case WicTiffDecodeStatus::unsupported_pixel_format:
            return "unsupported_wic_pixel_format";
        case WicTiffDecodeStatus::color_context_failed:
            return "wic_color_context_failed";
        case WicTiffDecodeStatus::invalid_icc_profile:
            return "invalid_icc_profile";
        case WicTiffDecodeStatus::memory_limit_exceeded:
            return "decoded_pixel_memory_limit_exceeded";
        case WicTiffDecodeStatus::allocation_failed:
            return "decoded_pixel_allocation_failed";
        case WicTiffDecodeStatus::pixel_decode_failed:
            return "wic_pixel_decode_failed";
        case WicTiffDecodeStatus::row_sink_failed:
            return "wic_row_sink_failed";
        case WicTiffDecodeStatus::cancelled:
            return "cancelled";
    }
    return "unknown_wic_tiff_decode_status";
}

const char* wic_pixel_format_name(const WicPixelFormat format) noexcept {
    switch (format) {
        case WicPixelFormat::unknown:
            return "unknown";
        case WicPixelFormat::rgb16:
            return "48bpp_rgb";
        case WicPixelFormat::rgba16:
            return "64bpp_rgba";
        case WicPixelFormat::prgba16:
            return "64bpp_prgba";
        case WicPixelFormat::bgra16:
            return "64bpp_bgra";
        case WicPixelFormat::pbgra16:
            return "64bpp_pbgra";
        case WicPixelFormat::gray16:
            return "16bpp_gray";
    }
    return "unknown";
}

}  // namespace negaflow::imageio
