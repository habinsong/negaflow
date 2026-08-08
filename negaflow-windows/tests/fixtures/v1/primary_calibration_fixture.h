#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/primary_calibration.h"

#include <array>
#include <string_view>

namespace negaflow::fixtures {

inline constexpr std::string_view primary_calibration_fixture_id =
    "primary-calibration-scalar-v1";
inline constexpr float primary_calibration_absolute_tolerance = 2.0e-5F;
inline constexpr float primary_calibration_relative_tolerance = 2.0e-5F;

// Repository-owned synthetic fixture calculated independently from the macOS
// calibrationPrimaries Float32 formula. This is not a Core Image render golden.
inline constexpr negaflow::imaging::PrimaryCalibrationParameters
    primary_calibration_parameters{
        0.65F,
        0.5F,
        -0.45F,
        -0.35F,
        0.25F,
        0.75F,
    };

inline constexpr std::array<negaflow::core::Rgba32F, 12>
    primary_calibration_input{{
        {-0.2F, 0.3F, 1.2F, 0.25F},
        {0.62F, 0.30F, 0.30F, 1.0F},
        {0.72F, 0.50F, 0.12F, 0.75F},
        {0.20F, 0.65F, 0.30F, 0.5F},
        {0.10F, 0.68F, 0.72F, 0.2F},
        {0.18F, 0.22F, 0.82F, 0.9F},
        {0.62F, 0.18F, 0.70F, 1.0F},
        {0.5F, 0.5F, 0.5F, 0.4F},
        {0.51F, 0.50F, 0.49F, 0.6F},
        {0.95F, 0.90F, 0.85F, 0.8F},
        {1.2F, -0.1F, 0.2F, 1.0F},
        {0.35F, 0.30F, 0.25F, 0.7F},
    }};

inline constexpr std::array<negaflow::core::Rgba32F, 12>
    primary_calibration_expected{{
        {0.0F, 0.180000186F, 1.0F, 0.25F},
        {0.699999988F, 0.369760156F, 0.220000029F, 1.0F},
        {0.840000033F, 0.794080138F, 0.0F, 0.75F},
        {0.278750002F, 0.571249962F, 0.280570000F, 0.5F},
        {0.003624797F, 0.775423408F, 0.816375256F, 0.2F},
        {0.057500124F, 0.0F, 1.0F, 0.9F},
        {0.878125072F, 0.001874924F, 0.864105523F, 1.0F},
        {0.5F, 0.5F, 0.5F, 0.4F},
        {0.51F, 0.50F, 0.49F, 0.6F},
        {0.974999964F, 0.946799934F, 0.824999988F, 0.8F},
        {1.0F, 0.112000465F, 0.0F, 1.0F},
        {0.375F, 0.346799970F, 0.225000024F, 0.7F},
    }};

}  // namespace negaflow::fixtures
