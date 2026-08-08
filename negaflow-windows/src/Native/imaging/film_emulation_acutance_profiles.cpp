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
    }
    return nullptr;
}

}  // namespace negaflow::imaging::detail
