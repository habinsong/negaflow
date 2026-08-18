#include "negaflow/imaging/film_base_picker.h"

#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
#include <string_view>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

// 오렌지 마스크 베이스. macOS `isFilmBaseCandidate` 의 R≥G≥B 단조와 R−B 분리를 만족합니다.
constexpr negaflow::core::Rgba32F base_pixel{0.36F, 0.20F, 0.11F, 1.0F};

// 장면(짙은 밀도). 베이스보다 한참 어두워 후보 바닥 아래로 떨어집니다.
constexpr negaflow::core::Rgba32F scene_pixel{0.020F, 0.011F, 0.006F, 1.0F};

// 필름 밖 검정 띠. macOS 주석이 말한 "클릭이 빗나가면 base 0.004 가 앉아 화면이 검게 죽는"
// 자리이며, 타당성 검사가 걸러야 합니다.
constexpr negaflow::core::Rgba32F black_bar{0.004F, 0.003F, 0.002F, 1.0F};

[[nodiscard]] negaflow::imaging::WorkingImage make_image(
    const std::uint32_t width,
    const std::uint32_t height) {
    negaflow::imaging::WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.assign(static_cast<std::size_t>(width) * height, scene_pixel);
    return image;
}

void fill(
    negaflow::imaging::WorkingImage& image,
    const std::uint32_t left,
    const std::uint32_t top,
    const std::uint32_t width,
    const std::uint32_t height,
    const negaflow::core::Rgba32F value) {
    for (std::uint32_t y = top; y < top + height; ++y) {
        for (std::uint32_t x = left; x < left + width; ++x) {
            image.pixels[(static_cast<std::size_t>(y) * image.stride_pixels) + x] = value;
        }
    }
}

[[nodiscard]] bool near(const float value, const float expected) noexcept {
    return std::abs(value - expected) <= 1.0e-3F;
}

/// 왼쪽 세로 띠가 필름 베이스인 스캔입니다. 그 띠를 클릭하면 베이스 값이 나와야 합니다.
void verify_picks_the_base_band() {
    negaflow::imaging::WorkingImage image = make_image(800U, 600U);
    fill(image, 0U, 0U, 160U, 600U, base_pixel);

    const negaflow::imaging::FilmBasePickResult picked =
        negaflow::imaging::sample_film_base(
            image, 0.10, 0.50, negaflow::imaging::NegativeFilmType::color);
    expect(
        picked.status == negaflow::imaging::FilmBasePickStatus::ok,
        "film_base_picker_accepts_the_base_band");
    expect(
        near(picked.rgb[0], base_pixel.red) && near(picked.rgb[1], base_pixel.green) &&
            near(picked.rgb[2], base_pixel.blue),
        "film_base_picker_returns_the_base_transmittance");
}

/// macOS `snapToBase` — 조준이 빗나가도 창 안에서 베이스 성분으로 스냅합니다. 클릭이 띠
/// 바깥(장면 쪽)이라도 로컬 창(짧은 변 × 0.12 = 72px)이 띠를 물면 같은 값이 나옵니다.
void verify_snaps_from_a_near_miss() {
    negaflow::imaging::WorkingImage image = make_image(800U, 600U);
    fill(image, 0U, 0U, 160U, 600U, base_pixel);

    const negaflow::imaging::FilmBasePickResult picked =
        negaflow::imaging::sample_film_base(
            image, 0.23, 0.50, negaflow::imaging::NegativeFilmType::color);
    expect(
        picked.status == negaflow::imaging::FilmBasePickStatus::ok &&
            near(picked.rgb[0], base_pixel.red),
        "film_base_picker_snaps_to_the_base_from_a_near_miss");
}

/// macOS `isPlausibleBase` — 필름 밖 검정 띠를 집으면 거절합니다. 이것이 없으면 base 0.004
/// 가 Dmin 으로 앉아 반전이 전 구간 클리핑되고 사진이 통째로 검게 죽습니다.
void verify_rejects_the_black_bar() {
    negaflow::imaging::WorkingImage image = make_image(800U, 600U);
    fill(image, 0U, 0U, 160U, 600U, base_pixel);
    fill(image, 640U, 0U, 160U, 600U, black_bar);

    const negaflow::imaging::FilmBasePickResult picked =
        negaflow::imaging::sample_film_base(
            image, 0.95, 0.50, negaflow::imaging::NegativeFilmType::color);
    expect(
        picked.status == negaflow::imaging::FilmBasePickStatus::implausible,
        "film_base_picker_rejects_a_pick_outside_the_film");
}

/// 장면 한복판을 집어도 거절합니다 — 스캔 전체의 베이스 수준(후보 luma p99)의 절반에
/// 못 미치기 때문입니다(macOS `minimumBaseLumaRatio` 0.5).
void verify_rejects_the_scene() {
    negaflow::imaging::WorkingImage image = make_image(800U, 600U);
    fill(image, 0U, 0U, 160U, 600U, base_pixel);

    const negaflow::imaging::FilmBasePickResult picked =
        negaflow::imaging::sample_film_base(
            image, 0.70, 0.50, negaflow::imaging::NegativeFilmType::color);
    expect(
        picked.status == negaflow::imaging::FilmBasePickStatus::implausible,
        "film_base_picker_rejects_a_pick_inside_the_scene");
}

/// 잘못된 레이아웃과 유한하지 않은 좌표는 `invalid_image` 입니다 — 호출부가 Dmin 을 바꾸지
/// 않도록 `implausible` 과 구분합니다.
void verify_rejects_bad_input() {
    negaflow::imaging::WorkingImage empty{};
    expect(
        negaflow::imaging::sample_film_base(
            empty, 0.5, 0.5, negaflow::imaging::NegativeFilmType::color)
                .status == negaflow::imaging::FilmBasePickStatus::invalid_image,
        "film_base_picker_rejects_an_empty_image");

    negaflow::imaging::WorkingImage image = make_image(800U, 600U);
    fill(image, 0U, 0U, 160U, 600U, base_pixel);
    expect(
        negaflow::imaging::sample_film_base(
            image,
            std::numeric_limits<double>::quiet_NaN(),
            0.5,
            negaflow::imaging::NegativeFilmType::color)
                .status == negaflow::imaging::FilmBasePickStatus::invalid_image,
        "film_base_picker_rejects_a_non_finite_coordinate");
}

/// 흑백 네거티브는 중립 베이스입니다. 오렌지 판정을 쓰면 회색 베이스가 전부 탈락합니다.
void verify_neutral_base() {
    negaflow::imaging::WorkingImage image = make_image(800U, 600U);
    constexpr negaflow::core::Rgba32F neutral{0.30F, 0.30F, 0.30F, 1.0F};
    constexpr negaflow::core::Rgba32F dark{0.02F, 0.02F, 0.02F, 1.0F};
    image.pixels.assign(image.pixels.size(), dark);
    fill(image, 0U, 0U, 160U, 600U, neutral);

    const negaflow::imaging::FilmBasePickResult picked =
        negaflow::imaging::sample_film_base(
            image, 0.10, 0.50, negaflow::imaging::NegativeFilmType::black_and_white);
    expect(
        picked.status == negaflow::imaging::FilmBasePickStatus::ok &&
            near(picked.rgb[0], neutral.red) && near(picked.rgb[2], neutral.blue),
        "film_base_picker_accepts_a_neutral_base_for_black_and_white");
}

/// RealScan.tiff 와 같은 631×403 잘린 프레임 — 가장자리 24px 가 오렌지 리베이트.
void verify_picks_a_narrow_rebate_on_a_small_frame() {
    constexpr std::uint32_t width = 631U;
    constexpr std::uint32_t height = 403U;
    constexpr std::uint32_t rebate = 24U;
    negaflow::imaging::WorkingImage image = make_image(width, height);
    fill(image, 0U, 0U, width, rebate, base_pixel);
    fill(image, 0U, height - rebate, width, rebate, base_pixel);
    fill(image, 0U, 0U, rebate, height, base_pixel);
    fill(image, width - rebate, 0U, rebate, height, base_pixel);

    const negaflow::imaging::FilmBasePickResult edge =
        negaflow::imaging::sample_film_base(
            image, 0.02, 0.50, negaflow::imaging::NegativeFilmType::color);
    expect(
        edge.status == negaflow::imaging::FilmBasePickStatus::ok &&
            near(edge.rgb[0], base_pixel.red),
        "film_base_picker_accepts_a_narrow_rebate_edge");

    const negaflow::imaging::FilmBasePickResult scene =
        negaflow::imaging::sample_film_base(
            image, 0.50, 0.50, negaflow::imaging::NegativeFilmType::color);
    expect(
        scene.status == negaflow::imaging::FilmBasePickStatus::implausible,
        "film_base_picker_rejects_the_scene_inside_a_rebated_frame");
}

void verify_status_names() {
    expect(
        std::string_view{negaflow::imaging::film_base_pick_status_name(
            negaflow::imaging::FilmBasePickStatus::implausible)} == "implausible",
        "film_base_pick_status_name_reports_implausible");
}

}  // namespace

int main() {
    verify_picks_the_base_band();
    verify_snaps_from_a_near_miss();
    verify_rejects_the_black_bar();
    verify_rejects_the_scene();
    verify_rejects_bad_input();
    verify_neutral_base();
    verify_picks_a_narrow_rebate_on_a_small_frame();
    verify_status_names();
    if (failures != 0) {
        std::cerr << failures << " film base picker checks failed\n";
        return 1;
    }
    std::cout << "film base picker checks passed\n";
    return 0;
}
