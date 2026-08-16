#pragma once

#include "../film_look_command_support.h"

#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/working_tone_adjuster.h"

#include <filesystem>
#include <string_view>

namespace negaflow::cli {

struct DevelopedExportOptions final {
    std::filesystem::path source{};
    std::filesystem::path destination{};
    negaflow::imaging::ManualNegativeDevelopParameters negative{};
    negaflow::imaging::WorkingToneAdjustParameters tone{};
    FilmLookCommandRecipe film_look{};
};

struct DevelopedExportOptionsParseResult final {
    DevelopedExportOptions options{};
    std::string_view error_code{};

    [[nodiscard]] bool succeeded() const noexcept { return error_code.empty(); }
};

[[nodiscard]] bool is_developed_export_argument_count(int argument_count) noexcept;

[[nodiscard]] DevelopedExportOptionsParseResult parse_developed_export_options(
    int argument_count,
    const wchar_t* const arguments[]);

}  // namespace negaflow::cli
