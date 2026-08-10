#include "negaflow/imaging/digital_film_physics.h"

namespace negaflow::imaging {
namespace {

constexpr DigitalFilmPhysics ektachrome_e100{
    {0.020, 0.014, 0.010}, {0.030, 0.011, 0.004}, 0.0038,
    {0.026, 0.34, 1.15}};
constexpr DigitalFilmPhysics provia_100f{
    {0.018, 0.012, 0.009}, {0.028, 0.010, 0.004}, 0.0034,
    {0.026, 0.32, 1.10}};
constexpr DigitalFilmPhysics velvia_50{
    {0.016, 0.011, 0.008}, {0.026, 0.009, 0.003}, 0.0032,
    {0.029, 0.30, 1.20}};
constexpr DigitalFilmPhysics portra_160{
    {0.030, 0.021, 0.015}, {0.045, 0.017, 0.006}, 0.0042,
    {0.020, 0.42, 1.25}};
constexpr DigitalFilmPhysics portra_400{
    {0.033, 0.023, 0.016}, {0.050, 0.019, 0.007}, 0.0046,
    {0.027, 0.44, 1.40}};
constexpr DigitalFilmPhysics portra_800{
    {0.036, 0.025, 0.018}, {0.056, 0.021, 0.008}, 0.0052,
    {0.034, 0.46, 1.60}};
constexpr DigitalFilmPhysics ektar_100{
    {0.026, 0.018, 0.013}, {0.040, 0.015, 0.005}, 0.0038,
    {0.015, 0.36, 1.10}};
constexpr DigitalFilmPhysics ultramax_400{
    {0.034, 0.024, 0.017}, {0.052, 0.020, 0.007}, 0.0048,
    {0.032, 0.48, 1.50}};
constexpr DigitalFilmPhysics colorplus_200{
    {0.034, 0.024, 0.017}, {0.054, 0.021, 0.008}, 0.0048,
    {0.030, 0.50, 1.45}};
constexpr DigitalFilmPhysics fujicolor_c200{
    {0.032, 0.023, 0.017}, {0.048, 0.019, 0.007}, 0.0046,
    {0.029, 0.46, 1.42}};
constexpr DigitalFilmPhysics pro_400h{
    {0.031, 0.022, 0.016}, {0.046, 0.018, 0.006}, 0.0044,
    {0.024, 0.40, 1.35}};
constexpr DigitalFilmPhysics velvia_100{
    {0.017, 0.012, 0.009}, {0.027, 0.010, 0.004}, 0.0033,
    {0.026, 0.31, 1.15}};
constexpr DigitalFilmPhysics e100_vs{
    {0.017, 0.011, 0.009}, {0.029, 0.010, 0.004}, 0.0035,
    {0.036, 0.33, 1.18}};
constexpr DigitalFilmPhysics astia_100f{
    {0.020, 0.014, 0.010}, {0.030, 0.011, 0.004}, 0.0040,
    {0.023, 0.33, 1.10}};
constexpr DigitalFilmPhysics kodachrome_64{
    {0.019, 0.013, 0.010}, {0.028, 0.010, 0.004}, 0.0042,
    {0.033, 0.30, 1.08}};
constexpr DigitalFilmPhysics gold_200{
    {0.034, 0.024, 0.017}, {0.053, 0.020, 0.007}, 0.0048,
    {0.030, 0.48, 1.45}};
constexpr DigitalFilmPhysics pro_image_100{
    {0.031, 0.022, 0.016}, {0.047, 0.018, 0.006}, 0.0044,
    {0.017, 0.40, 1.20}};
constexpr DigitalFilmPhysics superia_400{
    {0.032, 0.023, 0.016}, {0.050, 0.019, 0.007}, 0.0046,
    {0.028, 0.44, 1.40}};
constexpr DigitalFilmPhysics superia_premium_400{
    {0.031, 0.022, 0.016}, {0.048, 0.018, 0.007}, 0.0044,
    {0.025, 0.42, 1.35}};
constexpr DigitalFilmPhysics superia_200{
    {0.030, 0.022, 0.015}, {0.049, 0.018, 0.007}, 0.0044,
    {0.020, 0.40, 1.25}};
constexpr DigitalFilmPhysics reala_100{
    {0.030, 0.021, 0.015}, {0.045, 0.017, 0.006}, 0.0043,
    {0.015, 0.38, 1.15}};
constexpr DigitalFilmPhysics industrial_100{
    {0.030, 0.021, 0.015}, {0.046, 0.018, 0.006}, 0.0043,
    {0.018, 0.40, 1.20}};
constexpr DigitalFilmPhysics lomo_cn_800{
    {0.036, 0.025, 0.018}, {0.055, 0.021, 0.008}, 0.0050,
    {0.036, 0.52, 1.55}};
constexpr DigitalFilmPhysics vision3_500t{
    {0.032, 0.023, 0.016}, {0.034, 0.013, 0.005}, 0.0050,
    {0.022, 0.36, 1.30}};
constexpr DigitalFilmPhysics vision3_250d{
    {0.030, 0.021, 0.015}, {0.031, 0.012, 0.004}, 0.0046,
    {0.018, 0.34, 1.20}};
constexpr DigitalFilmPhysics vision3_50d{
    {0.028, 0.020, 0.014}, {0.030, 0.011, 0.004}, 0.0042,
    {0.013, 0.32, 1.10}};
constexpr DigitalFilmPhysics vision3_200t{
    {0.030, 0.022, 0.015}, {0.032, 0.012, 0.004}, 0.0048,
    {0.016, 0.33, 1.15}};

}  // namespace

const DigitalFilmPhysics* digital_film_physics(
    const FilmEmulation emulation) noexcept {
    switch (emulation) {
        case FilmEmulation::none: return nullptr;
        case FilmEmulation::ektachrome_e100: return &ektachrome_e100;
        case FilmEmulation::provia_100f: return &provia_100f;
        case FilmEmulation::velvia_50: return &velvia_50;
        case FilmEmulation::portra_160: return &portra_160;
        case FilmEmulation::portra_400: return &portra_400;
        case FilmEmulation::portra_800: return &portra_800;
        case FilmEmulation::ektar_100: return &ektar_100;
        case FilmEmulation::ultramax_400: return &ultramax_400;
        case FilmEmulation::colorplus_200: return &colorplus_200;
        case FilmEmulation::fujicolor_c200: return &fujicolor_c200;
        case FilmEmulation::pro_400h: return &pro_400h;
        case FilmEmulation::velvia_100: return &velvia_100;
        case FilmEmulation::e100_vs: return &e100_vs;
        case FilmEmulation::astia_100f: return &astia_100f;
        case FilmEmulation::kodachrome_64: return &kodachrome_64;
        case FilmEmulation::gold_200: return &gold_200;
        case FilmEmulation::pro_image_100: return &pro_image_100;
        case FilmEmulation::superia_400: return &superia_400;
        case FilmEmulation::superia_premium_400: return &superia_premium_400;
        case FilmEmulation::superia_200: return &superia_200;
        case FilmEmulation::reala_100: return &reala_100;
        case FilmEmulation::industrial_100: return &industrial_100;
        case FilmEmulation::lomo_cn_800: return &lomo_cn_800;
        case FilmEmulation::vision3_500t: return &vision3_500t;
        case FilmEmulation::vision3_250d: return &vision3_250d;
        case FilmEmulation::vision3_50d: return &vision3_50d;
        case FilmEmulation::vision3_200t: return &vision3_200t;
    }
    return nullptr;
}

}  // namespace negaflow::imaging
