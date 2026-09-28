#pragma once

#include "negaflow/imaging/kernel_accelerator.h"

#include <cstdint>

// `gpu_kernel_table.cpp` 의 표가 가리키는 항목 중 상주 화상과 이어지는 것들입니다.
namespace negaflow::pipeline::gpu_table_detail {

bool accelerate_custom_color_target(
    float* pixels,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t stride_pixels,
    std::uint32_t target) noexcept;

// 표에 상주 점 표본 항목을 겁니다.
void attach_resident_kernels(imaging::KernelAccelerator& table) noexcept;

}  // namespace negaflow::pipeline::gpu_table_detail
