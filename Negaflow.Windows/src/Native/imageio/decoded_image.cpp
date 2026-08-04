#include "negaflow/imageio/decoded_image.h"

namespace negaflow::imageio {

std::uint8_t channel_count(const DecodedPixelLayout layout) noexcept {
    return layout == DecodedPixelLayout::rgb16 ? 3U : 4U;
}

const char* decoded_pixel_layout_name(const DecodedPixelLayout layout) noexcept {
    return layout == DecodedPixelLayout::rgb16 ? "rgb16" : "rgba16";
}

const char* alpha_mode_name(const AlphaMode mode) noexcept {
    switch (mode) {
        case AlphaMode::opaque:
            return "opaque";
        case AlphaMode::associated:
            return "associated";
        case AlphaMode::unassociated:
            return "unassociated";
    }
    return "unknown";
}

}  // namespace negaflow::imageio
