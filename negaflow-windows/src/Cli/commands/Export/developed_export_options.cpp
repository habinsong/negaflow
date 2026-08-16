#include "developed_export_options.h"

#include <array>
#include <charconv>
#include <cmath>
#include <cstddef>
#include <system_error>

namespace negaflow::cli {
namespace {

[[nodiscard]] bool parse_finite_float(const std::wstring_view text, float& value) noexcept {
    if (text.empty() || text.size() > 127U) {
        return false;
    }
    std::array<char, 128> ascii{};
    for (std::size_t index = 0U; index < text.size(); ++index) {
        if (text[index] < 0 || text[index] > 127) {
            return false;
        }
        ascii[index] = static_cast<char>(text[index]);
    }
    const auto [end, error] =
        std::from_chars(ascii.data(), ascii.data() + text.size(), value, std::chars_format::general);
    return error == std::errc{} && end == ascii.data() + text.size() && std::isfinite(value);
}

}  // namespace

bool is_developed_export_argument_count(const int argument_count) noexcept {
    return argument_count == 8 || argument_count == 11 ||
        argument_count == 14 || argument_count == 17;
}

DevelopedExportOptionsParseResult parse_developed_export_options(
    const int argument_count,
    const wchar_t* const arguments[]) {
    DevelopedExportOptionsParseResult result{};
    const bool tone_arguments_explicit = argument_count == 14 || argument_count == 17;
    const bool film_look_arguments_explicit = argument_count == 11 || argument_count == 17;

    result.options.source = arguments[2];
    result.options.destination = arguments[3];
    for (std::size_t channel = 0U; channel < result.options.negative.dmin.size(); ++channel) {
        if (!parse_finite_float(arguments[channel + 4U], result.options.negative.dmin[channel])) {
            result.error_code = "invalid_dmin";
            return result;
        }
    }

    const std::wstring_view film_type{arguments[7]};
    if (film_type == L"color") {
        result.options.negative.film_type = negaflow::imaging::NegativeFilmType::color;
    } else if (film_type == L"bw") {
        result.options.negative.film_type =
            negaflow::imaging::NegativeFilmType::black_and_white;
    } else {
        result.error_code = "unknown_film_type";
        return result;
    }

    if (tone_arguments_explicit &&
        (!parse_finite_float(arguments[8], result.options.tone.exposure_stops) ||
         !parse_finite_float(arguments[9], result.options.tone.basic.contrast) ||
         !parse_finite_float(arguments[10], result.options.tone.curve.highlights) ||
         !parse_finite_float(arguments[11], result.options.tone.curve.lights) ||
         !parse_finite_float(arguments[12], result.options.tone.curve.darks) ||
         !parse_finite_float(arguments[13], result.options.tone.curve.shadows) ||
         !negaflow::imaging::valid_working_tone_adjust_parameters(result.options.tone))) {
        result.error_code = "invalid_tone_adjustment_parameter";
        return result;
    }

    if (film_look_arguments_explicit) {
        const std::size_t first_argument = tone_arguments_explicit ? 14U : 8U;
        const FilmLookRecipeParseStatus status = parse_film_look_recipe(
            arguments[first_argument],
            arguments[first_argument + 1U],
            arguments[first_argument + 2U],
            result.options.film_look);
        if (status != FilmLookRecipeParseStatus::ok) {
            result.error_code = film_look_recipe_parse_status_name(status);
            return result;
        }
    }
    if (result.options.film_look.parameters.source_kind !=
        negaflow::imaging::DevelopSourceKind::film_scan) {
        result.error_code = "negative_develop_requires_film_scan_source";
    }
    return result;
}

}  // namespace negaflow::cli
