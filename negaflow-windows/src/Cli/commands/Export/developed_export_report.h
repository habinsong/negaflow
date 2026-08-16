#pragma once

#include "../film_look_command_support.h"
#include "../process_cpu_time.h"

#include "negaflow/imageio/image_file_observation.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "negaflow/output/wic_png_export.h"
#include "negaflow/output/wic_tiff_export.h"

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string_view>

namespace negaflow::cli {

using DevelopedExportClock = std::chrono::steady_clock;

inline constexpr std::uint32_t developed_export_rows_per_copy = 64U;

struct DevelopedExportStageTiming final {
    std::uint64_t wall_microseconds{0};
    std::optional<std::uint64_t> cpu_microseconds{};
};

struct DevelopedExportPipelineReport final {
    const negaflow::imaging::ManualNegativeDevelopParameters& negative_parameters;
    const negaflow::imaging::WorkingToneAdjustParameters& tone_parameters;
    const negaflow::imaging::StreamedScannerToWorkingResult& prepared;
    const negaflow::imaging::ManualNegativeDevelopResult& developed;
    const negaflow::imaging::WorkingToneAdjustResult& adjusted;
    const FilmLookCommandRecipe& film_look_recipe;
    const negaflow::imaging::WorkingFilmLookResult& film_look;
    std::uint64_t source_file_bytes{0};
    std::size_t film_look_workspace_bytes{0U};
    DevelopedExportStageTiming decode_and_color{};
    DevelopedExportStageTiming develop{};
    DevelopedExportStageTiming tone_adjust{};
    DevelopedExportStageTiming film_look_timing{};
    DevelopedExportStageTiming output{};
    DevelopedExportStageTiming total{};
};

[[nodiscard]] DevelopedExportStageTiming make_developed_export_stage_timing(
    DevelopedExportClock::time_point wall_started,
    DevelopedExportClock::time_point wall_finished,
    const ProcessCpuTimeSnapshot& cpu_started,
    const ProcessCpuTimeSnapshot& cpu_finished) noexcept;

int print_developed_export_error(
    std::string_view code,
    std::uint32_t native_error_code = 0U,
    std::uint32_t cleanup_error_code = 0U,
    const char* detail = nullptr);

int print_developed_export_observation_error(
    const negaflow::imageio::ImageFileObservationResult& observation);

int print_developed_png_success(
    const negaflow::output::WicPngExportResult& exported,
    const DevelopedExportPipelineReport& context);

int print_developed_tiff_success(
    const negaflow::output::WicTiffExportResult& exported,
    const DevelopedExportPipelineReport& context);

}  // namespace negaflow::cli
