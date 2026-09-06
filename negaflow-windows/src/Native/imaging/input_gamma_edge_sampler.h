#pragma once
#include "negaflow/color/input_gamma_estimator.h"
#include "negaflow/imageio/wic_tiff_decoder.h"
#include <vector>

namespace negaflow::imaging {
class InputGammaEdgeSampler final {
public:
    bool begin(const negaflow::imageio::WicTiffFrameView& frame) noexcept {
        if (frame.width < 32U || frame.height < 32U || frame.width > frame.stride_bytes / 6U) { return false; }
        try {
            width_ = frame.width;
            height_ = frame.height;
            edges_.resize(64U * 96U * 2U);
            for (std::uint32_t y = 0; y < 64U; ++y) {
                for (std::uint32_t x = 0; x < 96U; ++x) {
                    const auto tile = y / 16U * 4U + x / 24U;
                    edges_[(y * 96U + x) * 2U].tile = tile;
                    edges_[(y * 96U + x) * 2U + 1U].tile = tile;
                }
            }
            return true;
        } catch (...) { return false; }
    }

    bool write(const negaflow::imageio::WicTiffRowChunk& chunk) noexcept {
        const auto stride = chunk.stride_bytes / 2U;
        if (stride == 0U || chunk.stride_bytes % 2U != 0U || width_ > stride / 3U ||
            chunk.first_row > height_ || chunk.row_count > height_ - chunk.first_row ||
            chunk.row_count > chunk.samples.size() / stride) { return false; }
        for (std::uint32_t row = 0; row < 64U; ++row) {
            const auto y = 8U + static_cast<std::uint32_t>(static_cast<std::uint64_t>(row) * (height_ - 17U) / 63U);
            for (std::uint32_t index = 0; index < 9U; ++index) {
                const auto source_y = y + index - 4U;
                if (source_y < chunk.first_row || source_y - chunk.first_row >= chunk.row_count) { continue; }
                for (std::uint32_t column = 0; column < 96U; ++column) {
                    const auto x = 8U + static_cast<std::uint32_t>(static_cast<std::uint64_t>(column) * (width_ - 17U) / 95U);
                    const auto offset = static_cast<std::size_t>(source_y - chunk.first_row) * stride + x * 3U;
                    auto& vertical = edges_[(row * 96U + column) * 2U + 1U].samples[index];
                    for (std::size_t c = 0; c < 3U; ++c) { vertical[c] = chunk.samples[offset + c] / 65535.0; }
                    if (index == 4U) {
                        auto& horizontal = edges_[(row * 96U + column) * 2U].samples;
                        for (std::size_t i = 0; i < 9U; ++i) {
                            const auto at = offset + i * 3U - 12U;
                            for (std::size_t c = 0; c < 3U; ++c) { horizontal[i][c] = chunk.samples[at + c] / 65535.0; }
                        }
                    }
                }
            }
        }
        return true;
    }

    std::optional<negaflow::color::InputGammaEstimate> estimate() const noexcept {
        return negaflow::color::estimate_input_gamma(edges_);
    }
private:
    std::uint32_t width_{0}, height_{0};
    std::vector<negaflow::color::InputGammaEdge> edges_{};
};
}  // namespace negaflow::imaging
