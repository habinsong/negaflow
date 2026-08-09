#include "negaflow_abi.h"

#include "negaflow/core/build_info.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "negaflow/pipeline/develop_export.h"

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string_view>

static_assert(sizeof(nf_build_info_v1) == 44U);
static_assert(offsetof(nf_build_info_v1, source_commit_sha1) == 24U);

// The managed side declares the same layout by hand. A drift on either side would
// still bind and then read garbage, so the sizes and the two offsets that padding
// actually decides are pinned here.
static_assert(sizeof(nf_develop_export_request_v1) == 96U);
static_assert(offsetof(nf_develop_export_request_v1, film_emulation_intensity) == 80U);
static_assert(sizeof(nf_develop_export_request_v2) == 96U);
static_assert(offsetof(nf_develop_export_request_v2, base_estimation_mode) == 32U);
static_assert(offsetof(nf_develop_export_request_v2, film_emulation_intensity) == 80U);
static_assert(sizeof(nf_develop_export_request_v3) == 112U);
static_assert(offsetof(nf_develop_export_request_v3, base_estimation_mode) == 32U);
static_assert(offsetof(nf_develop_export_request_v3, density) == 92U);
static_assert(sizeof(nf_develop_export_request_v4) == 128U);
static_assert(offsetof(nf_develop_export_request_v4, density) == 92U);
static_assert(offsetof(nf_develop_export_request_v4, film_stock_dmin_id) == 112U);
static_assert(sizeof(nf_point_curve_point_v1) == 16U);
static_assert(sizeof(nf_point_curve_v1) == 1032U);
static_assert(offsetof(nf_point_curve_v1, points) == 8U);
static_assert(sizeof(nf_develop_export_request_v5) == 4256U);
static_assert(offsetof(nf_develop_export_request_v5, point_curve_rgb) == 128U);
static_assert(sizeof(nf_develop_export_request_v6) == 4352U);
static_assert(offsetof(nf_develop_export_request_v6, color_mixer_hue) == 4256U);
static_assert(sizeof(nf_develop_export_request_v7) == 4400U);
static_assert(offsetof(nf_develop_export_request_v7, color_grading_shadows_hue) == 4352U);
static_assert(sizeof(nf_develop_export_result_v1) == 136U);
static_assert(offsetof(nf_develop_export_result_v1, failure_name) == 12U);
static_assert(offsetof(nf_develop_export_result_v1, source_file_bytes) == 104U);
static_assert(sizeof(nf_develop_export_result_v2) == 152U);
static_assert(offsetof(nf_develop_export_result_v2, applied_dmin) == 136U);

namespace {

[[nodiscard]] std::uint8_t decode_hex_nibble(const char value) noexcept {
    if (value >= '0' && value <= '9') {
        return static_cast<std::uint8_t>(value - '0');
    }
    if (value >= 'a' && value <= 'f') {
        return static_cast<std::uint8_t>(value - 'a' + 10);
    }
    if (value >= 'A' && value <= 'F') {
        return static_cast<std::uint8_t>(value - 'A' + 10);
    }
    return 0xFFU;
}

void decode_source_commit(
    const std::string_view source_commit,
    std::uint8_t (&destination)[20]) noexcept {
    if (source_commit.size() != 40U) {
        return;
    }

    for (std::size_t index = 0; index < 20U; ++index) {
        const std::uint8_t high = decode_hex_nibble(source_commit[index * 2U]);
        const std::uint8_t low = decode_hex_nibble(source_commit[(index * 2U) + 1U]);
        if (high == 0xFFU || low == 0xFFU) {
            std::memset(destination, 0, 20U);
            return;
        }
        destination[index] = static_cast<std::uint8_t>((high << 4U) | low);
    }
}

void copy_failure_name(
    const char* const source,
    char (&destination)[NF_FAILURE_NAME_CAPACITY]) noexcept {
    std::memset(destination, 0, NF_FAILURE_NAME_CAPACITY);
    if (source == nullptr) {
        return;
    }
    std::size_t index = 0U;
    while (index + 1U < NF_FAILURE_NAME_CAPACITY && source[index] != '\0') {
        destination[index] = source[index];
        ++index;
    }
}

[[nodiscard]] bool map_export_format(
    const std::uint32_t value,
    negaflow::pipeline::DevelopExportFormat& format) noexcept {
    switch (value) {
        case NF_EXPORT_FORMAT_PNG16:
            format = negaflow::pipeline::DevelopExportFormat::png16;
            return true;
        case NF_EXPORT_FORMAT_TIFF16:
            format = negaflow::pipeline::DevelopExportFormat::tiff16;
            return true;
        default:
            return false;
    }
}

[[nodiscard]] bool map_film_type(
    const std::uint32_t value,
    negaflow::imaging::NegativeFilmType& film_type) noexcept {
    switch (value) {
        case NF_FILM_TYPE_COLOR:
            film_type = negaflow::imaging::NegativeFilmType::color;
            return true;
        case NF_FILM_TYPE_BLACK_AND_WHITE:
            film_type = negaflow::imaging::NegativeFilmType::black_and_white;
            return true;
        default:
            return false;
    }
}

[[nodiscard]] bool map_source_kind(
    const std::uint32_t value,
    negaflow::imaging::DevelopSourceKind& source_kind) noexcept {
    switch (value) {
        case NF_DEVELOP_SOURCE_FILM_SCAN:
            source_kind = negaflow::imaging::DevelopSourceKind::film_scan;
            return true;
        case NF_DEVELOP_SOURCE_RENDERED_DIGITAL:
            source_kind = negaflow::imaging::DevelopSourceKind::rendered_digital;
            return true;
        default:
            return false;
    }
}

[[nodiscard]] bool map_base_estimation_mode(
    const std::uint32_t value,
    negaflow::pipeline::NegativeBaseEstimationMode& mode) noexcept {
    switch (value) {
        case NF_BASE_ESTIMATION_AUTO:
            mode = negaflow::pipeline::NegativeBaseEstimationMode::auto_estimate;
            return true;
        case NF_BASE_ESTIMATION_PRESET:
            mode = negaflow::pipeline::NegativeBaseEstimationMode::preset;
            return true;
        case NF_BASE_ESTIMATION_MANUAL:
            mode = negaflow::pipeline::NegativeBaseEstimationMode::manual;
            return true;
        default:
            return false;
    }
}

// Explicit rather than a cast, so adding a profile on either side cannot silently
// shift what an existing catalog value means.
[[nodiscard]] bool map_film_emulation(
    const std::uint32_t value,
    negaflow::imaging::FilmEmulation& emulation) noexcept {
    using negaflow::imaging::FilmEmulation;
    switch (value) {
        case 0U: emulation = FilmEmulation::none; return true;
        case 1U: emulation = FilmEmulation::ektachrome_e100; return true;
        case 2U: emulation = FilmEmulation::provia_100f; return true;
        case 3U: emulation = FilmEmulation::velvia_50; return true;
        case 4U: emulation = FilmEmulation::portra_160; return true;
        case 5U: emulation = FilmEmulation::portra_400; return true;
        case 6U: emulation = FilmEmulation::portra_800; return true;
        case 7U: emulation = FilmEmulation::ektar_100; return true;
        case 8U: emulation = FilmEmulation::ultramax_400; return true;
        case 9U: emulation = FilmEmulation::colorplus_200; return true;
        case 10U: emulation = FilmEmulation::fujicolor_c200; return true;
        case 11U: emulation = FilmEmulation::pro_400h; return true;
        default: return false;
    }
}

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

[[nodiscard]] bool map_point_curve(
    const nf_point_curve_v1& source,
    negaflow::imaging::PointCurve& destination) noexcept {
    if (source.reserved != 0U || source.point_count > NF_POINT_CURVE_MAX_POINTS) {
        return false;
    }
    destination.point_count = source.point_count;
    for (std::size_t index = 0U; index < source.point_count; ++index) {
        destination.points[index] = {source.points[index].x, source.points[index].y};
    }
    return true;
}

[[nodiscard]] bool map_request_v5(
    const nf_develop_export_request_v5& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    nf_develop_export_request_v4 prefix{};
    std::memcpy(&prefix, &request, sizeof(prefix));
    if (!map_request_v4(prefix, require_destination, pipeline_request, result)) {
        return false;
    }
    if (!map_point_curve(request.point_curve_rgb, pipeline_request.tone.point_curves.rgb) ||
        !map_point_curve(request.point_curve_red, pipeline_request.tone.point_curves.red) ||
        !map_point_curve(request.point_curve_green, pipeline_request.tone.point_curves.green) ||
        !map_point_curve(request.point_curve_blue, pipeline_request.tone.point_curves.blue) ||
        !negaflow::imaging::valid_point_curves(pipeline_request.tone.point_curves)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("invalid_point_curves", result.failure_name);
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v6(
    const nf_develop_export_request_v6& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    nf_develop_export_request_v5 prefix{};
    std::memcpy(&prefix, &request, sizeof(prefix));
    if (!map_request_v5(prefix, require_destination, pipeline_request, result)) {
        return false;
    }
    for (std::size_t index = 0U; index < 8U; ++index) {
        pipeline_request.tone.color_mixer.hue[index] = request.color_mixer_hue[index];
        pipeline_request.tone.color_mixer.saturation[index] = request.color_mixer_saturation[index];
        pipeline_request.tone.color_mixer.luminance[index] = request.color_mixer_luminance[index];
    }
    if (!negaflow::imaging::valid_color_mixer_parameters(pipeline_request.tone.color_mixer)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("invalid_color_mixer", result.failure_name);
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v7(
    const nf_develop_export_request_v7& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    nf_develop_export_request_v6 prefix{};
    std::memcpy(&prefix, &request, sizeof(prefix));
    if (!map_request_v6(prefix, require_destination, pipeline_request, result)) {
        return false;
    }
    pipeline_request.tone.color_grading.shadows = {
        request.color_grading_shadows_hue,
        request.color_grading_shadows_saturation,
        request.color_grading_shadows_luminance};
    pipeline_request.tone.color_grading.midtones = {
        request.color_grading_midtones_hue,
        request.color_grading_midtones_saturation,
        request.color_grading_midtones_luminance};
    pipeline_request.tone.color_grading.highlights = {
        request.color_grading_highlights_hue,
        request.color_grading_highlights_saturation,
        request.color_grading_highlights_luminance};
    pipeline_request.tone.color_grading.blending = request.color_grading_blending;
    pipeline_request.tone.color_grading.balance = request.color_grading_balance;
    if (!negaflow::imaging::valid_color_grading_parameters(pipeline_request.tone.color_grading)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("invalid_color_grading", result.failure_name);
        return false;
    }
    return true;
}

[[nodiscard]] std::uint64_t elapsed_microseconds(
    const std::chrono::steady_clock::time_point started,
    const std::chrono::steady_clock::time_point finished) noexcept {
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(finished - started).count());
}

void write_outcome(
    const negaflow::pipeline::DevelopExportOutcome& outcome,
    const std::uint64_t wall_microseconds,
    nf_develop_export_result_v1& result) noexcept {
    result.succeeded = outcome.succeeded ? 1U : 0U;
    result.failed_stage = static_cast<std::uint32_t>(outcome.failed_stage);
    copy_failure_name(outcome.failure_name, result.failure_name);
    result.native_error_code = outcome.native_error_code;
    result.cleanup_error_code = outcome.cleanup_error_code;
    result.image_width = outcome.image_width;
    result.image_height = outcome.image_height;
    result.film_look_route = static_cast<std::uint32_t>(outcome.film_look_route);
    result.film_look_color_applied = outcome.film_look_color_applied ? 1U : 0U;
    result.film_look_acutance_applied = outcome.film_look_acutance_applied ? 1U : 0U;
    result.source_file_bytes = outcome.source_file_bytes;
    result.output_file_bytes = outcome.output_file_bytes;
    result.film_look_workspace_bytes =
        static_cast<std::uint64_t>(outcome.film_look_workspace_bytes);
    result.wall_microseconds = wall_microseconds;
}

void write_outcome_v2(
    const negaflow::pipeline::DevelopExportOutcome& outcome,
    const std::uint64_t wall_microseconds,
    nf_develop_export_result_v2& result) noexcept {
    result.succeeded = outcome.succeeded ? 1U : 0U;
    result.failed_stage = static_cast<std::uint32_t>(outcome.failed_stage);
    copy_failure_name(outcome.failure_name, result.failure_name);
    result.native_error_code = outcome.native_error_code;
    result.cleanup_error_code = outcome.cleanup_error_code;
    result.image_width = outcome.image_width;
    result.image_height = outcome.image_height;
    result.film_look_route = static_cast<std::uint32_t>(outcome.film_look_route);
    result.film_look_color_applied = outcome.film_look_color_applied ? 1U : 0U;
    result.film_look_acutance_applied = outcome.film_look_acutance_applied ? 1U : 0U;
    result.source_file_bytes = outcome.source_file_bytes;
    result.output_file_bytes = outcome.output_file_bytes;
    result.film_look_workspace_bytes =
        static_cast<std::uint64_t>(outcome.film_look_workspace_bytes);
    result.wall_microseconds = wall_microseconds;
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        result.applied_dmin[channel] = outcome.applied_dmin[channel];
    }
    switch (outcome.base_source) {
        case negaflow::pipeline::DevelopBaseSource::manual:
            result.base_source = NF_DEVELOP_BASE_SOURCE_MANUAL;
            break;
        case negaflow::pipeline::DevelopBaseSource::auto_scene_edge:
            result.base_source = NF_DEVELOP_BASE_SOURCE_AUTO_SCENE_EDGE;
            break;
        case negaflow::pipeline::DevelopBaseSource::auto_fallback:
            result.base_source = NF_DEVELOP_BASE_SOURCE_AUTO_FALLBACK;
            break;
        case negaflow::pipeline::DevelopBaseSource::auto_connected_component:
            result.base_source = NF_DEVELOP_BASE_SOURCE_AUTO_CONNECTED_COMPONENT;
            break;
        case negaflow::pipeline::DevelopBaseSource::auto_continuous_border:
            result.base_source = NF_DEVELOP_BASE_SOURCE_AUTO_CONTINUOUS_BORDER;
            break;
        case negaflow::pipeline::DevelopBaseSource::auto_distributed_mask:
            result.base_source = NF_DEVELOP_BASE_SOURCE_AUTO_DISTRIBUTED_MASK;
            break;
        case negaflow::pipeline::DevelopBaseSource::auto_strip_fallback:
            result.base_source = NF_DEVELOP_BASE_SOURCE_AUTO_STRIP_FALLBACK;
            break;
        case negaflow::pipeline::DevelopBaseSource::preset_measured:
            result.base_source = NF_DEVELOP_BASE_SOURCE_PRESET_MEASURED;
            break;
        case negaflow::pipeline::DevelopBaseSource::preset_fallback:
            result.base_source = NF_DEVELOP_BASE_SOURCE_PRESET_FALLBACK;
            break;
    }
}

[[nodiscard]] bool prepare_result(
    const nf_develop_export_request_v1* const request,
    nf_develop_export_result_v1* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

[[nodiscard]] bool prepare_result_v2(
    const nf_develop_export_request_v2* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

[[nodiscard]] bool prepare_result_v3(
    const nf_develop_export_request_v3* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

[[nodiscard]] bool prepare_result_v4(
    const nf_develop_export_request_v4* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

[[nodiscard]] bool prepare_result_v5(
    const nf_develop_export_request_v5* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

[[nodiscard]] bool prepare_result_v6(
    const nf_develop_export_request_v6* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }
    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

[[nodiscard]] bool prepare_result_v7(
    const nf_develop_export_request_v7* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }
    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);
    status = NF_STATUS_OK;
    return true;
}

}  // namespace

uint32_t NF_CALL nf_get_abi_version(void) {
    return NF_ABI_VERSION;
}

nf_status_t NF_CALL nf_get_build_info_v1(nf_build_info_v1* const output) {
    if (output == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (output->struct_size < static_cast<std::uint32_t>(sizeof(nf_build_info_v1))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }

    const negaflow::core::BuildInfo source = negaflow::core::query_build_info();
    nf_build_info_v1 result{};
    result.struct_size = static_cast<std::uint32_t>(sizeof(nf_build_info_v1));
    result.abi_version = NF_ABI_VERSION;
    result.architecture = static_cast<std::uint32_t>(source.architecture);
    result.cpu_feature_flags = source.cpu_features;
    result.compiler_id = NF_COMPILER_MSVC;
    result.compiler_version = source.compiler_version;
    decode_source_commit(source.source_commit, result.source_commit_sha1);

    std::memcpy(output, &result, sizeof(result));
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v1(
    const nf_develop_export_request_v1* const request,
    nf_develop_export_result_v1* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result(request, result, status)) {
        return status;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }

    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v2(
    const nf_develop_export_request_v2* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v2(request, result, status)) {
        return status;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v2(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }

    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v3(
    const nf_develop_export_request_v3* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v3(request, result, status)) {
        return status;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v3(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }

    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v4(
    const nf_develop_export_request_v4* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v4(request, result, status)) {
        return status;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v4(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }

    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v5(
    const nf_develop_export_request_v5* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v5(request, result, status)) {
        return status;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v5(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }

    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v6(
    const nf_develop_export_request_v6* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v6(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v6(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v7(
    const nf_develop_export_request_v7* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v7(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v7(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v1(
    const nf_develop_export_request_v1* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v1* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }

    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v2(
    const nf_develop_export_request_v2* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v2(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v2(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }

    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v3(
    const nf_develop_export_request_v3* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v3(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v3(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }

    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v4(
    const nf_develop_export_request_v4* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v4(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v4(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }

    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v5(
    const nf_develop_export_request_v5* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v5(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v5(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }

    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v6(
    const nf_develop_export_request_v6* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v6(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v6(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v7(
    const nf_develop_export_request_v7* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v7(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v7(*request, false, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes));
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_get_tone_limits_v1(nf_tone_limits_v1* const output) {
    if (output == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (output->struct_size < static_cast<std::uint32_t>(sizeof(*output))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }

    const std::uint32_t declared_size = output->struct_size;
    output->maximum_exposure_stops = negaflow::imaging::maximum_exposure_stops;
    output->maximum_tone_control = negaflow::imaging::maximum_tone_control;
    output->minimum_film_emulation_intensity = 0.0;
    output->maximum_film_emulation_intensity = 1.0;
    output->struct_size = declared_size;
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_get_negative_limits_v1(nf_negative_limits_v1* const output) {
    if (output == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (output->struct_size < static_cast<std::uint32_t>(sizeof(*output))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }

    const std::uint32_t declared_size = output->struct_size;
    output->minimum_manual_dmin = negaflow::imaging::minimum_manual_dmin;
    output->maximum_manual_dmin = negaflow::imaging::maximum_manual_dmin;
    output->struct_size = declared_size;
    return NF_STATUS_OK;
}
