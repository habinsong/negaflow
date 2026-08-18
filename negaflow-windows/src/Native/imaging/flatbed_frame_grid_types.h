#pragma once

/* 평판 격자 검출이 주고받는 타입 한 벌입니다. 신호·프로파일·띠·격자 맞추기가 모두
   같은 구조체를 봐야 하므로 파일마다 다시 쓰지 않습니다. */

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

namespace negaflow::imaging::flatbed_detail {

constexpr double kGridEvidenceFloor = 0.15;

struct IntRange final {
    int first{0};
    int last{0};  // exclusive

    [[nodiscard]] int count() const noexcept { return last - first; }
};

struct DoubleRange final {
    double first{0.0};
    double last{0.0};
};

struct Geometry final {
    double along_mm{0.0};
    double across_mm{0.0};
    double gap_min_mm{0.0};
    double gap_max_mm{0.0};
    bool rigid_pitch{false};
    double pixels_per_mm_x{0.0};
    double pixels_per_mm_y{0.0};

    [[nodiscard]] double along_pixels_y() const noexcept {
        return along_mm * pixels_per_mm_y;
    }
    [[nodiscard]] double across_pixels_x() const noexcept {
        return across_mm * pixels_per_mm_x;
    }
    [[nodiscard]] double gap_min_pixels_y() const noexcept {
        return gap_min_mm * pixels_per_mm_y;
    }
    [[nodiscard]] double gap_max_pixels_y() const noexcept {
        return gap_max_mm * pixels_per_mm_y;
    }
    [[nodiscard]] DoubleRange pitch_pixels_y() const noexcept {
        const double slack = rigid_pitch ? 0.02 : 0.05;
        return {
            (along_mm * (1.0 - slack) + gap_min_mm) * pixels_per_mm_y,
            (along_mm * (1.0 + slack) + gap_max_mm) * pixels_per_mm_y,
        };
    }
};

struct ColumnProfiles final {
    std::vector<double> detail{};
    std::vector<double> mean{};
};

struct RowProfiles final {
    std::vector<double> mean{};
    std::vector<double> detail{};
    std::vector<double> grain{};
    std::vector<double> surround{};
};

struct Slot final {
    IntRange measured{};
    IntRange snapped{};
};

struct GapEvidence final {
    std::vector<double> plateau{};
    std::vector<double> edge{};
    std::vector<double> content{};
    std::vector<double> prefix{};
    std::vector<double> content_prefix{};

    [[nodiscard]] int count() const noexcept {
        return static_cast<int>(plateau.size());
    }

    [[nodiscard]] std::pair<double, double> content_sum(
        const double from,
        const double to) const noexcept {
        const int lower = std::max(0, static_cast<int>(std::lround(from)));
        const int upper = std::min(count(), static_cast<int>(std::lround(to)));
        if (upper <= lower) {
            return {0.0, 0.0};
        }
        return {content_prefix[static_cast<std::size_t>(upper)] -
                    content_prefix[static_cast<std::size_t>(lower)],
                static_cast<double>(upper - lower)};
    }

    [[nodiscard]] std::optional<double> score(
        const double center,
        const double half) const noexcept {
        const int lower = static_cast<int>(std::lround(center - half));
        const int upper = static_cast<int>(std::lround(center + half));
        if (lower < 0 || upper > count() || upper <= lower) {
            return std::nullopt;
        }
        const double flat = (prefix[static_cast<std::size_t>(upper)] -
                             prefix[static_cast<std::size_t>(lower)]) /
                            static_cast<double>(upper - lower);
        const double leading = edge[static_cast<std::size_t>(std::clamp(
            lower, 0, count() - 1))];
        const double trailing = edge[static_cast<std::size_t>(std::clamp(
            upper - 1, 0, count() - 1))];
        const double edge_pair = std::sqrt(std::max(0.0, leading * trailing));
        return std::sqrt(std::max(0.0, flat) * std::max(0.0, edge_pair));
    }
};

struct Grid final {
    std::vector<double> boundaries{};
    double confidence{0.0};
};

}  // namespace negaflow::imaging::flatbed_detail
