#include "negaflow/pipeline/develop_export.h"

#include "negaflow/color/srgb_transfer.h"
#include "negaflow/core/parallel_rows.h"
#include "negaflow/core/pixel.h"
#include "negaflow/core/pointwise.h"
#include "negaflow/imaging/display_gamut_map.h"
#include "negaflow/imaging/working_image_resample.h"
#include "negaflow/imageio/wic_standard_image_decoder.h"
#include "negaflow/pipeline/film_look_workspace.h"

#include <cstring>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cwchar>
#include <stop_token>
#include <utility>

namespace negaflow::pipeline {
namespace {

[[nodiscard]] bool is_tiff_source(const std::filesystem::path& path) noexcept {
    const std::wstring extension = path.extension().wstring();
    return _wcsicmp(extension.c_str(), L".tif") == 0 ||
           _wcsicmp(extension.c_str(), L".tiff") == 0;
}

[[nodiscard]] DevelopExportOutcome fail(
    const DevelopExportStage stage,
    const char* const name,
    const std::uint32_t native_error_code = 0U,
    const std::uint32_t cleanup_error_code = 0U) noexcept {
    DevelopExportOutcome outcome{};
    outcome.succeeded = false;
    outcome.failed_stage = stage;
    outcome.failure_name = name;
    outcome.native_error_code = native_error_code;
    outcome.cleanup_error_code = cleanup_error_code;
    return outcome;
}

}  // namespace

const char* develop_export_stage_name(const DevelopExportStage stage) noexcept {
    switch (stage) {
        case DevelopExportStage::none:
            return "none";
        case DevelopExportStage::request_validation:
            return "request_validation";
        case DevelopExportStage::observe_source_before:
            return "observe_source_before";
        case DevelopExportStage::decode:
            return "decode";
        case DevelopExportStage::observe_source_after:
            return "observe_source_after";
        case DevelopExportStage::film_look_workspace:
            return "film_look_workspace";
        case DevelopExportStage::develop:
            return "develop";
        case DevelopExportStage::tone_adjust:
            return "tone_adjust";
        case DevelopExportStage::film_look:
            return "film_look";
        case DevelopExportStage::output:
            return "output";
        case DevelopExportStage::grain_mend:
            return "grain_mend";
        case DevelopExportStage::film_scan_denoise:
            return "film_scan_denoise";
        case DevelopExportStage::local_dodge_burn:
            return "local_dodge_burn";
        case DevelopExportStage::texture:
            return "texture";
        case DevelopExportStage::black_and_white:
            return "black_and_white";
        case DevelopExportStage::image_transform:
            return "image_transform";
        case DevelopExportStage::output_sharpening:
            return "output_sharpening";
        case DevelopExportStage::color_model:
            return "color_model";
        case DevelopExportStage::scene_correction:
            return "scene_correction";
        case DevelopExportStage::target_grade:
            return "target_grade";
        case DevelopExportStage::defect_component_repair:
            return "defect_component_repair";
        case DevelopExportStage::defect_clone_stamp:
            return "defect_clone_stamp";
        case DevelopExportStage::defect_brush:
            return "defect_brush";
    }
    return "unknown_stage";
}

namespace {

// Relative cost of each stage, used only to move the progress figure at a roughly even
// rate. The numbers come from a 3278x4944 16-bit scan measured on x64 Release, expressed
// in units of about a millisecond; a stage that will not run this time contributes almost
// nothing. They steer a progress bar and nothing else — no result depends on them.
struct StageCost final {
    std::uint32_t idle;
    std::uint32_t active;
};

constexpr StageCost decode_cost{170U, 170U};
constexpr StageCost defect_cost{1U, 60U};
constexpr StageCost auto_base_cost{1U, 30U};
constexpr StageCost invert_cost{1U, 250U};
constexpr StageCost scene_correction_cost{2U, 40U};
constexpr StageCost target_grade_cost{1U, 60U};
constexpr StageCost color_model_cost{5U, 60U};
constexpr StageCost tone_cost{5U, 290U};
constexpr StageCost film_look_cost{5U, 300U};
constexpr StageCost grain_mend_cost{2U, 900U};
constexpr StageCost denoise_cost{2U, 200U};
constexpr StageCost dodge_burn_cost{1U, 80U};
constexpr StageCost texture_cost{2U, 120U};
constexpr StageCost black_and_white_cost{1U, 20U};
constexpr StageCost transform_cost{1U, 40U};
constexpr StageCost output_sharpening_cost{1U, 80U};
constexpr StageCost preview_output_cost{60U, 60U};
constexpr StageCost export_output_cost{2600U, 2600U};

[[nodiscard]] constexpr std::uint32_t cost_of(
    const StageCost cost,
    const bool active) noexcept {
    return active ? cost.active : cost.idle;
}

// Owns the two things a long blocking call has to offer a UI: a way to stop it and a way
// to see where it is. Both are polled through caller-owned words, so nothing here calls
// back into managed code and nothing has to stay alive beyond the call.
class RunTracker final {
public:
    RunTracker(const DevelopRunControl& control, const std::uint32_t total_cost) noexcept
        : control_{control},
          total_cost_{total_cost == 0U ? 1U : total_cost} {}

    [[nodiscard]] bool cancelled() const noexcept {
        if (control_.cancel_flag == nullptr) {
            return false;
        }
        return std::atomic_ref<std::uint32_t>(*control_.cancel_flag)
                   .load(std::memory_order_relaxed) != 0U;
    }

    // Announces the stage about to run and how much of the remaining budget it owns.
    void begin(const DevelopExportStage stage, const std::uint32_t cost) noexcept {
        stage_cost_ = cost;
        if (control_.progress_stage != nullptr) {
            std::atomic_ref<std::uint32_t>(*control_.progress_stage)
                .store(static_cast<std::uint32_t>(stage), std::memory_order_relaxed);
        }
        publish(completed_cost_);
    }

    // Sub-stage movement for the few stages long enough that a single jump would look
    // like a hang. `fraction` is clamped, so a bad estimate cannot make progress go back.
    void within(const double fraction) noexcept {
        const double bounded = std::clamp(fraction, 0.0, 1.0);
        publish(
            completed_cost_ +
            static_cast<std::uint64_t>(bounded * static_cast<double>(stage_cost_)));
    }

    void finish() noexcept {
        completed_cost_ += stage_cost_;
        stage_cost_ = 0U;
        publish(completed_cost_);
    }

    void complete() noexcept {
        if (control_.progress_permille != nullptr) {
            std::atomic_ref<std::uint32_t>(*control_.progress_permille)
                .store(develop_progress_complete, std::memory_order_relaxed);
        }
    }

private:
    void publish(const std::uint64_t reached) noexcept {
        if (control_.progress_permille == nullptr) {
            return;
        }
        const std::uint64_t permille = std::min<std::uint64_t>(
            (reached * develop_progress_complete) / total_cost_,
            develop_progress_complete);
        std::atomic_ref<std::uint32_t>(*control_.progress_permille)
            .store(static_cast<std::uint32_t>(permille), std::memory_order_relaxed);
    }

    DevelopRunControl control_{};
    std::uint32_t total_cost_{1U};
    std::uint64_t completed_cost_{0U};
    std::uint32_t stage_cost_{0U};
};

[[nodiscard]] DevelopExportOutcome cancelled_outcome(
    const DevelopExportStage stage) noexcept {
    DevelopExportOutcome outcome = fail(stage, "cancelled");
    outcome.cancelled = true;
    return outcome;
}

// Turns the caller's cancel latch into the stop token the decoder and the content hash
// already understand, and forwards row progress into the tracker. Both facilities exist
// on those calls already; this only wires them to the run-level control.
class DecodeProgressBridge final
    : public negaflow::imageio::WicTiffDecodeProgressObserver {
public:
    DecodeProgressBridge(
        RunTracker& tracker,
        std::stop_source& source) noexcept
        : tracker_{tracker}, source_{source} {}

    void report(const negaflow::imageio::WicTiffDecodeProgress progress) noexcept override {
        if (progress.total_rows != 0U) {
            tracker_.within(
                static_cast<double>(progress.completed_rows) /
                static_cast<double>(progress.total_rows));
        }
        if (tracker_.cancelled()) {
            source_.request_stop();
        }
    }

private:
    RunTracker& tracker_;
    std::stop_source& source_;
};

class HashProgressBridge final
    : public negaflow::imageio::ImageContentHashProgressObserver {
public:
    HashProgressBridge(RunTracker& tracker, std::stop_source& source) noexcept
        : tracker_{tracker}, source_{source} {}

    void report(const negaflow::imageio::ImageContentHashProgress progress) noexcept override {
        if (progress.total_bytes != 0U) {
            tracker_.within(
                static_cast<double>(progress.completed_bytes) /
                static_cast<double>(progress.total_bytes));
        }
        if (tracker_.cancelled()) {
            source_.request_stop();
        }
    }

private:
    RunTracker& tracker_;
    std::stop_source& source_;
};

// Where a run ends. Publishing writes a verified 16-bit file; a preview stops before that
// and fills the caller's display buffer. Everything before the last stage is identical, so
// the two cannot drift into producing different pixels.
// GrainMend 단계에서 멈추고 검출 결과만 받아 가는 대상입니다. preview 와 배타적입니다.
struct DetectTarget final {
    std::uint8_t* mask{nullptr};
    std::size_t capacity_bytes{0};
    GrainMendDetectionOutcome* result{nullptr};
    negaflow::imaging::GrainMendRoi roi{};
};

struct PreviewTarget final {
    std::uint32_t maximum_width{0};
    std::uint32_t maximum_height{0};
    std::uint8_t* pixels{nullptr};
    std::size_t capacity_bytes{0};
    negaflow::color::SoftProofTransfer proof{};
};

[[nodiscard]] std::uint32_t preview_extent(
    const std::uint32_t source,
    const std::uint32_t maximum) noexcept {
    return source <= maximum ? source : maximum;
}

[[nodiscard]] DevelopExportOutcome write_preview(
    const negaflow::imaging::WorkingImage& image,
    const PreviewTarget& target,
    DevelopExportOutcome outcome) noexcept {
    if (target.pixels == nullptr || target.maximum_width == 0U ||
        target.maximum_height == 0U) {
        return fail(DevelopExportStage::output, "invalid_preview_target");
    }

    const std::uint32_t source_width = image.width;
    const std::uint32_t source_height = image.height;
    if (source_width == 0U || source_height == 0U || image.stride_pixels < source_width) {
        return fail(DevelopExportStage::output, "empty_preview_source");
    }

    // Fit inside the box without changing the aspect ratio. Integer arithmetic on the
    // larger side first so a very wide frame does not round its short side to zero.
    std::uint32_t width = preview_extent(source_width, target.maximum_width);
    std::uint32_t height = static_cast<std::uint32_t>(
        (static_cast<std::uint64_t>(source_height) * width) / source_width);
    if (height == 0U) {
        height = 1U;
    }
    if (height > target.maximum_height) {
        height = target.maximum_height;
        width = static_cast<std::uint32_t>(
            (static_cast<std::uint64_t>(source_width) * height) / source_height);
        if (width == 0U) {
            width = 1U;
        }
    }

    const std::uint64_t required =
        static_cast<std::uint64_t>(width) * static_cast<std::uint64_t>(height) * 4ULL;
    if (required > target.capacity_bytes) {
        return fail(DevelopExportStage::output, "preview_buffer_too_small");
    }

    // Soft proof is an affine in linear light and the sRGB encode below is not, so it has
    // to run per source pixel before the encode - averaging encoded samples and proofing
    // afterwards would not be the same picture. When proofing is off the factors are
    // exactly 1 and 0, so the arithmetic is an identity rather than a second code path
    // that could drift from this one.
    const negaflow::color::SoftProofTransfer proof = target.proof;

    // Converted straight from the working image rather than through a full-resolution
    // 16-bit copy. On a 17 MP scan that copy was about 104 MB allocated only to be
    // averaged away, and dropping it also removes a whole pass over the frame.
    std::atomic<std::uint64_t> first_failure{negaflow::core::no_row_failure};
    negaflow::core::for_each_row_block(
        height,
        static_cast<std::uint64_t>(source_width) * source_height,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
      for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
        const std::uint32_t source_y0 =
            static_cast<std::uint32_t>((static_cast<std::uint64_t>(y) * source_height) / height);
        std::uint32_t source_y1 = static_cast<std::uint32_t>(
            (static_cast<std::uint64_t>(y + 1U) * source_height) / height);
        if (source_y1 <= source_y0) {
            source_y1 = source_y0 + 1U;
        }

        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::uint32_t source_x0 =
                static_cast<std::uint32_t>((static_cast<std::uint64_t>(x) * source_width) / width);
            std::uint32_t source_x1 = static_cast<std::uint32_t>(
                (static_cast<std::uint64_t>(x + 1U) * source_width) / width);
            if (source_x1 <= source_x0) {
                source_x1 = source_x0 + 1U;
            }

            float red = 0.0F;
            float green = 0.0F;
            float blue = 0.0F;
            std::uint32_t count = 0U;
            bool finite = true;
            for (std::uint32_t sy = source_y0; sy < source_y1; ++sy) {
                const negaflow::core::Rgba32F* const row =
                    image.pixels.data() +
                    (static_cast<std::size_t>(sy) * image.stride_pixels);
                for (std::uint32_t sx = source_x0; sx < source_x1; ++sx) {
                    const negaflow::core::Rgba32F source = row[sx];
                    if (!negaflow::core::finite_rgb(source)) {
                        finite = false;
                        break;
                    }
                    // Hue-preserving fold instead of a per-channel clamp, then the paper
                    // and ink range, then the sRGB encode the 8-bit step quantises in.
                    const negaflow::core::Rgba32F folded =
                        negaflow::imaging::tone_safe_unit_rgb(source);
                    red += negaflow::color::linear_to_srgb_encoded(
                        (folded.red * proof.scale[0]) + proof.bias[0]);
                    green += negaflow::color::linear_to_srgb_encoded(
                        (folded.green * proof.scale[1]) + proof.bias[1]);
                    blue += negaflow::color::linear_to_srgb_encoded(
                        (folded.blue * proof.scale[2]) + proof.bias[2]);
                    ++count;
                }
                if (!finite) {
                    break;
                }
            }
            if (!finite || count == 0U) {
                negaflow::core::record_row_failure_value(first_failure, y, 1U);
                return;
            }

            const float inverse_count = 1.0F / static_cast<float>(count);
            // Under one 8-bit step of noise, added in the space the quantisation happens
            // in. Without it a smooth sky bands here even though the working image is
            // perfectly smooth.
            const auto quantise = [&](const float sum,
                                      const std::uint32_t channel) noexcept {
                const float encoded = (sum * inverse_count) +
                    negaflow::imaging::display_dither_offset(x, y, channel);
                return static_cast<std::uint8_t>(
                    std::clamp(encoded, 0.0F, 1.0F) * 255.0F + 0.5F);
            };

            std::uint8_t* const destination =
                target.pixels + ((static_cast<std::size_t>(y) * width + x) * 4U);
            // BGRA8 with opaque alpha, which is what a XAML Image accepts.
            destination[0] = quantise(blue, 2U);
            destination[1] = quantise(green, 1U);
            destination[2] = quantise(red, 0U);
            destination[3] = 0xFFU;
        }
      }
        });

    if (negaflow::core::has_row_failure(
            first_failure.load(std::memory_order_relaxed))) {
        return fail(DevelopExportStage::output, "non_finite_preview_pixel");
    }

    outcome.image_width = width;
    outcome.image_height = height;
    outcome.output_file_bytes = required;
    outcome.succeeded = true;
    outcome.failure_name = "ok";
    return outcome;
}

// Adds up what this particular request will actually run. A frame with GrainMend off and
// no tone change spends nearly all its time in decode and publish, and the progress
// figure has to reflect that rather than a fixed stage list.
[[nodiscard]] std::uint32_t plan_total_cost(
    const DevelopExportRequest& request,
    const bool preview) noexcept {
    const bool negative_source = request.film_polarity == FilmPolarity::negative;
    const bool monochrome =
        request.negative.film_type ==
        negaflow::imaging::NegativeFilmType::black_and_white;
    const bool graded =
        request.develop_target != DevelopTarget::main ||
        !request.scanner_profile_id.empty();

    std::uint32_t total = 0U;
    total += cost_of(decode_cost, true);
    total += cost_of(defect_cost, !request.defect_recipe.order.empty());
    total += cost_of(
        auto_base_cost,
        negative_source &&
            request.base_estimation_mode != NegativeBaseEstimationMode::manual);
    total += cost_of(invert_cost, negative_source);
    total += cost_of(scene_correction_cost, true);
    total += cost_of(target_grade_cost, graded);
    total += cost_of(color_model_cost, true);
    total += cost_of(tone_cost, true);
    total += cost_of(
        film_look_cost,
        request.film_look.source_kind !=
            negaflow::imaging::DevelopSourceKind::film_scan);
    total += cost_of(
        grain_mend_cost,
        request.grain_mend.strength > negaflow::imaging::grain_mend_identity_threshold);
    total += cost_of(denoise_cost, request.film_scan_denoise.strength > 0.0);
    total += cost_of(
        dodge_burn_cost, !request.local_dodge_burn.adjustments.empty());
    total += cost_of(texture_cost, true);
    total += cost_of(black_and_white_cost, monochrome);
    total += cost_of(transform_cost, true);
    total += cost_of(
        output_sharpening_cost,
        request.output_sharpening.strength >
            negaflow::imaging::texture_stage_identity_threshold);
    total += cost_of(preview ? preview_output_cost : export_output_cost, true);
    return total;
}

[[nodiscard]] DevelopExportOutcome run_develop(
    const DevelopExportRequest& request,
    const PreviewTarget* const preview,
    const DevelopRunControl& control,
    const DetectTarget* const detect = nullptr) noexcept {
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
    RunTracker tracker{control, plan_total_cost(request, preview != nullptr)};
    std::stop_source stop{};
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::request_validation);
    }

    const negaflow::imageio::ImageFileObservationResult before =
        negaflow::imageio::observe_image_file(request.source);
    if (before.status != negaflow::imageio::ImageFileObservationStatus::ok) {
        return fail(
            DevelopExportStage::observe_source_before,
            negaflow::imageio::image_file_observation_status_name(before.status),
            before.native_error_code);
    }
    if (request.expected_defect_source_identity) {
        tracker.begin(DevelopExportStage::observe_source_before, 0U);
        HashProgressBridge hash_progress{tracker, stop};
        negaflow::imageio::ImageContentHashControl hash_control{};
        hash_control.mode = negaflow::imageio::ImageContentHashMode::sha256;
        hash_control.stop_token = stop.get_token();
        hash_control.progress_observer = &hash_progress;
        const negaflow::imageio::ImageContentHashResult hashed =
            negaflow::imageio::hash_image_content(request.source, hash_control);
        if (hashed.status == negaflow::imageio::ImageContentHashStatus::cancelled) {
            return cancelled_outcome(DevelopExportStage::observe_source_before);
        }
        if (hashed.status != negaflow::imageio::ImageContentHashStatus::ok) {
            return fail(
                DevelopExportStage::observe_source_before,
                negaflow::imageio::image_content_hash_status_name(hashed.status),
                hashed.native_error_code);
        }
        if (!negaflow::imageio::same_image_file_observation(
                before.observation,
                hashed.observation)) {
            return fail(
                DevelopExportStage::observe_source_before,
                "source_changed_before_decode");
        }
        const ExpectedSourceIdentity& expected =
            *request.expected_defect_source_identity;
        if (hashed.file_bytes != expected.file_bytes ||
            hashed.sha256 != expected.sha256) {
            return fail(
                DevelopExportStage::observe_source_before,
                "defect_source_identity_mismatch");
        }
    }

    tracker.begin(DevelopExportStage::decode, cost_of(decode_cost, true));
    DecodeProgressBridge decode_progress{tracker, stop};
    negaflow::imageio::WicTiffDecodeControl decode_control{};
    decode_control.rows_per_copy = request.rows_per_copy;
    decode_control.stop_token = stop.get_token();
    decode_control.progress_observer = &decode_progress;
    negaflow::imaging::WorkingImage decoded_image{};
    if (is_tiff_source(request.source)) {
        auto prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
            request.source,
            {},
            {},
            decode_control);
        if (prepared.decode.status == negaflow::imageio::WicTiffDecodeStatus::cancelled) {
            return cancelled_outcome(DevelopExportStage::decode);
        }
        if (prepared.decode.status != negaflow::imageio::WicTiffDecodeStatus::ok) {
            if (prepared.decode.status ==
                    negaflow::imageio::WicTiffDecodeStatus::row_sink_failed &&
                prepared.working.status !=
                    negaflow::imaging::ScannerToWorkingStatus::invalid_argument) {
                return fail(
                    DevelopExportStage::decode,
                    negaflow::imaging::scanner_to_working_status_name(
                        prepared.working.status),
                    prepared.working.info.native_error_code);
            }
            return fail(
                DevelopExportStage::decode,
                negaflow::imageio::wic_tiff_decode_status_name(prepared.decode.status));
        }
        if (prepared.working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
            return fail(
                DevelopExportStage::decode,
                negaflow::imaging::scanner_to_working_status_name(
                    prepared.working.status),
                prepared.working.info.native_error_code);
        }
        decoded_image = std::move(prepared.working.image);
    } else {
        const negaflow::imageio::WicStandardImageDecodeResult decoded =
            negaflow::imageio::decode_standard_image_with_wic(
                request.source,
                {},
                stop.get_token());
        if (decoded.status == negaflow::imageio::WicStandardImageDecodeStatus::cancelled) {
            return cancelled_outcome(DevelopExportStage::decode);
        }
        if (decoded.status != negaflow::imageio::WicStandardImageDecodeStatus::ok) {
            return fail(
                DevelopExportStage::decode,
                negaflow::imageio::wic_standard_image_decode_status_name(decoded.status));
        }
        negaflow::imaging::ScannerToWorkingResult working =
            negaflow::imaging::convert_scanner_to_working(decoded.image);
        if (working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
            return fail(
                DevelopExportStage::decode,
                negaflow::imaging::scanner_to_working_status_name(working.status),
                working.info.native_error_code);
        }
        decoded_image = std::move(working.image);
    }

    const negaflow::imageio::ImageFileObservationResult after =
        negaflow::imageio::observe_image_file(request.source);
    if (after.status != negaflow::imageio::ImageFileObservationStatus::ok) {
        return fail(
            DevelopExportStage::observe_source_after,
            negaflow::imageio::image_file_observation_status_name(after.status),
            after.native_error_code);
    }
    if (!negaflow::imageio::same_image_file_observation(
            before.observation,
            after.observation)) {
        return fail(
            DevelopExportStage::observe_source_after, "source_changed_during_decode");
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::decode);
    }

    tracker.begin(
        DevelopExportStage::defect_component_repair,
        cost_of(defect_cost, !request.defect_recipe.order.empty()));
    DefectRecipeStageResult defect_recipe = apply_defect_recipe(
        std::move(decoded_image),
        request.defect_recipe);
    if (defect_recipe.status != DefectRecipeStageStatus::ok) {
        const DevelopExportStage stage = [&]() {
            if (defect_recipe.status == DefectRecipeStageStatus::clone_failed) {
                return DevelopExportStage::defect_clone_stamp;
            }
            if (defect_recipe.status == DefectRecipeStageStatus::brush_failed) {
                return DevelopExportStage::defect_brush;
            }
            return DevelopExportStage::defect_component_repair;
        }();
        return fail(
            stage,
            defect_recipe_stage_status_name(defect_recipe));
    }
    decoded_image = std::move(defect_recipe.image);
    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::defect_component_repair);
    }

    const std::uint32_t decoded_width = decoded_image.width;
    negaflow::imaging::WorkingFilmLookParameters film_look_parameters =
        request.film_look;
    film_look_parameters.monochrome =
        request.negative.film_type ==
        negaflow::imaging::NegativeFilmType::black_and_white;

    FilmLookWorkspaceStorage workspace{};
    const FilmLookWorkspacePrepareStatus workspace_status =
        prepare_film_look_workspace(film_look_parameters, decoded_width, workspace);
    if (workspace_status != FilmLookWorkspacePrepareStatus::ok) {
        return fail(
            DevelopExportStage::film_look_workspace,
            film_look_workspace_prepare_status_name(workspace_status));
    }
    const std::size_t workspace_bytes = film_look_workspace_bytes(workspace);

    negaflow::imaging::ManualNegativeDevelopParameters negative = request.negative;
    DevelopBaseSource base_source = DevelopBaseSource::manual;
    negaflow::imaging::ManualNegativeDevelopInfo developed_info{};
    negaflow::imaging::WorkingImage developed_image{};
    const bool positive = request.film_polarity == FilmPolarity::positive;
    const bool negative_source = !positive;
    tracker.begin(
        DevelopExportStage::develop,
        cost_of(
            auto_base_cost,
            negative_source &&
                request.base_estimation_mode != NegativeBaseEstimationMode::manual) +
            cost_of(invert_cost, negative_source));
    if (negative_source &&
        (request.base_estimation_mode == NegativeBaseEstimationMode::auto_estimate ||
         request.base_estimation_mode == NegativeBaseEstimationMode::preset)) {
        const negaflow::imaging::AutoNegativeBaseResult resolved =
            negaflow::imaging::resolve_auto_negative_base(
                decoded_image,
                negative.film_type);
        if (resolved.status != negaflow::imaging::AutoNegativeBaseStatus::ok) {
            return fail(
                DevelopExportStage::develop,
                negaflow::imaging::auto_negative_base_status_name(resolved.status));
        }
        if (request.base_estimation_mode == NegativeBaseEstimationMode::preset) {
            negative.use_preset_response = true;
            negative.preset_dmax_normalized = request.film_stock_preset->dmax_normalized;
            if (negaflow::imaging::confident_auto_negative_base_source(
                    resolved.source)) {
                negative.dmin = resolved.dmin;
                base_source = DevelopBaseSource::preset_measured;
            } else {
                negative.dmin = request.film_stock_preset->dmin;
                base_source = DevelopBaseSource::preset_fallback;
            }
            for (std::size_t channel = 0U; channel < negative.dmin.size(); ++channel) {
                negative.dmin[channel] *= request.film_stock_preset->light_gain[channel];
            }
        } else {
            negative.dmin = resolved.dmin;
        }
        if (request.base_estimation_mode == NegativeBaseEstimationMode::auto_estimate) {
            switch (resolved.source) {
            case negaflow::imaging::AutoNegativeBaseSource::connected_component:
                base_source = DevelopBaseSource::auto_connected_component;
                break;
            case negaflow::imaging::AutoNegativeBaseSource::continuous_border:
                base_source = DevelopBaseSource::auto_continuous_border;
                break;
            case negaflow::imaging::AutoNegativeBaseSource::distributed_mask:
                base_source = DevelopBaseSource::auto_distributed_mask;
                break;
            case negaflow::imaging::AutoNegativeBaseSource::strip_fallback:
                base_source = DevelopBaseSource::auto_strip_fallback;
                break;
            case negaflow::imaging::AutoNegativeBaseSource::scene_edge:
                base_source = DevelopBaseSource::auto_scene_edge;
                break;
            case negaflow::imaging::AutoNegativeBaseSource::fallback:
                base_source = DevelopBaseSource::auto_fallback;
                break;
            }
        }
    }

    if (negative_source) {
        auto developed = negaflow::imaging::develop_manual_negative(
            std::move(decoded_image),
            negative);
        if (developed.status != negaflow::imaging::ManualNegativeDevelopStatus::ok) {
            if (developed.status ==
                negaflow::imaging::ManualNegativeDevelopStatus::kernel_failed) {
                return fail(
                    DevelopExportStage::develop,
                    negaflow::core::kernel_status_name(
                        developed.info.kernel_status));
            }
            return fail(
                DevelopExportStage::develop,
                negaflow::imaging::manual_negative_develop_status_name(
                    developed.status));
        }
        developed_info = developed.info;
        developed_image = std::move(developed.image);
    } else {
        // Positive film scans and rendered-digital input are already positive
        // working images. Negative base and inversion do not participate.
        developed_image = std::move(decoded_image);
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::develop);
    }

    tracker.begin(
        DevelopExportStage::scene_correction, cost_of(scene_correction_cost, true));
    negaflow::imaging::SceneCorrectionParameters scene_correction =
        request.scene_correction;
    scene_correction.negative_source = negative_source;
    negaflow::imaging::SceneCorrectionInfo scene_correction_info{};
    const negaflow::core::KernelStatus scene_correction_status =
        negaflow::imaging::apply_scene_correction(
            {
                developed_image.pixels.data(),
                developed_image.pixels.size(),
                developed_image.width,
                developed_image.height,
                developed_image.stride_pixels,
            },
            scene_correction,
            scene_correction_info);
    if (scene_correction_status != negaflow::core::KernelStatus::ok) {
        return fail(
            DevelopExportStage::scene_correction,
            negaflow::core::kernel_status_name(scene_correction_status));
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::scene_correction);
    }

    tracker.begin(
        DevelopExportStage::target_grade,
        cost_of(
            target_grade_cost,
            request.develop_target != DevelopTarget::main ||
                !request.scanner_profile_id.empty()));
    if (request.develop_target == DevelopTarget::noritsu ||
        request.develop_target == DevelopTarget::sp3000 ||
        request.develop_target == DevelopTarget::f135 ||
        request.develop_target == DevelopTarget::hr) {
        negaflow::imaging::ScannerTargetStyle target_style =
            negaflow::imaging::ScannerTargetStyle::noritsu;
        switch (request.develop_target) {
            case DevelopTarget::sp3000:
                target_style = negaflow::imaging::ScannerTargetStyle::sp3000;
                break;
            case DevelopTarget::f135:
                target_style = negaflow::imaging::ScannerTargetStyle::f135;
                break;
            case DevelopTarget::hr:
                target_style = negaflow::imaging::ScannerTargetStyle::hr;
                break;
            default:
                break;
        }
        negaflow::imaging::ScannerTargetGradeInfo target_info{};
        const negaflow::core::KernelStatus target_status =
            negaflow::imaging::apply_scanner_target_grade(
                {
                    developed_image.pixels.data(),
                    developed_image.pixels.size(),
                    developed_image.width,
                    developed_image.height,
                    developed_image.stride_pixels,
                },
                target_style,
                negative.film_type == negaflow::imaging::NegativeFilmType::black_and_white,
                positive,
                request.scanner_profile_id,
                target_info);
        if (target_status != negaflow::core::KernelStatus::ok) {
            return fail(
                DevelopExportStage::target_grade,
                negaflow::core::kernel_status_name(target_status));
        }
    }
    if (request.develop_target == DevelopTarget::rescue) {
        negaflow::imaging::RescueGradeInfo rescue_info{};
        const negaflow::core::KernelStatus rescue_status =
            negaflow::imaging::apply_rescue_grade(
                {
                    developed_image.pixels.data(),
                    developed_image.pixels.size(),
                    developed_image.width,
                    developed_image.height,
                    developed_image.stride_pixels,
                },
                negative.film_type == negaflow::imaging::NegativeFilmType::color,
                rescue_info);
        if (rescue_status != negaflow::core::KernelStatus::ok) {
            return fail(
                DevelopExportStage::target_grade,
                negaflow::core::kernel_status_name(rescue_status));
        }
    }
    if ((request.develop_target == DevelopTarget::main ||
         request.develop_target == DevelopTarget::print) &&
        !request.scanner_profile_id.empty()) {
        negaflow::imaging::ScannerProfileGradeInfo profile_info{};
        const negaflow::core::KernelStatus profile_status =
            negaflow::imaging::apply_scanner_profile_grade(
                {
                    developed_image.pixels.data(),
                    developed_image.pixels.size(),
                    developed_image.width,
                    developed_image.height,
                    developed_image.stride_pixels,
                },
                request.scanner_profile_id,
                profile_info);
        if (profile_status != negaflow::core::KernelStatus::ok) {
            return fail(
                DevelopExportStage::target_grade,
                negaflow::core::kernel_status_name(profile_status));
        }
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::target_grade);
    }

    tracker.begin(DevelopExportStage::color_model, cost_of(color_model_cost, true));
    const negaflow::core::KernelStatus color_model_status =
        negaflow::imaging::apply_color_model(
            {
                developed_image.pixels.data(),
                developed_image.pixels.size(),
                developed_image.width,
                developed_image.height,
                developed_image.stride_pixels,
            },
            {
                developed_image.pixels.data(),
                developed_image.pixels.size(),
                developed_image.width,
                developed_image.height,
                developed_image.stride_pixels,
            },
            request.color_model);
    if (color_model_status != negaflow::core::KernelStatus::ok) {
        return fail(
            DevelopExportStage::color_model,
            negaflow::core::kernel_status_name(color_model_status));
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::color_model);
    }

    tracker.begin(DevelopExportStage::tone_adjust, cost_of(tone_cost, true));
    auto adjusted = negaflow::imaging::apply_working_tone_adjustments(
        std::move(developed_image),
        request.tone);
    if (adjusted.status != negaflow::imaging::WorkingToneAdjustStatus::ok) {
        if (adjusted.status ==
            negaflow::imaging::WorkingToneAdjustStatus::kernel_failed) {
            return fail(
                DevelopExportStage::tone_adjust,
                negaflow::core::kernel_status_name(adjusted.info.kernel_status));
        }
        if (adjusted.status ==
            negaflow::imaging::WorkingToneAdjustStatus::measurement_failed) {
            return fail(
                DevelopExportStage::tone_adjust,
                negaflow::imaging::tone_curve_measurement_status_name(
                    adjusted.info.measurement.status));
        }
        return fail(
            DevelopExportStage::tone_adjust,
            negaflow::imaging::working_tone_adjust_status_name(adjusted.status));
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::tone_adjust);
    }

    tracker.begin(
        DevelopExportStage::film_look,
        cost_of(
            film_look_cost,
            request.film_look.source_kind !=
                negaflow::imaging::DevelopSourceKind::film_scan));
    auto film_look = negaflow::imaging::apply_working_film_look(
        std::move(adjusted.image),
        film_look_parameters,
        film_look_workspace_view(workspace));
    if (film_look.status != negaflow::imaging::WorkingFilmLookStatus::ok) {
        if (film_look.status ==
            negaflow::imaging::WorkingFilmLookStatus::kernel_failed) {
            return fail(
                DevelopExportStage::film_look,
                negaflow::core::kernel_status_name(film_look.info.kernel_status));
        }
        return fail(
            DevelopExportStage::film_look,
            negaflow::imaging::working_film_look_status_name(film_look.status));
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::film_look);
    }

    tracker.begin(
        DevelopExportStage::grain_mend,
        cost_of(
            grain_mend_cost,
            request.grain_mend.strength >
                negaflow::imaging::grain_mend_identity_threshold));
    if (detect != nullptr) {
        // 검토 도구는 수리 결과가 아니라 판정을 원합니다. 여기서 멈추는 이유는
        // GrainMend 가 film look 뒤, 즉 현상된 양화 위에서 돌기 때문입니다.
        const auto detected = negaflow::imaging::detect_grain_mend(
            film_look.image,
            request.grain_mend,
            detect->roi,
            negaflow::core::CancelFlag{control.cancel_flag});
        if (detected.status == negaflow::imaging::GrainMendStatus::cancelled) {
            return cancelled_outcome(DevelopExportStage::grain_mend);
        }
        if (detected.status != negaflow::imaging::GrainMendStatus::ok) {
            return fail(
                DevelopExportStage::grain_mend,
                negaflow::imaging::grain_mend_status_name(detected.status));
        }
        if (detect->result != nullptr) {
            detect->result->width = detected.width;
            detect->result->height = detected.height;
            detect->result->accepted_pixels = detected.accepted_pixels;
            detect->result->mask_byte_count = detected.mask.size();
            detect->result->source_width = film_look.image.width;
            detect->result->source_height = film_look.image.height;
            detect->result->roi_x = detected.roi_x;
            detect->result->roi_y = detected.roi_y;
            detect->result->roi_width = detected.roi_width;
            detect->result->roi_height = detected.roi_height;
        }
        // 크기만 묻는 호출(mask 가 null)도 실패가 아니라 정상 결과입니다.
        if (detect->mask != nullptr) {
            if (detect->capacity_bytes < detected.mask.size()) {
                return fail(
                    DevelopExportStage::grain_mend, "mask_buffer_too_small");
            }
            std::memcpy(detect->mask, detected.mask.data(), detected.mask.size());
        }
        DevelopExportOutcome detected_outcome{};
        detected_outcome.succeeded = true;
        detected_outcome.failure_name = "ok";
        detected_outcome.image_width = detected.width;
        detected_outcome.image_height = detected.height;
        detected_outcome.grain_mend_candidate_pixels = detected.accepted_pixels;
        tracker.finish();
        tracker.complete();
        return detected_outcome;
    }

    // The one stage long enough that a stage-boundary check is not good enough. It gets
    // the caller's latch directly and stops between its own internal passes.
    auto grain_mend = negaflow::imaging::apply_grain_mend(
        std::move(film_look.image),
        request.grain_mend,
        negaflow::core::CancelFlag{control.cancel_flag});
    if (grain_mend.status == negaflow::imaging::GrainMendStatus::cancelled) {
        return cancelled_outcome(DevelopExportStage::grain_mend);
    }
    if (grain_mend.status != negaflow::imaging::GrainMendStatus::ok) {
        if (grain_mend.status ==
            negaflow::imaging::GrainMendStatus::kernel_failed) {
            return fail(
                DevelopExportStage::grain_mend,
                negaflow::core::kernel_status_name(
                    grain_mend.info.kernel_status));
        }
        return fail(
            DevelopExportStage::grain_mend,
            negaflow::imaging::grain_mend_status_name(grain_mend.status));
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::grain_mend);
    }

    tracker.begin(
        DevelopExportStage::film_scan_denoise,
        cost_of(denoise_cost, request.film_scan_denoise.strength > 0.0F));
    auto film_scan_denoise = negaflow::imaging::apply_film_scan_denoise(
        std::move(grain_mend.image),
        request.film_scan_denoise,
        negaflow::core::CancelFlag{control.cancel_flag});
    if (film_scan_denoise.status ==
        negaflow::imaging::FilmScanDenoiseStatus::cancelled) {
        return cancelled_outcome(DevelopExportStage::film_scan_denoise);
    }
    if (film_scan_denoise.status !=
        negaflow::imaging::FilmScanDenoiseStatus::ok) {
        if (film_scan_denoise.status ==
            negaflow::imaging::FilmScanDenoiseStatus::kernel_failed) {
            return fail(
                DevelopExportStage::film_scan_denoise,
                negaflow::core::kernel_status_name(
                    film_scan_denoise.info.kernel_status));
        }
        return fail(
            DevelopExportStage::film_scan_denoise,
            negaflow::imaging::film_scan_denoise_status_name(
                film_scan_denoise.status));
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::film_scan_denoise);
    }

    tracker.begin(
        DevelopExportStage::local_dodge_burn,
        cost_of(dodge_burn_cost, !request.local_dodge_burn.adjustments.empty()));
    auto local_dodge_burn = negaflow::imaging::apply_local_dodge_burn(
        std::move(film_scan_denoise.image),
        request.local_dodge_burn);
    if (local_dodge_burn.status !=
        negaflow::imaging::LocalDodgeBurnStatus::ok) {
        if (local_dodge_burn.status ==
            negaflow::imaging::LocalDodgeBurnStatus::kernel_failed) {
            return fail(
                DevelopExportStage::local_dodge_burn,
                negaflow::core::kernel_status_name(
                    local_dodge_burn.info.kernel_status));
        }
        return fail(
            DevelopExportStage::local_dodge_burn,
            negaflow::imaging::local_dodge_burn_status_name(
                local_dodge_burn.status));
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::local_dodge_burn);
    }

    tracker.begin(DevelopExportStage::texture, cost_of(texture_cost, true));
    negaflow::imaging::TextureStageParameters texture_parameters =
        request.texture;
    if (film_look.info.route ==
        negaflow::imaging::FilmLookRoute::digital_film_look) {
        texture_parameters.grain = 0.0F;
        texture_parameters.halation = 0.0F;
    }
    auto texture = negaflow::imaging::apply_texture_stage(
        std::move(local_dodge_burn.image),
        texture_parameters);
    if (texture.status != negaflow::imaging::TextureStageStatus::ok) {
        if (texture.status ==
            negaflow::imaging::TextureStageStatus::kernel_failed) {
            return fail(
                DevelopExportStage::texture,
                negaflow::core::kernel_status_name(texture.info.kernel_status));
        }
        return fail(
            DevelopExportStage::texture,
            negaflow::imaging::texture_stage_status_name(texture.status));
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::texture);
    }

    tracker.begin(
        DevelopExportStage::black_and_white,
        cost_of(
            black_and_white_cost,
            negative.film_type ==
                negaflow::imaging::NegativeFilmType::black_and_white));
    auto black_and_white = negaflow::imaging::apply_bw_toning(
        std::move(texture.image),
        negative.film_type,
        request.bw_toning);
    if (black_and_white.status != negaflow::imaging::BwToningStatus::ok) {
        return fail(
            DevelopExportStage::black_and_white,
            negaflow::imaging::bw_toning_status_name(black_and_white.status));
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::black_and_white);
    }

    tracker.begin(DevelopExportStage::image_transform, cost_of(transform_cost, true));
    auto image_transform = negaflow::imaging::apply_image_transform(
        std::move(black_and_white.image),
        request.image_transform);
    if (image_transform.status != negaflow::imaging::ImageTransformStatus::ok) {
        return fail(
            DevelopExportStage::image_transform,
            negaflow::imaging::image_transform_status_name(
                image_transform.status));
    }

    bool output_resized = false;
    negaflow::imaging::WorkingImage output_image = std::move(image_transform.image);
    // macOS applies the optional long-edge cap after all geometric recipe transforms,
    // before final output sharpening and encoding. It is an export-only operation:
    // preview and review masks retain their source-derived geometry.
    if (preview == nullptr && detect == nullptr && request.output_long_edge != 0U) {
        const std::uint32_t current_long_edge = std::max(
            output_image.width, output_image.height);
        if (current_long_edge > request.output_long_edge) {
            const double scale = static_cast<double>(request.output_long_edge) /
                static_cast<double>(current_long_edge);
            const std::uint32_t output_width = static_cast<std::uint32_t>(
                std::max(1LL, std::llround(static_cast<double>(output_image.width) * scale)));
            const std::uint32_t output_height = static_cast<std::uint32_t>(
                std::max(1LL, std::llround(static_cast<double>(output_image.height) * scale)));
            auto resampled = negaflow::imaging::resample_working_image_lanczos3(
                output_image, output_width, output_height);
            if (resampled.status != negaflow::imaging::WorkingImageResampleStatus::ok) {
                return fail(
                    DevelopExportStage::image_transform,
                    negaflow::imaging::working_image_resample_status_name(resampled.status));
            }
            output_image = std::move(resampled.image);
            output_resized = true;
        }
    }

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::image_transform);
    }

    negaflow::imaging::OutputSharpeningResult output_sharpening{};
    if (request.output_sharpening.strength >
        negaflow::imaging::texture_stage_identity_threshold) {
        tracker.begin(
            DevelopExportStage::output_sharpening,
            cost_of(output_sharpening_cost, true));
        output_sharpening = negaflow::imaging::apply_output_sharpening(
            std::move(output_image), request.output_sharpening);
        if (output_sharpening.status != negaflow::imaging::TextureStageStatus::ok) {
            return fail(
                DevelopExportStage::output_sharpening,
                negaflow::imaging::texture_stage_status_name(output_sharpening.status));
        }
        tracker.finish();
        if (tracker.cancelled()) {
            return cancelled_outcome(DevelopExportStage::output_sharpening);
        }
    } else {
        output_sharpening.status = negaflow::imaging::TextureStageStatus::ok;
        output_sharpening.image = std::move(output_image);
    }

    // The last poll before anything is published. From here the run either produces the
    // whole artifact or fails, so a cancel arriving now is not honoured rather than
    // leaving a half-written file behind.
    tracker.begin(
        DevelopExportStage::output,
        cost_of(preview != nullptr ? preview_output_cost : export_output_cost, true));
    DevelopExportOutcome outcome{};
    outcome.image_width = output_sharpening.image.width;
    outcome.image_height = output_sharpening.image.height;
    outcome.source_file_bytes = before.observation.file_bytes;
    outcome.film_look_workspace_bytes = workspace_bytes;
    outcome.film_look_route = film_look.info.route;
    outcome.film_look_color_applied = film_look.info.color_applied;
    outcome.film_look_acutance_applied = film_look.info.acutance_applied;
    outcome.defect_region_applied = defect_recipe.info.region_applied;
    outcome.defect_region_edits_applied =
        defect_recipe.info.region_applied_edit_count;
    outcome.defect_region_repaired_pixels =
        defect_recipe.info.region_repaired_pixels;
    outcome.defect_clone_applied = defect_recipe.info.clone_applied;
    outcome.defect_clone_edits_applied =
        defect_recipe.info.clone_applied_edit_count;
    outcome.defect_clone_patched_pixels =
        defect_recipe.info.clone_patched_pixels;
    outcome.defect_clone_peak_patch_bytes =
        defect_recipe.info.clone_peak_patch_bytes;
    outcome.grain_mend_applied = grain_mend.info.applied;
    outcome.grain_mend_candidate_pixels = grain_mend.info.candidate_pixels;
    outcome.grain_mend_repaired_pixels = grain_mend.info.repaired_pixels;
    outcome.film_scan_denoise_applied = film_scan_denoise.info.applied;
    outcome.film_scan_denoise_tiles =
        film_scan_denoise.info.tiles_processed;
    outcome.local_dodge_burn_adjustments_applied =
        local_dodge_burn.info.adjustments_applied;
    outcome.texture_applied = texture.info.applied;
    outcome.black_and_white_neutralized =
        black_and_white.info.neutralized;
    outcome.bw_toning_applied = black_and_white.info.toned;
    outcome.image_transform_applied = image_transform.info.applied || output_resized;
    outcome.output_sharpening_applied = output_sharpening.info.applied;
    outcome.applied_dmin = developed_info.applied_dmin;
    outcome.base_source = base_source;

    if (preview != nullptr) {
        DevelopExportOutcome preview_outcome =
            write_preview(output_sharpening.image, *preview, outcome);
        if (preview_outcome.succeeded) {
            tracker.finish();
            tracker.complete();
        }
        return preview_outcome;
    }

    if (request.format == DevelopExportFormat::png16) {
        negaflow::output::WicPngExportLimits output_limits{};
        output_limits.output_dpi = request.output_dpi;
        output_limits.bits_per_sample = request.output_bit_depth;
        output_limits.color_space = request.output_color_space;
        // PNG 는 EXIF 를 담지 않는다. 정책은 파일에 아무 흔적도 남기지 않는다.
        const negaflow::output::WicPngExportResult exported =
            negaflow::output::export_working_to_srgb16_png(
                output_sharpening.image,
                request.destination,
                output_limits);
        if (exported.status != negaflow::output::WicPngExportStatus::ok) {
            if (exported.status ==
                negaflow::output::WicPngExportStatus::working_conversion_failed) {
                return fail(
                    DevelopExportStage::output,
                    negaflow::output::working_to_srgb16_status_name(
                        exported.conversion_status),
                    exported.native_error_code,
                    exported.cleanup_error_code);
            }
            return fail(
                DevelopExportStage::output,
                negaflow::output::wic_png_export_status_name(exported.status),
                exported.native_error_code,
                exported.cleanup_error_code);
        }
        outcome.output_file_bytes = exported.info.artifact_bytes;
        outcome.succeeded = true;
        outcome.failure_name = "ok";
        tracker.finish();
        tracker.complete();
        return outcome;
    }

    if (request.format == DevelopExportFormat::jpeg8) {
        negaflow::output::WicJpegExportLimits jpeg_limits{};
        jpeg_limits.metadata_policy = request.metadata_policy;
        jpeg_limits.metadata = request.metadata;
        const negaflow::output::WicJpegExportResult exported =
            negaflow::output::export_working_to_srgb8_jpeg(
                output_sharpening.image,
                request.destination,
                request.jpeg_quality,
                request.output_dpi,
                jpeg_limits);
        if (exported.status != negaflow::output::WicJpegExportStatus::ok) {
            if (exported.status ==
                negaflow::output::WicJpegExportStatus::working_conversion_failed) {
                return fail(
                    DevelopExportStage::output,
                    negaflow::output::working_to_srgb16_status_name(
                        exported.conversion_status),
                    exported.native_error_code,
                    exported.cleanup_error_code);
            }
            return fail(
                DevelopExportStage::output,
                negaflow::output::wic_jpeg_export_status_name(exported.status),
                exported.native_error_code,
                exported.cleanup_error_code);
        }
        outcome.output_file_bytes = exported.info.artifact_bytes;
        outcome.succeeded = true;
        outcome.failure_name = "ok";
        tracker.finish();
        tracker.complete();
        return outcome;
    }

    negaflow::output::WicTiffExportLimits output_limits{};
    output_limits.compression = request.tiff_compression;
    output_limits.output_dpi = request.output_dpi;
    output_limits.bits_per_sample = request.output_bit_depth;
    output_limits.color_space = request.output_color_space;
    output_limits.metadata_policy = request.metadata_policy;
    output_limits.metadata = request.metadata;
    const negaflow::output::WicTiffExportResult exported =
        negaflow::output::export_working_to_srgb16_tiff(
        output_sharpening.image,
            request.destination,
            output_limits);
    if (exported.status != negaflow::output::WicTiffExportStatus::ok) {
        if (exported.status ==
            negaflow::output::WicTiffExportStatus::working_conversion_failed) {
            return fail(
                DevelopExportStage::output,
                negaflow::output::working_to_srgb16_status_name(
                    exported.conversion_status),
                exported.native_error_code,
                exported.cleanup_error_code);
        }
        return fail(
            DevelopExportStage::output,
            negaflow::output::wic_tiff_export_status_name(exported.status),
            exported.native_error_code,
            exported.cleanup_error_code);
    }
    outcome.output_file_bytes = exported.info.artifact_bytes;
    outcome.succeeded = true;
    outcome.failure_name = "ok";
    tracker.finish();
    tracker.complete();
    return outcome;
}

}  // namespace

DevelopExportOutcome develop_and_export(
    const DevelopExportRequest& request,
    const DevelopRunControl& control) noexcept {
    return run_develop(request, nullptr, control);
}

GrainMendDetectionOutcome develop_detect_grain_mend(
    const DevelopExportRequest& request,
    std::uint8_t* const mask,
    const std::size_t mask_capacity_bytes,
    const DevelopRunControl& control,
    const negaflow::imaging::GrainMendRoi& roi) noexcept {
    GrainMendDetectionOutcome detection{};
    const DetectTarget target{mask, mask_capacity_bytes, &detection, roi};
    detection.outcome = run_develop(request, nullptr, control, &target);
    return detection;
}

DevelopExportOutcome develop_preview(
    const DevelopExportRequest& request,
    const std::uint32_t maximum_width,
    const std::uint32_t maximum_height,
    std::uint8_t* const pixels,
    const std::size_t pixel_capacity_bytes,
    const DevelopRunControl& control,
    const DevelopPreviewProof& proof) noexcept {
    // Profile-only proofing changes which space the frame is shown in, not its values, so
    // only the paper and ink simulation resolves to an affine here.
    const PreviewTarget target{
        maximum_width,
        maximum_height,
        pixels,
        pixel_capacity_bytes,
        proof.enabled && proof.simulate_paper_and_black_ink
            ? negaflow::color::soft_proof_transfer(proof.paper)
            : negaflow::color::SoftProofTransfer{},
    };
    return run_develop(request, &target, control);
}

}  // namespace negaflow::pipeline
