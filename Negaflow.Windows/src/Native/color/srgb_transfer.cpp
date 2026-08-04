#include "negaflow/color/srgb_transfer.h"

#include <cmath>

namespace negaflow::color {

float srgb_encoded_to_linear(const float encoded) noexcept {
    const float magnitude = std::abs(encoded);
    if (magnitude <= 0.04045F) {
        return encoded / 12.92F;
    }
    return std::copysign(
        std::pow((magnitude + 0.055F) / 1.055F, 2.4F),
        encoded);
}

}  // namespace negaflow::color
