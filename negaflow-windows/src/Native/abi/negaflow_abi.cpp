#include "negaflow_abi.h"

#include "negaflow/color/soft_proof.h"
#include "negaflow/core/build_info.h"
#include "negaflow/core/tiff_probe.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "negaflow/imaging/auto_adjust.h"
#include "negaflow/imaging/infrared_defect_detector.h"
#include "negaflow/imaging/flatbed_frame_grid_detector.h"
#include "negaflow/imageio/wic_tiff_decoder.h"
#include "negaflow/pipeline/develop_export.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <limits>
#include <new>
#include <span>
#include <string_view>
#include <vector>

struct nf_infrared_detection_handle_v1 final {
    negaflow::imaging::InfraredDetection detection{};
};

struct nf_flatbed_frame_grid_handle_v1 final {
    std::vector<negaflow::imaging::FlatbedFrameDetection> detections{};
};

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
static_assert(sizeof(nf_develop_export_request_v8) == 4408U);
static_assert(offsetof(nf_develop_export_request_v8, defect_removal_strength) == 4400U);
static_assert(sizeof(nf_develop_export_request_v9) == 4440U);
static_assert(offsetof(nf_develop_export_request_v9, noise_reduction_strength) == 4408U);
static_assert(offsetof(nf_develop_export_request_v9, noise_reduction_film_profile) == 4432U);
static_assert(sizeof(nf_develop_export_request_v10) == 4464U);
static_assert(offsetof(nf_develop_export_request_v10, texture_grain) == 4440U);
static_assert(offsetof(nf_develop_export_request_v10, texture_vignette) == 4456U);
static_assert(sizeof(nf_develop_export_request_v11) == 4552U);
static_assert(offsetof(nf_develop_export_request_v11, bw_toning_mode) == 4464U);
static_assert(offsetof(nf_develop_export_request_v11, straighten_angle) == 4544U);
static_assert(sizeof(nf_local_dodge_burn_point_v1) == 8U);
static_assert(sizeof(nf_local_dodge_burn_stroke_v1) == 16U);
static_assert(sizeof(nf_local_dodge_burn_adjustment_v1) == 64U);
static_assert(sizeof(nf_develop_export_request_v12) == 4600U);
static_assert(offsetof(nf_develop_export_request_v12, local_adjustments) == 4552U);
static_assert(offsetof(nf_develop_export_request_v12, local_strokes) == 4568U);
static_assert(offsetof(nf_develop_export_request_v12, local_points) == 4584U);
static_assert(sizeof(nf_develop_export_request_v13) == 4632U);
static_assert(offsetof(nf_develop_export_request_v13, warmth) == 4600U);
static_assert(offsetof(nf_develop_export_request_v13, blue_primary) == 4628U);
static_assert(sizeof(nf_develop_export_request_v14) == 4640U);
static_assert(offsetof(nf_develop_export_request_v14, auto_levels) == 4632U);
static_assert(offsetof(nf_develop_export_request_v14, auto_neutral_balance) == 4636U);
static_assert(sizeof(nf_develop_export_request_v15) == 4648U);
static_assert(offsetof(nf_develop_export_request_v15, develop_target) == 4640U);
static_assert(offsetof(nf_develop_export_request_v15, reserved) == 4644U);
static_assert(sizeof(nf_develop_export_request_v16) == 4656U);
static_assert(offsetof(nf_develop_export_request_v16, scanner_profile_id) == 4648U);
static_assert(sizeof(nf_develop_export_request_v17) == 4664U);
static_assert(offsetof(nf_develop_export_request_v17, film_polarity) == 4656U);
static_assert(sizeof(nf_defect_region_edit_v1) == 56U);
static_assert(offsetof(nf_defect_region_edit_v1, strength) == 32U);
static_assert(offsetof(nf_defect_region_edit_v1, preferred_angle_degrees) == 48U);
static_assert(sizeof(nf_develop_export_request_v18) == 4696U);
static_assert(offsetof(nf_develop_export_request_v18, defect_region_edits) == 4664U);
static_assert(offsetof(nf_develop_export_request_v18, defect_mask_bytes) == 4680U);
static_assert(sizeof(nf_develop_export_request_v19) == 4720U);
static_assert(offsetof(nf_develop_export_request_v19, defect_source_file_bytes) == 4696U);
static_assert(offsetof(nf_develop_export_request_v19, defect_source_sha256) == 4704U);
static_assert(sizeof(nf_defect_clone_point_v1) == 16U);
static_assert(sizeof(nf_defect_clone_stroke_v1) == 40U);
static_assert(offsetof(nf_defect_clone_stroke_v1, offset_x) == 8U);
static_assert(sizeof(nf_defect_clone_edit_v1) == 24U);
static_assert(offsetof(nf_defect_clone_edit_v1, strength) == 16U);
static_assert(sizeof(nf_defect_recipe_edit_ref_v1) == 8U);
static_assert(sizeof(nf_develop_export_request_v20) == 4784U);
static_assert(offsetof(nf_develop_export_request_v20, defect_clone_edits) == 4720U);
static_assert(offsetof(nf_develop_export_request_v20, defect_clone_strokes) == 4736U);
static_assert(offsetof(nf_develop_export_request_v20, defect_clone_points) == 4752U);
static_assert(offsetof(nf_develop_export_request_v20, defect_edit_order) == 4768U);
static_assert(sizeof(nf_defect_brush_point_v1) == 16U);
static_assert(sizeof(nf_defect_brush_stroke_v1) == 16U);
static_assert(offsetof(nf_defect_brush_stroke_v1, thickness) == 8U);
static_assert(sizeof(nf_defect_brush_edit_v1) == 24U);
static_assert(offsetof(nf_defect_brush_edit_v1, strength) == 16U);
static_assert(sizeof(nf_develop_export_request_v21) == 4832U);
static_assert(offsetof(nf_develop_export_request_v21, defect_brush_edits) == 4784U);
static_assert(offsetof(nf_develop_export_request_v21, defect_brush_strokes) == 4800U);
static_assert(offsetof(nf_develop_export_request_v21, defect_brush_points) == 4816U);
static_assert(sizeof(nf_defect_infrared_edit_v1) == 24U);
static_assert(offsetof(nf_defect_infrared_edit_v1, attenuation_offset) == 12U);
static_assert(sizeof(nf_develop_export_request_v24) == 4864U);
static_assert(offsetof(nf_develop_export_request_v24, defect_infrared_edits) == 4832U);
static_assert(offsetof(
                  nf_develop_export_request_v24,
                  defect_infrared_attenuation_bytes) == 4848U);
static_assert(sizeof(nf_defect_infrared_item_v1) == 16U);
static_assert(sizeof(nf_develop_export_request_v25) == 4880U);
static_assert(offsetof(
                  nf_develop_export_request_v25,
                  defect_infrared_items) == 4864U);
static_assert(sizeof(nf_develop_export_request_v26) == 4896U);
static_assert(offsetof(
                  nf_develop_export_request_v26,
                  output_sharpening_strength) == 4880U);
static_assert(sizeof(nf_develop_export_result_v1) == 136U);
static_assert(offsetof(nf_develop_export_result_v1, failure_name) == 12U);
static_assert(offsetof(nf_develop_export_result_v1, source_file_bytes) == 104U);
static_assert(sizeof(nf_develop_export_result_v2) == 152U);
static_assert(offsetof(nf_develop_export_result_v2, applied_dmin) == 136U);
// v3 has to keep the v2 prefix byte for byte; only then is the appended cancellation
// answer a pure addition rather than a silent reinterpretation of an existing field.
static_assert(sizeof(nf_develop_export_result_v3) == 160U);
static_assert(offsetof(nf_develop_export_result_v3, failure_name) == 12U);
static_assert(offsetof(nf_develop_export_result_v3, source_file_bytes) == 104U);
static_assert(offsetof(nf_develop_export_result_v3, applied_dmin) == 136U);
static_assert(offsetof(nf_develop_export_result_v3, base_source) == 148U);
static_assert(offsetof(nf_develop_export_result_v3, cancelled) == 152U);
static_assert(sizeof(nf_develop_run_state_v1) == 16U);
static_assert(sizeof(nf_soft_proof_media_v1) == 40U);
static_assert(offsetof(nf_soft_proof_media_v1, paper_white_rgb) == 16U);
static_assert(offsetof(nf_soft_proof_media_v1, black_ink_rgb) == 28U);
static_assert(sizeof(nf_soft_proof_v1) == 40U);
static_assert(offsetof(nf_soft_proof_v1, paper_white_rgb) == 16U);
static_assert(offsetof(nf_soft_proof_v1, black_ink_rgb) == 28U);
static_assert(sizeof(nf_auto_adjust_result_v1) == 88U);
static_assert(offsetof(nf_auto_adjust_result_v1, exposure) == 8U);
static_assert(offsetof(nf_auto_adjust_result_v1, warmth) == 72U);
static_assert(offsetof(nf_auto_adjust_result_v1, tint) == 80U);
static_assert(sizeof(nf_infrared_detector_parameters_v1) == 48U);
static_assert(offsetof(nf_infrared_detector_parameters_v1, maximum_coverage) == 16U);
static_assert(sizeof(nf_infrared_detection_summary_v1) == 112U);
static_assert(offsetof(nf_infrared_detection_summary_v1, coverage) == 48U);
static_assert(offsetof(nf_infrared_detection_summary_v1, candidate_count) == 80U);
static_assert(sizeof(nf_infrared_cluster_v1) == 40U);
static_assert(offsetof(nf_infrared_cluster_v1, core_mask_byte_count) == 24U);
static_assert(sizeof(nf_infrared_component_v1) == 32U);
static_assert(sizeof(nf_infrared_preview_point_v1) == 8U);
static_assert(sizeof(nf_flatbed_frame_grid_summary_v1) == 24U);
static_assert(sizeof(nf_flatbed_frame_detection_v1) == 56U);
static_assert(offsetof(nf_flatbed_frame_detection_v1, x) == 16U);
static_assert(sizeof(nf_tiff_source_info_v1) == 32U);
static_assert(offsetof(nf_tiff_source_info_v1, file_bytes) == 24U);
static_assert(offsetof(nf_develop_run_state_v1, cancel_requested) == 4U);
static_assert(offsetof(nf_develop_run_state_v1, stage) == 8U);
static_assert(offsetof(nf_develop_run_state_v1, progress_permille) == 12U);

namespace {

class InfraredPlaneSink final : public negaflow::imageio::WicTiffRowSink {
public:
    InfraredPlaneSink(
        const bool allow_gray,
        const negaflow::core::CancelFlag cancel) noexcept
        : allow_gray_(allow_gray), cancel_(cancel) {}

    bool begin(const negaflow::imageio::WicTiffFrameView& frame) noexcept override {
        try {
            const bool valid_layout =
                frame.layout == negaflow::imageio::DecodedPixelLayout::rgb16 ||
                frame.layout == negaflow::imageio::DecodedPixelLayout::rgba16 ||
                (allow_gray_ &&
                 frame.layout == negaflow::imageio::DecodedPixelLayout::gray16);
            channels_ = negaflow::imageio::channel_count(frame.layout);
            const std::uint64_t area = static_cast<std::uint64_t>(frame.width) * frame.height;
            if (!valid_layout || channels_ == 0U || frame.width == 0U || frame.height == 0U ||
                area > std::numeric_limits<std::size_t>::max() || cancel_.requested()) {
                return false;
            }
            width_ = frame.width;
            height_ = frame.height;
            values_.assign(static_cast<std::size_t>(area), 0.0F);
            return true;
        } catch (...) {
            return false;
        }
    }

    bool write(const negaflow::imageio::WicTiffRowChunk& rows) noexcept override {
        if (cancel_.requested() || rows.first_row != next_row_ || rows.row_count == 0U ||
            rows.first_row > height_ || rows.row_count > height_ - rows.first_row ||
            rows.stride_bytes % sizeof(std::uint16_t) != 0U) {
            return false;
        }
        const std::size_t stride = rows.stride_bytes / sizeof(std::uint16_t);
        if (stride < static_cast<std::size_t>(width_) * channels_ ||
            rows.samples.size() != stride * rows.row_count) {
            return false;
        }
        constexpr float scale = 1.0F / 65'535.0F;
        for (std::uint32_t row = 0U; row < rows.row_count; ++row) {
            const std::uint16_t* const source = rows.samples.data() + row * stride;
            float* const destination = values_.data() +
                static_cast<std::size_t>(rows.first_row + row) * width_;
            for (std::uint32_t x = 0U; x < width_; ++x) {
                destination[x] = static_cast<float>(source[x * channels_]) * scale;
            }
        }
        next_row_ += rows.row_count;
        return true;
    }

    void complete(const negaflow::imageio::WicTiffDecodeStatus status) noexcept override {
        complete_ = status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            next_row_ == height_;
        if (!complete_) {
            std::vector<float>{}.swap(values_);
        }
    }

    [[nodiscard]] bool complete() const noexcept { return complete_; }
    [[nodiscard]] std::uint32_t width() const noexcept { return width_; }
    [[nodiscard]] std::uint32_t height() const noexcept { return height_; }
    [[nodiscard]] std::vector<float>& values() noexcept { return values_; }

private:
    bool allow_gray_{false};
    negaflow::core::CancelFlag cancel_{};
    std::uint8_t channels_{0U};
    std::uint32_t width_{0U};
    std::uint32_t height_{0U};
    std::uint32_t next_row_{0U};
    bool complete_{false};
    std::vector<float> values_{};
};

[[nodiscard]] negaflow::imaging::InfraredDetectorParameters infrared_parameters(
    const nf_infrared_detector_parameters_v1& source) noexcept {
    negaflow::imaging::InfraredDetectorParameters result{};
    result.sensitivity = source.sensitivity;
    result.dilate_radius = source.dilate_radius;
    result.minimum_area = source.minimum_area;
    result.maximum_coverage = source.maximum_coverage;
    result.alignment_search_radius = source.alignment_search_radius;
    result.cluster_tile = source.cluster_tile;
    result.cluster_padding = source.cluster_padding;
    return result;
}

[[nodiscard]] std::uint32_t infrared_status(
    const negaflow::imaging::InfraredDetectionStatus value) noexcept {
    switch (value) {
        case negaflow::imaging::InfraredDetectionStatus::ok:
            return NF_INFRARED_DETECTION_OK;
        case negaflow::imaging::InfraredDetectionStatus::unreadable:
            return NF_INFRARED_DETECTION_UNREADABLE;
        case negaflow::imaging::InfraredDetectionStatus::too_small:
            return NF_INFRARED_DETECTION_TOO_SMALL;
        case negaflow::imaging::InfraredDetectionStatus::no_defects:
            return NF_INFRARED_DETECTION_NO_DEFECTS;
        case negaflow::imaging::InfraredDetectionStatus::coverage_too_high:
            return NF_INFRARED_DETECTION_COVERAGE_TOO_HIGH;
        case negaflow::imaging::InfraredDetectionStatus::cancelled:
            return NF_INFRARED_DETECTION_CANCELLED;
        case negaflow::imaging::InfraredDetectionStatus::allocation_failed:
            return NF_INFRARED_DETECTION_ALLOCATION_FAILED;
    }
    return NF_INFRARED_DETECTION_UNREADABLE;
}

[[nodiscard]] std::uint32_t flatbed_frame_grid_status(
    const negaflow::imaging::FlatbedFrameGridStatus value) noexcept {
    switch (value) {
        case negaflow::imaging::FlatbedFrameGridStatus::ok:
            return NF_FLATBED_FRAME_GRID_OK;
        case negaflow::imaging::FlatbedFrameGridStatus::invalid_input:
            return NF_FLATBED_FRAME_GRID_INVALID_INPUT;
        case negaflow::imaging::FlatbedFrameGridStatus::cancelled:
            return NF_FLATBED_FRAME_GRID_CANCELLED;
        case negaflow::imaging::FlatbedFrameGridStatus::allocation_failed:
            return NF_FLATBED_FRAME_GRID_ALLOCATION_FAILED;
    }
    return NF_FLATBED_FRAME_GRID_INVALID_INPUT;
}

[[nodiscard]] bool flatbed_frame_format(
    const std::uint32_t value,
    negaflow::imaging::FlatbedFrameFormat& result) noexcept {
    if (value > NF_FLATBED_FRAME_MEDIUM_617) return false;
    result = static_cast<negaflow::imaging::FlatbedFrameFormat>(value);
    return true;
}

[[nodiscard]] std::uint32_t infrared_alignment_status(
    const negaflow::imaging::InfraredAlignmentStatus value) noexcept {
    switch (value) {
        case negaflow::imaging::InfraredAlignmentStatus::not_requested:
            return NF_INFRARED_ALIGNMENT_NOT_REQUESTED;
        case negaflow::imaging::InfraredAlignmentStatus::aligned:
            return NF_INFRARED_ALIGNMENT_ALIGNED;
        case negaflow::imaging::InfraredAlignmentStatus::insufficient_texture:
            return NF_INFRARED_ALIGNMENT_INSUFFICIENT_TEXTURE;
        case negaflow::imaging::InfraredAlignmentStatus::weak_correlation:
            return NF_INFRARED_ALIGNMENT_WEAK_CORRELATION;
        case negaflow::imaging::InfraredAlignmentStatus::search_limit_reached:
            return NF_INFRARED_ALIGNMENT_SEARCH_LIMIT_REACHED;
    }
    return NF_INFRARED_ALIGNMENT_INSUFFICIENT_TEXTURE;
}

[[nodiscard]] nf_status_t publish_infrared_detection(
    negaflow::imaging::InfraredDetectionResult&& detection,
    nf_infrared_detection_summary_v1* const summary,
    nf_infrared_detection_handle_v1** const handle) noexcept {
    summary->status = infrared_status(detection.status);
    summary->width = detection.detection.width;
    summary->height = detection.detection.height;
    summary->offset_x = detection.detection.offset_x;
    summary->offset_y = detection.detection.offset_y;
    summary->alignment_status = infrared_alignment_status(detection.detection.alignment.status);
    summary->alignment_search_radius = detection.detection.alignment.search_radius;
    summary->alignment_downsample_factor = detection.detection.alignment.downsample_factor;
    summary->coverage = detection.detection.coverage;
    summary->median_gain = detection.detection.median_gain;
    summary->alignment_peak_correlation = detection.detection.alignment.peak_correlation;
    summary->alignment_runner_up_correlation =
        detection.detection.alignment.runner_up_correlation;
    summary->candidate_count = detection.detection.candidate_count;
    summary->confirmed_count = detection.detection.confirmed_count;
    summary->cluster_count = detection.detection.clusters.size();
    summary->component_count = detection.detection.components.size();
    if (detection.status != negaflow::imaging::InfraredDetectionStatus::ok) {
        return NF_STATUS_OK;
    }
    auto* const owned = new (std::nothrow) nf_infrared_detection_handle_v1{};
    if (owned == nullptr) {
        summary->status = NF_INFRARED_DETECTION_ALLOCATION_FAILED;
        return NF_STATUS_OK;
    }
    owned->detection = std::move(detection.detection);
    *handle = owned;
    return NF_STATUS_OK;
}

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

[[nodiscard]] bool map_film_polarity(
    const std::uint32_t value,
    negaflow::pipeline::FilmPolarity& polarity) noexcept {
    switch (value) {
        case NF_FILM_POLARITY_NEGATIVE:
            polarity = negaflow::pipeline::FilmPolarity::negative;
            return true;
        case NF_FILM_POLARITY_POSITIVE:
            polarity = negaflow::pipeline::FilmPolarity::positive;
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
        case 12U: emulation = FilmEmulation::tri_x_400; return true;
        case 13U: emulation = FilmEmulation::hp5_plus; return true;
        case 14U: emulation = FilmEmulation::fp4_plus; return true;
        case 15U: emulation = FilmEmulation::delta_100; return true;
        case 16U: emulation = FilmEmulation::delta_400; return true;
        case 17U: emulation = FilmEmulation::delta_3200; return true;
        case 18U: emulation = FilmEmulation::tmax_100; return true;
        case 19U: emulation = FilmEmulation::tmax_400; return true;
        case 20U: emulation = FilmEmulation::tmax_p3200; return true;
        case 21U: emulation = FilmEmulation::kentmere_400; return true;
        case 22U: emulation = FilmEmulation::ortho_plus; return true;
        case 23U: emulation = FilmEmulation::sfx_200; return true;
        case 24U: emulation = FilmEmulation::rollei_ir; return true;
        case 25U: emulation = FilmEmulation::scala_200x; return true;
        case 26U: emulation = FilmEmulation::rollei_superpan; return true;
        case 27U: emulation = FilmEmulation::velvia_100; return true;
        case 28U: emulation = FilmEmulation::e100_vs; return true;
        case 29U: emulation = FilmEmulation::astia_100f; return true;
        case 30U: emulation = FilmEmulation::kodachrome_64; return true;
        case 31U: emulation = FilmEmulation::gold_200; return true;
        case 32U: emulation = FilmEmulation::pro_image_100; return true;
        case 33U: emulation = FilmEmulation::superia_400; return true;
        case 34U: emulation = FilmEmulation::superia_premium_400; return true;
        case 35U: emulation = FilmEmulation::superia_200; return true;
        case 36U: emulation = FilmEmulation::reala_100; return true;
        case 37U: emulation = FilmEmulation::industrial_100; return true;
        case 38U: emulation = FilmEmulation::lomo_cn_800; return true;
        case 39U: emulation = FilmEmulation::vision3_500t; return true;
        case 40U: emulation = FilmEmulation::vision3_250d; return true;
        case 41U: emulation = FilmEmulation::vision3_50d; return true;
        case 42U: emulation = FilmEmulation::vision3_200t; return true;
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

[[nodiscard]] bool map_request_v8(
    const nf_develop_export_request_v8& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    nf_develop_export_request_v7 prefix{};
    std::memcpy(&prefix, &request, sizeof(prefix));
    if (!map_request_v7(prefix, require_destination, pipeline_request, result)) {
        return false;
    }
    pipeline_request.grain_mend.strength = request.defect_removal_strength;
    if (!negaflow::imaging::valid_grain_mend_parameters(
            pipeline_request.grain_mend)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("invalid_grain_mend_parameters", result.failure_name);
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v9(
    const nf_develop_export_request_v9& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v8(
            request.v8,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }

    pipeline_request.film_scan_denoise.strength =
        request.noise_reduction_strength;
    pipeline_request.film_scan_denoise.axes = {
        request.noise_reduction_luma,
        request.noise_reduction_chroma,
        request.noise_reduction_dark_tone,
        request.noise_reduction_detail,
        request.noise_reduction_grain_protect,
    };
    switch (request.noise_reduction_film_profile) {
        case NF_FILM_SCAN_DENOISE_COLOR_NEGATIVE:
            pipeline_request.film_scan_denoise.film_profile =
                negaflow::imaging::FilmScanDenoiseFilmProfile::color_negative;
            break;
        case NF_FILM_SCAN_DENOISE_COLOR_POSITIVE:
            pipeline_request.film_scan_denoise.film_profile =
                negaflow::imaging::FilmScanDenoiseFilmProfile::color_positive;
            break;
        case NF_FILM_SCAN_DENOISE_BLACK_AND_WHITE_NEGATIVE:
            pipeline_request.film_scan_denoise.film_profile =
                negaflow::imaging::FilmScanDenoiseFilmProfile::
                    black_and_white_negative;
            break;
        case NF_FILM_SCAN_DENOISE_BLACK_AND_WHITE_POSITIVE:
            pipeline_request.film_scan_denoise.film_profile =
                negaflow::imaging::FilmScanDenoiseFilmProfile::
                    black_and_white_positive;
            break;
        default:
            result.succeeded = 0U;
            result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
            copy_failure_name(
                "invalid_film_scan_denoise_parameters",
                result.failure_name);
            return false;
    }
    if (!negaflow::imaging::valid_film_scan_denoise_parameters(
            pipeline_request.film_scan_denoise)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name(
            "invalid_film_scan_denoise_parameters",
            result.failure_name);
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v10(
    const nf_develop_export_request_v10& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v9(
            request.v9,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    pipeline_request.texture = {
        request.texture_grain,
        request.texture_sharpness,
        request.texture_halation,
        request.texture_clarity,
        request.texture_vignette,
    };
    pipeline_request.film_look.grain_override = request.texture_grain;
    pipeline_request.film_look.halation_override = request.texture_halation;
    if (!negaflow::imaging::valid_texture_stage_parameters(
            pipeline_request.texture)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("invalid_texture_parameters", result.failure_name);
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v11(
    const nf_develop_export_request_v11& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v10(
            request.v10,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    switch (request.bw_toning_mode) {
        case 0U:
            pipeline_request.bw_toning.mode =
                negaflow::imaging::BwToningMode::none;
            break;
        case 1U:
            pipeline_request.bw_toning.mode =
                negaflow::imaging::BwToningMode::selenium;
            break;
        case 2U:
            pipeline_request.bw_toning.mode =
                negaflow::imaging::BwToningMode::sepia;
            break;
        default:
            pipeline_request.bw_toning.mode =
                static_cast<negaflow::imaging::BwToningMode>(request.bw_toning_mode);
            break;
    }
    pipeline_request.bw_toning.shadow_hue = request.bw_toning_shadow_hue;
    pipeline_request.bw_toning.highlight_hue = request.bw_toning_highlight_hue;
    pipeline_request.bw_toning.strength = request.bw_toning_strength;
    pipeline_request.image_transform = {
        static_cast<negaflow::imaging::ImageRotation>(request.image_rotation),
        request.flip_horizontal != 0U,
        request.flip_vertical != 0U,
        request.has_crop != 0U,
        {
            request.crop_x,
            request.crop_y,
            request.crop_width,
            request.crop_height,
        },
        request.straighten_angle,
    };
    if ((request.flip_horizontal > 1U) || (request.flip_vertical > 1U) ||
        (request.has_crop > 1U) ||
        !negaflow::imaging::valid_bw_toning_parameters(
            pipeline_request.bw_toning) ||
        !negaflow::imaging::valid_image_transform_parameters(
            pipeline_request.image_transform)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name(
            "invalid_post_pipeline_parameters",
            result.failure_name);
        return false;
    }
    return true;
}

[[nodiscard]] bool valid_flat_range(
    const std::uint32_t offset,
    const std::uint32_t count,
    const std::uint32_t total) noexcept {
    return offset <= total && count <= total - offset;
}

void fail_local_dodge_burn_request(
    nf_develop_export_result_v2& result,
    const char* const failure_name) noexcept {
    result.succeeded = 0U;
    result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
    copy_failure_name(failure_name, result.failure_name);
}

[[nodiscard]] bool map_request_v12(
    const nf_develop_export_request_v12& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v11(
            request.v11,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    if (request.local_adjustment_reserved != 0U ||
        request.local_stroke_reserved != 0U ||
        request.local_point_reserved != 0U ||
        request.local_adjustment_count > NF_LOCAL_DODGE_BURN_MAX_ADJUSTMENTS ||
        request.local_stroke_count > NF_LOCAL_DODGE_BURN_MAX_STROKES ||
        request.local_point_count > NF_LOCAL_DODGE_BURN_MAX_POINTS ||
        (request.local_adjustment_count != 0U &&
         request.local_adjustments == nullptr) ||
        (request.local_stroke_count != 0U && request.local_strokes == nullptr) ||
        (request.local_point_count != 0U && request.local_points == nullptr)) {
        fail_local_dodge_burn_request(
            result,
            "invalid_local_dodge_burn_payload");
        return false;
    }

    try {
        for (std::uint32_t index = 0U; index < request.local_point_count; ++index) {
            const nf_local_dodge_burn_point_v1& point =
                request.local_points[index];
            if (!std::isfinite(point.x) || !std::isfinite(point.y)) {
                fail_local_dodge_burn_request(
                    result,
                    "invalid_local_dodge_burn_payload");
                return false;
            }
        }
        for (std::uint32_t index = 0U; index < request.local_stroke_count; ++index) {
            const nf_local_dodge_burn_stroke_v1& stroke =
                request.local_strokes[index];
            if (!valid_flat_range(
                    stroke.point_offset,
                    stroke.point_count,
                    request.local_point_count) ||
                !std::isfinite(stroke.thickness) ||
                !std::isfinite(stroke.feather)) {
                fail_local_dodge_burn_request(
                    result,
                    "invalid_local_dodge_burn_payload");
                return false;
            }
        }

        pipeline_request.local_dodge_burn.adjustments.reserve(
            request.local_adjustment_count);
        for (std::uint32_t index = 0U;
             index < request.local_adjustment_count;
             ++index) {
            const nf_local_dodge_burn_adjustment_v1& source =
                request.local_adjustments[index];
            const bool brush = source.mask_kind == NF_LOCAL_DODGE_BURN_MASK_BRUSH;
            const bool polygon = source.mask_kind == NF_LOCAL_DODGE_BURN_MASK_POLYGON;
            if (source.mode > NF_LOCAL_DODGE_BURN_MODE_BURN ||
                source.enabled > 1U ||
                source.mask_kind > NF_LOCAL_DODGE_BURN_MASK_POLYGON ||
                !std::isfinite(source.amount) ||
                !std::isfinite(source.center_x) ||
                !std::isfinite(source.center_y) ||
                !std::isfinite(source.radius) ||
                !std::isfinite(source.feather) ||
                !std::isfinite(source.start_x) ||
                !std::isfinite(source.start_y) ||
                !std::isfinite(source.end_x) ||
                !std::isfinite(source.end_y) ||
                !valid_flat_range(
                    source.stroke_offset,
                    source.stroke_count,
                    request.local_stroke_count) ||
                !valid_flat_range(
                    source.point_offset,
                    source.point_count,
                    request.local_point_count) ||
                (brush && (source.point_offset != 0U || source.point_count != 0U)) ||
                (polygon &&
                 (source.stroke_offset != 0U || source.stroke_count != 0U)) ||
                (!brush && !polygon &&
                 (source.stroke_offset != 0U || source.stroke_count != 0U ||
                  source.point_offset != 0U || source.point_count != 0U))) {
                fail_local_dodge_burn_request(
                    result,
                    "invalid_local_dodge_burn_payload");
                return false;
            }

            negaflow::imaging::LocalDodgeBurnAdjustment adjustment{};
            adjustment.mode = source.mode == NF_LOCAL_DODGE_BURN_MODE_DODGE
                ? negaflow::imaging::LocalDodgeBurnMode::dodge
                : negaflow::imaging::LocalDodgeBurnMode::burn;
            adjustment.enabled = source.enabled != 0U;
            adjustment.amount = source.amount;
            adjustment.mask.kind = static_cast<
                negaflow::imaging::LocalDodgeBurnMaskKind>(source.mask_kind);
            adjustment.mask.center = {source.center_x, source.center_y};
            adjustment.mask.radius = source.radius;
            adjustment.mask.feather = source.feather;
            adjustment.mask.start = {source.start_x, source.start_y};
            adjustment.mask.end = {source.end_x, source.end_y};

            if (brush) {
                adjustment.mask.strokes.reserve(source.stroke_count);
                for (std::uint32_t stroke_index = 0U;
                     stroke_index < source.stroke_count;
                     ++stroke_index) {
                    const nf_local_dodge_burn_stroke_v1& flat_stroke =
                        request.local_strokes[
                            source.stroke_offset + stroke_index];
                    negaflow::imaging::LocalDodgeBurnStroke stroke{};
                    stroke.thickness = flat_stroke.thickness;
                    stroke.feather = flat_stroke.feather;
                    stroke.points.reserve(flat_stroke.point_count);
                    for (std::uint32_t point_index = 0U;
                         point_index < flat_stroke.point_count;
                         ++point_index) {
                        const nf_local_dodge_burn_point_v1& point =
                            request.local_points[
                                flat_stroke.point_offset + point_index];
                        stroke.points.push_back({point.x, point.y});
                    }
                    adjustment.mask.strokes.push_back(std::move(stroke));
                }
            } else if (polygon) {
                adjustment.mask.points.reserve(source.point_count);
                for (std::uint32_t point_index = 0U;
                     point_index < source.point_count;
                     ++point_index) {
                    const nf_local_dodge_burn_point_v1& point =
                        request.local_points[source.point_offset + point_index];
                    adjustment.mask.points.push_back({point.x, point.y});
                }
            }
            pipeline_request.local_dodge_burn.adjustments.push_back(
                std::move(adjustment));
        }
    } catch (const std::bad_alloc&) {
        fail_local_dodge_burn_request(
            result,
            "local_dodge_burn_recipe_allocation_failed");
        return false;
    }

    if (!negaflow::imaging::valid_local_dodge_burn_parameters(
            pipeline_request.local_dodge_burn)) {
        fail_local_dodge_burn_request(
            result,
            "invalid_local_dodge_burn_parameters");
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v13(
    const nf_develop_export_request_v13& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v12(
            request.v12,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    pipeline_request.color_model = {
        request.warmth,
        request.tint,
        request.color_depth,
        request.vibrance,
        request.saturation,
        request.red_primary,
        request.green_primary,
        request.blue_primary,
    };
    return true;
}

[[nodiscard]] bool map_request_v14(
    const nf_develop_export_request_v14& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v13(
            request.v13,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    if (request.auto_levels > 1U || request.auto_neutral_balance > 1U) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("invalid_scene_correction_flag", result.failure_name);
        return false;
    }
    pipeline_request.scene_correction = {
        request.auto_levels == 1U,
        request.auto_neutral_balance == 1U,
        pipeline_request.film_look.source_kind ==
            negaflow::imaging::DevelopSourceKind::film_scan,
    };
    return true;
}

[[nodiscard]] bool map_request_v15(
    const nf_develop_export_request_v15& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v14(
            request.v14,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    if (request.reserved != 0U || request.develop_target > NF_DEVELOP_TARGET_RESCUE) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("invalid_develop_target", result.failure_name);
        return false;
    }
    pipeline_request.develop_target =
        static_cast<negaflow::pipeline::DevelopTarget>(request.develop_target);
    return true;
}

[[nodiscard]] bool map_request_v16(
    const nf_develop_export_request_v16& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v15(
            request.v15,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    if (request.scanner_profile_id != nullptr) {
        pipeline_request.scanner_profile_id = request.scanner_profile_id;
    }
    return true;
}

[[nodiscard]] bool map_request_v17(
    const nf_develop_export_request_v17& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v16(
            request.v16,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    if (request.reserved != 0U ||
        !map_film_polarity(request.film_polarity, pipeline_request.film_polarity)) {
        result.succeeded = 0U;
        result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
        copy_failure_name("invalid_film_polarity", result.failure_name);
        return false;
    }
    return true;
}

void fail_defect_region_request(
    nf_develop_export_result_v2& result,
    const char* const failure_name) noexcept {
    result.succeeded = 0U;
    result.failed_stage = NF_DEVELOP_STAGE_REQUEST_VALIDATION;
    copy_failure_name(failure_name, result.failure_name);
}

[[nodiscard]] bool map_request_v18(
    const nf_develop_export_request_v18& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v17(
            request.v17,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    if (request.defect_region_reserved != 0U ||
        request.defect_mask_reserved != 0U ||
        request.defect_region_edit_count > NF_DEFECT_REGION_MAX_EDITS ||
        request.defect_mask_byte_count > NF_DEFECT_REGION_MAX_MASK_BYTES ||
        (request.defect_region_edit_count != 0U &&
         request.defect_region_edits == nullptr) ||
        (request.defect_mask_byte_count != 0U &&
         request.defect_mask_bytes == nullptr) ||
        (request.defect_region_edit_count == 0U &&
         request.defect_mask_byte_count != 0U)) {
        fail_defect_region_request(result, "invalid_defect_region_payload");
        return false;
    }

    try {
        std::size_t total_mask_bytes = 0U;
        pipeline_request.defect_recipe.regions.edits.reserve(
            request.defect_region_edit_count);
        pipeline_request.defect_recipe.order.reserve(
            request.defect_region_edit_count);
        for (std::uint32_t index = 0U;
             index < request.defect_region_edit_count;
             ++index) {
            const nf_defect_region_edit_v1& source =
                request.defect_region_edits[index];
            const std::uint64_t required = source.height == 0U
                ? 0U
                : static_cast<std::uint64_t>(source.height - 1U) *
                          source.mask_stride_bytes +
                      source.width;
            if (source.enabled > 1U || source.has_preferred_angle > 1U ||
                source.reserved != 0U || source.width <= 2U ||
                source.height <= 2U ||
                source.mask_stride_bytes < source.width ||
                required > source.mask_byte_count ||
                !valid_flat_range(
                    source.mask_offset,
                    source.mask_byte_count,
                    request.defect_mask_byte_count) ||
                !std::isfinite(source.strength) ||
                source.strength < 0.0 || source.strength > 1.0 ||
                !std::isfinite(source.preferred_angle_degrees) ||
                (source.has_preferred_angle == 0U &&
                 source.preferred_angle_degrees != 0.0) ||
                (source.has_preferred_angle != 0U &&
                 (source.preferred_angle_degrees < 0.0 ||
                  source.preferred_angle_degrees > 180.0)) ||
                source.mask_byte_count >
                    NF_DEFECT_REGION_MAX_MASK_BYTES - total_mask_bytes) {
                fail_defect_region_request(
                    result,
                    "invalid_defect_region_payload");
                return false;
            }
            total_mask_bytes += source.mask_byte_count;
            negaflow::pipeline::DefectRegionEdit edit{};
            edit.enabled = source.enabled != 0U;
            edit.roi_x = source.roi_x;
            edit.roi_y = source.roi_y;
            edit.width = source.width;
            edit.height = source.height;
            edit.mask = std::span<const std::uint8_t>(
                request.defect_mask_bytes + source.mask_offset,
                source.mask_byte_count);
            edit.mask_stride_bytes = source.mask_stride_bytes;
            edit.repair = {
                source.has_preferred_angle != 0U,
                source.preferred_angle_degrees,
                source.strength,
            };
            pipeline_request.defect_recipe.regions.edits.push_back(edit);
            pipeline_request.defect_recipe.order.push_back({
                negaflow::pipeline::DefectRecipeEditKind::region,
                pipeline_request.defect_recipe.regions.edits.size() - 1U,
            });
        }
    } catch (const std::bad_alloc&) {
        fail_defect_region_request(
            result,
            "defect_region_recipe_allocation_failed");
        return false;
    }
    return true;
}

[[nodiscard]] bool map_request_v19(
    const nf_develop_export_request_v19& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (!map_request_v18(
            request.v18,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }
    const bool has_edits = request.v18.defect_region_edit_count != 0U;
    const bool has_identity = request.has_defect_source_identity != 0U;
    if (request.has_defect_source_identity > 1U || request.reserved != 0U ||
        has_edits != has_identity ||
        (!has_identity &&
         (request.defect_source_file_bytes != 0U ||
          request.defect_source_sha256 != nullptr)) ||
        (has_identity &&
         (request.defect_source_file_bytes == 0U ||
          request.defect_source_sha256 == nullptr))) {
        fail_defect_region_request(result, "invalid_defect_source_identity");
        return false;
    }
    if (has_identity) {
        negaflow::pipeline::ExpectedSourceIdentity identity{};
        identity.file_bytes = request.defect_source_file_bytes;
        std::memcpy(
            identity.sha256.data(),
            request.defect_source_sha256,
            identity.sha256.size());
        pipeline_request.expected_defect_source_identity = identity;
    }
    return true;
}

[[nodiscard]] bool map_source_identity_v20(
    const nf_develop_export_request_v19& request,
    const bool has_edits,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    const bool has_identity = request.has_defect_source_identity != 0U;
    if (request.has_defect_source_identity > 1U || request.reserved != 0U ||
        has_edits != has_identity ||
        (!has_identity &&
         (request.defect_source_file_bytes != 0U ||
          request.defect_source_sha256 != nullptr)) ||
        (has_identity &&
         (request.defect_source_file_bytes == 0U ||
          request.defect_source_sha256 == nullptr))) {
        fail_defect_region_request(result, "invalid_defect_source_identity");
        return false;
    }
    if (has_identity) {
        negaflow::pipeline::ExpectedSourceIdentity identity{};
        identity.file_bytes = request.defect_source_file_bytes;
        std::memcpy(
            identity.sha256.data(),
            request.defect_source_sha256,
            identity.sha256.size());
        pipeline_request.expected_defect_source_identity = identity;
    }
    return true;
}

[[nodiscard]] bool map_request_v20_core(
    const nf_develop_export_request_v20& request,
    const bool require_destination,
    const std::uint32_t brush_count,
    const bool allow_brush,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    const std::uint64_t expected_order_count =
        static_cast<std::uint64_t>(request.v19.v18.defect_region_edit_count) +
        request.defect_clone_edit_count + brush_count;
    if (request.defect_clone_edit_reserved != 0U ||
        request.defect_clone_stroke_reserved != 0U ||
        request.defect_clone_point_reserved != 0U ||
        request.defect_edit_order_reserved != 0U ||
        request.defect_clone_edit_count > NF_DEFECT_CLONE_MAX_EDITS ||
        request.defect_clone_stroke_count > NF_DEFECT_CLONE_MAX_STROKES ||
        request.defect_clone_point_count > NF_DEFECT_CLONE_MAX_POINTS ||
        request.defect_edit_order_count >
            NF_DEFECT_RECIPE_MAX_ORDERED_EDITS ||
        request.defect_edit_order_count != expected_order_count ||
        (request.defect_clone_edit_count != 0U &&
         request.defect_clone_edits == nullptr) ||
        (request.defect_clone_stroke_count != 0U &&
         request.defect_clone_strokes == nullptr) ||
        (request.defect_clone_point_count != 0U &&
         request.defect_clone_points == nullptr) ||
        (request.defect_edit_order_count != 0U &&
         request.defect_edit_order == nullptr) ||
        (request.defect_clone_edit_count == 0U &&
         (request.defect_clone_stroke_count != 0U ||
          request.defect_clone_point_count != 0U))) {
        fail_defect_region_request(result, "invalid_defect_clone_payload");
        return false;
    }
    if (!map_request_v18(
            request.v19.v18,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }

    try {
        std::vector<std::uint8_t> referenced_strokes(
            request.defect_clone_stroke_count, 0U);
        std::vector<std::uint8_t> referenced_points(
            request.defect_clone_point_count, 0U);
        auto& recipe = pipeline_request.defect_recipe;
        recipe.order.clear();
        recipe.clone_points_storage.reserve(request.defect_clone_point_count);
        for (std::uint32_t index = 0U;
             index < request.defect_clone_point_count;
             ++index) {
            const nf_defect_clone_point_v1 source =
                request.defect_clone_points[index];
            if (!std::isfinite(source.x) || !std::isfinite(source.y)) {
                fail_defect_region_request(
                    result, "invalid_defect_clone_payload");
                return false;
            }
            recipe.clone_points_storage.push_back({source.x, source.y});
        }

        recipe.clone_strokes_storage.reserve(
            request.defect_clone_stroke_count);
        for (std::uint32_t index = 0U;
             index < request.defect_clone_stroke_count;
             ++index) {
            const nf_defect_clone_stroke_v1& source =
                request.defect_clone_strokes[index];
            if (!valid_flat_range(
                    source.point_offset,
                    source.point_count,
                    request.defect_clone_point_count) ||
                !std::isfinite(source.offset_x) ||
                !std::isfinite(source.offset_y) ||
                !std::isfinite(source.diameter_pixels) ||
                source.diameter_pixels <= 0.0 ||
                !std::isfinite(source.hardness) ||
                source.hardness < 0.0 || source.hardness > 1.0) {
                fail_defect_region_request(
                    result, "invalid_defect_clone_payload");
                return false;
            }
            for (std::uint32_t point = 0U; point < source.point_count; ++point) {
                std::uint8_t& marker = referenced_points[
                    static_cast<std::size_t>(source.point_offset) + point];
                if (marker != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_clone_payload");
                    return false;
                }
                marker = 1U;
            }
            const negaflow::imaging::DefectClonePoint* stroke_points =
                source.point_count == 0U
                ? nullptr
                : recipe.clone_points_storage.data() + source.point_offset;
            recipe.clone_strokes_storage.push_back({
                std::span<const negaflow::imaging::DefectClonePoint>(
                    stroke_points,
                    source.point_count),
                source.offset_x,
                source.offset_y,
                source.diameter_pixels,
                source.hardness,
            });
        }
        if (!std::all_of(
                referenced_points.begin(),
                referenced_points.end(),
                [](const std::uint8_t value) { return value != 0U; })) {
            fail_defect_region_request(
                result, "invalid_defect_clone_payload");
            return false;
        }

        recipe.clones.reserve(request.defect_clone_edit_count);
        for (std::uint32_t index = 0U;
             index < request.defect_clone_edit_count;
             ++index) {
            const nf_defect_clone_edit_v1& source =
                request.defect_clone_edits[index];
            if (source.enabled > 1U || source.reserved != 0U ||
                !valid_flat_range(
                    source.stroke_offset,
                    source.stroke_count,
                    request.defect_clone_stroke_count) ||
                !std::isfinite(source.strength) || source.strength < 0.0 ||
                source.strength > 1.0) {
                fail_defect_region_request(
                    result, "invalid_defect_clone_payload");
                return false;
            }
            for (std::uint32_t stroke = 0U;
                 stroke < source.stroke_count;
                 ++stroke) {
                std::uint8_t& marker = referenced_strokes[
                    static_cast<std::size_t>(source.stroke_offset) + stroke];
                if (marker != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_clone_payload");
                    return false;
                }
                marker = 1U;
            }
            const negaflow::imaging::DefectCloneStroke* edit_strokes =
                source.stroke_count == 0U
                ? nullptr
                : recipe.clone_strokes_storage.data() + source.stroke_offset;
            recipe.clones.push_back({
                source.enabled != 0U,
                {
                    std::span<const negaflow::imaging::DefectCloneStroke>(
                        edit_strokes,
                        source.stroke_count),
                    source.strength,
                },
            });
        }
        if (!std::all_of(
                referenced_strokes.begin(),
                referenced_strokes.end(),
                [](const std::uint8_t value) { return value != 0U; })) {
            fail_defect_region_request(
                result, "invalid_defect_clone_payload");
            return false;
        }

        std::vector<std::uint8_t> referenced_regions(
            request.v19.v18.defect_region_edit_count, 0U);
        std::vector<std::uint8_t> referenced_clones(
            request.defect_clone_edit_count, 0U);
        std::vector<std::uint8_t> referenced_brushes(brush_count, 0U);
        recipe.order.reserve(request.defect_edit_order_count);
        for (std::uint32_t position = 0U;
             position < request.defect_edit_order_count;
             ++position) {
            const nf_defect_recipe_edit_ref_v1 source =
                request.defect_edit_order[position];
            if (source.kind == NF_DEFECT_RECIPE_EDIT_REGION) {
                if (source.index >= referenced_regions.size() ||
                    referenced_regions[source.index] != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_edit_order");
                    return false;
                }
                referenced_regions[source.index] = 1U;
                recipe.order.push_back({
                    negaflow::pipeline::DefectRecipeEditKind::region,
                    source.index,
                });
            } else if (source.kind == NF_DEFECT_RECIPE_EDIT_CLONE) {
                if (source.index >= referenced_clones.size() ||
                    referenced_clones[source.index] != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_edit_order");
                    return false;
                }
                referenced_clones[source.index] = 1U;
                recipe.order.push_back({
                    negaflow::pipeline::DefectRecipeEditKind::clone,
                    source.index,
                });
            } else if (allow_brush &&
                       source.kind == NF_DEFECT_RECIPE_EDIT_BRUSH) {
                if (source.index >= referenced_brushes.size() ||
                    referenced_brushes[source.index] != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_edit_order");
                    return false;
                }
                referenced_brushes[source.index] = 1U;
                recipe.order.push_back({
                    negaflow::pipeline::DefectRecipeEditKind::brush,
                    source.index,
                });
            } else {
                fail_defect_region_request(
                    result, "invalid_defect_edit_order");
                return false;
            }
        }
        if (!std::all_of(
                referenced_regions.begin(),
                referenced_regions.end(),
                [](const std::uint8_t value) { return value != 0U; }) ||
            !std::all_of(
                referenced_clones.begin(),
                referenced_clones.end(),
                [](const std::uint8_t value) { return value != 0U; }) ||
            !std::all_of(
                referenced_brushes.begin(),
                referenced_brushes.end(),
                [](const std::uint8_t value) { return value != 0U; })) {
            fail_defect_region_request(result, "invalid_defect_edit_order");
            return false;
        }
    } catch (const std::bad_alloc&) {
        fail_defect_region_request(
        result, "defect_clone_recipe_allocation_failed");
        return false;
    }

    const bool has_edits = expected_order_count != 0U;
    return map_source_identity_v20(
        request.v19,
        has_edits,
        pipeline_request,
        result);
}

[[nodiscard]] bool map_request_v20(
    const nf_develop_export_request_v20& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    return map_request_v20_core(
        request,
        require_destination,
        0U,
        false,
        pipeline_request,
        result);
}

[[nodiscard]] bool map_request_v21(
    const nf_develop_export_request_v21& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (request.defect_brush_edit_reserved != 0U ||
        request.defect_brush_stroke_reserved != 0U ||
        request.defect_brush_point_reserved != 0U ||
        request.defect_brush_edit_count > NF_DEFECT_BRUSH_MAX_EDITS ||
        request.defect_brush_stroke_count > NF_DEFECT_BRUSH_MAX_STROKES ||
        request.defect_brush_point_count > NF_DEFECT_BRUSH_MAX_POINTS ||
        (request.defect_brush_edit_count != 0U &&
         request.defect_brush_edits == nullptr) ||
        (request.defect_brush_stroke_count != 0U &&
         request.defect_brush_strokes == nullptr) ||
        (request.defect_brush_point_count != 0U &&
         request.defect_brush_points == nullptr) ||
        (request.defect_brush_edit_count == 0U &&
         (request.defect_brush_stroke_count != 0U ||
          request.defect_brush_point_count != 0U))) {
        fail_defect_region_request(result, "invalid_defect_brush_payload");
        return false;
    }
    try {
        auto& recipe = pipeline_request.defect_recipe;
        std::vector<std::uint8_t> referenced_strokes(
            request.defect_brush_stroke_count, 0U);
        std::vector<std::uint8_t> referenced_points(
            request.defect_brush_point_count, 0U);
        recipe.brush_points_storage.reserve(request.defect_brush_point_count);
        for (std::uint32_t index = 0U;
             index < request.defect_brush_point_count;
             ++index) {
            const nf_defect_brush_point_v1 source =
                request.defect_brush_points[index];
            if (!std::isfinite(source.x) || !std::isfinite(source.y) ||
                source.x < 0.0 || source.x > 1.0 ||
                source.y < 0.0 || source.y > 1.0) {
                fail_defect_region_request(
                    result, "invalid_defect_brush_payload");
                return false;
            }
            recipe.brush_points_storage.push_back({source.x, source.y});
        }
        recipe.brush_strokes_storage.reserve(
            request.defect_brush_stroke_count);
        for (std::uint32_t index = 0U;
             index < request.defect_brush_stroke_count;
             ++index) {
            const nf_defect_brush_stroke_v1& source =
                request.defect_brush_strokes[index];
            if (!valid_flat_range(
                    source.point_offset,
                    source.point_count,
                    request.defect_brush_point_count) ||
                !std::isfinite(source.thickness) || source.thickness < 0.0 ||
                source.thickness > 1.0) {
                fail_defect_region_request(
                    result, "invalid_defect_brush_payload");
                return false;
            }
            for (std::uint32_t point = 0U; point < source.point_count; ++point) {
                std::uint8_t& marker = referenced_points[
                    static_cast<std::size_t>(source.point_offset) + point];
                if (marker != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_brush_payload");
                    return false;
                }
                marker = 1U;
            }
            const negaflow::imaging::DefectBrushPoint* points =
                source.point_count == 0U
                ? nullptr
                : recipe.brush_points_storage.data() + source.point_offset;
            recipe.brush_strokes_storage.push_back({
                std::span<const negaflow::imaging::DefectBrushPoint>(
                    points, source.point_count),
                source.thickness,
            });
        }
        if (!std::all_of(
                referenced_points.begin(),
                referenced_points.end(),
                [](const std::uint8_t value) { return value != 0U; })) {
            fail_defect_region_request(
                result, "invalid_defect_brush_payload");
            return false;
        }
        recipe.brushes.reserve(request.defect_brush_edit_count);
        for (std::uint32_t index = 0U;
             index < request.defect_brush_edit_count;
             ++index) {
            const nf_defect_brush_edit_v1& source =
                request.defect_brush_edits[index];
            if (source.enabled > 1U || source.reserved != 0U ||
                !valid_flat_range(
                    source.stroke_offset,
                    source.stroke_count,
                    request.defect_brush_stroke_count) ||
                !std::isfinite(source.strength) || source.strength < 0.0 ||
                source.strength > 1.0) {
                fail_defect_region_request(
                    result, "invalid_defect_brush_payload");
                return false;
            }
            for (std::uint32_t stroke = 0U;
                 stroke < source.stroke_count;
                 ++stroke) {
                std::uint8_t& marker = referenced_strokes[
                    static_cast<std::size_t>(source.stroke_offset) + stroke];
                if (marker != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_brush_payload");
                    return false;
                }
                marker = 1U;
            }
            const negaflow::imaging::DefectBrushStroke* strokes =
                source.stroke_count == 0U
                ? nullptr
                : recipe.brush_strokes_storage.data() + source.stroke_offset;
            recipe.brushes.push_back({
                source.enabled != 0U,
                {
                    std::span<const negaflow::imaging::DefectBrushStroke>(
                        strokes, source.stroke_count),
                    source.strength,
                },
            });
        }
        if (!std::all_of(
                referenced_strokes.begin(),
                referenced_strokes.end(),
                [](const std::uint8_t value) { return value != 0U; })) {
            fail_defect_region_request(
                result, "invalid_defect_brush_payload");
            return false;
        }
    } catch (const std::bad_alloc&) {
        fail_defect_region_request(
            result, "defect_brush_recipe_allocation_failed");
        return false;
    }
    return map_request_v20_core(
        request.v20,
        require_destination,
        request.defect_brush_edit_count,
        true,
        pipeline_request,
        result);
}

[[nodiscard]] bool map_request_v24(
    const nf_develop_export_request_v24& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (request.defect_infrared_edit_reserved != 0U ||
        request.defect_infrared_attenuation_reserved != 0U ||
        request.defect_infrared_edit_count > NF_DEFECT_INFRARED_MAX_EDITS ||
        request.defect_infrared_attenuation_byte_count >
            NF_DEFECT_INFRARED_MAX_ATTENUATION_BYTES ||
        (request.defect_infrared_edit_count != 0U &&
         request.defect_infrared_edits == nullptr) ||
        (request.defect_infrared_attenuation_byte_count != 0U &&
         request.defect_infrared_attenuation_bytes == nullptr) ||
        (request.defect_infrared_edit_count == 0U &&
         request.defect_infrared_attenuation_byte_count != 0U)) {
        fail_defect_region_request(result, "invalid_defect_infrared_payload");
        return false;
    }
    if (!map_request_v21(
            request.v21,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }

    try {
        auto& recipe = pipeline_request.defect_recipe;
        if (request.defect_infrared_edit_count > recipe.regions.edits.size()) {
            fail_defect_region_request(
                result, "invalid_defect_infrared_payload");
            return false;
        }
        const std::size_t absent = std::numeric_limits<std::size_t>::max();
        std::vector<std::size_t> region_to_infrared(
            recipe.regions.edits.size(), absent);
        recipe.infrared.reserve(request.defect_infrared_edit_count);
        std::uint64_t consumed_attenuation_bytes = 0U;
        for (std::uint32_t index = 0U;
             index < request.defect_infrared_edit_count;
             ++index) {
            const nf_defect_infrared_edit_v1& source =
                request.defect_infrared_edits[index];
            if (source.region_edit_index >= recipe.regions.edits.size() ||
                source.has_attenuation > 1U || source.reserved != 0U ||
                region_to_infrared[source.region_edit_index] != absent) {
                fail_defect_region_request(
                    result, "invalid_defect_infrared_payload");
                return false;
            }
            const negaflow::pipeline::DefectRegionEdit& region =
                recipe.regions.edits[source.region_edit_index];
            const std::uint64_t exact_core_bytes =
                static_cast<std::uint64_t>(region.width) * region.height;
            if (region.repair.has_preferred_angle ||
                region.mask_stride_bytes != region.width ||
                region.mask.size() != exact_core_bytes) {
                fail_defect_region_request(
                    result, "invalid_defect_infrared_payload");
                return false;
            }

            std::span<const std::uint8_t> attenuation{};
            std::size_t attenuation_stride = 0U;
            if (source.has_attenuation == 0U) {
                if (source.attenuation_stride_bytes != 0U ||
                    source.attenuation_offset != 0U ||
                    source.attenuation_byte_count != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_infrared_payload");
                    return false;
                }
            } else {
                const std::uint64_t row_bytes =
                    static_cast<std::uint64_t>(region.width) * 2U;
                const std::uint64_t required = region.height == 0U
                    ? 0U
                    : static_cast<std::uint64_t>(region.height - 1U) *
                              source.attenuation_stride_bytes +
                          row_bytes;
                if (source.attenuation_stride_bytes < row_bytes ||
                    required != source.attenuation_byte_count ||
                    source.attenuation_offset != consumed_attenuation_bytes ||
                    !valid_flat_range(
                        source.attenuation_offset,
                        source.attenuation_byte_count,
                        request.defect_infrared_attenuation_byte_count)) {
                    fail_defect_region_request(
                        result, "invalid_defect_infrared_payload");
                    return false;
                }
                consumed_attenuation_bytes += source.attenuation_byte_count;
                attenuation = std::span<const std::uint8_t>(
                    request.defect_infrared_attenuation_bytes +
                        source.attenuation_offset,
                    source.attenuation_byte_count);
                attenuation_stride = source.attenuation_stride_bytes;
            }
            region_to_infrared[source.region_edit_index] = index;
            negaflow::pipeline::DefectInfraredEdit cluster{
                true,
                region.roi_x,
                region.roi_y,
                region.width,
                region.height,
                region.mask,
                region.mask_stride_bytes,
                attenuation,
                attenuation_stride,
                1.0,
            };
            negaflow::pipeline::DefectInfraredItem item{};
            item.enabled = region.enabled;
            item.strength = region.repair.strength;
            item.clusters.push_back(std::move(cluster));
            recipe.infrared.push_back(std::move(item));
        }
        if (consumed_attenuation_bytes !=
            request.defect_infrared_attenuation_byte_count) {
            fail_defect_region_request(
                result, "invalid_defect_infrared_payload");
            return false;
        }

        std::vector<std::size_t> compact_region_index(
            recipe.regions.edits.size(), absent);
        std::vector<negaflow::pipeline::DefectRegionEdit> compact_regions;
        compact_regions.reserve(
            recipe.regions.edits.size() - request.defect_infrared_edit_count);
        for (std::size_t index = 0U;
             index < recipe.regions.edits.size();
             ++index) {
            if (region_to_infrared[index] != absent) {
                continue;
            }
            compact_region_index[index] = compact_regions.size();
            compact_regions.push_back(recipe.regions.edits[index]);
        }
        for (negaflow::pipeline::DefectRecipeEditRef& reference : recipe.order) {
            if (reference.kind !=
                negaflow::pipeline::DefectRecipeEditKind::region) {
                continue;
            }
            const std::size_t infrared_index =
                region_to_infrared[reference.index];
            if (infrared_index != absent) {
                reference.kind =
                    negaflow::pipeline::DefectRecipeEditKind::infrared;
                reference.index = infrared_index;
            } else {
                reference.index = compact_region_index[reference.index];
            }
        }
        recipe.regions.edits = std::move(compact_regions);
        return true;
    } catch (const std::bad_alloc&) {
        fail_defect_region_request(
            result, "defect_infrared_recipe_allocation_failed");
        return false;
    }
}

[[nodiscard]] bool map_request_v25(
    const nf_develop_export_request_v25& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept {
    if (request.defect_infrared_item_reserved != 0U ||
        request.defect_infrared_item_count > NF_DEFECT_INFRARED_MAX_EDITS ||
        (request.defect_infrared_item_count != 0U) !=
            (request.defect_infrared_items != nullptr)) {
        fail_defect_region_request(
            result, "invalid_defect_infrared_item_payload");
        return false;
    }
    const std::size_t flat_cluster_count =
        request.v24.defect_infrared_edit_count;
    if ((flat_cluster_count == 0U) !=
        (request.defect_infrared_item_count == 0U)) {
        fail_defect_region_request(
            result, "invalid_defect_infrared_item_payload");
        return false;
    }
    std::size_t preflight_clusters = 0U;
    for (std::uint32_t item_index = 0U;
         item_index < request.defect_infrared_item_count;
         ++item_index) {
        const nf_defect_infrared_item_v1& source =
            request.defect_infrared_items[item_index];
        if (source.reserved_0 != 0U || source.reserved_1 != 0U ||
            source.cluster_count == 0U ||
            source.cluster_offset != preflight_clusters ||
            source.cluster_count > flat_cluster_count - preflight_clusters) {
            fail_defect_region_request(
                result, "invalid_defect_infrared_item_payload");
            return false;
        }
        preflight_clusters += source.cluster_count;
    }
    if (preflight_clusters != flat_cluster_count) {
        fail_defect_region_request(
            result, "invalid_defect_infrared_item_payload");
        return false;
    }
    if (!map_request_v24(
            request.v24,
            require_destination,
            pipeline_request,
            result)) {
        return false;
    }

    try {
        auto& recipe = pipeline_request.defect_recipe;
        if (recipe.infrared.size() != flat_cluster_count) {
            fail_defect_region_request(
                result, "invalid_defect_infrared_item_payload");
            return false;
        }

        const std::size_t absent = std::numeric_limits<std::size_t>::max();
        std::vector<std::size_t> cluster_to_item(flat_cluster_count, absent);
        std::vector<std::size_t> cluster_ordinal(flat_cluster_count, absent);
        std::vector<negaflow::pipeline::DefectInfraredItem> grouped{};
        grouped.reserve(request.defect_infrared_item_count);
        std::size_t consumed_clusters = 0U;
        for (std::uint32_t item_index = 0U;
             item_index < request.defect_infrared_item_count;
             ++item_index) {
            const nf_defect_infrared_item_v1& source =
                request.defect_infrared_items[item_index];
            if (source.reserved_0 != 0U || source.reserved_1 != 0U ||
                source.cluster_count == 0U ||
                source.cluster_offset != consumed_clusters ||
                source.cluster_count > flat_cluster_count - consumed_clusters) {
                fail_defect_region_request(
                    result, "invalid_defect_infrared_item_payload");
                return false;
            }

            negaflow::pipeline::DefectInfraredItem item{};
            const auto& first = recipe.infrared[consumed_clusters];
            if (first.clusters.size() != 1U) {
                fail_defect_region_request(
                    result, "invalid_defect_infrared_item_payload");
                return false;
            }
            item.enabled = first.enabled;
            item.strength = first.strength;
            item.clusters.reserve(source.cluster_count);
            for (std::uint32_t ordinal = 0U;
                 ordinal < source.cluster_count;
                 ++ordinal) {
                const std::size_t flat_index = consumed_clusters + ordinal;
                auto& singleton = recipe.infrared[flat_index];
                if (singleton.clusters.size() != 1U ||
                    singleton.enabled != item.enabled ||
                    singleton.strength != item.strength) {
                    fail_defect_region_request(
                        result, "invalid_defect_infrared_item_payload");
                    return false;
                }
                cluster_to_item[flat_index] = item_index;
                cluster_ordinal[flat_index] = ordinal;
                item.clusters.push_back(std::move(singleton.clusters.front()));
            }
            consumed_clusters += source.cluster_count;
            grouped.push_back(std::move(item));
        }
        if (consumed_clusters != flat_cluster_count) {
            fail_defect_region_request(
                result, "invalid_defect_infrared_item_payload");
            return false;
        }

        std::vector<negaflow::pipeline::DefectRecipeEditRef> collapsed_order{};
        collapsed_order.reserve(
            recipe.order.size() - flat_cluster_count + grouped.size());
        std::vector<std::uint8_t> referenced_items(grouped.size(), 0U);
        std::size_t active_item = absent;
        std::size_t expected_ordinal = 0U;
        for (const auto reference : recipe.order) {
            if (reference.kind !=
                negaflow::pipeline::DefectRecipeEditKind::infrared) {
                if (active_item != absent) {
                    fail_defect_region_request(
                        result, "invalid_defect_infrared_item_payload");
                    return false;
                }
                collapsed_order.push_back(reference);
                continue;
            }
            if (reference.index >= flat_cluster_count) {
                fail_defect_region_request(
                    result, "invalid_defect_infrared_item_payload");
                return false;
            }
            const std::size_t item_index = cluster_to_item[reference.index];
            const std::size_t ordinal = cluster_ordinal[reference.index];
            if (item_index == absent || ordinal == absent) {
                fail_defect_region_request(
                    result, "invalid_defect_infrared_item_payload");
                return false;
            }
            if (ordinal == 0U) {
                if (active_item != absent || referenced_items[item_index] != 0U) {
                    fail_defect_region_request(
                        result, "invalid_defect_infrared_item_payload");
                    return false;
                }
                referenced_items[item_index] = 1U;
                collapsed_order.push_back({
                    negaflow::pipeline::DefectRecipeEditKind::infrared,
                    item_index,
                });
                active_item = grouped[item_index].clusters.size() == 1U
                    ? absent
                    : item_index;
                expected_ordinal = 1U;
            } else {
                if (active_item != item_index || ordinal != expected_ordinal) {
                    fail_defect_region_request(
                        result, "invalid_defect_infrared_item_payload");
                    return false;
                }
                ++expected_ordinal;
                if (expected_ordinal == grouped[item_index].clusters.size()) {
                    active_item = absent;
                }
            }
        }
        if (active_item != absent ||
            !std::all_of(
                referenced_items.begin(),
                referenced_items.end(),
                [](const std::uint8_t value) { return value != 0U; })) {
            fail_defect_region_request(
                result, "invalid_defect_infrared_item_payload");
            return false;
        }

        recipe.infrared = std::move(grouped);
        recipe.order = std::move(collapsed_order);
        return true;
    } catch (const std::bad_alloc&) {
        fail_defect_region_request(
            result, "defect_infrared_recipe_allocation_failed");
        return false;
    }
}

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

[[nodiscard]] bool prepare_result_v8(
    const nf_develop_export_request_v8* const request,
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

[[nodiscard]] bool prepare_result_v9(
    const nf_develop_export_request_v9* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v10(
    const nf_develop_export_request_v10* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v11(
    const nf_develop_export_request_v11* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v10.v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v12(
    const nf_develop_export_request_v12* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v11.v10.v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v13(
    const nf_develop_export_request_v13* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v12.v11.v10.v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v14(
    const nf_develop_export_request_v14* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v13.v12.v11.v10.v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v15(
    const nf_develop_export_request_v15* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v14.v13.v12.v11.v10.v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v16(
    const nf_develop_export_request_v16* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v15.v14.v13.v12.v11.v10.v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v17(
    const nf_develop_export_request_v17* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v18(
    const nf_develop_export_request_v18* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v19(
    const nf_develop_export_request_v19* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v20(
    const nf_develop_export_request_v20* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v21(
    const nf_develop_export_request_v21* const request,
    nf_develop_export_result_v2* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
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
    const nf_develop_export_request_v21* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8.struct_size <
            static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v24(
    const nf_develop_export_request_v24* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
                .struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v25(
    const nf_develop_export_request_v25* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
                .struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
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

[[nodiscard]] bool prepare_result_v26(
    const nf_develop_export_request_v26* const request,
    nf_develop_export_result_v3* const result,
    nf_status_t& status) noexcept {
    if (request == nullptr || result == nullptr) {
        status = NF_STATUS_INVALID_ARGUMENT;
        return false;
    }
    if (request->v25.v24.v21.v20.v19.v18.v17.v16.v15.v14.v13.v12.v11.v10.v9.v8
                .struct_size < static_cast<std::uint32_t>(sizeof(*request)) ||
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

// The run state is optional. When present it is zeroed except for the caller's cancel
// latch, so a stale stage or progress reading from an earlier call cannot be mistaken for
// this one.
[[nodiscard]] bool prepare_run_state(
    nf_develop_run_state_v1* const run_state,
    negaflow::pipeline::DevelopRunControl& control,
    nf_status_t& status) noexcept {
    if (run_state == nullptr) {
        status = NF_STATUS_OK;
        return true;
    }
    if (run_state->struct_size < static_cast<std::uint32_t>(sizeof(*run_state))) {
        status = NF_STATUS_STRUCT_TOO_SMALL;
        return false;
    }
    run_state->stage = NF_DEVELOP_STAGE_NONE;
    run_state->progress_permille = 0U;
    control.cancel_flag = &run_state->cancel_requested;
    control.progress_stage = &run_state->stage;
    control.progress_permille = &run_state->progress_permille;
    status = NF_STATUS_OK;
    return true;
}

// A request the mapper refused never reaches the pipeline, so its rejection is written
// into the v2 result the mapper knows about and copied across here. Only the fields the
// mapper actually sets are carried; everything else stays zeroed.
void write_request_rejection_v3(
    const nf_develop_export_result_v2& mapping_result,
    nf_develop_export_result_v3& result) noexcept {
    result.succeeded = 0U;
    result.failed_stage = mapping_result.failed_stage;
    std::memcpy(
        result.failure_name,
        mapping_result.failure_name,
        sizeof(result.failure_name));
    result.native_error_code = mapping_result.native_error_code;
    result.cleanup_error_code = mapping_result.cleanup_error_code;
    result.cancelled = 0U;
}

void write_outcome_v3(
    const negaflow::pipeline::DevelopExportOutcome& outcome,
    const std::uint64_t wall_microseconds,
    nf_develop_export_result_v3& result) noexcept {
    nf_develop_export_result_v2 shared{};
    shared.struct_size = static_cast<std::uint32_t>(sizeof(shared));
    write_outcome_v2(outcome, wall_microseconds, shared);

    const std::uint32_t declared_size = result.struct_size;
    result.succeeded = shared.succeeded;
    result.failed_stage = shared.failed_stage;
    std::memcpy(result.failure_name, shared.failure_name, sizeof(result.failure_name));
    result.native_error_code = shared.native_error_code;
    result.cleanup_error_code = shared.cleanup_error_code;
    result.image_width = shared.image_width;
    result.image_height = shared.image_height;
    result.film_look_route = shared.film_look_route;
    result.film_look_color_applied = shared.film_look_color_applied;
    result.film_look_acutance_applied = shared.film_look_acutance_applied;
    result.source_file_bytes = shared.source_file_bytes;
    result.output_file_bytes = shared.output_file_bytes;
    result.film_look_workspace_bytes = shared.film_look_workspace_bytes;
    result.wall_microseconds = shared.wall_microseconds;
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        result.applied_dmin[channel] = shared.applied_dmin[channel];
    }
    result.base_source = shared.base_source;
    result.cancelled = outcome.cancelled ? 1U : 0U;
    result.reserved = 0U;
    result.struct_size = declared_size;
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

nf_status_t NF_CALL nf_develop_export_v8(
    const nf_develop_export_request_v8* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v8(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v8(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v9(
    const nf_develop_export_request_v9* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v9(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v9(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v10(
    const nf_develop_export_request_v10* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v10(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v10(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v11(
    const nf_develop_export_request_v11* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v11(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v11(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v12(
    const nf_develop_export_request_v12* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v12(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v12(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v13(
    const nf_develop_export_request_v13* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v13(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v13(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v14(
    const nf_develop_export_request_v14* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v14(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v14(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v15(
    const nf_develop_export_request_v15* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v15(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v15(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v16(
    const nf_develop_export_request_v16* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v16(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v16(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v17(
    const nf_develop_export_request_v17* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v17(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v17(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v18(
    const nf_develop_export_request_v18* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v18(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v18(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v19(
    const nf_develop_export_request_v19* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v19(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v19(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v20(
    const nf_develop_export_request_v20* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v20(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v20(*request, true, pipeline_request, *result)) {
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v2(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v21(
    const nf_develop_export_request_v21* const request,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v21(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v21(*request, true, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v8(
    const nf_develop_export_request_v8* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v8(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v8(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v9(
    const nf_develop_export_request_v9* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v9(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v9(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v10(
    const nf_develop_export_request_v10* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v10(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v10(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v11(
    const nf_develop_export_request_v11* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v11(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v11(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v12(
    const nf_develop_export_request_v12* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v12(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v12(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v13(
    const nf_develop_export_request_v13* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v13(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v13(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v14(
    const nf_develop_export_request_v14* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v14(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v14(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v15(
    const nf_develop_export_request_v15* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v15(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v15(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v16(
    const nf_develop_export_request_v16* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v16(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v16(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v17(
    const nf_develop_export_request_v17* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v17(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v17(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v18(
    const nf_develop_export_request_v18* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v18(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v18(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v19(
    const nf_develop_export_request_v19* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v19(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v19(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v20(
    const nf_develop_export_request_v20* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v20(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v20(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_preview_v21(
    const nf_develop_export_request_v21* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_export_result_v2* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v21(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    if (!map_request_v21(*request, false, pipeline_request, *result)) {
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

nf_status_t NF_CALL nf_develop_export_v22(
    const nf_develop_export_request_v21* const request,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v3(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v21(*request, true, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request, control);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v3(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v22(
    const nf_develop_export_request_v21* const request,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v3(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v21(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes),
            control);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v3(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v23(
    const nf_develop_export_request_v21* const request,
    const nf_soft_proof_v1* const soft_proof,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v3(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopPreviewProof proof{};
    if (soft_proof != nullptr) {
        if (soft_proof->struct_size < static_cast<std::uint32_t>(sizeof(*soft_proof))) {
            return NF_STATUS_STRUCT_TOO_SMALL;
        }
        proof.enabled = soft_proof->enabled != 0U;
        proof.simulate_paper_and_black_ink =
            soft_proof->simulate_paper_and_black_ink != 0U;
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            proof.paper.white[channel] =
                static_cast<double>(soft_proof->paper_white_rgb[channel]);
            proof.paper.black[channel] =
                static_cast<double>(soft_proof->black_ink_rgb[channel]);
        }
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v21(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes),
            control,
            proof);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v3(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v24(
    const nf_develop_export_request_v24* const request,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v24(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v24(*request, true, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request, control);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v3(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v24(
    const nf_develop_export_request_v24* const request,
    const nf_soft_proof_v1* const soft_proof,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v24(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopPreviewProof proof{};
    if (soft_proof != nullptr) {
        if (soft_proof->struct_size < static_cast<std::uint32_t>(sizeof(*soft_proof))) {
            return NF_STATUS_STRUCT_TOO_SMALL;
        }
        proof.enabled = soft_proof->enabled != 0U;
        proof.simulate_paper_and_black_ink =
            soft_proof->simulate_paper_and_black_ink != 0U;
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            proof.paper.white[channel] =
                static_cast<double>(soft_proof->paper_white_rgb[channel]);
            proof.paper.black[channel] =
                static_cast<double>(soft_proof->black_ink_rgb[channel]);
        }
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v24(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes),
            control,
            proof);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v3(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v25(
    const nf_develop_export_request_v25* const request,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v25(request, result, status)) {
        return status;
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v25(*request, true, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_and_export(pipeline_request, control);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v3(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v25(
    const nf_develop_export_request_v25* const request,
    const nf_soft_proof_v1* const soft_proof,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v25(request, result, status)) {
        return status;
    }
    if (pixels == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    negaflow::pipeline::DevelopPreviewProof proof{};
    if (soft_proof != nullptr) {
        if (soft_proof->struct_size < static_cast<std::uint32_t>(sizeof(*soft_proof))) {
            return NF_STATUS_STRUCT_TOO_SMALL;
        }
        proof.enabled = soft_proof->enabled != 0U;
        proof.simulate_paper_and_black_ink =
            soft_proof->simulate_paper_and_black_ink != 0U;
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            proof.paper.white[channel] =
                static_cast<double>(soft_proof->paper_white_rgb[channel]);
            proof.paper.black[channel] =
                static_cast<double>(soft_proof->black_ink_rgb[channel]);
        }
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v25(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::DevelopExportOutcome outcome =
        negaflow::pipeline::develop_preview(
            pipeline_request,
            maximum_width,
            maximum_height,
            pixels,
            static_cast<std::size_t>(pixel_capacity_bytes),
            control,
            proof);
    const auto finished = std::chrono::steady_clock::now();
    write_outcome_v3(outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_export_v26(
    const nf_develop_export_request_v26* const request,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v26(request, result, status)) return status;
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) return status;
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v26(*request, true, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const auto outcome = negaflow::pipeline::develop_and_export(pipeline_request, control);
    write_outcome_v3(outcome, elapsed_microseconds(started, std::chrono::steady_clock::now()), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_preview_v26(
    const nf_develop_export_request_v26* const request,
    const nf_soft_proof_v1* const soft_proof,
    const uint32_t maximum_width,
    const uint32_t maximum_height,
    uint8_t* const pixels,
    const uint32_t pixel_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v26(request, result, status)) return status;
    if (pixels == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    negaflow::pipeline::DevelopPreviewProof proof{};
    if (soft_proof != nullptr) {
        if (soft_proof->struct_size < static_cast<std::uint32_t>(sizeof(*soft_proof))) {
            return NF_STATUS_STRUCT_TOO_SMALL;
        }
        proof.enabled = soft_proof->enabled != 0U;
        proof.simulate_paper_and_black_ink =
            soft_proof->simulate_paper_and_black_ink != 0U;
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            proof.paper.white[channel] = static_cast<double>(soft_proof->paper_white_rgb[channel]);
            proof.paper.black[channel] = static_cast<double>(soft_proof->black_ink_rgb[channel]);
        }
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) return status;
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v26(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const auto outcome = negaflow::pipeline::develop_preview(
        pipeline_request, maximum_width, maximum_height, pixels,
        static_cast<std::size_t>(pixel_capacity_bytes), control, proof);
    write_outcome_v3(outcome, elapsed_microseconds(started, std::chrono::steady_clock::now()), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_read_soft_proof_media_v1(
    const uint8_t* const icc_bytes,
    const uint32_t icc_byte_count,
    nf_soft_proof_media_v1* const result) {
    if (result == nullptr || (icc_bytes == nullptr && icc_byte_count != 0U)) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }

    const std::span<const std::uint8_t> bytes{
        icc_bytes,
        static_cast<std::size_t>(icc_byte_count)};
    const negaflow::color::SoftProofMedia media =
        negaflow::color::read_soft_proof_media(bytes);
    const negaflow::color::SoftProofPaper paper =
        negaflow::color::soft_proof_paper(media);

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->is_rgb_output_profile =
        negaflow::color::is_rgb_output_profile(bytes) ? 1U : 0U;
    result->has_white = media.has_white ? 1U : 0U;
    result->has_black = media.has_black ? 1U : 0U;
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        result->paper_white_rgb[channel] = static_cast<float>(paper.white[channel]);
        result->black_ink_rgb[channel] = static_cast<float>(paper.black[channel]);
    }
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_auto_adjust_v1(
    const uint8_t* const pixels,
    const uint32_t width,
    const uint32_t height,
    const uint32_t stride_bytes,
    nf_auto_adjust_result_v1* const result) {
    if (pixels == nullptr || result == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }

    negaflow::imaging::AutoAdjustStats stats{};
    if (!negaflow::imaging::compute_auto_adjust_stats(
            pixels,
            width,
            height,
            static_cast<std::size_t>(stride_bytes),
            stats)) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    const negaflow::imaging::AutoToneResult tone = negaflow::imaging::auto_tone(stats);
    const negaflow::imaging::AutoWhiteBalanceResult balance =
        negaflow::imaging::auto_white_balance(stats);

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->exposure = tone.exposure;
    result->contrast = tone.contrast;
    result->highlights = tone.highlights;
    result->shadows = tone.shadows;
    result->whites = tone.whites;
    result->blacks = tone.blacks;
    result->density = tone.density;
    result->vibrance = tone.vibrance;
    result->warmth = balance.warmth;
    result->tint = balance.tint;
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_detect_infrared_defects_v1(
    const float* const infrared,
    const uint32_t infrared_stride_bytes,
    const float* const red,
    const uint32_t red_stride_bytes,
    const uint32_t width,
    const uint32_t height,
    const nf_infrared_detector_parameters_v1* const parameters,
    const uint32_t* const cancel_requested,
    nf_infrared_detection_summary_v1* const summary,
    nf_infrared_detection_handle_v1** const handle) {
    if (summary == nullptr || handle == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    *handle = nullptr;
    if (summary->struct_size < static_cast<std::uint32_t>(sizeof(*summary))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    if (infrared == nullptr || red == nullptr || parameters == nullptr ||
        parameters->struct_size < static_cast<std::uint32_t>(sizeof(*parameters)) ||
        parameters->reserved != 0U || parameters->reserved2 != 0U ||
        width == 0U || height == 0U) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    const std::uint64_t row_bytes = static_cast<std::uint64_t>(width) * sizeof(float);
    if (row_bytes > std::numeric_limits<std::uint32_t>::max() ||
        infrared_stride_bytes < row_bytes || red_stride_bytes < row_bytes) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    const std::uint32_t declared_size = summary->struct_size;
    std::memset(summary, 0, sizeof(*summary));
    summary->struct_size = declared_size;
    try {
        const std::size_t area = static_cast<std::size_t>(width) * height;
        if (height != 0U && area / height != width) {
            return NF_STATUS_INVALID_ARGUMENT;
        }
        std::vector<float> infrared_copy{};
        std::vector<float> red_copy{};
        std::span<const float> infrared_plane{};
        std::span<const float> red_plane{};
        if (infrared_stride_bytes == row_bytes) {
            infrared_plane = std::span<const float>(infrared, area);
        } else {
            infrared_copy.resize(area);
            const auto* bytes = reinterpret_cast<const std::uint8_t*>(infrared);
            for (std::uint32_t y = 0U; y < height; ++y) {
                std::memcpy(
                    infrared_copy.data() + static_cast<std::size_t>(y) * width,
                    bytes + static_cast<std::size_t>(y) * infrared_stride_bytes,
                    static_cast<std::size_t>(row_bytes));
            }
            infrared_plane = infrared_copy;
        }
        if (red_stride_bytes == row_bytes) {
            red_plane = std::span<const float>(red, area);
        } else {
            red_copy.resize(area);
            const auto* bytes = reinterpret_cast<const std::uint8_t*>(red);
            for (std::uint32_t y = 0U; y < height; ++y) {
                std::memcpy(
                    red_copy.data() + static_cast<std::size_t>(y) * width,
                    bytes + static_cast<std::size_t>(y) * red_stride_bytes,
                    static_cast<std::size_t>(row_bytes));
            }
            red_plane = red_copy;
        }

        auto detection = negaflow::imaging::detect_infrared_defects(
            infrared_plane,
            red_plane,
            width,
            height,
            infrared_parameters(*parameters),
            negaflow::core::CancelFlag{cancel_requested});
        return publish_infrared_detection(std::move(detection), summary, handle);
    } catch (const std::bad_alloc&) {
        summary->status = NF_INFRARED_DETECTION_ALLOCATION_FAILED;
        return NF_STATUS_OK;
    }
}

nf_status_t NF_CALL nf_detect_infrared_defects_from_tiff_v1(
    const wchar_t* const visible_path,
    const wchar_t* const infrared_path,
    const nf_infrared_detector_parameters_v1* const parameters,
    const uint32_t* const cancel_requested,
    nf_infrared_detection_summary_v1* const summary,
    nf_infrared_detection_handle_v1** const handle) {
    if (summary == nullptr || handle == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    *handle = nullptr;
    if (summary->struct_size < static_cast<std::uint32_t>(sizeof(*summary))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    if (visible_path == nullptr || visible_path[0] == L'\0' ||
        infrared_path == nullptr || infrared_path[0] == L'\0' ||
        parameters == nullptr ||
        parameters->struct_size < static_cast<std::uint32_t>(sizeof(*parameters)) ||
        parameters->reserved != 0U || parameters->reserved2 != 0U) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    const std::uint32_t declared_size = summary->struct_size;
    std::memset(summary, 0, sizeof(*summary));
    summary->struct_size = declared_size;
    const negaflow::core::CancelFlag cancel{cancel_requested};
    if (cancel.requested()) {
        summary->status = NF_INFRARED_DETECTION_CANCELLED;
        return NF_STATUS_OK;
    }
    try {
        negaflow::imageio::WicTiffDecodeControl control{};
        control.rows_per_copy = 32U;
        InfraredPlaneSink visible_sink{false, cancel};
        const auto visible = negaflow::imageio::decode_tiff_rows_with_wic(
            std::filesystem::path{visible_path}, visible_sink, {}, control);
        if (cancel.requested()) {
            summary->status = NF_INFRARED_DETECTION_CANCELLED;
            return NF_STATUS_OK;
        }
        if (visible.status != negaflow::imageio::WicTiffDecodeStatus::ok ||
            !visible_sink.complete()) {
            summary->status = NF_INFRARED_DETECTION_UNREADABLE;
            return NF_STATUS_OK;
        }

        InfraredPlaneSink infrared_sink{true, cancel};
        const auto infrared = negaflow::imageio::decode_tiff_rows_with_wic(
            std::filesystem::path{infrared_path}, infrared_sink, {}, control);
        if (cancel.requested()) {
            summary->status = NF_INFRARED_DETECTION_CANCELLED;
            return NF_STATUS_OK;
        }
        if (infrared.status != negaflow::imageio::WicTiffDecodeStatus::ok ||
            !infrared_sink.complete() ||
            infrared_sink.width() != visible_sink.width() ||
            infrared_sink.height() != visible_sink.height()) {
            summary->status = NF_INFRARED_DETECTION_UNREADABLE;
            return NF_STATUS_OK;
        }

        auto detection = negaflow::imaging::detect_infrared_defects(
            infrared_sink.values(),
            visible_sink.values(),
            visible_sink.width(),
            visible_sink.height(),
            infrared_parameters(*parameters),
            cancel);
        return publish_infrared_detection(std::move(detection), summary, handle);
    } catch (const std::bad_alloc&) {
        summary->status = NF_INFRARED_DETECTION_ALLOCATION_FAILED;
        return NF_STATUS_OK;
    } catch (...) {
        summary->status = NF_INFRARED_DETECTION_UNREADABLE;
        return NF_STATUS_OK;
    }
}

nf_status_t NF_CALL nf_infrared_detection_get_cluster_v1(
    const nf_infrared_detection_handle_v1* const handle,
    const uint64_t index,
    nf_infrared_cluster_v1* const cluster,
    uint8_t* const core_mask,
    const uint64_t core_mask_capacity_bytes,
    uint16_t* const attenuation_r16,
    const uint64_t attenuation_capacity_values) {
    if (handle == nullptr || cluster == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    if (cluster->struct_size < static_cast<std::uint32_t>(sizeof(*cluster))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    if (index >= handle->detection.clusters.size()) return NF_STATUS_INVALID_ARGUMENT;
    const auto& source = handle->detection.clusters[static_cast<std::size_t>(index)];
    const std::uint32_t declared_size = cluster->struct_size;
    std::memset(cluster, 0, sizeof(*cluster));
    cluster->struct_size = declared_size;
    cluster->roi_x = source.roi_x;
    cluster->roi_y_up = source.roi_y_up;
    cluster->width = source.width;
    cluster->height = source.height;
    cluster->core_mask_byte_count = source.core_mask.size();
    cluster->attenuation_value_count = source.attenuation_r16.size();
    if ((core_mask == nullptr) != (core_mask_capacity_bytes == 0U) ||
        (attenuation_r16 == nullptr) != (attenuation_capacity_values == 0U)) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (core_mask == nullptr && attenuation_r16 == nullptr) return NF_STATUS_OK;
    if (core_mask_capacity_bytes < source.core_mask.size() ||
        attenuation_capacity_values < source.attenuation_r16.size()) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (core_mask != nullptr) {
        std::memcpy(core_mask, source.core_mask.data(), source.core_mask.size());
    }
    if (attenuation_r16 != nullptr) {
        std::memcpy(
            attenuation_r16,
            source.attenuation_r16.data(),
            source.attenuation_r16.size() * sizeof(std::uint16_t));
    }
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_infrared_detection_get_component_v1(
    const nf_infrared_detection_handle_v1* const handle,
    const uint64_t index,
    nf_infrared_component_v1* const component,
    nf_infrared_preview_point_v1* const preview_points,
    const uint64_t preview_point_capacity) {
    if (handle == nullptr || component == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    if (component->struct_size < static_cast<std::uint32_t>(sizeof(*component))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    if (index >= handle->detection.components.size()) return NF_STATUS_INVALID_ARGUMENT;
    const auto& source = handle->detection.components[static_cast<std::size_t>(index)];
    const std::uint32_t declared_size = component->struct_size;
    std::memset(component, 0, sizeof(*component));
    component->struct_size = declared_size;
    component->classification = static_cast<std::uint32_t>(source.classification);
    component->confidence = source.confidence;
    component->area = source.area;
    component->preview_point_count = source.preview_points.size();
    if ((preview_points == nullptr) != (preview_point_capacity == 0U)) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (preview_points == nullptr) return NF_STATUS_OK;
    if (preview_point_capacity < source.preview_points.size()) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    for (std::size_t ordinal = 0U; ordinal < source.preview_points.size(); ++ordinal) {
        preview_points[ordinal] = nf_infrared_preview_point_v1{
            source.preview_points[ordinal].x,
            source.preview_points[ordinal].y};
    }
    return NF_STATUS_OK;
}

void NF_CALL nf_infrared_detection_destroy_v1(
    nf_infrared_detection_handle_v1* const handle) {
    delete handle;
}

nf_status_t NF_CALL nf_detect_flatbed_frame_grid_v1(
    const float* const luminance,
    const uint32_t stride_bytes,
    const uint32_t width,
    const uint32_t height,
    const double physical_width_mm,
    const double physical_height_mm,
    const uint32_t format,
    const uint32_t* const cancel_requested,
    nf_flatbed_frame_grid_summary_v1* const summary,
    nf_flatbed_frame_grid_handle_v1** const handle) {
    if (summary == nullptr || handle == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    *handle = nullptr;
    if (summary->struct_size < static_cast<std::uint32_t>(sizeof(*summary))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    negaflow::imaging::FlatbedFrameFormat native_format{};
    const std::uint64_t row_bytes = static_cast<std::uint64_t>(width) * sizeof(float);
    if (luminance == nullptr || width == 0U || height == 0U ||
        !std::isfinite(physical_width_mm) || !std::isfinite(physical_height_mm) ||
        physical_width_mm <= 0.0 || physical_height_mm <= 0.0 ||
        row_bytes > std::numeric_limits<std::uint32_t>::max() ||
        stride_bytes < row_bytes || !flatbed_frame_format(format, native_format)) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    const std::uint32_t declared_size = summary->struct_size;
    std::memset(summary, 0, sizeof(*summary));
    summary->struct_size = declared_size;
    try {
        const std::size_t area = static_cast<std::size_t>(width) * height;
        if (area / height != width) return NF_STATUS_INVALID_ARGUMENT;
        std::vector<float> copy{};
        std::span<const float> plane{};
        if (stride_bytes == row_bytes) {
            plane = std::span<const float>(luminance, area);
        } else {
            copy.resize(area);
            const auto* const bytes = reinterpret_cast<const std::uint8_t*>(luminance);
            for (std::uint32_t y = 0U; y < height; ++y) {
                std::memcpy(copy.data() + static_cast<std::size_t>(y) * width,
                            bytes + static_cast<std::size_t>(y) * stride_bytes,
                            static_cast<std::size_t>(row_bytes));
            }
            plane = copy;
        }
        auto result = negaflow::imaging::detect_flatbed_frame_grid(
            {plane, width, height, physical_width_mm, physical_height_mm},
            native_format,
            {cancel_requested});
        summary->status = flatbed_frame_grid_status(result.status);
        summary->detection_count = result.detections.size();
        if (result.status != negaflow::imaging::FlatbedFrameGridStatus::ok) {
            return NF_STATUS_OK;
        }
        auto* const owned = new (std::nothrow) nf_flatbed_frame_grid_handle_v1{};
        if (owned == nullptr) {
            summary->status = NF_FLATBED_FRAME_GRID_ALLOCATION_FAILED;
            summary->detection_count = 0U;
            return NF_STATUS_OK;
        }
        owned->detections = std::move(result.detections);
        *handle = owned;
        return NF_STATUS_OK;
    } catch (const std::bad_alloc&) {
        summary->status = NF_FLATBED_FRAME_GRID_ALLOCATION_FAILED;
        return NF_STATUS_OK;
    }
}

nf_status_t NF_CALL nf_flatbed_frame_grid_get_detection_v1(
    const nf_flatbed_frame_grid_handle_v1* const handle,
    const uint64_t index,
    nf_flatbed_frame_detection_v1* const detection) {
    if (handle == nullptr || detection == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    if (detection->struct_size < static_cast<std::uint32_t>(sizeof(*detection))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    if (index >= handle->detections.size()) return NF_STATUS_INVALID_ARGUMENT;
    const auto& source = handle->detections[static_cast<std::size_t>(index)];
    const std::uint32_t declared_size = detection->struct_size;
    std::memset(detection, 0, sizeof(*detection));
    detection->struct_size = declared_size;
    detection->row = source.row;
    detection->column = source.column;
    detection->x = source.x;
    detection->y = source.y;
    detection->width = source.width;
    detection->height = source.height;
    detection->confidence = source.confidence;
    return NF_STATUS_OK;
}

void NF_CALL nf_flatbed_frame_grid_destroy_v1(
    nf_flatbed_frame_grid_handle_v1* const handle) {
    delete handle;
}

nf_status_t NF_CALL nf_probe_tiff_source_v1(
    const wchar_t* const source_path,
    nf_tiff_source_info_v1* const result) {
    if (result == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    if (result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    if (source_path == nullptr || source_path[0] == L'\0') return NF_STATUS_INVALID_ARGUMENT;

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    try {
        const negaflow::core::TiffProbeResult probe =
            negaflow::core::probe_tiff_file(std::filesystem::path{source_path});
        if (probe.status != negaflow::core::TiffProbeStatus::ok) {
            result->status = NF_TIFF_SOURCE_PROBE_UNREADABLE;
            return NF_STATUS_OK;
        }
        const auto& info = probe.info;
        if (info.width == 0U || info.height == 0U ||
            info.width > std::numeric_limits<std::uint32_t>::max() ||
            info.height > std::numeric_limits<std::uint32_t>::max() ||
            info.samples_per_pixel == 0U || info.bits_per_sample_count == 0U ||
            info.sample_format_count == 0U || info.bits_per_sample[0] == 0U ||
            info.sample_format[0] == 0U || info.orientation == 0U || info.orientation > 8U) {
            result->status = NF_TIFF_SOURCE_PROBE_UNSUPPORTED;
            return NF_STATUS_OK;
        }
        result->status = NF_TIFF_SOURCE_PROBE_OK;
        result->pixel_width = static_cast<std::uint32_t>(info.width);
        result->pixel_height = static_cast<std::uint32_t>(info.height);
        result->samples_per_pixel = info.samples_per_pixel;
        result->bits_per_sample = info.bits_per_sample[0];
        result->sample_format = info.sample_format[0];
        result->orientation = info.orientation;
        result->file_bytes = info.file_bytes;
        return NF_STATUS_OK;
    } catch (...) {
        result->status = NF_TIFF_SOURCE_PROBE_UNREADABLE;
        return NF_STATUS_OK;
    }
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
