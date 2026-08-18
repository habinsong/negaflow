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

void test_invalid_manual_inputs_fail_closed() {
    // main 이 앞에서 세워 두던 값입니다. 시험을 나누면서 같은 값을 여기서 다시 세웁니다.
    const negaflow::imaging::ManualNegativeDevelopParameters parameters{
        {0.72F, 0.32F, 0.15F},
        negaflow::imaging::NegativeFilmType::color,
    };

    auto non_finite_parameters = parameters;
    non_finite_parameters.dmin[1] = std::numeric_limits<float>::quiet_NaN();
    const auto non_finite = negaflow::imaging::develop_manual_negative(
        make_working_image(),
        non_finite_parameters);
    expect(
        non_finite.status == negaflow::imaging::ManualNegativeDevelopStatus::invalid_parameter &&
            non_finite.image.pixels.empty(),
        "non-finite manual parameter publishes no pixels");

    auto malformed = make_working_image();
    malformed.stride_pixels = 1U;
    const auto failed = negaflow::imaging::develop_manual_negative(
        std::move(malformed),
        parameters);
    expect(
        failed.status == negaflow::imaging::ManualNegativeDevelopStatus::kernel_failed &&
            failed.info.kernel_status == negaflow::core::KernelStatus::invalid_stride &&
            failed.image.pixels.empty(),
        "invalid working layout publishes no pixels");
}

}  // namespace manual_negative_tests
