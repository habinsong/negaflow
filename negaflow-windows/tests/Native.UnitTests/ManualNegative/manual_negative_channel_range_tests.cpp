#include "manual_negative_test_support.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <utility>
#include <vector>

// 채널 밀도 범위비(ρ) ≠ 1 인 필름에서 고정 범위가 회색을 기울이는지, `channel_range` 가 그것을
// 지우는지, 그리고 장면 측정을 건너뛰는 재사용 경로와 선택 기반 백분위가 결과를 바꾸지 않는지
// 확인합니다. 기존 합성 프레임은 세 채널이 같은 밀도 응답(ρ = 1)을 써서 이 오차를 만들 수 없었습니다.
// macOS `ChannelRangeCalibrationTests` 와 같은 합성 사례입니다. 실제 필름·스캐너 정확도는 아닙니다.
namespace manual_negative_tests {
namespace {

constexpr int columns = 24;
constexpr int patch = 10;
constexpr int rows = 8;
constexpr std::array<double, 3> base{0.84, 0.55, 0.34};

[[nodiscard]] std::array<double, 3> film_scale(const double ratio) {
    return {std::pow(ratio, -1.0 / 3.0), std::pow(ratio, 1.0 / 6.0), std::pow(ratio, 2.0 / 3.0)};
}

[[nodiscard]] double gray_level(const int column) {
    return 0.04 + 0.86 * static_cast<double>(column) / static_cast<double>(columns - 1);
}

// 회색 계단(0.04…0.90)을 필름 직선 응답으로 찍은 네거티브. B/R 밀도비가 `ratio` 이다.
[[nodiscard]] negaflow::imaging::WorkingImage gray_negative(const double ratio) {
    const auto scale = film_scale(ratio);
    negaflow::imaging::WorkingImage image;
    image.width = static_cast<std::uint32_t>(columns * patch);
    image.height = static_cast<std::uint32_t>(rows * patch);
    image.stride_pixels = image.width;
    image.pixels.resize(static_cast<std::size_t>(image.width) * image.height);
    for (int column = 0; column < columns; ++column) {
        const double level = gray_level(column);
        std::array<float, 3> transmission{};
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            const double density =
                (0.60 + 0.62 * std::log10(level / 0.18)) * scale[channel];
            transmission[channel] =
                static_cast<float>(base[channel] * std::pow(10.0, -std::max(density, 0.0)));
        }
        for (int y = 0; y < rows * patch; ++y) {
            for (int x = column * patch; x < (column + 1) * patch; ++x) {
                image.pixels[static_cast<std::size_t>(y) * image.width + static_cast<std::size_t>(x)] =
                    {transmission[0], transmission[1], transmission[2], 1.0F};
            }
        }
    }
    return image;
}

[[nodiscard]] negaflow::imaging::ManualNegativeDevelopParameters off_parameters() {
    negaflow::imaging::ManualNegativeDevelopParameters parameters{
        {static_cast<float>(base[0]), static_cast<float>(base[1]), static_cast<float>(base[2])},
        negaflow::imaging::NegativeFilmType::color,
    };
    return parameters;
}

// 중간톤 회색 패치들의 |ln(B/R)| 평균. 0 이면 중립이다.
[[nodiscard]] double neutral_cast(const negaflow::imaging::WorkingImage& image) {
    double total = 0.0;
    int count = 0;
    const int y = rows * patch / 2;
    for (int column = 4; column <= 16; ++column) {
        const auto& pixel = image.pixels[
            static_cast<std::size_t>(y) * image.width + static_cast<std::size_t>(column * patch + patch / 2)];
        total += std::abs(std::log(static_cast<double>(pixel.blue) / static_cast<double>(pixel.red)));
        ++count;
    }
    return total / count;
}

}  // namespace

void test_channel_range_and_measurement_reuse() {
    // 1) ρ ≠ 1 에서 고정 범위는 회색을 기울이고, 심은 비율을 그대로 되돌린 channel_range 는 지운다.
    for (const double ratio : {1.0, 1.23, 1.5, 1.86}) {
        const auto scale = film_scale(ratio);
        const double geometric = std::cbrt(scale[0] * scale[1] * scale[2]);
        const std::array<float, 3> truth{
            static_cast<float>(scale[0] / geometric), static_cast<float>(scale[1] / geometric),
            static_cast<float>(scale[2] / geometric)};

        auto plain = negaflow::imaging::develop_manual_negative(gray_negative(ratio), off_parameters());
        expect(plain.status == negaflow::imaging::ManualNegativeDevelopStatus::ok, "plain OFF develops");
        auto calibrated_parameters = off_parameters();
        calibrated_parameters.channel_range = truth;
        auto calibrated = negaflow::imaging::develop_manual_negative(gray_negative(ratio), calibrated_parameters);
        expect(calibrated.status == negaflow::imaging::ManualNegativeDevelopStatus::ok,
            "calibrated OFF develops");

        const double plain_cast = neutral_cast(plain.image);
        const double calibrated_cast = neutral_cast(calibrated.image);
        if (ratio == 1.0) {
            expect(plain_cast < 0.01, "rho=1 fixed range is already neutral");
        } else {
            expect(plain_cast > 0.5 * std::log(ratio),
                "uncalibrated OFF leans when the channel range ratio is not 1");
        }
        expect(calibrated_cast < 0.03, "channel_range removes the gray cast");
        expect(std::abs(calibrated.info.dmax_normalized[2] / calibrated.info.dmax_normalized[0] -
                        truth[2] / truth[0]) < 1.0e-5F,
            "channel_range multiplies the fixed nominal range per channel");
    }

    // 2) channel_range 가 없는 것과 세 채널 1 은 같은 그림이다.
    {
        auto identity_parameters = off_parameters();
        identity_parameters.channel_range = std::array<float, 3>{1.0F, 1.0F, 1.0F};
        const auto none = negaflow::imaging::develop_manual_negative(gray_negative(1.5), off_parameters());
        const auto ones = negaflow::imaging::develop_manual_negative(gray_negative(1.5), identity_parameters);
        expect(images_equal(none.image.pixels, ones.image.pixels),
            "missing channel_range equals the equal-range behaviour");
    }

    // 3) 장면 범위를 쓰는 경로(자동 밸런스 ON)에서는 channel_range 를 쓰지 않는다.
    {
        auto on = off_parameters();
        on.adaptive_density = true;
        on.legacy_scene_response = true;
        auto with_range = on;
        with_range.channel_range = std::array<float, 3>{1.4F, 1.0F, 0.7F};
        const auto a = negaflow::imaging::develop_manual_negative(gray_negative(1.5), on);
        const auto b = negaflow::imaging::develop_manual_negative(gray_negative(1.5), with_range);
        expect(a.status == negaflow::imaging::ManualNegativeDevelopStatus::ok, "ON develops");
        expect(images_equal(a.image.pixels, b.image.pixels),
            "channel_range is ignored when the scene range is measured");
    }

    // 4) 밖의 값은 거부한다(조용히 자르면 화면과 파일이 어긋난다).
    for (const std::array<float, 3> bad : {std::array<float, 3>{0.2F, 1.0F, 1.0F},
                                           std::array<float, 3>{1.0F, 3.0F, 1.0F},
                                           std::array<float, 3>{1.0F, std::nanf(""), 1.0F}}) {
        auto parameters = off_parameters();
        parameters.channel_range = bad;
        const auto rejected = negaflow::imaging::develop_manual_negative(gray_negative(1.5), parameters);
        expect(rejected.status != negaflow::imaging::ManualNegativeDevelopStatus::ok,
            "out-of-range channel_range is rejected");
    }

    // 5) 측정 재사용: 같은 입력이면 결과 화소가 같고, 넘긴 값을 실제로 쓴다(측정을 건너뛴다).
    {
        auto on = off_parameters();
        on.adaptive_density = true;
        on.legacy_scene_response = true;
        const auto fresh = negaflow::imaging::develop_manual_negative(gray_negative(1.5), on);
        expect(fresh.status == negaflow::imaging::ManualNegativeDevelopStatus::ok &&
                   fresh.info.scene_range.has_value() &&
                   fresh.info.muted_scene_vibrance.saturation_measured,
            "fresh ON reports the scene range and saturation it measured");

        auto reuse = on;
        reuse.reused_scene_range = fresh.info.scene_range;
        reuse.reused_mean_saturation = fresh.info.muted_scene_vibrance.mean_saturation;
        const auto reused = negaflow::imaging::develop_manual_negative(gray_negative(1.5), reuse);
        expect(reused.status == negaflow::imaging::ManualNegativeDevelopStatus::ok &&
                   images_equal(fresh.image.pixels, reused.image.pixels) &&
                   reused.info.dmax_normalized == fresh.info.dmax_normalized &&
                   reused.info.black_input == fresh.info.black_input,
            "reusing the measurements gives identical pixels");

        auto forged = on;
        forged.reused_scene_range = negaflow::imaging::SceneRangeMeasurement{
            {1.0F, 1.1F, 1.2F}, fresh.info.black_input};
        const auto forced = negaflow::imaging::develop_manual_negative(gray_negative(1.5), forged);
        expect(forced.info.dmax_normalized == std::array<float, 3>{1.0F, 1.1F, 1.2F},
            "a reused scene range replaces the measurement");
    }

    // 6) 선택 기반 백분위는 전체 정렬(NEGA_DEBUG)과 같은 값을 낸다. 장면 범위와 black_input 이 비트 단위로 같아야 한다.
    {
        auto on = off_parameters();
        on.adaptive_density = true;
        on.legacy_scene_response = true;
        const auto selected = negaflow::imaging::develop_manual_negative(gray_negative(1.37), on);
        (void)_putenv_s("NEGA_DEBUG", "1");
        const auto sorted = negaflow::imaging::develop_manual_negative(gray_negative(1.37), on);
        (void)_putenv_s("NEGA_DEBUG", "");
        expect(selected.info.scene_range.has_value() && sorted.info.scene_range.has_value() &&
                   selected.info.scene_range->dmax_normalized == sorted.info.scene_range->dmax_normalized &&
                   selected.info.scene_range->black_input == sorted.info.scene_range->black_input &&
                   images_equal(selected.image.pixels, sorted.image.pixels),
            "selection percentile equals the full-sort percentile");
    }
}

}  // namespace manual_negative_tests
