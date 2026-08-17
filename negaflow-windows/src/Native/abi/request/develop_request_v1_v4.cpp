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

namespace negaflow::abi::detail {

// v1–v4: 경로·필름·기본 톤·필름 스톡. map_base_request 템플릿은 이 번역 단위에만 있습니다.

void write_rejected_request(
    const char* const name,
    nf_develop_export_result_v1& result) noexcept {
    result.succeeded = 0U;
    result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
    copy_failure_name(name, result.failure_name);
}

// Shared by the publish and preview entry points so one set of enum mappings governs both.
// `require_destination` is false for a preview, which writes no file.
[[nodiscard]] bool map_request(
    const nf_develop_export_request_v1& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v1& result) noexcept {
    if (request.source_path == nullptr ||
        (require_destination && request.destination_path == nullptr)) {
        write_rejected_request("missing_path", result);
        return false;
    }
    if (!map_export_format(request.output_format, pipeline_request.format)) {
        write_rejected_request("unknown_export_format", result);
        return false;
    }
    if (!map_film_type(request.film_type, pipeline_request.negative.film_type)) {
        write_rejected_request("unknown_film_type", result);
        return false;
    }
    if (!map_source_kind(
            request.film_look_source_kind,
            pipeline_request.film_look.source_kind)) {
        write_rejected_request("unknown_film_look_source_kind", result);
        return false;
    }
    pipeline_request.film_polarity =
        pipeline_request.film_look.source_kind ==
                negaflow::imaging::DevelopSourceKind::rendered_digital
            ? negaflow::pipeline::FilmPolarity::positive
            : negaflow::pipeline::FilmPolarity::negative;
    if (!map_film_emulation(
            request.film_emulation,
            pipeline_request.film_look.emulation)) {
        write_rejected_request("unknown_film_emulation", result);
        return false;
    }

    // std::filesystem::path construction can throw on a pathological input, and an
    // exception must never cross the ABI boundary.
    try {
        pipeline_request.source = std::filesystem::path{request.source_path};
        if (request.destination_path != nullptr) {
            pipeline_request.destination =
                std::filesystem::path{request.destination_path};
        }
    } catch (...) {
        write_rejected_request("invalid_path", result);
        return false;
    }

    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        pipeline_request.negative.dmin[channel] = request.dmin[channel];
    }
    pipeline_request.tone.exposure_stops = request.exposure_stops;
    pipeline_request.tone.basic.contrast = request.contrast;
    pipeline_request.tone.curve.highlights = request.highlights;
    pipeline_request.tone.curve.lights = request.lights;
    pipeline_request.tone.curve.darks = request.darks;
    pipeline_request.tone.curve.shadows = request.shadows;
    pipeline_request.film_look.intensity = request.film_emulation_intensity;
    pipeline_request.rows_per_copy = request.rows_per_copy;
    return true;
}

template <typename Request>
[[nodiscard]] bool map_base_request(
    const Request& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (request.source_path == nullptr ||
        (require_destination && request.destination_path == nullptr)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("missing_path", result.failure_name);
        return false;
    }
    if (!map_export_format(request.output_format, pipeline_request.format)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("unknown_export_format", result.failure_name);
        return false;
    }
    if (!map_film_type(request.film_type, pipeline_request.negative.film_type)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("unknown_film_type", result.failure_name);
        return false;
    }
    if (!map_base_estimation_mode(
            request.base_estimation_mode,
            pipeline_request.base_estimation_mode)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("unknown_base_estimation_mode", result.failure_name);
        return false;
    }
    if (!map_source_kind(
            request.film_look_source_kind,
            pipeline_request.film_look.source_kind)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("unknown_film_look_source_kind", result.failure_name);
        return false;
    }
    pipeline_request.film_polarity =
        pipeline_request.film_look.source_kind ==
                negaflow::imaging::DevelopSourceKind::rendered_digital
            ? negaflow::pipeline::FilmPolarity::positive
            : negaflow::pipeline::FilmPolarity::negative;
    if (!map_film_emulation(
            request.film_emulation,
            pipeline_request.film_look.emulation)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("unknown_film_emulation", result.failure_name);
        return false;
    }
    try {
        pipeline_request.source = std::filesystem::path{request.source_path};
        if (request.destination_path != nullptr) {
            pipeline_request.destination = std::filesystem::path{request.destination_path};
        }
    } catch (...) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("invalid_path", result.failure_name);
        return false;
    }

    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        pipeline_request.negative.dmin[channel] = request.dmin[channel];
    }
    pipeline_request.tone.exposure_stops = request.exposure_stops;
    pipeline_request.tone.basic.contrast = request.contrast;
    pipeline_request.tone.curve.highlights = request.highlights;
    pipeline_request.tone.curve.lights = request.lights;
    pipeline_request.tone.curve.darks = request.darks;
    pipeline_request.tone.curve.shadows = request.shadows;
    pipeline_request.film_look.intensity = request.film_emulation_intensity;
    pipeline_request.rows_per_copy = request.rows_per_copy;
    return true;
}

[[nodiscard]] bool map_request_v2(
    const nf_develop_export_request_v2& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_base_request(request, require_destination, pipeline_request, result)) {
        return false;
    }
    if (pipeline_request.base_estimation_mode ==
        negaflow::pipeline::NegativeBaseEstimationMode::preset) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("unsupported_base_estimation_mode", result.failure_name);
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v3(
    const nf_develop_export_request_v3& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_base_request(request, require_destination, pipeline_request, result)) {
        return false;
    }
    if (pipeline_request.base_estimation_mode ==
        negaflow::pipeline::NegativeBaseEstimationMode::preset) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("unsupported_base_estimation_mode", result.failure_name);
        return false;
    }
    pipeline_request.tone.basic.density = request.density;
    pipeline_request.tone.basic.highlights = request.highlight;
    pipeline_request.tone.basic.shadows = request.shadow;
    pipeline_request.tone.basic.whites = request.whites;
    pipeline_request.tone.basic.blacks = request.blacks;
    return true;
}

[[nodiscard]] bool map_request_v4(
    const nf_develop_export_request_v4& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_base_request(request, require_destination, pipeline_request, result)) {
        return false;
    }
    pipeline_request.tone.basic.density = request.density;
    pipeline_request.tone.basic.highlights = request.highlight;
    pipeline_request.tone.basic.shadows = request.shadow;
    pipeline_request.tone.basic.whites = request.whites;
    pipeline_request.tone.basic.blacks = request.blacks;
    if (pipeline_request.base_estimation_mode !=
        negaflow::pipeline::NegativeBaseEstimationMode::preset) {
        return true;
    }
    if (request.film_stock_dmin_id == nullptr) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("missing_film_stock", result.failure_name);
        return false;
    }
    const std::wstring_view stock_id{request.film_stock_dmin_id};
    const std::wstring_view light_id = request.light_source_profile_id == nullptr
        ? std::wstring_view{}
        : std::wstring_view{request.light_source_profile_id};
    pipeline_request.film_stock_preset =
        negaflow::imaging::resolve_film_stock_base_preset(
            stock_id,
            light_id,
            pipeline_request.negative.film_type);
    if (!pipeline_request.film_stock_preset) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("unknown_film_stock_or_light", result.failure_name);
        return false;
    }
    return true;
}

}  // namespace negaflow::abi::detail
