#include "manual_negative_test_support.h"

#include "negaflow/core/negative_inversion.h"
#include "negaflow/imaging/auto_negative_base_resolver.h"
#include "negaflow/imaging/film_stock_base_resolver.h"

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

void test_muted_scene_vibrance() {
    auto muted = make_uniform_working_image({0.52F, 0.50F, 0.48F, 0.75F});
    const auto muted_original = muted.pixels.front();
    const auto muted_result = negaflow::imaging::apply_muted_scene_vibrance(
        {muted.pixels.data(), muted.pixels.size(), muted.width, muted.height,
         muted.stride_pixels},
        false);
    const double expected_mean = (0.52 - 0.48) / 0.52;
    const double expected_amount = (0.24 - expected_mean) * 3.0;
    expect(
        muted_result.status == negaflow::core::KernelStatus::ok &&
            muted_result.info.applied &&
            std::abs(muted_result.info.mean_saturation - expected_mean) < 1.0e-6 &&
            std::abs(muted_result.info.amount - expected_amount) < 1.0e-6 &&
            (muted.pixels.front().red - muted.pixels.front().blue) >
                (muted_original.red - muted_original.blue) &&
            muted.pixels.front().alpha == muted_original.alpha,
        "muted color scene receives the measured low-chroma boost");

    auto saturated = make_uniform_working_image({0.80F, 0.30F, 0.10F, 1.0F});
    const auto saturated_original = saturated.pixels;
    const auto saturated_result = negaflow::imaging::apply_muted_scene_vibrance(
        {saturated.pixels.data(), saturated.pixels.size(), saturated.width,
         saturated.height, saturated.stride_pixels},
        false);
    expect(
        saturated_result.status == negaflow::core::KernelStatus::ok &&
            !saturated_result.info.applied && saturated_result.info.amount == 0.0 &&
            images_equal(saturated.pixels, saturated_original),
        "already saturated color scene is an exact identity");

    auto monochrome = make_uniform_working_image({0.52F, 0.50F, 0.48F, 1.0F});
    const auto monochrome_original = monochrome.pixels;
    const auto monochrome_result = negaflow::imaging::apply_muted_scene_vibrance(
        {monochrome.pixels.data(), monochrome.pixels.size(), monochrome.width,
         monochrome.height, monochrome.stride_pixels},
        true);
    expect(
        monochrome_result.status == negaflow::core::KernelStatus::ok &&
            !monochrome_result.info.applied &&
            images_equal(monochrome.pixels, monochrome_original),
        "B&W scene bypasses muted-scene vibrance");

    auto tiny = make_uniform_working_image({0.52F, 0.50F, 0.48F, 1.0F}, 4U, 4U);
    const auto tiny_original = tiny.pixels;
    const auto tiny_result = negaflow::imaging::apply_muted_scene_vibrance(
        {tiny.pixels.data(), tiny.pixels.size(), tiny.width, tiny.height,
         tiny.stride_pixels},
        false);
    expect(
        tiny_result.status == negaflow::core::KernelStatus::ok &&
            tiny_result.info.mean_saturation == 0.5 &&
            !tiny_result.info.applied && images_equal(tiny.pixels, tiny_original),
        "tiny scene follows the macOS measurement fallback identity");
}


}  // namespace manual_negative_tests
