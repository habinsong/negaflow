#include "negaflow/color/input_gamma_estimator.h"
#include <algorithm>
#include <cmath>
#include <limits>
#include <vector>

namespace negaflow::color {
namespace {
GammaPixel sub(GammaPixel a, GammaPixel b) noexcept { return {a[0]-b[0], a[1]-b[1], a[2]-b[2]}; }
GammaPixel midpoint(GammaPixel a, GammaPixel b) noexcept { return {(a[0]+b[0])/2, (a[1]+b[1])/2, (a[2]+b[2])/2}; }
double dot(GammaPixel a, GammaPixel b) noexcept { return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]; }
double length(GammaPixel a) noexcept { return std::sqrt(dot(a,a)); }
GammaPixel cross(GammaPixel a, GammaPixel b) noexcept {
    return {a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]};
}
double score(double gamma, std::span<const InputGammaEdge> edges) {
    std::vector<double> residuals;
    residuals.reserve(edges.size());
    for (const auto& edge : edges) {
        auto p = edge.samples;
        for (auto& pixel : p) { for (auto& channel : pixel) { channel = std::pow(channel, gamma); } }
        const auto a = midpoint(p[0],p[1]), b = midpoint(p[7],p[8]), d = sub(b,a);
        const auto norm = dot(d,d);
        if (norm <= 1e-12) { continue; }
        double error = 0;
        for (std::size_t index = 2; index <= 6; ++index) {
            const auto q = sub(p[index],a);
            const auto t = dot(q,d)/norm;
            const auto delta = sub(q,{t*d[0],t*d[1],t*d[2]});
            error += dot(delta,delta)/norm;
        }
        residuals.push_back(error/5);
    }
    if (residuals.empty()) { return std::numeric_limits<double>::infinity(); }
    const auto middle = residuals.begin()+static_cast<std::ptrdiff_t>(residuals.size()/2);
    std::nth_element(residuals.begin(),middle,residuals.end());
    return *middle;
}
double fit(std::span<const InputGammaEdge> edges) {
    double best = 1, loss = std::numeric_limits<double>::infinity();
    for (int index = 0; index <= 195; ++index) {
        const auto gamma = 0.1+index*0.02, candidate = score(gamma,edges);
        if (candidate < loss) { best=gamma; loss=candidate; }
    }
    const auto center = best;
    for (int index = -19; index <= 19; ++index) {
        const auto gamma = std::clamp(center+index*0.001,0.1,4.0), candidate=score(gamma,edges);
        if (candidate < loss) { best=gamma; loss=candidate; }
    }
    return best;
}
}  // namespace

bool accepts_input_gamma_edge(const InputGammaEdge& edge) noexcept {
    if (edge.tile >= 16U) { return false; }
    for (const auto& p : edge.samples) {
        for (const auto value : p) { if (!std::isfinite(value) || value <= 0.02 || value >= 0.98) { return false; } }
    }
    const auto& p = edge.samples;
    const auto a=midpoint(p[0],p[1]), b=midpoint(p[7],p[8]);
    const auto contrast=length(sub(b,a));
    return contrast >= 0.08 && std::max(length(sub(p[0],p[1])),length(sub(p[7],p[8]))) <= contrast*0.2 &&
        length(cross(a,b))/(length(a)*length(b)) >= 0.05;
}

std::optional<InputGammaEstimate> estimate_input_gamma(std::span<const InputGammaEdge> edges) noexcept {
    try {
        if (edges.size() > 12288U) { return {}; }
        std::vector<InputGammaEdge> valid, training, validation;
        std::array<std::vector<InputGammaEdge>,16> groups;
        std::array<bool,16> tiles{};
        for (const auto& edge : edges) {
            if (!accepts_input_gamma_edge(edge)) { continue; }
            groups[edge.tile].push_back(edge);
        }
        for (std::size_t tile = 0; tile < groups.size(); ++tile) {
            const auto& group = groups[tile];
            const auto count = std::min<std::size_t>(32U,group.size());
            tiles[tile] = count != 0U;
            for (std::size_t i = 0; i < count; ++i) {
                const auto& edge = group[i*group.size()/count];
                valid.push_back(edge);
                ((tile/4+tile%4)%2==0 ? training : validation).push_back(edge);
            }
        }
        if (valid.size()<48U || std::count(tiles.begin(),tiles.end(),true)<6 || training.size()<20U || validation.size()<20U) { return {}; }
        const auto first=fit(training), second=fit(validation);
        if (first<=0.12 || first>=3.98 || second<=0.12 || second>=3.98 || std::abs(std::log(first/second))>=0.15) { return {}; }
        const auto gamma=std::sqrt(first*second), residual=score(gamma,valid);
        const auto separated=std::min(score(std::max(0.1,gamma*0.75),valid),score(std::min(4.0,gamma*1.333333333333),valid));
        if (!std::isfinite(residual) || separated<=residual+std::max(1e-6,residual*0.25)) { return {}; }
        const auto support=std::min(1.0,static_cast<double>(valid.size())/128);
        const auto agreement=std::max(0.0,1-std::abs(std::log(first/second))/0.15);
        const auto separation=std::min(1.0,(separated-residual)/std::max(separated,1e-9));
        const auto evidence=std::min({support,agreement,separation});
        if (evidence<0.65) { return {}; }
        return InputGammaEstimate{std::round(gamma*1000)/1000,evidence,static_cast<std::uint32_t>(valid.size())};
    } catch (...) { return {}; }
}
}  // namespace negaflow::color
