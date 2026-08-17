#include "validate.h"

#include "export/support/outcome.h"

#include "negaflow/color/output_color_space.h"
#include "negaflow/imaging/bw_toning.h"
#include "negaflow/imaging/color_model.h"
#include "negaflow/imaging/film_scan_denoise.h"
#include "negaflow/imaging/grain_mend.h"
#include "negaflow/imaging/image_transform.h"
#include "negaflow/imaging/local_dodge_burn.h"
#include "negaflow/imaging/texture_stage.h"
#include "negaflow/imaging/working_film_look.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "negaflow/output/export_metadata.h"

#include <cmath>

namespace negaflow::pipeline::develop_export_detail {

std::optional<DevelopExportOutcome> validate_request(
    const DevelopExportRequest& request,
    const PreviewTarget* const preview,
    const DetectTarget* const detect) noexcept {
    if (request.source.empty() ||
        (preview == nullptr && detect == nullptr && request.destination.empty())) {
        return fail(DevelopExportStage::request_validation, "missing_path");
    }
    if (request.format != DevelopExportFormat::png16 &&
        request.format != DevelopExportFormat::tiff16 &&
        request.format != DevelopExportFormat::jpeg8) {
        return fail(DevelopExportStage::request_validation, "unknown_export_format");
    }
    if (!std::isfinite(request.jpeg_quality) || request.jpeg_quality < 0.0F ||
        request.jpeg_quality > 1.0F) {
        return fail(DevelopExportStage::request_validation, "invalid_jpeg_quality");
    }
    if (request.tiff_compression != negaflow::output::WicTiffCompression::none &&
        request.tiff_compression != negaflow::output::WicTiffCompression::lzw &&
        request.tiff_compression != negaflow::output::WicTiffCompression::deflate) {
        return fail(DevelopExportStage::request_validation, "invalid_tiff_compression");
    }
    if (request.output_bit_depth != 8U && request.output_bit_depth != 16U) {
        return fail(DevelopExportStage::request_validation, "invalid_output_bit_depth");
    }
    if (negaflow::color::output_color_space_name(request.output_color_space) == nullptr) {
        return fail(DevelopExportStage::request_validation, "invalid_output_color_space");
    }
    if (!negaflow::output::is_known_export_metadata_policy(
            static_cast<std::uint32_t>(request.metadata_policy))) {
        return fail(DevelopExportStage::request_validation, "invalid_metadata_policy");
    }
    // JPEG 은 아직 sRGB 만 게시합니다. 고른 것과 다른 공간의 파일을 조용히 내보내느니
    // 거부합니다 — 잘못 이름 붙은 색은 나중에 되돌릴 수 없습니다.
    if (request.format == DevelopExportFormat::jpeg8 &&
        request.output_color_space != negaflow::color::OutputColorSpace::srgb) {
        return fail(DevelopExportStage::request_validation, "jpeg_requires_srgb");
    }
    if (request.format == DevelopExportFormat::jpeg8 && request.preserve_alpha) {
        return fail(DevelopExportStage::request_validation, "jpeg_does_not_support_alpha");
    }
    if (request.film_polarity != FilmPolarity::negative &&
        request.film_polarity != FilmPolarity::positive) {
        return fail(DevelopExportStage::request_validation, "unknown_film_polarity");
    }
    if (request.film_polarity == FilmPolarity::negative &&
        request.film_look.source_kind !=
            negaflow::imaging::DevelopSourceKind::film_scan) {
        return fail(
            DevelopExportStage::request_validation,
            "negative_requires_film_scan_source");
    }
    if (request.rows_per_copy == 0U) {
        return fail(DevelopExportStage::request_validation, "invalid_rows_per_copy");
    }
    if (request.base_estimation_mode != NegativeBaseEstimationMode::manual &&
        request.base_estimation_mode != NegativeBaseEstimationMode::auto_estimate &&
        request.base_estimation_mode != NegativeBaseEstimationMode::preset) {
        return fail(DevelopExportStage::request_validation, "unsupported_base_estimation_mode");
    }
    if (request.base_estimation_mode == NegativeBaseEstimationMode::preset &&
        !request.film_stock_preset) {
        return fail(DevelopExportStage::request_validation, "unknown_film_stock");
    }
    if (!negaflow::imaging::valid_working_tone_adjust_parameters(request.tone)) {
        return fail(
            DevelopExportStage::request_validation,
            "invalid_tone_adjustment_parameter");
    }
    if (!negaflow::imaging::valid_color_model_parameters(request.color_model)) {
        return fail(
            DevelopExportStage::request_validation,
            "invalid_color_model_parameter");
    }
    if (!negaflow::imaging::valid_working_film_look_parameters(request.film_look)) {
        return fail(
            DevelopExportStage::request_validation, "invalid_film_look_parameters");
    }
    if (!negaflow::imaging::valid_grain_mend_parameters(request.grain_mend)) {
        return fail(
            DevelopExportStage::request_validation, "invalid_grain_mend_parameters");
    }
    if (!negaflow::imaging::valid_film_scan_denoise_parameters(
            request.film_scan_denoise)) {
        return fail(
            DevelopExportStage::request_validation,
            "invalid_film_scan_denoise_parameters");
    }
    if (!negaflow::imaging::valid_local_dodge_burn_parameters(
            request.local_dodge_burn)) {
        return fail(
            DevelopExportStage::request_validation,
            "invalid_local_dodge_burn_parameters");
    }
    if (!negaflow::imaging::valid_texture_stage_parameters(request.texture)) {
        return fail(
            DevelopExportStage::request_validation,
            "invalid_texture_parameters");
    }
    if (!negaflow::imaging::valid_bw_toning_parameters(request.bw_toning)) {
        return fail(
            DevelopExportStage::request_validation,
            "invalid_bw_toning_parameters");
    }
    if (!negaflow::imaging::valid_image_transform_parameters(
            request.image_transform)) {
        return fail(
            DevelopExportStage::request_validation,
            "invalid_image_transform_parameters");
    }
    if (!negaflow::imaging::valid_output_sharpening_parameters(
            request.output_sharpening)) {
        return fail(
            DevelopExportStage::request_validation,
            "invalid_output_sharpening_parameters");
    }
    return std::nullopt;
}

}  // namespace negaflow::pipeline::develop_export_detail
