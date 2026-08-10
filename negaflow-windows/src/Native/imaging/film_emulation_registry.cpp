#include "negaflow/imaging/film_emulation_registry.h"

namespace negaflow::imaging {

bool valid_film_emulation(const FilmEmulation emulation) noexcept {
    switch (emulation) {
        case FilmEmulation::none:
        case FilmEmulation::ektachrome_e100:
        case FilmEmulation::provia_100f:
        case FilmEmulation::velvia_50:
        case FilmEmulation::portra_160:
        case FilmEmulation::portra_400:
        case FilmEmulation::portra_800:
        case FilmEmulation::ektar_100:
        case FilmEmulation::ultramax_400:
        case FilmEmulation::colorplus_200:
        case FilmEmulation::fujicolor_c200:
        case FilmEmulation::pro_400h:
        case FilmEmulation::tri_x_400:
        case FilmEmulation::hp5_plus:
        case FilmEmulation::fp4_plus:
        case FilmEmulation::delta_100:
        case FilmEmulation::delta_400:
        case FilmEmulation::delta_3200:
        case FilmEmulation::tmax_100:
        case FilmEmulation::tmax_400:
        case FilmEmulation::tmax_p3200:
        case FilmEmulation::kentmere_400:
        case FilmEmulation::ortho_plus:
        case FilmEmulation::sfx_200:
        case FilmEmulation::rollei_ir:
        case FilmEmulation::scala_200x:
        case FilmEmulation::rollei_superpan:
        case FilmEmulation::velvia_100:
        case FilmEmulation::e100_vs:
        case FilmEmulation::astia_100f:
        case FilmEmulation::kodachrome_64:
        case FilmEmulation::gold_200:
        case FilmEmulation::pro_image_100:
        case FilmEmulation::superia_400:
        case FilmEmulation::superia_premium_400:
        case FilmEmulation::superia_200:
        case FilmEmulation::reala_100:
        case FilmEmulation::industrial_100:
        case FilmEmulation::lomo_cn_800:
        case FilmEmulation::vision3_500t:
        case FilmEmulation::vision3_250d:
        case FilmEmulation::vision3_50d:
        case FilmEmulation::vision3_200t:
            return true;
    }
    return false;
}

FilmEmulationKind film_emulation_kind(
    const FilmEmulation emulation) noexcept {
    switch (emulation) {
        case FilmEmulation::none:
            return FilmEmulationKind::none;
        case FilmEmulation::ektachrome_e100:
        case FilmEmulation::provia_100f:
        case FilmEmulation::velvia_50:
        case FilmEmulation::velvia_100:
        case FilmEmulation::e100_vs:
        case FilmEmulation::astia_100f:
        case FilmEmulation::kodachrome_64:
            return FilmEmulationKind::slide;
        case FilmEmulation::portra_160:
        case FilmEmulation::portra_400:
        case FilmEmulation::portra_800:
        case FilmEmulation::ektar_100:
        case FilmEmulation::ultramax_400:
        case FilmEmulation::colorplus_200:
        case FilmEmulation::fujicolor_c200:
        case FilmEmulation::pro_400h:
        case FilmEmulation::gold_200:
        case FilmEmulation::pro_image_100:
        case FilmEmulation::superia_400:
        case FilmEmulation::superia_premium_400:
        case FilmEmulation::superia_200:
        case FilmEmulation::reala_100:
        case FilmEmulation::industrial_100:
        case FilmEmulation::lomo_cn_800:
            return FilmEmulationKind::negative;
        case FilmEmulation::tri_x_400:
        case FilmEmulation::hp5_plus:
        case FilmEmulation::fp4_plus:
        case FilmEmulation::delta_100:
        case FilmEmulation::delta_400:
        case FilmEmulation::delta_3200:
        case FilmEmulation::tmax_100:
        case FilmEmulation::tmax_400:
        case FilmEmulation::tmax_p3200:
        case FilmEmulation::kentmere_400:
        case FilmEmulation::ortho_plus:
        case FilmEmulation::sfx_200:
        case FilmEmulation::rollei_ir:
            return FilmEmulationKind::black_and_white_negative;
        case FilmEmulation::scala_200x:
        case FilmEmulation::rollei_superpan:
            return FilmEmulationKind::black_and_white_reversal;
        case FilmEmulation::vision3_500t:
        case FilmEmulation::vision3_250d:
        case FilmEmulation::vision3_50d:
        case FilmEmulation::vision3_200t:
            return FilmEmulationKind::motion_picture;
    }
    return FilmEmulationKind::none;
}

bool is_black_and_white_film_emulation(
    const FilmEmulation emulation) noexcept {
    const FilmEmulationKind kind = film_emulation_kind(emulation);
    return kind == FilmEmulationKind::black_and_white_negative ||
           kind == FilmEmulationKind::black_and_white_reversal;
}

}  // namespace negaflow::imaging
