#include "negaflow/imageio/decoded_image.h"

namespace negaflow::imageio {

std::uint8_t channel_count(const DecodedPixelLayout layout) noexcept {
    switch (layout) {
        case DecodedPixelLayout::rgb16: return 3U;
        case DecodedPixelLayout::rgba16: return 4U;
        case DecodedPixelLayout::gray16: return 1U;
    }
    return 0U;
}

const char* decoded_pixel_layout_name(const DecodedPixelLayout layout) noexcept {
    switch (layout) {
        case DecodedPixelLayout::rgb16: return "rgb16";
        case DecodedPixelLayout::rgba16: return "rgba16";
        case DecodedPixelLayout::gray16: return "gray16";
    }
    return "unknown";
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
