#pragma once
#include <array>
#include <cstdint>
#include <optional>
#include <span>

namespace negaflow::color {
using GammaPixel = std::array<double, 3>;
struct InputGammaEdge final {
    std::array<GammaPixel, 9> samples{};
    std::uint32_t tile{0};
};
struct InputGammaEstimate final {
    double gamma{0};
    double evidence{0};
    std::uint32_t edge_count{0};
};
[[nodiscard]] bool accepts_input_gamma_edge(const InputGammaEdge& edge) noexcept;
[[nodiscard]] std::optional<InputGammaEstimate> estimate_input_gamma(std::span<const InputGammaEdge> edges) noexcept;
}  // namespace negaflow::color
