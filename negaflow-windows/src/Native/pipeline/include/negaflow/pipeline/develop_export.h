#pragma once

#include "negaflow/color/soft_proof.h"
#include "negaflow/imageio/image_content_hash.h"
#include "negaflow/imageio/image_file_observation.h"
#include "negaflow/pipeline/defect_recipe_stage.h"
#include "negaflow/imaging/auto_negative_base_resolver.h"
#include "negaflow/imaging/bw_toning.h"
#include "negaflow/imaging/color_model.h"
#include "negaflow/imaging/film_stock_base_resolver.h"
#include "negaflow/imaging/film_scan_denoise.h"
#include "negaflow/imaging/grain_mend.h"
#include "negaflow/imaging/image_transform.h"
#include "negaflow/imaging/local_dodge_burn.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"
#include "negaflow/imaging/scene_correction.h"
#include "negaflow/imaging/rescue_grade.h"
#include "negaflow/imaging/scanner_profile_grade.h"
#include "negaflow/imaging/scanner_target_grade.h"
#include "negaflow/imaging/texture_stage.h"
#include "negaflow/imaging/working_film_look.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "negaflow/output/wic_png_export.h"
#include "negaflow/output/wic_jpeg_export.h"
#include "negaflow/color/output_color_space.h"
#include "negaflow/output/export_metadata.h"
#include "negaflow/output/wic_tiff_export.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <filesystem>
#include <optional>
#include <string>

namespace negaflow::pipeline {

enum class DevelopExportFormat : std::uint8_t {
    png16 = 0,
    tiff16,
    jpeg8,
};

enum class NegativeBaseEstimationMode : std::uint8_t {
    auto_estimate = 0,
    preset,
    manual,
};

enum class DevelopBaseSource : std::uint8_t {
    manual = 0,
    auto_scene_edge,
    auto_fallback,
    auto_connected_component,
    auto_continuous_border,
    auto_distributed_mask,
    auto_strip_fallback,
    preset_measured,
    preset_fallback,
};

enum class DevelopTarget : std::uint8_t {
    main = 0,
    print,
    noritsu,
    sp3000,
    f135,
    hr,
    rescue,
};

enum class FilmPolarity : std::uint8_t {
    negative = 0,
    positive,
};

struct ExpectedSourceIdentity final {
    std::uint64_t file_bytes{0U};
    std::array<std::uint8_t, 32U> sha256{};
};

struct DevelopExportRequest final {
    std::filesystem::path source{};
    std::filesystem::path destination{};
    DevelopExportFormat format{DevelopExportFormat::png16};
    FilmPolarity film_polarity{FilmPolarity::negative};
    NegativeBaseEstimationMode base_estimation_mode{NegativeBaseEstimationMode::manual};
    std::optional<negaflow::imaging::FilmStockBasePreset> film_stock_preset{};
    negaflow::imaging::ManualNegativeDevelopParameters negative{};
    negaflow::imaging::SceneCorrectionParameters scene_correction{};
    DevelopTarget develop_target{DevelopTarget::main};
    std::wstring scanner_profile_id{};
    negaflow::imaging::ColorModelParameters color_model{};
    negaflow::imaging::WorkingToneAdjustParameters tone{};
    negaflow::imaging::WorkingFilmLookParameters film_look{};
    DefectRecipeParameters defect_recipe{};
    // Present only when the ordered Defects payload is non-empty. It keys rebuildable
    // cleaned/proxy caches; the edit payload above remains the source of rendered pixels.
    std::optional<std::array<std::uint8_t, 32U>> defect_recipe_sha256{};
    // Explicit canonical identity of order[0..count). Native never infers that the
    // last retained recipe is a prefix of a new request.
    std::optional<std::array<std::uint8_t, 32U>> defect_recipe_append_prefix_sha256{};
    std::size_t defect_recipe_append_prefix_edit_count{0U};
    // Present only for source-bound Defects recipes. Ordinary renders do not hash
    // the source and retain the default low-I/O path.
    std::optional<ExpectedSourceIdentity> expected_defect_source_identity{};
    negaflow::imaging::GrainMendParameters grain_mend{};
    negaflow::imaging::FilmScanDenoiseParameters film_scan_denoise{};
    negaflow::imaging::LocalDodgeBurnParameters local_dodge_burn{};
    negaflow::imaging::TextureStageParameters texture{};
    negaflow::imaging::BwToningParameters bw_toning{};
    negaflow::imaging::ImageTransformParameters image_transform{};
    negaflow::imaging::OutputSharpeningParameters output_sharpening{};
    float jpeg_quality{1.0F};
    negaflow::output::WicTiffCompression tiff_compression{
        negaflow::output::WicTiffCompression::none};
    std::uint32_t output_dpi{0U};
    // 8 or 16. PNG and TIFF publish at this depth; eight-bit output is dithered before
    // quantization, as macOS does. JPEG ignores it - it is eight-bit by definition.
    std::uint32_t output_bit_depth{16U};
    // The space the published file is encoded in and whose profile it carries. Preview
    // ignores it - the canvas is always shown in the display's own space.
    negaflow::color::OutputColorSpace output_color_space{
        negaflow::color::OutputColorSpace::srgb};
    // 인화소가 준 ICC 입니다. 비어 있지 않으면 **이것이 published 색공간**이 되어
    // `output_color_space` 를 대신합니다 — 화소를 이 프로파일로 옮기고 파일에도 이것을
    // 박습니다. macOS `ExportEngine.write(outputProfile:)` 과 같은 뜻입니다. 바이트는
    // 호출자 것이며 이 호출이 끝날 때까지만 살아 있으면 됩니다. 미리보기는 무시합니다.
    std::span<const std::uint8_t> output_icc_profile{};
    // PNG/TIFF only. When false, the RGB export deliberately omits source alpha.
    bool preserve_alpha{false};
    // 게시하는 파일에 무엇을 적을지. 값이 비어 있으면 그 항목은 쓰지 않는다.
    negaflow::output::ExportMetadataPolicy metadata_policy{
        negaflow::output::ExportMetadataPolicy::minimal};
    negaflow::output::ExportMetadataFields metadata{};
    // Zero preserves source dimensions. Positive values cap the exported long edge;
    // they never upscale and do not alter previews or GrainMend detection.
    std::uint32_t output_long_edge{0U};
    std::uint32_t rows_per_copy{64U};
    // Background developed-cache generation writes the final BGRA result to disk and
    // must not also retain a full Rgba32F proxy for every catalog frame. Foreground
    // previews keep the macOS-compatible raw reuse path by default.
    bool retain_preview_raw{true};
};

// Cooperative cancellation and progress for one develop run.
//
// The caller owns all three words and they must outlive the call. `cancel_flag` is a
// one-way latch the caller sets to a non-zero value; the run only ever reads it. The run
// writes the stage it is inside and a 0...1000 completion figure, so a UI polls on its
// own timer instead of taking a callback back across the boundary — no reentrancy, no
// marshalling, and nothing to keep alive on the managed side but three integers.
//
// Any member may be null, which switches off just that facility.
struct DevelopRunControl final {
    std::uint32_t* cancel_flag{nullptr};
    std::uint32_t* progress_stage{nullptr};
    std::uint32_t* progress_permille{nullptr};
};

inline constexpr std::uint32_t develop_progress_complete = 1000U;

// Soft proof is a viewing simulation, so it rides alongside the preview call rather than
// inside DevelopExportRequest. Keeping it out of the recipe is what guarantees a published
// artefact can never carry it: there is no field for export to read.
//
// `paper` is what negaflow::color::soft_proof_paper already resolved from the destination
// profile. The ICC is parsed once, when the profile is chosen, instead of once per frame.
struct DevelopPreviewProof final {
    bool enabled{false};
    // macOS applies the paper and ink affine only in the paperAndBlackInk simulation;
    // the profile-only mode changes which space the frame is shown in, not its pixels.
    bool simulate_paper_and_black_ink{false};
    negaflow::color::SoftProofPaper paper{};
    // 색역을 벗어나는 화소를 미리보기 위에 표시할지. 판정은 ICM 이 하며, 못 하면
    // **표시하지 않습니다** — 근사로 대신하지 않는 것이 이 기능의 계약입니다.
    bool warn_out_of_gamut{false};
    // macOS `clippingOverlayEnabled`. 소프트 프루프와 같이 미리보기 전용입니다.
    bool clipping_overlay{false};
};

// Which stage refused. The caller reports the stage together with the stage's own
// status name, so a failure never collapses into a single opaque code.
enum class DevelopExportStage : std::uint8_t {
    none = 0,
    request_validation,
    observe_source_before,
    decode,
    observe_source_after,
    film_look_workspace,
    develop,
    tone_adjust,
    film_look,
    output,
    grain_mend,
    film_scan_denoise,
    local_dodge_burn,
    texture,
    black_and_white,
    image_transform,
    color_model,
    scene_correction,
    target_grade,
    defect_component_repair,
    defect_clone_stamp,
    defect_brush,
    output_sharpening,
};

struct DevelopExportOutcome final {
    bool succeeded{false};
    // Set when the caller's cancel flag ended the run. `failed_stage` is then the stage
    // that was interrupted and `failure_name` is "cancelled". A cancelled run publishes
    // nothing: no destination file and no preview pixels.
    bool cancelled{false};
    DevelopExportStage failed_stage{DevelopExportStage::none};

    // Stable ASCII name owned by the library. Never null once a call returns.
    const char* failure_name{"ok"};
    std::uint32_t native_error_code{0U};
    std::uint32_t cleanup_error_code{0U};

    std::uint32_t image_width{0U};
    std::uint32_t image_height{0U};
    std::uint64_t source_file_bytes{0U};
    std::size_t film_look_workspace_bytes{0U};
    negaflow::imaging::FilmLookRoute film_look_route{
        negaflow::imaging::FilmLookRoute::invalid};
    bool film_look_color_applied{false};
    bool film_look_acutance_applied{false};
    bool defect_region_applied{false};
    std::size_t defect_region_edits_applied{0U};
    std::size_t defect_region_repaired_pixels{0U};
    bool defect_clone_applied{false};
    std::size_t defect_clone_edits_applied{0U};
    std::size_t defect_clone_patched_pixels{0U};
    std::size_t defect_clone_peak_patch_bytes{0U};
    bool grain_mend_applied{false};
    std::size_t grain_mend_candidate_pixels{0U};
    std::size_t grain_mend_repaired_pixels{0U};
    bool film_scan_denoise_applied{false};
    std::uint32_t film_scan_denoise_tiles{0U};
    std::size_t local_dodge_burn_adjustments_applied{0U};
    bool texture_applied{false};
    bool black_and_white_neutralized{false};
    bool bw_toning_applied{false};
    bool image_transform_applied{false};
    bool output_sharpening_applied{false};
    std::uint64_t output_file_bytes{0U};
    std::array<float, 3> applied_dmin{};
    // 개발자 디버그 화면이 읽는 지표입니다. 네거티브 반전이 돈 호출에서만 채워집니다.
    std::array<float, 3> dmax_normalized{};
    std::array<float, 3> black_input{};
    bool debug_metrics_present{false};
    DevelopBaseSource base_source{DevelopBaseSource::manual};
    std::optional<negaflow::imaging::FilmBaseMeasurementMethod> measurement_method{};
    std::optional<negaflow::imaging::FilmBaseMeasurementDiagnostics> measurement_diagnostics{};
};

// Runs decode, manual negative develop, tone, Film Look, RGB GrainMend,
// FilmScanDenoise, local Dodge/Burn, Texture and the verified 16-bit publish in
// the order the macOS pipeline uses. The source file is observed before and
// after decoding and the call fails if it changed underneath. Blocking, and safe
// to call from a worker thread; it touches no UI and no global state.
[[nodiscard]] DevelopExportOutcome develop_and_export(
    const DevelopExportRequest& request,
    const DevelopRunControl& control = {}) noexcept;

// Decodes the unchanged source, applies only its accepted non-infrared defect recipe,
// and publishes an opaque, uncompressed, linear-sRGB RGB16 TIFF. It deliberately skips
// negative inversion, grading, look, grain and every other develop stage.
[[nodiscard]] DevelopExportOutcome bake_defect_recipe(
    const DevelopExportRequest& request,
    const DevelopRunControl& control = {}) noexcept;

// Runs the same pipeline but stops before publishing and writes a display bitmap into the
// caller's buffer instead: BGRA8, tightly packed, opaque alpha, at most the requested size
// with aspect preserved. `request.destination_path` is ignored.
//
// The downscale is a box average of the gamma-encoded sRGB samples. That is not the
// numerically correct way to resample — averaging should happen in linear light — and it
// is deliberate: this is a display bitmap, not a published artifact, and point sampling a
// film scan aliases badly enough to mislead. Nothing here feeds a golden or a contract.
[[nodiscard]] DevelopExportOutcome develop_preview(
    const DevelopExportRequest& request,
    std::uint32_t maximum_width,
    std::uint32_t maximum_height,
    std::uint8_t* pixels,
    std::size_t pixel_capacity_bytes,
    const DevelopRunControl& control = {},
    const DevelopPreviewProof& proof = {}) noexcept;

// Runs decode and any already-accepted defect recipe, then reports what automatic
// GrainMend would mark. Detection does not invert or apply a film look.
//
// macOS `runRegionDetect` reads cleaned raw (linear scan, before develop). The same
// dust on the inverted positive is a different image, so the review tools must
// see this pre-develop domain.
//
// `mask` receives one byte per pixel of the capped analysis image, whose size is reported
// in the result. Pass a null `mask` to learn `mask_byte_count` first; the maximum is
// grain_mend_maximum_detection_dimension squared, so a caller can also allocate once and
// never ask. A buffer that is too small fails with "mask_buffer_too_small" and still
// reports the size needed. `request.destination_path` is ignored.
struct GrainMendDetectionOutcome final {
    DevelopExportOutcome outcome{};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::uint64_t accepted_pixels{0U};
    std::uint64_t mask_byte_count{0U};
    std::uint32_t source_width{0U};
    std::uint32_t source_height{0U};
    std::uint32_t roi_x{0U};
    std::uint32_t roi_y{0U};
    std::uint32_t roi_width{0U};
    std::uint32_t roi_height{0U};
    // 채택된 결함 하나하나. 분류와 confidence 가 붙어 있으며 좌표는 검출 이미지 기준입니다.
    // macOS `DefectLabelField.components` 와 같은 자리이고, 이것이 있어야 화면이 종류별
    // 개수를 낼 수 있습니다.
    std::vector<negaflow::imaging::grain_mend_detail::ClassifiedComponent> components{};
    // macOS `DefectLabelField.automaticFalsePositiveRisk` /
    // `automaticCandidatePixelFraction`. 전체 프레임 자동에서만 채워지고 성분은 하나도
    // 버리지 않습니다 — 화면이 경고 문구만 바꿔 답니다.
    bool automatic_false_positive_risk{false};
    double automatic_candidate_pixel_fraction{0.0};
};

[[nodiscard]] GrainMendDetectionOutcome develop_detect_grain_mend(
    const DevelopExportRequest& request,
    std::uint8_t* mask,
    std::size_t mask_capacity_bytes,
    const DevelopRunControl& control = {},
    const negaflow::imaging::GrainMendRoi& roi = {}) noexcept;

[[nodiscard]] const char* develop_export_stage_name(
    DevelopExportStage stage) noexcept;

}  // namespace negaflow::pipeline
