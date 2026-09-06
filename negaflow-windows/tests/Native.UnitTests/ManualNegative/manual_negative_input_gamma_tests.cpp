#include "manual_negative_test_support.h"
#include <cmath>
#include <limits>

namespace manual_negative_tests {
void test_input_gamma_density_reference() {
    float previous = -1;
    for (const double gamma : {0.22, 0.32, 0.33, 0.34, 0.5, 1.0, 1.8, 2.2, 3.0, 4.0}) {
        const auto value = static_cast<float>(std::pow(0.35, gamma));
        const auto base = static_cast<float>(std::pow(0.85, gamma));
        auto image = make_uniform_working_image({value, value, value, 1.0F}, 64U, 64U);
        negaflow::imaging::ManualNegativeDevelopParameters parameters{{base, base, base}};
        parameters.input_gamma_reference_range = {1.55F, 1.55F, 1.55F};
        const auto result = negaflow::imaging::develop_manual_negative(std::move(image), parameters);
        expect(result.status == negaflow::imaging::ManualNegativeDevelopStatus::ok, "gamma reference renders");
        if (result.image.pixels.empty()) { continue; }
        expect(result.image.pixels[0].red > previous, "manual gamma is not cancelled by automatic density normalization");
        expect(result.info.dmax_normalized == *parameters.input_gamma_reference_range, "reference density stays fixed");
        previous = result.image.pixels[0].red;
    }
    for (const float invalid : {0.0F, -1.0F, std::numeric_limits<float>::quiet_NaN()}) {
        auto image = make_uniform_working_image({0.2F,0.2F,0.2F,1.0F});
        negaflow::imaging::ManualNegativeDevelopParameters parameters{{0.8F,0.8F,0.8F}};
        parameters.input_gamma_reference_range = {invalid,1.55F,1.55F};
        const auto result = negaflow::imaging::develop_manual_negative(std::move(image),parameters);
        expect(result.status != negaflow::imaging::ManualNegativeDevelopStatus::ok && result.image.pixels.empty(),
            "invalid gamma reference does not publish pixels");
    }
}
}
