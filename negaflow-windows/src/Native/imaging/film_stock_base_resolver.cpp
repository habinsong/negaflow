#include "negaflow/imaging/film_stock_base_resolver.h"

#include <algorithm>
#include <array>
#include <cmath>

namespace negaflow::imaging {
namespace {

struct FilmStock final {
    std::wstring_view id;
    std::array<float, 3> dmin_density;
    std::array<float, 3> dmax_density;
};

constexpr std::array<FilmStock, 27> stocks{{
    {L"kodak-portra-160", {0.22F, 0.62F, 0.82F}, {2.20F, 2.80F, 3.00F}},
    {L"kodak-portra-400", {0.21F, 0.62F, 0.82F}, {2.25F, 2.85F, 3.05F}},
    {L"kodak-portra-800", {0.27F, 0.70F, 0.95F}, {2.20F, 2.75F, 2.95F}},
    {L"kodak-ektar-100", {0.25F, 0.62F, 0.82F}, {2.25F, 2.85F, 3.05F}},
    {L"kodak-gold-200", {0.24F, 0.65F, 0.88F}, {2.05F, 2.60F, 2.80F}},
    {L"kodak-ultramax-400", {0.25F, 0.65F, 0.90F}, {2.05F, 2.60F, 2.80F}},
    {L"kodak-pro-image-100", {0.25F, 0.65F, 0.85F}, {2.05F, 2.60F, 2.85F}},
    {L"kodak-colorplus-200", {0.25F, 0.65F, 0.90F}, {2.05F, 2.60F, 2.90F}},
    {L"fuji-c200", {0.20F, 0.58F, 0.88F}, {1.85F, 2.35F, 2.65F}},
    {L"fuji-200", {0.20F, 0.58F, 0.88F}, {1.85F, 2.35F, 2.65F}},
    {L"fuji-400", {0.14F, 0.55F, 0.95F}, {2.00F, 2.60F, 2.80F}},
    {L"fuji-superia-400", {0.20F, 0.58F, 0.88F}, {2.00F, 2.60F, 2.80F}},
    {L"fuji-100", {0.20F, 0.58F, 0.85F}, {1.85F, 2.35F, 2.65F}},
    {L"vision3-50d", {0.16F, 0.60F, 0.85F}, {1.90F, 2.70F, 2.90F}},
    {L"vision3-200t", {0.20F, 0.62F, 0.87F}, {2.05F, 2.75F, 2.95F}},
    {L"vision3-250d", {0.17F, 0.62F, 0.87F}, {2.00F, 2.70F, 2.95F}},
    {L"vision3-500t", {0.20F, 0.62F, 0.87F}, {2.05F, 2.75F, 2.95F}},
    {L"cinestill-50d", {0.20F, 0.65F, 0.90F}, {2.00F, 2.70F, 2.90F}},
    {L"cinestill-400d", {0.24F, 0.67F, 0.92F}, {2.05F, 2.75F, 2.95F}},
    {L"cinestill-800t", {0.24F, 0.70F, 0.95F}, {2.10F, 2.75F, 3.00F}},
    {L"lomo-cn-100", {0.22F, 0.62F, 0.88F}, {2.00F, 2.55F, 2.80F}},
    {L"lomo-cn-400", {0.24F, 0.67F, 0.92F}, {2.05F, 2.65F, 2.90F}},
    {L"lomo-cn-800", {0.27F, 0.72F, 0.97F}, {2.10F, 2.70F, 2.95F}},
    {L"harman-phoenix-200", {0.22F, 0.32F, 0.40F}, {1.70F, 1.80F, 2.15F}},
    {L"harman-phoenix-ii", {0.22F, 0.32F, 0.47F}, {1.70F, 1.80F, 2.15F}},
    {L"orwo-wolfen-nc400", {0.40F, 0.42F, 0.55F}, {1.85F, 1.90F, 2.10F}},
    {L"orwo-wolfen-nc500", {0.45F, 0.48F, 0.62F}, {1.85F, 1.90F, 2.15F}},
}};

[[nodiscard]] std::optional<std::array<float, 3>> light_gain(
    const std::wstring_view id) noexcept {
    if (id.empty() || id == L"neutral") return std::array<float, 3>{1.0F, 1.0F, 1.0F};
    if (id == L"white-led") return std::array<float, 3>{0.98F, 1.0F, 1.04F};
    if (id == L"warm-led") return std::array<float, 3>{1.06F, 1.0F, 0.92F};
    if (id == L"halogen") return std::array<float, 3>{1.09F, 1.0F, 0.88F};
    if (id == L"fluorescent") return std::array<float, 3>{0.97F, 1.03F, 1.0F};
    return std::nullopt;
}

}  // namespace

std::optional<FilmStockBasePreset> resolve_film_stock_base_preset(
    const std::wstring_view film_stock_id,
    const std::wstring_view light_source_profile_id,
    const NegativeFilmType film_type) noexcept {
    const auto stock = std::find_if(stocks.begin(), stocks.end(), [film_stock_id](const FilmStock& value) {
        return value.id == film_stock_id;
    });
    const auto gain = light_gain(light_source_profile_id);
    if (stock == stocks.end() || !gain) return std::nullopt;

    FilmStockBasePreset result{};
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        result.dmin[channel] = std::pow(10.0F, -stock->dmin_density[channel]);
        result.dmax_normalized[channel] = stock->dmax_density[channel] - stock->dmin_density[channel];
        result.light_gain[channel] = film_type == NegativeFilmType::black_and_white
            ? 1.0F
            : (*gain)[channel];
    }
    return result;
}

}  // namespace negaflow::imaging
