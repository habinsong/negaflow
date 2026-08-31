#include "manual_negative_test_support.h"

#include "negaflow/core/negative_inversion.h"
#include "negaflow/imaging/auto_negative_base_resolver.h"
#include "negaflow/imaging/film_stock_base_resolver.h"
#include "negaflow/imaging/mipmap_downsampler.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
#include <utility>
#include <vector>

namespace manual_negative_tests {

void test_manual_negative_development() {
    std::vector<negaflow::core::Rgba32F> affine_source(8U * 7U);
    for (std::uint32_t y = 0U; y < 7U; ++y) {
        const float value = y < 2U ? 0.125F : (y < 4U ? 0.375F : 0.625F);
        for (std::uint32_t x = 0U; x < 8U; ++x) {
            affine_source[static_cast<std::size_t>(y) * 8U + x] =
                {value, value, value, 1.0F};
        }
    }
    const auto affine_proxy = negaflow::imaging::downsample_for_statistics(
        {affine_source.data(), affine_source.size(), 8U, 7U, 8U}, 4U, 3U);
    expect(
        affine_proxy.width == 4U && affine_proxy.height == 3U &&
            affine_proxy.pixels.size() == 12U &&
            affine_proxy.pixels[0].red == 0.25F &&
            affine_proxy.pixels[4].red == 0.50F &&
            affine_proxy.pixels[8].red == 0.625F,
        "statistics proxy keeps the macOS uniform affine scale and y-down top crop");

    negaflow::imaging::WorkingImage source = make_working_image();
    std::array<negaflow::core::Rgba32F, 2> expected{};
    const negaflow::core::NegativeInversionParameters reference_parameters{
        {0.72F, 0.32F, 0.15F},
        {1.55F, 1.55F, 1.55F},
    };
    const auto reference_status = negaflow::core::apply_negative_inversion(
        {source.pixels.data(), source.pixels.size(), 2U, 1U, 2U},
        {expected.data(), expected.size(), 2U, 1U, 2U},
        reference_parameters,
        negaflow::core::color_negative_print_response());
    expect(reference_status == negaflow::core::KernelStatus::ok, "reference inversion succeeds");

    const negaflow::imaging::ManualNegativeDevelopParameters parameters{
        {0.72F, 0.32F, 0.15F},
        negaflow::imaging::NegativeFilmType::color,
    };
    const auto developed = negaflow::imaging::develop_manual_negative(
        std::move(source),
        parameters);
    expect(
        developed.status == negaflow::imaging::ManualNegativeDevelopStatus::ok,
        "manual color negative development succeeds");
    expect(
        developed.info.dmax_normalized == std::array<float, 3>{1.55F, 1.55F, 1.55F},
        "color generic density range is fixed");
    expect(developed.image.pixels.size() == expected.size(), "developed pixel count");
    if (developed.image.pixels.size() == expected.size()) {
        expect(pixels_equal(developed.image.pixels[0], expected[0]), "first in-place pixel exact");
        expect(pixels_equal(developed.image.pixels[1], expected[1]), "second in-place pixel exact");
        expect(developed.image.pixels[1].alpha == 0.5F, "alpha is preserved in place");
    }

    const negaflow::imaging::ManualNegativeDevelopParameters clamped_parameters{
        {0.0F, 2.0F, 0.5F},
        negaflow::imaging::NegativeFilmType::black_and_white,
    };
    const auto clamped = negaflow::imaging::develop_manual_negative(
        make_working_image(),
        clamped_parameters);
    expect(
        clamped.status == negaflow::imaging::ManualNegativeDevelopStatus::ok &&
            clamped.info.applied_dmin == std::array<float, 3>{0.001F, 1.0F, 0.5F},
        "manual Dmin follows baseline clamp");
    expect(
        clamped.info.dmax_normalized == std::array<float, 3>{2.17F, 2.17F, 2.17F},
        "B&W generic density range is fixed");

    const negaflow::imaging::ManualNegativeDevelopParameters scene_parameters{
        {0.80F, 0.60F, 0.40F},
        negaflow::imaging::NegativeFilmType::color,
    };
    const auto scene = negaflow::imaging::develop_manual_negative(
        make_scene_working_image(),
        scene_parameters);
    expect(
        scene.status == negaflow::imaging::ManualNegativeDevelopStatus::ok,
        "scene-ranged manual development succeeds");
    expect(
        std::abs(scene.info.dmax_normalized[0] - 1.10F) < 1.0e-4F &&
            std::abs(scene.info.dmax_normalized[1] - 0.99F) < 1.0e-4F &&
            std::abs(scene.info.dmax_normalized[2] - 0.88F) < 1.0e-4F,
        "scene-ranged manual development uses the robust low percentile per channel");
    expect(
        scene.info.dmax_normalized[0] != scene.info.dmax_normalized[2],
        "color scene range retains per-channel density differences");
    expect(
        scene.info.muted_scene_vibrance.applied &&
            scene.info.muted_scene_vibrance.amount == 0.5,
        "non-preset color scene runs muted-scene vibrance after inversion");

    // 바랜 필름은 밀도 범위가 **진짜로** 좁습니다. 앞 판은 좁은 범위를 "측정 실패" 로 보고
    // `normal_range`(1.55, 고대비 가정) 로 돌아갔고, 그 가정이 사진을 검게 눌렀습니다 -
    // 1996 년 카메라 스캔에서 현상 결과가 정상의 13 분의 1 밝기로 나왔습니다. 좁은 것과
    // 실패한 것은 다릅니다. 잰 값을 그대로 씁니다.
    const auto faded = negaflow::imaging::develop_manual_negative(
        make_faded_scene_working_image(),
        {{0.80F, 0.60F, 0.40F}, negaflow::imaging::NegativeFilmType::color});
    expect(
        faded.status == negaflow::imaging::ManualNegativeDevelopStatus::ok,
        "faded manual development succeeds");
    expect(
        faded.info.dmax_normalized[0] < 0.42F,
        "a genuinely flat negative keeps its measured range instead of snapping to normal");
    expect(
        faded.info.dmax_normalized[0] != faded.info.dmax_normalized[2],
        "a faded negative keeps its per-channel range difference");
    // 파랑이 가장 먼저 바래므로 파랑의 범위가 가장 좁아야 합니다. 앞 판의 `max(0.4)` 바닥은
    // 그 차이를 통째로 삼켰습니다 - 카메라 스캔 다섯 장 중 넷이 파랑에서 정확히 0.40 이었고,
    // 그만큼 파랑이 과하게 늘어나 사진이 노랗게 나왔습니다.
    expect(
        faded.info.dmax_normalized[2] < faded.info.dmax_normalized[1] &&
            faded.info.dmax_normalized[2] > 0.0F,
        "the faded blue layer keeps its own narrow range");

    const auto affine_proxy_scene = negaflow::imaging::develop_manual_negative(
        make_affine_proxy_scene_image(),
        {{0.80F, 0.80F, 0.80F}, negaflow::imaging::NegativeFilmType::color});
    const float affine_proxy_expected = std::log10(0.80F / 0.12F);
    expect(
        affine_proxy_scene.status == negaflow::imaging::ManualNegativeDevelopStatus::ok &&
            std::abs(affine_proxy_scene.info.dmax_normalized[0] - affine_proxy_expected) < 1.0e-5F &&
            std::abs(affine_proxy_scene.info.dmax_normalized[1] - affine_proxy_expected) < 1.0e-5F &&
            std::abs(affine_proxy_scene.info.dmax_normalized[2] - affine_proxy_expected) < 1.0e-5F,
        "scene-range proxy uses uniform pixel-centre bilinear affine sampling on both axes");

    negaflow::imaging::ManualNegativeDevelopParameters preset_parameters = scene_parameters;
    preset_parameters.use_preset_response = true;
    preset_parameters.preset_dmax_normalized = {2.04F, 2.23F, 2.23F};
    const auto preset_scene = negaflow::imaging::develop_manual_negative(
        make_scene_working_image(),
        preset_parameters);
    expect(
        preset_scene.status == negaflow::imaging::ManualNegativeDevelopStatus::ok &&
            preset_scene.info.dmax_normalized[0] < preset_scene.info.dmax_normalized[1] &&
            std::abs(preset_scene.info.dmax_normalized[1] - preset_scene.info.dmax_normalized[2]) < 1.0e-5F,
        "preset keeps the measured density scale and stock channel ratio");
    expect(
        !preset_scene.info.muted_scene_vibrance.applied,
        "preset color scene bypasses muted-scene vibrance");

    const auto scene_bw = negaflow::imaging::develop_manual_negative(
        make_scene_working_image(),
        {scene_parameters.dmin, negaflow::imaging::NegativeFilmType::black_and_white});
    expect(
        scene_bw.status == negaflow::imaging::ManualNegativeDevelopStatus::ok &&
            scene_bw.info.dmax_normalized[0] == scene_bw.info.dmax_normalized[1] &&
            scene_bw.info.dmax_normalized[1] == scene_bw.info.dmax_normalized[2],
        "B&W scene range remains neutral");
    expect(
        !scene_bw.info.muted_scene_vibrance.applied,
        "B&W scene-ranged development bypasses muted-scene vibrance");
}

}  // namespace manual_negative_tests
