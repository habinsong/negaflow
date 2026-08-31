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

#include "negaflow/imaging/auto_negative_base_resolver.h"
#include "negaflow/imaging/scanner_to_working.h"

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

}  // namespace

int main() {
    the_band_is_measured_at_full_resolution_not_on_the_grid();
    a_photograph_without_a_rebate_yields_no_band();
    the_gate_counts_film_brighter_than_the_base();
    a_clipped_band_is_refused();
    a_diluted_rebate_is_recovered_even_though_the_gate_stays_shut();
    if (failures != 0) {
        std::cerr << failures << " auto negative base rebate assertion(s) failed\n";
        return 1;
    }
    std::cout << "auto negative base rebate tests passed\n";
    return 0;
}
