#include "request/develop_request_map.h"

#include "support/abi_text.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <limits>
#include <new>
#include <string>
#include <string_view>
#include <vector>
#include <string>

namespace negaflow::abi::detail {

// v26–v34: 출력 샤픈·캘리브레이션·JPEG/TIFF·색공간·메타데이터·알파.

[[nodiscard]] bool map_request_v26(
    const nf_develop_export_request_v26& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (request.output_sharpening_reserved != 0U ||
        request.output_sharpening_medium > NF_OUTPUT_SHARPENING_GLOSSY_PAPER ||
        request.output_sharpening_dpi < 0 ||
        !std::isfinite(request.output_sharpening_strength) ||
        request.output_sharpening_strength < 0.0F ||
        request.output_sharpening_strength > 1.0F) {
        fail_defect_region_request(result, "invalid_output_sharpening_parameters");
        return false;
    }
    if (!map_request_v25(request.v25, require_destination, pipeline_request, result)) {
        return false;
    }
    pipeline_request.output_sharpening.strength = request.output_sharpening_strength;
    pipeline_request.output_sharpening.medium =
        static_cast<negaflow::imaging::OutputSharpeningMedium>(
            request.output_sharpening_medium);
    pipeline_request.output_sharpening.dpi = request.output_sharpening_dpi;
    return true;
}

[[nodiscard]] bool map_request_v27(
    const nf_develop_export_request_v27& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (request.primary_calibration_reserved0 != 0U ||
        request.primary_calibration_reserved1 != 0U) {
        fail_defect_region_request(result, "invalid_primary_calibration_parameters");
        return false;
    }
    if (!map_request_v26(request.v26, require_destination, pipeline_request, result)) {
        return false;
    }
    pipeline_request.tone.primary_calibration = {
        request.primary_calibration_red_hue,
        request.primary_calibration_red_saturation,
        request.primary_calibration_green_hue,
        request.primary_calibration_green_saturation,
        request.primary_calibration_blue_hue,
        request.primary_calibration_blue_saturation,
    };
    if (!negaflow::imaging::valid_primary_calibration_parameters(
            pipeline_request.tone.primary_calibration)) {
        fail_defect_region_request(result, "invalid_primary_calibration_parameters");
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v28(
    const nf_develop_export_request_v28& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (request.output_options_reserved0 != 0U || request.output_options_reserved1 != 0U ||
        !std::isfinite(request.jpeg_quality) || request.jpeg_quality < 0.0F ||
        request.jpeg_quality > 1.0F) {
        fail_defect_region_request(result, "invalid_output_options");
        return false;
    }
    if (!map_request_v27(request.v27, require_destination, pipeline_request, result)) {
        return false;
    }
    pipeline_request.jpeg_quality = request.jpeg_quality;
    pipeline_request.output_dpi = request.output_dpi;
    return true;
}

[[nodiscard]] bool map_request_v29(
    const nf_develop_export_request_v29& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (request.output_geometry_reserved0 != 0U ||
        request.output_geometry_reserved1 != 0U ||
        request.output_geometry_reserved2 != 0U) {
        fail_defect_region_request(result, "invalid_output_geometry");
        return false;
    }
    if (!map_request_v28(request.v28, require_destination, pipeline_request, result)) {
        return false;
    }
    pipeline_request.output_long_edge = request.output_long_edge;
    return true;
}

[[nodiscard]] bool map_request_v30(
    const nf_develop_export_request_v30& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (request.output_encoding_reserved0 != 0U ||
        request.output_encoding_reserved1 != 0U ||
        request.output_encoding_reserved2 != 0U ||
        request.tiff_compression > NF_TIFF_COMPRESSION_DEFLATE) {
        fail_defect_region_request(result, "invalid_output_encoding");
        return false;
    }
    if (!map_request_v29(request.v29, require_destination, pipeline_request, result)) {
        return false;
    }
    switch (request.tiff_compression) {
        case NF_TIFF_COMPRESSION_NONE:
            pipeline_request.tiff_compression =
                negaflow::output::WicTiffCompression::none;
            return true;
        case NF_TIFF_COMPRESSION_LZW:
            pipeline_request.tiff_compression =
                negaflow::output::WicTiffCompression::lzw;
            return true;
        case NF_TIFF_COMPRESSION_DEFLATE:
            pipeline_request.tiff_compression =
                negaflow::output::WicTiffCompression::deflate;
            return true;
    }
    fail_defect_region_request(result, "invalid_output_encoding");
    return false;
}

[[nodiscard]] bool map_request_v31(
    const nf_develop_export_request_v31& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (request.output_depth_reserved0 != 0U ||
        request.output_depth_reserved1 != 0U ||
        request.output_depth_reserved2 != 0U ||
        (request.output_bit_depth != 8U && request.output_bit_depth != 16U)) {
        fail_defect_region_request(result, "invalid_output_bit_depth");
        return false;
    }
    if (!map_request_v30(request.v30, require_destination, pipeline_request, result)) {
        return false;
    }
    pipeline_request.output_bit_depth = request.output_bit_depth;
    return true;
}

[[nodiscard]] bool map_request_v32(
    const nf_develop_export_request_v32& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (request.output_space_reserved0 != 0U ||
        request.output_space_reserved1 != 0U ||
        request.output_space_reserved2 != 0U ||
        request.output_color_space > 2U) {
        fail_defect_region_request(result, "invalid_output_color_space");
        return false;
    }
    if (!map_request_v31(request.v31, require_destination, pipeline_request, result)) {
        return false;
    }
    pipeline_request.output_color_space =
        static_cast<negaflow::color::OutputColorSpace>(request.output_color_space);
    return true;
}

/* 문자열은 선택이다. 널이면 빈 값으로 둔다 — 빈 태그를 쓰지 않기 위해서다. */
[[nodiscard]] std::wstring optional_text(const wchar_t* const value) {
    return value == nullptr ? std::wstring{} : std::wstring{value};
}

[[nodiscard]] bool map_request_v33(
    const nf_develop_export_request_v33& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (request.metadata_reserved0 != 0U ||
        request.metadata_reserved1 != 0U ||
        request.metadata_reserved2 != 0U ||
        !negaflow::output::is_known_export_metadata_policy(request.metadata_policy)) {
        fail_defect_region_request(result, "invalid_metadata_policy");
        return false;
    }
    if (!map_request_v32(request.v32, require_destination, pipeline_request, result)) {
        return false;
    }
    try {
        pipeline_request.metadata_policy =
            static_cast<negaflow::output::ExportMetadataPolicy>(request.metadata_policy);
        pipeline_request.metadata.make = optional_text(request.metadata_make);
        pipeline_request.metadata.model = optional_text(request.metadata_model);
        pipeline_request.metadata.software = optional_text(request.metadata_software);
        pipeline_request.metadata.artist = optional_text(request.metadata_artist);
        pipeline_request.metadata.copyright = optional_text(request.metadata_copyright);
        pipeline_request.metadata.film_type = optional_text(request.metadata_film_type);
        pipeline_request.metadata.film_stock = optional_text(request.metadata_film_stock);
        pipeline_request.metadata.captured_at = optional_text(request.metadata_captured_at);
        // 원본은 이미 요청에 있다. 정책이 원본 메타데이터를 실으라고 하면 여기서 읽는다 —
        // 호출측이 경로를 한 번 더 넘길 이유가 없으므로 ABI 는 그대로 둔다.
        pipeline_request.metadata.source_path = pipeline_request.source.wstring();
    } catch (const std::bad_alloc&) {
        fail_defect_region_request(result, "allocation_failed");
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v34(
    const nf_develop_export_request_v34& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (request.alpha_reserved0 != 0U || request.alpha_reserved1 != 0U ||
        request.alpha_reserved2 != 0U || request.preserve_alpha > 1U) {
        fail_defect_region_request(result, "invalid_preserve_alpha");
        return false;
    }
    if (!map_request_v33(request.v33, require_destination, pipeline_request, result)) {
        return false;
    }
    pipeline_request.preserve_alpha = request.preserve_alpha != 0U;
    return true;
}

}  // namespace negaflow::abi::detail
