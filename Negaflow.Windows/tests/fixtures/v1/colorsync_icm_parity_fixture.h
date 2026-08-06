#pragma once

// Generated from Negaflow.Windows/baseline/colorsync-icm-parity-v1.json by
// Negaflow.Windows/scripts/generate_colorsync_parity_fixture.py.
// Do not edit by hand.
//
// `source` holds the 16-bit integers both colour management systems receive,
// recovered as round(in * 65535) exactly as the synthesis rule requires.
// `macos_linear` holds the ColorSync reference output in linear-sRGB float.

#include <array>
#include <cstddef>
#include <cstdint>
#include <string_view>

namespace negaflow::fixtures {

inline constexpr std::string_view colorsync_icm_parity_fixture_id =
    "colorsync-icm-parity-v1";
inline constexpr std::string_view colorsync_icm_parity_profile_sha256 =
    "8c2dce29801bda9b1f532b3236f61f91171267ad8bbc997d46fb662cf9125d02";
inline constexpr std::size_t colorsync_icm_parity_profile_bytes =
    556U;
inline constexpr std::string_view colorsync_icm_parity_operating_system =
    "macOS 26.5.0";
inline constexpr std::string_view colorsync_icm_parity_source_commit =
    "e4a38a74fd4f131f26bff1c9dfcea34bbc2e711f";

struct ColorSyncParityPatch final {
    std::string_view name;
    std::array<std::uint16_t, 3> source;
    std::array<float, 3> macos_linear;
};

inline constexpr std::array<ColorSyncParityPatch, 34>
    colorsync_icm_parity_patches{{
        {
            "near_black_000",
            {0U, 0U, 0U},
            {0.0F, 0.0F, 0.0F},
        },
        {
            "near_black_005",
            {328U, 328U, 328U},
            {0.000312809949F, 0.000312809949F, 0.000312809949F},
        },
        {
            "near_black_010",
            {655U, 655U, 655U},
            {0.000624666223F, 0.000624666223F, 0.000624666223F},
        },
        {
            "near_black_020",
            {1311U, 1311U, 1311U},
            {0.00125028612F, 0.00125028612F, 0.00125028612F},
        },
        {
            "near_black_050",
            {3277U, 3277U, 3277U},
            {0.00312523847F, 0.00312523847F, 0.00312523847F},
        },
        {
            "neutral_ramp_125",
            {8192U, 8192U, 8192U},
            {0.0103090033F, 0.0103090033F, 0.0103090033F},
        },
        {
            "neutral_ramp_250",
            {16384U, 16384U, 16384U},
            {0.047367733F, 0.047367733F, 0.047367733F},
        },
        {
            "neutral_ramp_375",
            {24576U, 24576U, 24576U},
            {0.115580171F, 0.115580171F, 0.115580171F},
        },
        {
            "neutral_ramp_500",
            {32768U, 32768U, 32768U},
            {0.217644989F, 0.217644989F, 0.217644989F},
        },
        {
            "neutral_ramp_625",
            {40959U, 40959U, 40959U},
            {0.355571777F, 0.355571777F, 0.355571777F},
        },
        {
            "neutral_ramp_750",
            {49151U, 49151U, 49151U},
            {0.531043231F, 0.531043231F, 0.531043231F},
        },
        {
            "neutral_ramp_875",
            {57343U, 57343U, 57343U},
            {0.745445013F, 0.745445013F, 0.745445013F},
        },
        {
            "neutral_ramp_1000",
            {65535U, 65535U, 65535U},
            {1.0F, 1.0F, 1.0F},
        },
        {
            "red_full",
            {65535U, 0U, 0U},
            {1.0F, 0.0F, 0.0F},
        },
        {
            "green_full",
            {0U, 65535U, 0U},
            {0.0F, 1.0F, 0.0F},
        },
        {
            "blue_full",
            {0U, 0U, 65535U},
            {0.0F, 0.0F, 1.0F},
        },
        {
            "cyan_full",
            {0U, 65535U, 65535U},
            {0.0F, 1.0F, 1.0F},
        },
        {
            "magenta_full",
            {65535U, 0U, 65535U},
            {1.0F, 0.0F, 1.0F},
        },
        {
            "yellow_full",
            {65535U, 65535U, 0U},
            {1.0F, 1.0F, 0.0F},
        },
        {
            "red_half_saturation",
            {65535U, 32768U, 32768U},
            {1.0F, 0.217644989F, 0.217644989F},
        },
        {
            "green_half_saturation",
            {32768U, 65535U, 32768U},
            {0.217644989F, 1.0F, 0.217644989F},
        },
        {
            "blue_half_saturation",
            {32768U, 32768U, 65535U},
            {0.217644989F, 0.217644989F, 1.0F},
        },
        {
            "cyan_half_saturation",
            {32768U, 65535U, 65535U},
            {0.217644989F, 1.0F, 1.0F},
        },
        {
            "magenta_half_saturation",
            {65535U, 32768U, 65535U},
            {1.0F, 0.217644989F, 1.0F},
        },
        {
            "yellow_half_saturation",
            {65535U, 65535U, 32768U},
            {1.0F, 1.0F, 0.217644989F},
        },
        {
            "skin_light",
            {57540U, 49086U, 43450U},
            {0.751090825F, 0.529499471F, 0.404889256F},
        },
        {
            "skin_medium",
            {50396U, 37552U, 29556U},
            {0.561086833F, 0.293732136F, 0.173451915F},
        },
        {
            "skin_deep",
            {27983U, 18219U, 12845U},
            {0.153789312F, 0.0598291159F, 0.0277315285F},
        },
        {
            "highlight_950",
            {62258U, 62258U, 62258U},
            {0.893280864F, 0.893280864F, 0.893280864F},
        },
        {
            "highlight_980",
            {64224U, 64224U, 64224U},
            {0.956517398F, 0.956517398F, 0.956517398F},
        },
        {
            "shadow_red",
            {13107U, 1311U, 1311U},
            {0.0289911889F, 0.00125028612F, 0.00125028612F},
        },
        {
            "shadow_blue",
            {1311U, 1966U, 13107U},
            {0.00125028612F, 0.00187495234F, 0.0289911889F},
        },
        {
            "shadow_neutral_075",
            {4915U, 4915U, 4915U},
            {0.00468738098F, 0.00468738098F, 0.00468738098F},
        },
        {
            "shadow_chromatic_low",
            {655U, 524U, 786U},
            {0.000624666223F, 0.000499732967F, 0.00074959948F},
        },
    }};

}  // namespace negaflow::fixtures
