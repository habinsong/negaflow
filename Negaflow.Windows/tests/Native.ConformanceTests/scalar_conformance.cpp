#include "negaflow/core/build_info.h"
#include "negaflow/core/negative_inversion.h"
#include "scalar_foundation_fixture.h"

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <limits>

int main() {
    constexpr float dmin = negaflow::fixtures::color_negative_dmin;
    constexpr float dmax = negaflow::fixtures::color_negative_dmax_normalized;
    const negaflow::core::NegativeInversionParameters parameters{
        {dmin, dmin, dmin},
        {dmax, dmax, dmax},
    };

    double maximum_absolute_error = 0.0;
    double maximum_relative_error = 0.0;
    std::size_t finite_output_count = 0U;
    std::size_t failure_count = 0U;

    for (const negaflow::fixtures::NegativeInversionCase& fixture_case :
         negaflow::fixtures::color_negative_cases) {
        const float transmission = dmin * std::pow(10.0F, -fixture_case.density);
        const negaflow::core::Rgba32F source{
            transmission,
            transmission,
            transmission,
            1.0F,
        };
        negaflow::core::Rgba32F output{};
        const negaflow::core::KernelStatus kernel_status =
            negaflow::core::apply_negative_inversion(
                {&source, 1U, 1U, 1U, 1U},
                {&output, 1U, 1U, 1U, 1U},
                parameters,
                negaflow::core::color_negative_print_response());
        if (kernel_status != negaflow::core::KernelStatus::ok ||
            !std::isfinite(output.red)) {
            ++failure_count;
            continue;
        }

        ++finite_output_count;
        const double actual = static_cast<double>(output.red);
        const double absolute_error = std::abs(actual - fixture_case.expected);
        const double relative_scale = std::max(std::abs(actual), std::abs(fixture_case.expected));
        const double relative_error =
            relative_scale == 0.0 ? 0.0 : absolute_error / relative_scale;
        maximum_absolute_error = std::max(maximum_absolute_error, absolute_error);
        maximum_relative_error = std::max(maximum_relative_error, relative_error);

        const double allowed_error =
            static_cast<double>(negaflow::fixtures::negative_inversion_absolute_tolerance) +
            (static_cast<double>(negaflow::fixtures::negative_inversion_relative_tolerance) *
             relative_scale);
        if (absolute_error > allowed_error) {
            ++failure_count;
        }
    }

    const negaflow::core::BuildInfo build_info = negaflow::core::query_build_info();
    const bool passed = failure_count == 0U;
    std::cout << "{\"schema_version\":1,\"status\":\""
              << (passed ? "ok" : "failed") << "\",\"fixture_id\":\""
              << negaflow::fixtures::scalar_foundation_fixture_id
              << "\",\"algorithm_version\":\""
              << negaflow::core::negative_inversion_algorithm_version
              << "\",\"architecture\":\""
              << negaflow::core::architecture_name(build_info.architecture)
              << "\",\"source_dirty\":" << (build_info.source_dirty ? "true" : "false")
              << ",\"case_count\":" << negaflow::fixtures::color_negative_cases.size()
              << ",\"finite_output_count\":" << finite_output_count
              << ",\"failure_count\":" << failure_count
              << ",\"max_absolute_error\":"
              << std::setprecision(std::numeric_limits<double>::max_digits10)
              << maximum_absolute_error << ",\"max_relative_error\":"
              << maximum_relative_error << "}\n";
    return passed ? 0 : 1;
}
