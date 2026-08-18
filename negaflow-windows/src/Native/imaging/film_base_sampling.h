#pragma once

// 필름 베이스 표본 추출의 공통 내부입니다. macOS 는 `FilmBaseSampleGrid`,
// `FilmBaseStatistics`, `FilmBaseEstimator` 를 한 모듈에 두고 자동 추정
// (`FilmBaseEstimator.estimate`)과 스포이드(`FilmBasePicker.sample`)가 **같은 함수**를
// 부릅니다. Windows 도 두 경로가 같은 코드를 쓰도록 여기로 모읍니다 — 갈라 두면 언젠가
// 한쪽만 고쳐지고 같은 클릭이 자동 추정과 다른 Dmin 을 냅니다.

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/film_base_measurement.h"
#include "negaflow/imaging/manual_negative_developer.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

namespace negaflow::imaging::film_base_detail {

using BaseMeasurement = std::array<double, 3>;

// macOS `FilmBaseSampleGrid` — 축소본 한 장과 셀별 luma 입니다.
struct SampleGrid final {
    std::uint32_t width{};
    std::uint32_t height{};
    std::vector<negaflow::core::Rgba32F> pixels;
    std::vector<double> lumas;
};

struct SampleGridGeometry final {
    std::uint32_t width{};
    std::uint32_t height{};
    double uniform_scale{};
};

// macOS `FilmBaseStatistics.percentile` — 정렬 후 `(n-1)×fraction` 자리입니다.
[[nodiscard]] double percentile(std::vector<double>& values, double fraction) noexcept;

// macOS `FilmBaseStatistics.median` — 짝수면 두 가운데 값의 평균입니다.
[[nodiscard]] double median(std::vector<double> values);

// macOS `medianRB` 의 `values[values.count / 2]` — 짝수면 위쪽입니다.
[[nodiscard]] double upper_median(std::vector<double> values);

[[nodiscard]] bool finite_rgb(const negaflow::core::Rgba32F& pixel) noexcept;

[[nodiscard]] double luma_of(const negaflow::core::Rgba32F& pixel) noexcept;

[[nodiscard]] bool has_compatible_layout(const WorkingImage& image) noexcept;

// macOS `FilmBaseEstimator.isFilmBaseCandidate`.
[[nodiscard]] bool is_component_candidate(
    const negaflow::core::Rgba32F& pixel,
    NegativeFilmType film_type) noexcept;

// macOS `FilmBaseStatistics.coherentCluster` + 채널 median.
[[nodiscard]] std::optional<BaseMeasurement> coherent_measurement(
    const std::vector<negaflow::core::Rgba32F>& pixels,
    const std::vector<std::size_t>& selected);

[[nodiscard]] std::optional<SampleGridGeometry> make_sample_grid_geometry(
    const WorkingImage& image,
    std::uint32_t minimum_width,
    std::uint32_t maximum_width) noexcept;

// macOS `FilmBaseSampleGrid(image:)` — 긴 변 32…256 으로 줄인 축소본입니다.
[[nodiscard]] std::optional<SampleGrid> make_sample_grid(const WorkingImage& image);

// 후보 셀의 색인입니다. macOS 는 `grid.samples.filter { isFilmBaseCandidate(...) }` 입니다.
[[nodiscard]] std::vector<std::size_t> candidate_indices(
    const SampleGrid& grid,
    NegativeFilmType film_type,
    const std::vector<bool>* excluded = nullptr);

// macOS `FilmBaseEstimator.candidateLumaPeak` — 후보 luma 의 p99 입니다.
[[nodiscard]] double candidate_luma_peak(
    const SampleGrid& grid,
    NegativeFilmType film_type);

// 격자 칸을 macOS `FilmBaseSample` 로 바꿉니다.
[[nodiscard]] negaflow::imaging::FilmBaseSample sample_at(
    const SampleGrid& grid,
    std::size_t index);

[[nodiscard]] std::vector<negaflow::imaging::FilmBaseSample> samples_from_indices(
    const SampleGrid& grid,
    const std::vector<std::size_t>& selected);

// macOS `FilmBaseEstimator.connectedBaseComponent`.
[[nodiscard]] std::optional<negaflow::imaging::FilmBaseMeasurement> connected_component_base(
    const SampleGrid& grid,
    NegativeFilmType film_type);

}  // namespace negaflow::imaging::film_base_detail
