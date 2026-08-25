#include "infrared_confirmation.h"

#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <limits>
#include <numeric>
#include <vector>

namespace negaflow::imaging::infrared_detail {

namespace {

// 컴포넌트 좌표를 한 번만 풀어 두고 모든 이동 칸이 나눠 씁니다. 예전에는 `weighted_score` 가
// 칸마다 화소마다 `pixel % width` 와 `pixel / width` 를 다시 했습니다 - 실제
// `GT-X900_frame_18` 의 가장 큰 후보(bbox 116,595px)는 이동 칸이 5,353개여서 정수 나눗셈만
// 10억 회를 넘겼고, 그 후보 하나가 confirmation 634ms 의 98% 였습니다.
struct ComponentCoordinates final {
    std::vector<std::int32_t> x{};
    std::vector<std::int32_t> y{};
};

[[nodiscard]] ComponentCoordinates resolve_coordinates(
    const RawComponent& component,
    const std::uint32_t width) {
    ComponentCoordinates resolved{};
    resolved.x.resize(component.pixels.size());
    resolved.y.resize(component.pixels.size());
    for (std::size_t ordinal = 0U; ordinal < component.pixels.size(); ++ordinal) {
        const std::size_t pixel = component.pixels[ordinal];
        resolved.x[ordinal] = static_cast<std::int32_t>(pixel % width);
        resolved.y[ordinal] = static_cast<std::int32_t>(pixel / width);
    }
    return resolved;
}

[[nodiscard]] double resolved_score(
    const ComponentCoordinates& coordinates,
    const std::span<const float> weights,
    const std::span<const float> visible,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::int32_t dx,
    const std::int32_t dy) noexcept {
    double score = 0.0;
    const auto signed_width = static_cast<std::int32_t>(width);
    const auto signed_height = static_cast<std::int32_t>(height);
    for (std::size_t ordinal = 0U; ordinal < coordinates.x.size(); ++ordinal) {
        const std::int32_t x = coordinates.x[ordinal] + dx;
        const std::int32_t y = coordinates.y[ordinal] + dy;
        if (x >= 0 && y >= 0 && x < signed_width && y < signed_height) {
            score += static_cast<double>(weights[ordinal]) *
                visible[static_cast<std::size_t>(y) * width +
                    static_cast<std::uint32_t>(x)];
        }
    }
    return score;
}

}  // namespace

double weighted_score(
    const RawComponent& component,
    const std::span<const float> weights,
    const std::span<const float> visible,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::int32_t dx,
    const std::int32_t dy) {
    return resolved_score(
        resolve_coordinates(component, width), weights, visible, width, height, dx, dy);
}

float selection_bias(const float significance) noexcept {
    const double x = static_cast<double>(tuning::kMinimumSignificance - significance);
    const double density = std::exp(-0.5 * x * x) /
        std::sqrt(2.0 * tuning::kPi);
    const double tail = 0.5 * std::erfc(x / std::sqrt(2.0));
    return tail > 1.0e-12 ? static_cast<float>(density / tail) : 0.0F;
}

bool confirm_component(
    const RawComponent& component,
    const std::span<const float> density,
    const std::span<const float> visible,
    const std::uint32_t width,
    const std::uint32_t height,
    const float magnitude_floor,
    const std::int32_t search,
    const std::int32_t origin_x,
    const std::int32_t origin_y,
    ConfirmedDefect& confirmed) {
    std::vector<float> weights(component.pixels.size(), 0.0F);
    double square_sum = 0.0;
    for (std::size_t ordinal = 0U; ordinal < component.pixels.size(); ++ordinal) {
        const float weight = std::max(0.0F, density[component.pixels[ordinal]] - magnitude_floor);
        weights[ordinal] = weight;
        square_sum += static_cast<double>(weight) * weight;
    }
    if (!(square_sum > 0.0)) return false;
    const ComponentCoordinates coordinates = resolve_coordinates(component, width);

    // 이 격자는 (2*search+1)^2 번 `weighted_score` 를 부르고 그 하나하나가 컴포넌트 화소를
    // 전부 훑습니다. 바깥 후보 반복은 이미 병렬이지만 **큰 결함 하나가 통째로 직렬**이 되어,
    // 실제 `GT-X900_frame_18` 에서 후보 359개 중 하나가 622ms 로 confirmation 634ms 의 98%
    // 였습니다(bbox 116,595px). 행마다 최선을 따로 구한 뒤 dy 순서로 합치므로 결과는
    // 순차판과 **같습니다** - 원래도 처음으로 더 큰 점수를 만난 칸이 이깁니다.
    const std::size_t search_rows = static_cast<std::size_t>(2 * search + 1);
    std::vector<double> row_best(search_rows, -std::numeric_limits<double>::infinity());
    std::vector<std::int32_t> row_best_dx(search_rows, 0);
    negaflow::core::for_each_row_block(
        static_cast<std::uint32_t>(search_rows),
        static_cast<std::uint64_t>(search_rows) * search_rows *
            std::max<std::size_t>(component.pixels.size(), 1U),
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t row = first_row; row < first_row + row_count; ++row) {
                const std::int32_t dy = static_cast<std::int32_t>(row) - search;
                double row_value = -std::numeric_limits<double>::infinity();
                std::int32_t row_dx = 0;
                for (std::int32_t dx = -search; dx <= search; ++dx) {
                    const double score = resolved_score(
                        coordinates, weights, visible, width, height,
                        dx + origin_x, dy + origin_y);
                    if (score > row_value) {
                        row_value = score;
                        row_dx = dx;
                    }
                }
                row_best[row] = row_value;
                row_best_dx[row] = row_dx;
            }
        });
    double best = -std::numeric_limits<double>::infinity();
    std::int32_t best_x = 0;
    std::int32_t best_y = 0;
    for (std::size_t row = 0U; row < search_rows; ++row) {
        if (row_best[row] > best) {
            best = row_best[row];
            best_x = row_best_dx[row];
            best_y = static_cast<std::int32_t>(row) - search;
        }
    }
    if (!(best > 0.0)) return false;

    const auto extent = static_cast<std::int32_t>(
        std::min(component.max_x - component.min_x,
                 component.max_y - component.min_y) / 2U + 1U);
    const std::int32_t null_inner = 2 * extent + 2;
    std::vector<double> null_samples{};
    null_samples.reserve(static_cast<std::size_t>(2 * search + 1) *
                         static_cast<std::size_t>(2 * search + 1));
    for (std::int32_t dy = -search; dy <= search; ++dy) {
        for (std::int32_t dx = -search; dx <= search; ++dx) {
            if (std::max(std::abs(dx), std::abs(dy)) >= null_inner) {
                null_samples.push_back(resolved_score(
                    coordinates, weights, visible, width, height,
                    dx + origin_x, dy + origin_y));
            }
        }
    }
    // 위 격자가 비면(큰 결함은 `null_inner` 가 `search` 를 넘어 한 칸도 안 남습니다) null 표본이
    // 전부 여기서 나옵니다. 반경 하나만으로 200개를 채우고 끝나지만 그 한 반경이 수천 칸이라
    // 위 격자와 맞먹는 비용입니다. 바깥 반경 반복과 멈춤 조건은 그대로 두고 **한 반경 안만**
    // 병렬로 셉니다 - 칸 목록과 넣는 순서가 순차판과 같으므로 표본 집합이 같습니다.
    std::vector<std::int32_t> ring_dx{};
    std::vector<std::int32_t> ring_dy{};
    std::vector<double> ring_scores{};
    for (std::int32_t radius = std::max(null_inner, search + 1);
         null_samples.size() < tuning::kMinimumNullSamples && radius <=
             std::max(null_inner, search + 1) + 2 * extent + 8;
         ++radius) {
        ring_dx.clear();
        ring_dy.clear();
        for (std::int32_t dy = -radius; dy <= radius; ++dy) {
            const std::int32_t step = std::abs(dy) == radius ? 1 : 2 * radius;
            for (std::int32_t dx = -radius; dx <= radius; dx += step) {
                ring_dx.push_back(dx);
                ring_dy.push_back(dy);
            }
        }
        ring_scores.assign(ring_dx.size(), 0.0);
        negaflow::core::for_each_row_block(
            static_cast<std::uint32_t>(ring_dx.size()),
            static_cast<std::uint64_t>(ring_dx.size()) *
                std::max<std::size_t>(component.pixels.size(), 1U),
            [&](const std::uint32_t first, const std::uint32_t count) noexcept {
                for (std::uint32_t cell = first; cell < first + count; ++cell) {
                    ring_scores[cell] = resolved_score(
                        coordinates, weights, visible, width, height,
                        ring_dx[cell] + origin_x, ring_dy[cell] + origin_y);
                }
            });
        null_samples.insert(null_samples.end(), ring_scores.begin(), ring_scores.end());
    }
    if (null_samples.size() < tuning::kMinimumNullSamples) return false;
    std::sort(null_samples.begin(), null_samples.end());
    const double center = null_samples[null_samples.size() / 2U];
    std::vector<double> deviations(null_samples.size(), 0.0);
    std::transform(null_samples.begin(), null_samples.end(), deviations.begin(),
                   [center](const double value) { return std::abs(value - center); });
    std::sort(deviations.begin(), deviations.end());
    const double deviation = 1.4826 * deviations[deviations.size() / 2U];
    const float significance = deviation > 0.0
        ? static_cast<float>((best - center) / deviation)
        : std::numeric_limits<float>::max();
    if (significance < tuning::kMinimumSignificance) return false;
    const double signal = best - static_cast<double>(selection_bias(significance)) * deviation - center;
    if (!(signal > 0.0)) return false;
    const float gain = static_cast<float>(signal / square_sum);
    if (!std::isfinite(gain) || gain <= 0.0F) return false;
    confirmed = ConfirmedDefect{
        best_x + origin_x,
        best_y + origin_y,
        std::clamp(gain, 0.2F, 4.0F),
        significance};
    return true;
}

ConsensusOffset coarse_consensus_offset(
    const std::vector<RawComponent>& candidates,
    const std::span<const float> density,
    const std::span<const float> visible,
    const std::uint32_t width,
    const std::uint32_t height,
    const float magnitude_floor,
    const std::int32_t search) {
    std::vector<std::size_t> order(candidates.size(), 0U);
    std::iota(order.begin(), order.end(), 0U);
    std::sort(order.begin(), order.end(), [&](const std::size_t a, const std::size_t b) {
        return candidates[a].source_area > candidates[b].source_area;
    });
    std::vector<std::int32_t> votes_x{};
    std::vector<std::int32_t> votes_y{};
    const std::size_t vote_count = std::min<std::size_t>(64U, order.size());
    votes_x.reserve(vote_count);
    votes_y.reserve(vote_count);
    for (std::size_t ordinal = 0U; ordinal < vote_count; ++ordinal) {
        const RawComponent& candidate = candidates[order[ordinal]];
        const auto extent = static_cast<std::int32_t>(
            std::min(candidate.max_x - candidate.min_x,
                     candidate.max_y - candidate.min_y) / 2U + 1U);
        ConfirmedDefect vote{};
        if (confirm_component(candidate, density, visible, width, height,
                              magnitude_floor, search + extent, 0, 0, vote)) {
            votes_x.push_back(vote.offset_x);
            votes_y.push_back(vote.offset_y);
        }
    }
    if (votes_x.size() < 8U) return {};
    std::sort(votes_x.begin(), votes_x.end());
    std::sort(votes_y.begin(), votes_y.end());
    return ConsensusOffset{
        votes_x[votes_x.size() / 2U],
        votes_y[votes_y.size() / 2U]};
}

}  // namespace negaflow::imaging::infrared_detail
