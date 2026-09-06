#pragma once
#include "export/stages/decode.h"
#include "negaflow/imageio/decoded_image.h"

namespace negaflow::pipeline::develop_export_detail {
using EncodedSourceImage = std::shared_ptr<const negaflow::imageio::DecodedImage>;

[[nodiscard]] std::shared_ptr<const negaflow::imaging::WorkingImage> decoded_source_try_take(
    const std::filesystem::path&, const negaflow::imageio::ImageFileObservation&,
    std::uint32_t box_width, std::uint32_t box_height, negaflow::color::InputGammaInterpretation) noexcept;
void decoded_source_put(const std::filesystem::path&, const negaflow::imageio::ImageFileObservation&,
    std::uint32_t box_width, std::uint32_t box_height,
    std::shared_ptr<const negaflow::imaging::WorkingImage>, negaflow::color::InputGammaInterpretation) noexcept;
[[nodiscard]] EncodedSourceImage encoded_source_try_take(const std::filesystem::path&,
    const negaflow::imageio::ImageFileObservation&, std::uint32_t box_width, std::uint32_t box_height) noexcept;
void encoded_source_put(const std::filesystem::path&, const negaflow::imageio::ImageFileObservation&,
    std::uint32_t box_width, std::uint32_t box_height, EncodedSourceImage) noexcept;
}
