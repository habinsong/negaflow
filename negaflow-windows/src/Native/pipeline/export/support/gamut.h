#pragma once

#include "negaflow/color/output_color_space.h"

#include <cstddef>
#include <cstdint>

namespace negaflow::pipeline::develop_export_detail {

// 색역을 벗어나는 화소를 macOS 와 같은 색으로 덧칠한다. ICM 이 못 하면 칠하지 않는다.
void mark_out_of_gamut(
    std::uint8_t* pixels,
    std::uint32_t width,
    std::uint32_t height,
    negaflow::color::OutputColorSpace destination) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
