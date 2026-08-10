#include "film_emulation_acutance_profiles.h"

namespace negaflow::imaging::detail {
namespace {

constexpr FilmEmulationAcutanceProfileData identity{1.0, 0.0, 1.042};
constexpr FilmEmulationAcutanceProfileData ektachrome_e100{1.0, 0.12, 1.042};
constexpr FilmEmulationAcutanceProfileData provia_100f{1.1, 0.20, 1.137};
constexpr FilmEmulationAcutanceProfileData velvia_50{1.2, 0.22, 1.238};
constexpr FilmEmulationAcutanceProfileData portra_160{1.0, 0.08, 1.042};
constexpr FilmEmulationAcutanceProfileData portra_400{1.0, 0.05, 1.042};
constexpr FilmEmulationAcutanceProfileData portra_800{1.0, 0.03, 1.042};
constexpr FilmEmulationAcutanceProfileData ektar_100{1.0, 0.16, 1.042};
constexpr FilmEmulationAcutanceProfileData ultramax_400{1.0, 0.04, 1.042};
constexpr FilmEmulationAcutanceProfileData colorplus_200{1.0, 0.07, 1.042};
constexpr FilmEmulationAcutanceProfileData fujicolor_c200{1.0, 0.06, 1.042};
constexpr FilmEmulationAcutanceProfileData pro_400h{1.0, 0.04, 1.042};
constexpr FilmEmulationAcutanceProfileData velvia_100{1.15, 0.20, 1.18675};
constexpr FilmEmulationAcutanceProfileData e100_vs{1.1, 0.18, 1.137};
constexpr FilmEmulationAcutanceProfileData astia_100f{1.0, 0.14, 1.042};
constexpr FilmEmulationAcutanceProfileData kodachrome_64{1.2, 0.22, 1.238};
constexpr FilmEmulationAcutanceProfileData gold_200{1.0, 0.06, 1.042};
constexpr FilmEmulationAcutanceProfileData pro_image_100{1.0, 0.07, 1.042};
constexpr FilmEmulationAcutanceProfileData superia_400{1.0, 0.05, 1.042};
constexpr FilmEmulationAcutanceProfileData superia_premium_400{
    1.0, 0.06, 1.042};
constexpr FilmEmulationAcutanceProfileData superia_200{1.0, 0.08, 1.042};
constexpr FilmEmulationAcutanceProfileData reala_100{1.0, 0.10, 1.042};
constexpr FilmEmulationAcutanceProfileData industrial_100{1.0, 0.09, 1.042};
constexpr FilmEmulationAcutanceProfileData lomo_cn_800{1.0, 0.03, 1.042};
constexpr FilmEmulationAcutanceProfileData vision3_500t{1.0, 0.04, 1.042};
constexpr FilmEmulationAcutanceProfileData vision3_250d{1.0, 0.06, 1.042};
constexpr FilmEmulationAcutanceProfileData vision3_50d{1.0, 0.12, 1.042};
constexpr FilmEmulationAcutanceProfileData vision3_200t{1.0, 0.06, 1.042};
// The fixed Core Image goldens currently cover radii 1.0, 1.1, and 1.2.
// Other B&W radii use the quadratic through those three calibrated points.
constexpr FilmEmulationAcutanceProfileData tri_x_400{0.9, 0.05, 0.953};
constexpr FilmEmulationAcutanceProfileData hp5_plus{0.9, 0.05, 0.953};
constexpr FilmEmulationAcutanceProfileData fp4_plus{1.0, 0.11, 1.042};
constexpr FilmEmulationAcutanceProfileData delta_100{1.15, 0.20, 1.18675};
constexpr FilmEmulationAcutanceProfileData delta_400{1.05, 0.14, 1.08875};
constexpr FilmEmulationAcutanceProfileData delta_3200{0.8, 0.02, 0.870};
constexpr FilmEmulationAcutanceProfileData tmax_100{1.25, 0.26, 1.29075};
constexpr FilmEmulationAcutanceProfileData tmax_400{1.25, 0.24, 1.29075};
constexpr FilmEmulationAcutanceProfileData tmax_p3200{0.9, 0.06, 0.953};
constexpr FilmEmulationAcutanceProfileData kentmere_400{0.85, 0.03, 0.91075};
constexpr FilmEmulationAcutanceProfileData ortho_plus{1.15, 0.19, 1.18675};
constexpr FilmEmulationAcutanceProfileData sfx_200{1.0, 0.11, 1.042};
constexpr FilmEmulationAcutanceProfileData rollei_ir{1.1, 0.16, 1.137};
constexpr FilmEmulationAcutanceProfileData scala_200x{1.1, 0.17, 1.137};
constexpr FilmEmulationAcutanceProfileData rollei_superpan{
    1.05, 0.14, 1.08875};

}  // namespace

const FilmEmulationAcutanceProfileData* film_emulation_acutance_profile_data(
    const FilmEmulation emulation) noexcept {
    switch (emulation) {
        case FilmEmulation::none:
            return &identity;
        case FilmEmulation::ektachrome_e100:
            return &ektachrome_e100;
        case FilmEmulation::provia_100f:
            return &provia_100f;
        case FilmEmulation::velvia_50:
            return &velvia_50;
        case FilmEmulation::portra_160:
            return &portra_160;
        case FilmEmulation::portra_400:
            return &portra_400;
        case FilmEmulation::portra_800:
            return &portra_800;
        case FilmEmulation::ektar_100:
            return &ektar_100;
        case FilmEmulation::ultramax_400:
            return &ultramax_400;
        case FilmEmulation::colorplus_200:
            return &colorplus_200;
        case FilmEmulation::fujicolor_c200:
            return &fujicolor_c200;
        case FilmEmulation::pro_400h:
            return &pro_400h;
        case FilmEmulation::velvia_100:
            return &velvia_100;
        case FilmEmulation::e100_vs:
            return &e100_vs;
        case FilmEmulation::astia_100f:
            return &astia_100f;
        case FilmEmulation::kodachrome_64:
            return &kodachrome_64;
        case FilmEmulation::gold_200:
            return &gold_200;
        case FilmEmulation::pro_image_100:
            return &pro_image_100;
        case FilmEmulation::superia_400:
            return &superia_400;
        case FilmEmulation::superia_premium_400:
            return &superia_premium_400;
        case FilmEmulation::superia_200:
            return &superia_200;
        case FilmEmulation::reala_100:
            return &reala_100;
        case FilmEmulation::industrial_100:
            return &industrial_100;
        case FilmEmulation::lomo_cn_800:
            return &lomo_cn_800;
        case FilmEmulation::vision3_500t:
            return &vision3_500t;
        case FilmEmulation::vision3_250d:
            return &vision3_250d;
        case FilmEmulation::vision3_50d:
            return &vision3_50d;
        case FilmEmulation::vision3_200t:
            return &vision3_200t;
        case FilmEmulation::tri_x_400:
            return &tri_x_400;
        case FilmEmulation::hp5_plus:
            return &hp5_plus;
        case FilmEmulation::fp4_plus:
            return &fp4_plus;
        case FilmEmulation::delta_100:
            return &delta_100;
        case FilmEmulation::delta_400:
            return &delta_400;
        case FilmEmulation::delta_3200:
            return &delta_3200;
        case FilmEmulation::tmax_100:
            return &tmax_100;
        case FilmEmulation::tmax_400:
            return &tmax_400;
        case FilmEmulation::tmax_p3200:
            return &tmax_p3200;
        case FilmEmulation::kentmere_400:
            return &kentmere_400;
        case FilmEmulation::ortho_plus:
            return &ortho_plus;
        case FilmEmulation::sfx_200:
            return &sfx_200;
        case FilmEmulation::rollei_ir:
            return &rollei_ir;
        case FilmEmulation::scala_200x:
            return &scala_200x;
        case FilmEmulation::rollei_superpan:
            return &rollei_superpan;
    }
    return nullptr;
}

}  // namespace negaflow::imaging::detail
