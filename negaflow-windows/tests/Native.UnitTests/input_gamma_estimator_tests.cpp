#include "negaflow/color/input_gamma_estimator.h"
#include <cmath>
#include <iostream>
#include <vector>

namespace {
int failures = 0;
void expect(bool value, const char* message) {
    if (!value) { ++failures; std::cerr << "FAIL: " << message << '\n'; }
}
std::vector<negaflow::color::InputGammaEdge> edges(double gamma) {
    std::vector<negaflow::color::InputGammaEdge> result;
    for (std::uint32_t index = 0; index < 256U; ++index) {
        const auto offset = static_cast<double>(index % 17U) * 0.008;
        const negaflow::color::GammaPixel a{0.08+offset, 0.4+offset, 0.14+offset};
        const negaflow::color::GammaPixel b{0.65-offset, 0.2+offset, 0.75-offset};
        negaflow::color::InputGammaEdge edge{};
        edge.tile = index % 16U;
        constexpr std::array<double,9> weights{0,0,0.15,0.32,0.5,0.72,0.9,1,1};
        for (std::size_t i = 0; i < 9U; ++i) {
            for (std::size_t c = 0; c < 3U; ++c) {
                edge.samples[i][c] = std::pow(std::pow(a[c],gamma) + weights[i]*(std::pow(b[c],gamma)-std::pow(a[c],gamma)),1/gamma);
            }
        }
        result.push_back(edge);
    }
    return result;
}
}
int main() {
    using namespace negaflow::color;
    for (double gamma : {0.22,0.5,1.0,1.8,2.2,3.5}) {
        const auto estimate = estimate_input_gamma(edges(gamma));
        expect(estimate && std::abs(estimate->gamma-gamma) < 0.015 && estimate->evidence >= 0.65, "known power recovered");
        if (estimate) { std::cout << gamma << " -> " << estimate->gamma << " evidence=" << estimate->evidence << '\n'; }
    }
    expect(!estimate_input_gamma({}), "empty image rejected");
    auto sparse = edges(2.2);
    for (auto& edge : sparse) { edge.tile = 0; }
    expect(!estimate_input_gamma(sparse), "spatially sparse edges rejected");
    auto mixed = edges(1.0);
    const auto other = edges(2.4);
    for (std::size_t i = 0; i < mixed.size(); ++i) {
        if ((mixed[i].tile/4U+mixed[i].tile%4U)%2U != 0U) { mixed[i]=other[i]; }
    }
    expect(!estimate_input_gamma(mixed), "holdout disagreement rejected");
    for (const double value : {0.0,0.4,1.0}) {
        auto flat = edges(2.2);
        for (auto& edge : flat) { for (auto& pixel : edge.samples) { pixel={value,value,value}; } }
        expect(!estimate_input_gamma(flat), "flat gray or clipped image rejected");
    }
    std::cout << "gamma estimator failures=" << failures << '\n';
    return failures == 0 ? 0 : 1;
}
