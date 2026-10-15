#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstddef>
#include <cstdint>

namespace negaflow::imaging {

inline constexpr char texture_stage_algorithm_version[] =
    "chromabase-texture-stage-cpu-v1";
inline constexpr float texture_stage_identity_threshold = 1.0e-3F;
inline constexpr std::uint32_t texture_stage_tile_side = 512U;
// SP 타겟이 사용자 부분 대비와 별개로 기본으로 얹는 부분 대비입니다(macOS
// `ScannerTargetGrade.spLocalContrast`). 그레이드 단계가 아니라 여기서 걸어야 GPU 상주 사슬이
// 그레이드에서 끊기지 않습니다 — 두 플랫폼 모두 질감 단계, 사용자 부분 대비 바로 앞입니다.
inline constexpr float sp_target_local_contrast = 0.2F;

// 부분 대비 한 번의 계획입니다(macOS `DetailEnhancement.localContrast`). CPU 판
// (`detail_enhancement.cpp`)과 GPU 판(`gpu_local_contrast.cpp`)이 같은 값을 쓰도록 여기서만
// 정합니다. 경계 보존 베이스는 `factor` 배로 줄인 해상도의 자기 안내 가이디드 필터입니다.
inline constexpr float local_contrast_epsilon = 0.01F;
inline constexpr float local_contrast_halo = 0.18F;

struct LocalContrastPlan final {
    std::uint32_t factor{1U};
    std::uint32_t low_width{0U};
    std::uint32_t low_height{0U};
    // 축소 평면의 가우시안 시그마(Core Image 의미).
    float low_sigma{0.0F};
    float amount{0.0F};
};

[[nodiscard]] LocalContrastPlan plan_local_contrast(
    std::uint32_t width,
    std::uint32_t height,
    float clarity) noexcept;

struct TextureStageParameters final {
    float grain{0.0F};
    float sharpness{0.0F};
    float halation{0.0F};
    float clarity{0.0F};
    float vignette{0.0F};
    // 현상 타겟이 기본으로 얹는 부분 대비(0…1). 사용자 `clarity` 앞에 따로 겁니다.
    float target_clarity{0.0F};
};

enum class TextureStageStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    kernel_failed,
    allocation_failed,
};

struct TextureStageInfo final {
    bool applied{false};
    bool grain_applied{false};
    bool sharpness_applied{false};
    bool halation_applied{false};
    bool clarity_applied{false};
    bool vignette_applied{false};
    std::size_t output_scratch_peak_bytes{0U};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::ok};
};

struct TextureStageResult final {
    TextureStageStatus status{TextureStageStatus::invalid_parameter};
    TextureStageInfo info{};
    WorkingImage image{};
};

// Export sharpening is deliberately separate from the creative Texture sharpness
// control. Its radius is tied to the requested output medium and DPI, and it runs
// after crop/rotation so the final artifact is sharpened exactly once.
enum class OutputSharpeningMedium : std::uint8_t {
    screen = 0,
    matte_paper,
    glossy_paper,
};

struct OutputSharpeningParameters final {
    float strength{0.0F};
    OutputSharpeningMedium medium{OutputSharpeningMedium::screen};
    std::int32_t dpi{0};
};

struct OutputSharpeningInfo final {
    bool applied{false};
    float radius{0.0F};
    float intensity{0.0F};
    std::size_t scratch_peak_bytes{0U};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::ok};
};

struct OutputSharpeningResult final {
    TextureStageStatus status{TextureStageStatus::invalid_parameter};
    OutputSharpeningInfo info{};
    WorkingImage image{};
};

[[nodiscard]] bool valid_texture_stage_parameters(
    const TextureStageParameters& parameters) noexcept;

// CPU baseline for macOS TextureStage. Spatial stages use overlap tiles and a
// fixed +/-3 sigma Gaussian truncation. Grain is deterministic by pixel
// coordinate so preview and export cannot disagree. Alpha is preserved.
[[nodiscard]] TextureStageResult apply_texture_stage(
    WorkingImage image,
    const TextureStageParameters& parameters) noexcept;

[[nodiscard]] const char* texture_stage_status_name(
    TextureStageStatus status) noexcept;

[[nodiscard]] bool valid_output_sharpening_parameters(
    const OutputSharpeningParameters& parameters) noexcept;

[[nodiscard]] OutputSharpeningResult apply_output_sharpening(
    WorkingImage image,
    const OutputSharpeningParameters& parameters) noexcept;

}  // namespace negaflow::imaging
