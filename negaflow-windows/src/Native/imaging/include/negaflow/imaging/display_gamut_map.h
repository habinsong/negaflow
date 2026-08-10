#pragma once

#include "negaflow/core/pixel.h"

#include <algorithm>
#include <cstdint>

namespace negaflow::imaging {

// The working image deliberately keeps values below 0 and above 1 so a flat master does
// not lose highlight latitude or saturated colour. Only the display boundary has to fold
// them into [0,1], and folding each channel on its own is what produces coloured
// highlight bands: the channel that clips first drags the hue with it.
//
// Instead the luma is held and the chroma is scaled by the largest factor that keeps
// every channel inside the range, so hue survives and only saturation gives way. A pixel
// already inside [0,1] comes back unchanged, which is why an ordinary photo is untouched.
//
// This is the display path only. Published 16-bit artefacts keep the plain clamp, which
// is what the macOS export boundary does too.
[[nodiscard]] inline negaflow::core::Rgba32F tone_safe_unit_rgb(
    const negaflow::core::Rgba32F pixel) noexcept {
    const float luma = std::clamp(
        (pixel.red * 0.2126F) + (pixel.green * 0.7152F) + (pixel.blue * 0.0722F),
        0.0F,
        1.0F);
    const float chroma_red = pixel.red - luma;
    const float chroma_green = pixel.green - luma;
    const float chroma_blue = pixel.blue - luma;

    const auto channel_limit = [luma](const float chroma) noexcept {
        if (chroma > 1.0e-5F) {
            return (1.0F - luma) / chroma;
        }
        if (chroma < -1.0e-5F) {
            return -luma / chroma;
        }
        return 1.0F;
    };

    const float scale = std::clamp(
        std::min(
            1.0F,
            std::min(
                channel_limit(chroma_red),
                std::min(channel_limit(chroma_green), channel_limit(chroma_blue)))),
        0.0F,
        1.0F);

    return {
        std::clamp(luma + (scale * chroma_red), 0.0F, 1.0F),
        std::clamp(luma + (scale * chroma_green), 0.0F, 1.0F),
        std::clamp(luma + (scale * chroma_blue), 0.0F, 1.0F),
        pixel.alpha,
    };
}

// Banding appears when a smooth gradient quantises to 8 bits and neighbouring pixels land
// on the same step. Adding under one step of noise in the space the quantisation happens
// in scatters the boundary pixels between adjacent steps, so the band reads as stipple
// and the average tone is unchanged.
//
// macOS draws this from CIRandomGenerator, which has no shared seed. Hashing the pixel
// coordinate instead makes the Windows preview reproducible; the distribution is the
// same, so only the particular noise differs.
[[nodiscard]] inline float display_dither_offset(
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t channel) noexcept {
    std::uint32_t hash = (x * 0x9E3779B1U) ^ (y * 0x85EBCA77U) ^ (channel * 0xC2B2AE3DU);
    hash ^= hash >> 15U;
    hash *= 0x2545F491U;
    hash ^= hash >> 13U;
    const float unit = static_cast<float>(hash >> 8U) / 16777215.0F;
    return (unit - 0.5F) / 255.0F;
}

}  // namespace negaflow::imaging
