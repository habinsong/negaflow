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

struct TextureStageParameters final {
    float grain{0.0F};
    float sharpness{0.0F};
    float halation{0.0F};
    float clarity{0.0F};
    float vignette{0.0F};
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
