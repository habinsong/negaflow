#include "film_look_command_support.h"

#include <array>
#include <charconv>
#include <cmath>
#include <system_error>

namespace negaflow::cli {
namespace {

[[nodiscard]] bool parse_finite_double(
    const std::wstring_view text,
    double& value) noexcept {
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
    const auto [end, error] = std::from_chars(
        ascii.data(),
        ascii.data() + text.size(),
        value,
        std::chars_format::general);
    return error == std::errc{} && end == ascii.data() + text.size() &&
           std::isfinite(value);
}

[[nodiscard]] bool try_parse_source_kind(
    const std::wstring_view text,
    negaflow::imaging::DevelopSourceKind& source_kind) noexcept {
    if (text == L"film_scan") {
        source_kind = negaflow::imaging::DevelopSourceKind::film_scan;
        return true;
    }
    if (text == L"rendered_digital") {
        source_kind = negaflow::imaging::DevelopSourceKind::rendered_digital;
        return true;
    }
    return false;
}

[[nodiscard]] bool try_parse_emulation(
    const std::wstring_view text,
    negaflow::imaging::FilmEmulation& emulation) noexcept {
    using negaflow::imaging::FilmEmulation;
    if (text == L"none") {
        emulation = FilmEmulation::none;
    } else if (text == L"ektachrome_e100") {
        emulation = FilmEmulation::ektachrome_e100;
    } else if (text == L"provia_100f") {
        emulation = FilmEmulation::provia_100f;
    } else if (text == L"velvia_50") {
        emulation = FilmEmulation::velvia_50;
    } else if (text == L"portra_160") {
        emulation = FilmEmulation::portra_160;
    } else if (text == L"portra_400") {
        emulation = FilmEmulation::portra_400;
    } else if (text == L"portra_800") {
        emulation = FilmEmulation::portra_800;
    } else if (text == L"ektar_100") {
        emulation = FilmEmulation::ektar_100;
    } else if (text == L"ultramax_400") {
        emulation = FilmEmulation::ultramax_400;
    } else if (text == L"colorplus_200") {
        emulation = FilmEmulation::colorplus_200;
    } else if (text == L"fujicolor_c200") {
        emulation = FilmEmulation::fujicolor_c200;
    } else if (text == L"pro_400h") {
        emulation = FilmEmulation::pro_400h;
    } else if (text == L"tri_x_400") {
        emulation = FilmEmulation::tri_x_400;
    } else if (text == L"hp5_plus") {
        emulation = FilmEmulation::hp5_plus;
    } else if (text == L"fp4_plus") {
        emulation = FilmEmulation::fp4_plus;
    } else if (text == L"delta_100") {
        emulation = FilmEmulation::delta_100;
    } else if (text == L"delta_400") {
        emulation = FilmEmulation::delta_400;
    } else if (text == L"delta_3200") {
        emulation = FilmEmulation::delta_3200;
    } else if (text == L"tmax_100") {
        emulation = FilmEmulation::tmax_100;
    } else if (text == L"tmax_400") {
        emulation = FilmEmulation::tmax_400;
    } else if (text == L"tmax_p3200") {
        emulation = FilmEmulation::tmax_p3200;
    } else if (text == L"kentmere_400") {
        emulation = FilmEmulation::kentmere_400;
    } else if (text == L"ortho_plus") {
        emulation = FilmEmulation::ortho_plus;
    } else if (text == L"sfx_200") {
        emulation = FilmEmulation::sfx_200;
    } else if (text == L"rollei_ir") {
        emulation = FilmEmulation::rollei_ir;
    } else if (text == L"scala_200x") {
        emulation = FilmEmulation::scala_200x;
    } else if (text == L"rollei_superpan") {
        emulation = FilmEmulation::rollei_superpan;
    } else if (text == L"velvia_100") {
        emulation = FilmEmulation::velvia_100;
    } else if (text == L"e100_vs") {
        emulation = FilmEmulation::e100_vs;
    } else if (text == L"astia_100f") {
        emulation = FilmEmulation::astia_100f;
    } else if (text == L"kodachrome_64") {
        emulation = FilmEmulation::kodachrome_64;
    } else if (text == L"gold_200") {
        emulation = FilmEmulation::gold_200;
    } else if (text == L"pro_image_100") {
        emulation = FilmEmulation::pro_image_100;
    } else if (text == L"superia_400") {
        emulation = FilmEmulation::superia_400;
    } else if (text == L"superia_premium_400") {
        emulation = FilmEmulation::superia_premium_400;
    } else if (text == L"superia_200") {
        emulation = FilmEmulation::superia_200;
    } else if (text == L"reala_100") {
        emulation = FilmEmulation::reala_100;
    } else if (text == L"industrial_100") {
        emulation = FilmEmulation::industrial_100;
    } else if (text == L"lomo_cn_800") {
        emulation = FilmEmulation::lomo_cn_800;
    } else if (text == L"vision3_500t") {
        emulation = FilmEmulation::vision3_500t;
    } else if (text == L"vision3_250d") {
        emulation = FilmEmulation::vision3_250d;
    } else if (text == L"vision3_50d") {
        emulation = FilmEmulation::vision3_50d;
    } else if (text == L"vision3_200t") {
        emulation = FilmEmulation::vision3_200t;
    } else {
        return false;
    }
    return true;
}

}  // namespace

FilmLookRecipeParseStatus parse_film_look_recipe(
    const std::wstring_view source_kind,
    const std::wstring_view emulation,
    const std::wstring_view intensity,
    FilmLookCommandRecipe& recipe) noexcept {
    recipe = {};
    if (!try_parse_source_kind(source_kind, recipe.parameters.source_kind)) {
        return FilmLookRecipeParseStatus::unknown_source_kind;
    }
    if (!try_parse_emulation(emulation, recipe.parameters.emulation)) {
        return FilmLookRecipeParseStatus::unknown_emulation;
    }
    if (!parse_finite_double(intensity, recipe.parameters.intensity)) {
        return FilmLookRecipeParseStatus::invalid_intensity;
    }
    if (!negaflow::imaging::valid_working_film_look_parameters(
            recipe.parameters)) {
        return FilmLookRecipeParseStatus::invalid_parameters;
    }
    recipe.arguments_explicit = true;
    return FilmLookRecipeParseStatus::ok;
}

const char* film_look_recipe_parse_status_name(
    const FilmLookRecipeParseStatus status) noexcept {
    switch (status) {
        case FilmLookRecipeParseStatus::ok:
            return "ok";
        case FilmLookRecipeParseStatus::unknown_source_kind:
            return "unknown_film_look_source_kind";
        case FilmLookRecipeParseStatus::unknown_emulation:
            return "unknown_film_emulation";
        case FilmLookRecipeParseStatus::invalid_intensity:
            return "invalid_film_look_intensity";
        case FilmLookRecipeParseStatus::invalid_parameters:
            return "invalid_film_look_parameters";
    }
    return "unknown_film_look_recipe_parse_status";
}

const char* film_emulation_recipe_name(
    const negaflow::imaging::FilmEmulation emulation) noexcept {
    using negaflow::imaging::FilmEmulation;
    switch (emulation) {
        case FilmEmulation::none:
            return "none";
        case FilmEmulation::ektachrome_e100:
            return "ektachrome_e100";
        case FilmEmulation::provia_100f:
            return "provia_100f";
        case FilmEmulation::velvia_50:
            return "velvia_50";
        case FilmEmulation::portra_160:
            return "portra_160";
        case FilmEmulation::portra_400:
            return "portra_400";
        case FilmEmulation::portra_800:
            return "portra_800";
        case FilmEmulation::ektar_100:
            return "ektar_100";
        case FilmEmulation::ultramax_400:
            return "ultramax_400";
        case FilmEmulation::colorplus_200:
            return "colorplus_200";
        case FilmEmulation::fujicolor_c200:
            return "fujicolor_c200";
        case FilmEmulation::pro_400h:
            return "pro_400h";
        case FilmEmulation::tri_x_400:
            return "tri_x_400";
        case FilmEmulation::hp5_plus:
            return "hp5_plus";
        case FilmEmulation::fp4_plus:
            return "fp4_plus";
        case FilmEmulation::delta_100:
            return "delta_100";
        case FilmEmulation::delta_400:
            return "delta_400";
        case FilmEmulation::delta_3200:
            return "delta_3200";
        case FilmEmulation::tmax_100:
            return "tmax_100";
        case FilmEmulation::tmax_400:
            return "tmax_400";
        case FilmEmulation::tmax_p3200:
            return "tmax_p3200";
        case FilmEmulation::kentmere_400:
            return "kentmere_400";
        case FilmEmulation::ortho_plus:
            return "ortho_plus";
        case FilmEmulation::sfx_200:
            return "sfx_200";
        case FilmEmulation::rollei_ir:
            return "rollei_ir";
        case FilmEmulation::scala_200x:
            return "scala_200x";
        case FilmEmulation::rollei_superpan:
            return "rollei_superpan";
        case FilmEmulation::velvia_100:
            return "velvia_100";
        case FilmEmulation::e100_vs:
            return "e100_vs";
        case FilmEmulation::astia_100f:
            return "astia_100f";
        case FilmEmulation::kodachrome_64:
            return "kodachrome_64";
        case FilmEmulation::gold_200:
            return "gold_200";
        case FilmEmulation::pro_image_100:
            return "pro_image_100";
        case FilmEmulation::superia_400:
            return "superia_400";
        case FilmEmulation::superia_premium_400:
            return "superia_premium_400";
        case FilmEmulation::superia_200:
            return "superia_200";
        case FilmEmulation::reala_100:
            return "reala_100";
        case FilmEmulation::industrial_100:
            return "industrial_100";
        case FilmEmulation::lomo_cn_800:
            return "lomo_cn_800";
        case FilmEmulation::vision3_500t:
            return "vision3_500t";
        case FilmEmulation::vision3_250d:
            return "vision3_250d";
        case FilmEmulation::vision3_50d:
            return "vision3_50d";
        case FilmEmulation::vision3_200t:
            return "vision3_200t";
    }
    return "unknown";
}

}  // namespace negaflow::cli
