// 자동 베이스가 얇은 리베이트를 놓쳤을 때 도는 구조길의 계약입니다.
//
// 실제로 깨진 스캔(OpticFilm8100-0001, 5136x3543)에서 리베이트는 높이의 0.45% 뿐이라 256 폭
// 격자에서 최소 크기 문턱을 못 넘고, 다음으로 밝은 덩어리인 **사진 내용** 이 베이스로
// 뽑혔습니다(0.143/0.060/0.029, 실제 0.357/0.150/0.076). 반전의 0 점이 낮게 앉아 사진이
// 통째로 어두워집니다.
//
// 조각마다 계약을 겁니다. 끝에서 끝까지 한 번에 거는 시험은 추정기 전체의 동작을 합성
// 이미지로 흉내 내야 하는데, 그 이미지는 사진이 아니라서 무엇을 고정하는지가 흐려집니다.

#include "auto_negative_base_rebate.h"

#include "negaflow/imaging/analysis_region.h"
#include "negaflow/imaging/auto_negative_base_resolver.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <array>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <optional>
#include <vector>

namespace {

using negaflow::imaging::auto_base_detail::accept_rebate_base;
using negaflow::imaging::auto_base_detail::brighter_than_base_fraction;
using negaflow::imaging::auto_base_detail::rebate_base;
using negaflow::imaging::film_base_detail::SampleGrid;
using negaflow::imaging::film_base_detail::make_sample_grid;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

void expect_near(
    const double actual,
    const double expected,
    const double tolerance,
    const char* const message) {
    if (!(std::abs(actual - expected) <= tolerance)) {
        std::cerr << "FAIL: " << message << " (actual " << actual << ", expected " << expected
                  << " +-" << tolerance << ")\n";
        ++failures;
    }
}

constexpr std::uint32_t width = 1024U;
constexpr std::uint32_t height = 708U;

/// 스캔 한 장입니다. `rebate_rows` 가 0 이면 리베이트가 찍히지 않은 사진입니다.
[[nodiscard]] negaflow::imaging::WorkingImage make_scan(
    const std::uint32_t rebate_rows,
    const float rebate_red,
    const float rebate_green,
    const float rebate_blue) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.assign(static_cast<std::size_t>(width) * height, negaflow::core::Rgba32F{});
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            negaflow::core::Rgba32F pixel{};
            if (y < 6U || y + 12U >= height) {
                // 스캐너가 아무것도 읽지 않은 자리입니다.
                pixel = negaflow::core::Rgba32F{0.001F, 0.001F, 0.001F, 1.0F};
            } else if (rebate_rows > 0U && y < 6U + rebate_rows) {
                pixel = negaflow::core::Rgba32F{rebate_red, rebate_green, rebate_blue, 1.0F};
            } else {
                const float shade =
                    0.85F + (0.30F * static_cast<float>(x) / static_cast<float>(width));
                pixel = negaflow::core::Rgba32F{
                    0.110F * shade, 0.0455F * shade, 0.0170F * shade, 1.0F};
            }
            image.pixels[static_cast<std::size_t>(y) * image.stride_pixels + x] = pixel;
        }
    }
    return image;
}

void the_band_is_measured_at_full_resolution_not_on_the_grid() {
    // 리베이트 세 줄. 격자에서는 위아래 검은 여백과 평균되어 절반 값으로 뭉개집니다 —
    // 그래서 **찾기만** 축소본에서 하고 **재기** 는 원본에서 합니다. 이 시험이 고정하는
    // 것이 바로 그 두 단계의 분리입니다.
    const negaflow::imaging::WorkingImage image = make_scan(3U, 0.357F, 0.150F, 0.0763F);
    const std::optional<SampleGrid> grid = make_sample_grid(image);
    expect(grid.has_value(), "band: the sample grid is built");
    if (!grid.has_value()) {
        return;
    }
    const std::optional<negaflow::imaging::film_base_detail::BaseMeasurement> measured =
        rebate_base(image, *grid, negaflow::imaging::NegativeFilmType::color, true);
    expect(measured.has_value(), "band: the rebate is found");
    if (!measured.has_value()) {
        return;
    }
    expect_near((*measured)[0], 0.357, 0.01, "band: red is the rebate, undiluted");
    expect_near((*measured)[1], 0.150, 0.01, "band: green is the rebate, undiluted");
    expect_near((*measured)[2], 0.0763, 0.01, "band: blue is the rebate, undiluted");
}

void a_photograph_without_a_rebate_yields_no_band() {
    const negaflow::imaging::WorkingImage image = make_scan(0U, 0.0F, 0.0F, 0.0F);
    const std::optional<SampleGrid> grid = make_sample_grid(image);
    expect(grid.has_value(), "no rebate: the sample grid is built");
    if (!grid.has_value()) {
        return;
    }
    const std::optional<negaflow::imaging::film_base_detail::BaseMeasurement> measured =
        rebate_base(image, *grid, negaflow::imaging::NegativeFilmType::color, true);
    // 리베이트가 없으면 가장 밝은 유지 수준은 장면 자신입니다. 그 값이 지금 값보다 밝을 수는
    // 없으므로 채택 심사에서 걸리고, 사진은 손대지 않은 채 남습니다.
    if (measured.has_value()) {
        const std::array<float, 3> scene_base{0.1265F, 0.0523F, 0.0196F};
        expect(
            !accept_rebate_base(*measured, scene_base),
            "no rebate: a band that is not brighter than the scene base is refused");
    }
}

void the_gate_counts_film_brighter_than_the_base() {
    const negaflow::imaging::WorkingImage image = make_scan(3U, 0.357F, 0.150F, 0.0763F);
    const std::optional<SampleGrid> grid = make_sample_grid(image);
    expect(grid.has_value(), "gate: the sample grid is built");
    if (!grid.has_value()) {
        return;
    }
    // 장면 한복판을 베이스라고 우기면 필름의 절반이 그보다 밝습니다 — 모순이고, 문지기가
    // 열려야 합니다.
    const double wrong = brighter_than_base_fraction(*grid, {0.100F, 0.0414F, 0.0155F});
    expect(wrong > 0.05, "gate: a base below the scene opens the gate");
    // 리베이트를 베이스로 잡으면 그보다 밝은 것은 없습니다.
    const double right = brighter_than_base_fraction(*grid, {0.357F, 0.150F, 0.0763F});
    expect(right <= 0.05, "gate: the true base keeps the gate shut");
}

void a_clipped_band_is_refused() {
    // 평판의 맨 광원은 센서 최대치에 붙습니다. 필름 베이스는 자기도 밀도가 있어 절대
    // 포화되지 않으므로, 포화된 띠를 채택하면 사진이 새까매집니다. 색이 없는 흑백에서는
    // 이것이 유일한 구분점입니다.
    const std::array<float, 3> current{0.14F, 0.06F, 0.03F};
    expect(
        !accept_rebate_base({0.9995, 0.9995, 0.9995}, current),
        "clipped: bare light saturating the sensor is refused");
    expect(
        accept_rebate_base({0.357, 0.150, 0.0763}, current),
        "clipped: a brighter unsaturated band is accepted");
    expect(
        !accept_rebate_base({0.10, 0.04, 0.02}, current),
        "clipped: a band darker than the current base is refused");
}

void a_diluted_rebate_is_recovered_even_though_the_gate_stays_shut() {
    // **문지기만으로는 못 잡는 경우입니다.** 이 스캔에서 추정기는 리베이트를 아예 놓치는
    // 대신 축소본에서 뭉개진 절반 값(0.179)을 고릅니다. 그 값은 장면보다는 밝아서 "베이스
    // 보다 밝은 화소" 가 거의 없고, 문지기가 열리지 않습니다. 그래도 사진은 두 배 어둡게
    // 나옵니다.
    //
    // 얇은 띠는 그 자체로 "여기서 읽은 값은 못 믿는다" 는 표시이므로, 그때는 문지기와
    // 무관하게 원본에서 확인합니다.
    const negaflow::imaging::WorkingImage image = make_scan(3U, 0.357F, 0.150F, 0.0763F);
    const negaflow::imaging::AutoNegativeBaseResult resolved =
        negaflow::imaging::resolve_auto_negative_base(
            image, negaflow::imaging::NegativeFilmType::color);

    expect(
        resolved.status == negaflow::imaging::AutoNegativeBaseStatus::ok,
        "diluted: the resolver reports ok");
    expect(
        resolved.brighter_than_base <= 0.05,
        "diluted: the gate stays shut - this is the case the gate cannot see");
    expect(resolved.rebate_rescued, "diluted: the thin band is checked at full resolution");
    expect_near(resolved.dmin[0], 0.357, 0.01, "diluted: red is the undiluted rebate");
    expect_near(resolved.dmin[1], 0.150, 0.01, "diluted: green is the undiluted rebate");
    expect_near(resolved.dmin[2], 0.0763, 0.01, "diluted: blue is the undiluted rebate");
}

void a_warm_light_boundary_does_not_replace_measured_film() {
    auto image = make_scan(0U, 0.357F, 0.150F, 0.0763F);
    for (auto& pixel : image.pixels) { pixel = {0.357F, 0.150F, 0.0763F, 1}; }
    // A short mixed edge can be too small for the connected-component base,
    // while still spanning the rebate locator's minimum sustained run.
    for (std::uint32_t y = 16; y < 24; ++y) {
        for (std::uint32_t x = 16; x < 316; ++x) {
            image.pixels[static_cast<std::size_t>(y) * width + x] = {0.57F, 0.51F, 0.36F, 1};
        }
    }
    const auto grid = make_sample_grid(image);
    expect(grid.has_value(), "warm light: sample grid exists");
    if (!grid) { return; }
    const auto proposed = rebate_base(image, *grid, negaflow::imaging::NegativeFilmType::color, true);
    expect(proposed.has_value() && (*proposed)[1] > 0.30,
        "warm light: the bright mixed boundary reaches rebate measurement");
    const auto resolved = negaflow::imaging::resolve_auto_negative_base(
        image, negaflow::imaging::NegativeFilmType::color);
    expect_near(resolved.dmin[0], 0.357, 0.01, "warm light: retain measured film red");
    expect_near(resolved.dmin[1], 0.150, 0.01, "warm light: retain measured film green");
    expect_near(resolved.dmin[2], 0.0763, 0.01, "warm light: retain measured film blue");
}

/// 위아래 프레임 사이 틈(각 `gap_rows` 줄)이 베이스이고, 그 사이가 사진입니다. 사진은 짙은 면과
/// 얇은 면이 섞였고 얇은 면도 베이스보다는 모든 채널이 어둡습니다(염료는 빛을 덜어내기만 합니다).
/// 위아래가 대칭이라 macOS 시험(`FilmBasePhysicalEnvelopeTests`)이 y 방향과 무관하게 같은 장면을
/// 씁니다.
[[nodiscard]] negaflow::imaging::WorkingImage make_frame_with_gap(
    const std::array<float, 3>& base,
    const std::array<float, 3>& dense,
    const std::array<float, 3>& thin,
    const std::uint32_t gap_rows) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.assign(static_cast<std::size_t>(width) * height, negaflow::core::Rgba32F{});
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            negaflow::core::Rgba32F pixel{};
            if (y < gap_rows || y >= height - gap_rows) {
                pixel = {base[0], base[1], base[2], 1.0F};
            } else if ((x / 128U + (y - gap_rows) / 128U) % 3U == 0U) {
                pixel = {thin[0], thin[1], thin[2], 1.0F};
            } else {
                pixel = {dense[0], dense[1], dense[2], 1.0F};
            }
            image.pixels[static_cast<std::size_t>(y) * image.stride_pixels + x] = pixel;
        }
    }
    return image;
}

/// 두 틈 사이의 사진 영역(크롭)입니다.
[[nodiscard]] negaflow::imaging::AnalysisRegion photo_between_gaps(const std::uint32_t gap_rows) {
    negaflow::imaging::AnalysisRegion region{};
    region.left = 0.02;
    region.top = static_cast<double>(gap_rows + 8U) / static_cast<double>(height);
    region.width = 0.96;
    region.height = 1.0 - 2.0 * region.top;
    return region;
}

void a_base_that_is_not_orange_is_still_the_base() {
    // 2026-10-31 GT-X900 · Kodak Vision3 250D 4~11번의 값입니다. 틈의 베이스가 초록·파랑이 빨강보다
    // 밝아 오렌지 후보에서 빠졌고, 사진 속 짙은 오렌지 면이 베이스로 골라져 반전이 어둡고 붉게
    // 잘렸습니다. 베이스는 색이 아니라 "모든 채널이 함께 가장 밝다" 로 찾아야 합니다.
    constexpr std::uint32_t gap_rows = 90U;
    const auto image = make_frame_with_gap(
        {0.30F, 0.34F, 0.33F}, {0.13F, 0.08F, 0.08F}, {0.24F, 0.25F, 0.22F}, gap_rows);
    for (const bool cropped : {true, false}) {
        const auto resolved = negaflow::imaging::resolve_auto_negative_base(
            image,
            negaflow::imaging::NegativeFilmType::color,
            cropped ? std::optional{photo_between_gaps(gap_rows)} : std::nullopt);
        const char* const label = cropped ? "cropped" : "uncropped";
        expect(resolved.status == negaflow::imaging::AutoNegativeBaseStatus::ok, label);
        expect_near(resolved.dmin[0], 0.30, 0.01, cropped ? "not orange (crop): red is the gap" : "not orange: red is the gap");
        expect_near(resolved.dmin[1], 0.34, 0.01, cropped ? "not orange (crop): green is the gap" : "not orange: green is the gap");
        expect_near(resolved.dmin[2], 0.33, 0.01, cropped ? "not orange (crop): blue is the gap" : "not orange: blue is the gap");
    }
}

void a_purple_base_is_still_the_base() {
    // Harman Phoenix 처럼 마스크가 오렌지가 아닌 필름입니다(XP2 계열의 보랏빛 베이스).
    constexpr std::uint32_t gap_rows = 90U;
    const auto image = make_frame_with_gap(
        {0.34F, 0.26F, 0.36F}, {0.12F, 0.07F, 0.06F}, {0.27F, 0.20F, 0.25F}, gap_rows);
    const auto resolved = negaflow::imaging::resolve_auto_negative_base(
        image, negaflow::imaging::NegativeFilmType::color, photo_between_gaps(gap_rows));
    expect_near(resolved.dmin[0], 0.34, 0.01, "purple: red is the gap");
    expect_near(resolved.dmin[1], 0.26, 0.01, "purple: green is the gap");
    expect_near(resolved.dmin[2], 0.36, 0.01, "purple: blue is the gap");
}

void neutral_light_beside_an_orange_base_stays_light() {
    // 오렌지 필름 디카 스캔에서 포화되지 않은 맨 광원(중성)이 틈 위에 찍힌 경우입니다. 광원은
    // 모든 채널이 베이스보다 밝지만 필름이 아닙니다 — 상대 색도로 걸러져 베이스가 그대로 남아야
    // 합니다.
    constexpr std::uint32_t light_rows = 60U;
    constexpr std::uint32_t gap_rows = 150U;
    auto image = make_frame_with_gap(
        {0.357F, 0.150F, 0.0763F}, {0.110F, 0.0455F, 0.0170F}, {0.30F, 0.12F, 0.060F}, gap_rows);
    for (std::uint32_t y = 0U; y < height; ++y) {
        if (y >= light_rows && y < height - light_rows) {
            continue;
        }
        for (std::uint32_t x = 0U; x < width; ++x) {
            image.pixels[static_cast<std::size_t>(y) * width + x] = {0.70F, 0.70F, 0.70F, 1.0F};
        }
    }
    const auto resolved = negaflow::imaging::resolve_auto_negative_base(
        image, negaflow::imaging::NegativeFilmType::color, photo_between_gaps(gap_rows));
    expect_near(resolved.dmin[0], 0.357, 0.01, "orange + light: red stays the base");
    expect_near(resolved.dmin[1], 0.150, 0.01, "orange + light: green stays the base");
    expect_near(resolved.dmin[2], 0.0763, 0.01, "orange + light: blue stays the base");
}

}  // namespace

int main() {
    the_band_is_measured_at_full_resolution_not_on_the_grid();
    a_photograph_without_a_rebate_yields_no_band();
    the_gate_counts_film_brighter_than_the_base();
    a_clipped_band_is_refused();
    a_diluted_rebate_is_recovered_even_though_the_gate_stays_shut();
    a_warm_light_boundary_does_not_replace_measured_film();
    a_base_that_is_not_orange_is_still_the_base();
    a_purple_base_is_still_the_base();
    neutral_light_beside_an_orange_base_stays_light();
    if (failures != 0) {
        std::cerr << failures << " auto negative base rebate assertion(s) failed\n";
        return 1;
    }
    std::cout << "auto negative base rebate tests passed\n";
    return 0;
}
