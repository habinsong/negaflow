#include "negaflow/imaging/digital_bw_film_profile.h"

namespace negaflow::imaging {
namespace {

constexpr DigitalBwFilmProfile tri_x_400{
    {0.28, 0.32, 0.40}, 0.56, 0.72, 0.68, 10.0, 1.0,
    0.056, 1.55, 0.9, 0.05, 0.024, 0.012, 0.0040, false};
constexpr DigitalBwFilmProfile hp5_plus{
    {0.28, 0.33, 0.39}, 0.55, 0.75, 0.72, 10.5, 1.0,
    0.053, 1.50, 0.9, 0.05, 0.023, 0.009, 0.0038, false};
constexpr DigitalBwFilmProfile fp4_plus{
    {0.27, 0.34, 0.39}, 0.52, 0.70, 0.78, 11.0, 1.0,
    0.032, 1.15, 1.0, 0.11, 0.018, 0.007, 0.0035, false};
constexpr DigitalBwFilmProfile delta_100{
    {0.28, 0.36, 0.36}, 0.54, 0.40, 0.46, 8.5, 1.0,
    0.029, 1.08, 1.15, 0.20, 0.015, 0.006, 0.0032, false};
constexpr DigitalBwFilmProfile delta_400{
    {0.28, 0.36, 0.36}, 0.56, 0.42, 0.48, 9.0, 1.0,
    0.037, 1.32, 1.05, 0.14, 0.020, 0.008, 0.0038, false};
constexpr DigitalBwFilmProfile delta_3200{
    {0.29, 0.35, 0.36}, 0.64, 0.34, 0.40, 7.0, 1.0,
    0.055, 1.95, 0.8, 0.02, 0.030, 0.028, 0.0058, false};
constexpr DigitalBwFilmProfile tmax_100{
    {0.30, 0.44, 0.26}, 0.55, 0.34, 0.42, 8.5, 1.0,
    0.026, 1.02, 1.25, 0.26, 0.013, 0.005, 0.0030, false};
constexpr DigitalBwFilmProfile tmax_400{
    {0.30, 0.43, 0.27}, 0.57, 0.36, 0.44, 9.0, 1.0,
    0.033, 1.28, 1.25, 0.24, 0.018, 0.007, 0.0036, false};
constexpr DigitalBwFilmProfile tmax_p3200{
    {0.30, 0.42, 0.28}, 0.66, 0.30, 0.36, 6.5, 1.0,
    0.059, 2.05, 0.9, 0.06, 0.032, 0.014, 0.0050, false};
constexpr DigitalBwFilmProfile kentmere_400{
    {0.29, 0.32, 0.39}, 0.60, 0.62, 0.56, 8.5, 1.0,
    0.060, 1.62, 0.85, 0.03, 0.027, 0.012, 0.0042, false};
constexpr DigitalBwFilmProfile ortho_plus{
    {0.02, 0.42, 0.56}, 0.62, 0.46, 0.50, 7.0, 1.0,
    0.027, 1.06, 1.15, 0.19, 0.014, 0.006, 0.0033, false};
constexpr DigitalBwFilmProfile sfx_200{
    {0.46, 0.30, 0.24}, 0.54, 0.52, 0.56, 8.0, 1.0,
    0.034, 1.30, 1.0, 0.11, 0.020, 0.005, 0.0038, false};
constexpr DigitalBwFilmProfile rollei_ir{
    {0.60, 0.22, 0.18}, 0.65, 0.54, 0.58, 7.5, 1.0,
    0.036, 1.35, 1.1, 0.16, 0.022, 0.040, 0.0072, false};
constexpr DigitalBwFilmProfile scala_200x{
    {0.28, 0.34, 0.38}, 0.82, 0.24, 0.22, 4.5, 1.85,
    0.028, 1.22, 1.1, 0.17, 0.016, 0.007, 0.0032, true};
constexpr DigitalBwFilmProfile rollei_superpan{
    {0.42, 0.31, 0.27}, 0.72, 0.32, 0.30, 5.5, 1.60,
    0.024, 1.26, 1.05, 0.14, 0.019, 0.026, 0.0058, true};

}  // namespace

const DigitalBwFilmProfile* digital_bw_film_profile(
    const FilmEmulation emulation) noexcept {
    switch (emulation) {
        case FilmEmulation::tri_x_400: return &tri_x_400;
        case FilmEmulation::hp5_plus: return &hp5_plus;
        case FilmEmulation::fp4_plus: return &fp4_plus;
        case FilmEmulation::delta_100: return &delta_100;
        case FilmEmulation::delta_400: return &delta_400;
        case FilmEmulation::delta_3200: return &delta_3200;
        case FilmEmulation::tmax_100: return &tmax_100;
        case FilmEmulation::tmax_400: return &tmax_400;
        case FilmEmulation::tmax_p3200: return &tmax_p3200;
        case FilmEmulation::kentmere_400: return &kentmere_400;
        case FilmEmulation::ortho_plus: return &ortho_plus;
        case FilmEmulation::sfx_200: return &sfx_200;
        case FilmEmulation::rollei_ir: return &rollei_ir;
        case FilmEmulation::scala_200x: return &scala_200x;
        case FilmEmulation::rollei_superpan: return &rollei_superpan;
        default: return nullptr;
    }
}

}  // namespace negaflow::imaging
