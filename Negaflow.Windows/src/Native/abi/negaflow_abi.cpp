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
static_assert(sizeof(nf_develop_export_result_v1) == 136U);
static_assert(offsetof(nf_develop_export_result_v1, failure_name) == 12U);
static_assert(offsetof(nf_develop_export_result_v1, source_file_bytes) == 104U);

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
    if (request == nullptr || result == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (request->struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }

    const std::uint32_t result_struct_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = result_struct_size;
    result->failed_stage = NF_DEVELOP_STAGE_NONE;
    copy_failure_name("ok", result->failure_name);

    if (request->source_path == nullptr || request->destination_path == nullptr) {
        write_rejected_request("missing_path", *result);
        return NF_STATUS_OK;
    }

    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_export_format(request->output_format, pipeline_request.format)) {
        write_rejected_request("unknown_export_format", *result);
        return NF_STATUS_OK;
    }
    if (!map_film_type(request->film_type, pipeline_request.negative.film_type)) {
        write_rejected_request("unknown_film_type", *result);
        return NF_STATUS_OK;
    }
    if (!map_source_kind(
            request->film_look_source_kind,
            pipeline_request.film_look.source_kind)) {
        write_rejected_request("unknown_film_look_source_kind", *result);
        return NF_STATUS_OK;
    }
    if (!map_film_emulation(
            request->film_emulation,
            pipeline_request.film_look.emulation)) {
        write_rejected_request("unknown_film_emulation", *result);
        return NF_STATUS_OK;
    }

    // std::filesystem::path construction can throw on a pathological input, and an
    // exception must never cross the ABI boundary.
    try {
        pipeline_request.source = std::filesystem::path{request->source_path};
        pipeline_request.destination =
            std::filesystem::path{request->destination_path};
    } catch (...) {
        write_rejected_request("invalid_path", *result);
        return NF_STATUS_OK;
    }

    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        pipeline_request.negative.dmin[channel] = request->dmin[channel];
    }
    pipeline_request.tone.exposure_stops = request->exposure_stops;
    pipeline_request.tone.basic.contrast = request->contrast;
    pipeline_request.tone.curve.highlights = request->highlights;
    pipeline_request.tone.curve.lights = request->lights;
    pipeline_request.tone.curve.darks = request->darks;
    pipeline_request.tone.curve.shadows = request->shadows;
    pipeline_request.film_look.intensity = request->film_emulation_intensity;
    pipeline_request.rows_per_copy = request->rows_per_copy;

    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();

    result->succeeded = outcome.succeeded ? 1U : 0U;
    result->failed_stage = static_cast<std::uint32_t>(outcome.failed_stage);
    copy_failure_name(outcome.failure_name, result->failure_name);
    result->native_error_code = outcome.native_error_code;
    result->cleanup_error_code = outcome.cleanup_error_code;
    result->image_width = outcome.image_width;
    result->image_height = outcome.image_height;
    result->film_look_route = static_cast<std::uint32_t>(outcome.film_look_route);
    result->film_look_color_applied = outcome.film_look_color_applied ? 1U : 0U;
    result->film_look_acutance_applied = outcome.film_look_acutance_applied ? 1U : 0U;
    result->source_file_bytes = outcome.source_file_bytes;
    result->output_file_bytes = outcome.output_file_bytes;
    result->film_look_workspace_bytes =
        static_cast<std::uint64_t>(outcome.film_look_workspace_bytes);
    result->wall_microseconds = static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(finished - started)
            .count());
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
