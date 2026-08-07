#pragma once

#include "negaflow/imageio/image_file_observation.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"
#include "negaflow/imaging/working_film_look.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "negaflow/output/wic_png_export.h"
#include "negaflow/output/wic_tiff_export.h"

#include <cstddef>
#include <cstdint>
#include <filesystem>

namespace negaflow::pipeline {

enum class DevelopExportFormat : std::uint8_t {
    png16 = 0,
    tiff16,
};

struct DevelopExportRequest final {
    std::filesystem::path source{};
    std::filesystem::path destination{};
    DevelopExportFormat format{DevelopExportFormat::png16};
    negaflow::imaging::ManualNegativeDevelopParameters negative{};
    negaflow::imaging::WorkingToneAdjustParameters tone{};
    negaflow::imaging::WorkingFilmLookParameters film_look{};
    std::uint32_t rows_per_copy{64U};
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
};

struct DevelopExportOutcome final {
    bool succeeded{false};
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
    std::uint64_t output_file_bytes{0U};
};

// Runs decode, manual negative develop, tone, Film Look and the verified 16-bit
// publish in the order the macOS pipeline uses. The source file is observed before
// and after decoding and the call fails if it changed underneath. Blocking, and
// safe to call from a worker thread; it touches no UI and no global state.
[[nodiscard]] DevelopExportOutcome develop_and_export(
    const DevelopExportRequest& request) noexcept;

[[nodiscard]] const char* develop_export_stage_name(
    DevelopExportStage stage) noexcept;

}  // namespace negaflow::pipeline
