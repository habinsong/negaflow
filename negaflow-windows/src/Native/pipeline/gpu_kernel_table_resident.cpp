#include "gpu_kernel_table_resident.h"

#include "negaflow/pipeline/gpu_accelerator.h"

namespace negaflow::pipeline::gpu_table_detail {
namespace {

// 점 표본은 원본 화소를 그대로 옮기므로 근사가 아닙니다. 상주가 아니면 거짓이고, 그때는
// 호출부가 호스트에서 같은 점을 뽑습니다.
bool accelerate_resident_point_samples(
    const float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t sample_width,
    const std::uint32_t sample_height,
    float* const out) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.sample_resident_points(
        pixels, width, height, sample_width, sample_height, out);
}

}  // namespace

bool accelerate_custom_color_target(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const std::uint32_t target) noexcept {
    return GpuAccelerator::shared().apply_custom_color_target(
        pixels, width, height, stride_pixels, target);
}

void attach_resident_kernels(imaging::KernelAccelerator& table) noexcept {
    table.resident_point_samples = accelerate_resident_point_samples;
}

}  // namespace negaflow::pipeline::gpu_table_detail
