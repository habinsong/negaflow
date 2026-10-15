#pragma once

// 필름 베이스 표본 추출의 공통 내부입니다. macOS 는 `FilmBaseSampleGrid`,
// `FilmBaseStatistics`, `FilmBaseEstimator` 를 한 모듈에 두고 자동 추정
// (`FilmBaseEstimator.estimate`)과 스포이드(`FilmBasePicker.sample`)가 **같은 함수**를
// 부릅니다. Windows 도 두 경로가 같은 코드를 쓰도록 여기로 모읍니다 — 갈라 두면 언젠가
// 한쪽만 고쳐지고 같은 클릭이 자동 추정과 다른 Dmin 을 냅니다.

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/analysis_region.h"
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

// macOS `FilmBaseSampleGrid.excludingInterior(of:)` — 크롭(사진) 영역 안의 칸을 검정으로 지운
// 사본입니다. 베이스 후보를 크롭 바깥 띠에서만 찾습니다. 지운 칸은 후보 판정(최소 luma)을
// 통과하지 못해 성분·모드·바닥 계산에 끼지 않습니다.
[[nodiscard]] SampleGrid excluding_interior(const SampleGrid& grid, const AnalysisRegion& region);

// 크롭(사진) 영역 **밖**의 칸을 검정으로 지운 사본입니다 — 띠에 베이스가 없을 때 사진 안에서만
// 찾습니다(macOS `FilmBaseSampleGrid.keepingInterior(of:)`).
[[nodiscard]] SampleGrid keeping_interior(const SampleGrid& grid, const AnalysisRegion& region);

// 칸이 크롭(사진) 영역에 걸치는가 — 바깥으로 정수화한 격자 사각형 기준(`excluding_interior` 와 같음).
[[nodiscard]] bool is_interior(
    const SampleGrid& grid, const AnalysisRegion& region, std::uint32_t x, std::uint32_t y) noexcept;

// 크롭 바깥 띠에서 광원과 베이스를 가르는 문턱입니다 — 번들 컬러 네거티브 마스크 색도의
// 전형값(중앙값)의 절반(측정 잡음·광원 색 여유). 강등은 두 색도 축(R/G, G/B)을 함께 보고,
// 형제 병합·리베이트 교체는 R/B 차를 봅니다(macOS `ringMaskChroma`·`backlightMaskLogMargin`).
struct RingMaskChroma final {
    double red_green{0.0};
    double green_blue{0.0};
    double red_blue{0.0};
};

[[nodiscard]] RingMaskChroma ring_mask_chroma() noexcept;

// 칸들의 log10(R/B) 중앙값(짝수면 위쪽)입니다.
[[nodiscard]] double median_log_red_blue(
    const SampleGrid& grid,
    const std::vector<std::size_t>& cells);

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

// macOS `FilmBaseEstimator.connectedBaseComponent`. `ring_only` 는 크롭 바깥 띠 격자에서
// 찾는다는 뜻이며, 그때만 색도 관계로 광원을 강등합니다.
// 베이스를 어디서 찾는가(macOS `FilmBaseEstimator.SearchScope`). 크롭이 있으면 크롭 바깥
// 띠(`ring`) → 크롭 안 사진(`photo`) 순서입니다.
enum class BaseSearchScope {
    // 프레임 전체 — 백라이트·퍼포레이션이 섞일 수 있어 밝기 사전확률 강등을 씁니다.
    frame,
    // 크롭 바깥 띠 — 리베이트·백라이트·홀더가 남습니다. 광원은 색도 관계로 가릅니다.
    ring,
    // 크롭 안 사진 — 전부 필름이라 광원이 없습니다. 강등하지 않습니다.
    photo,
};

// `demotes` 가 거짓이면 광원 강등 없이 가장 밝은 성분을 냅니다(띠 강등이 사진과 모순일 때의 재시도).
[[nodiscard]] std::optional<negaflow::imaging::FilmBaseMeasurement> connected_component_base(
    const SampleGrid& grid,
    NegativeFilmType film_type,
    BaseSearchScope scope = BaseSearchScope::frame,
    bool demotes = true);

}  // namespace negaflow::imaging::film_base_detail
