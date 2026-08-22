// 제품 경로 형태학 — 풀 재사용 + RGB 톱햇 오케스트레이터.
//
// GPU 가 안 돌면 실패합니다. 폴백이면 CPU 와 같아서 시험이 비게 됩니다.

#include "grain_mend_morphology.h"

#include <cstdint>
#include <iostream>
#include <vector>

#include "negaflow/imaging/kernel_accelerator.h"
#include "negaflow/pipeline/gpu_accelerator.h"

namespace {

using negaflow::pipeline::GpuAccelerator;
namespace morphology = negaflow::imaging::grain_mend_detail;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

constexpr std::uint32_t width = 77U;
constexpr std::uint32_t height = 53U;

[[nodiscard]] std::vector<float> make_plane(const std::uint32_t seed_mix) {
    std::vector<float> plane(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::uint32_t seed = (x * 73856093U) ^ (y * 19349663U) ^ seed_mix;
            const std::uint32_t mixed = (seed ^ (seed >> 13U)) * 1274126177U;
            const float noise = static_cast<float>(mixed >> 8U) / 16777216.0F;
            const bool speck = ((x * 5U) + (y * 3U) + seed_mix) % 89U == 0U;
            float value = 0.25F + (static_cast<float>(y) / 52.0F) * 0.4F + (noise - 0.5F) * 0.08F;
            if (speck) {
                value = 0.98F;
            }
            plane[(static_cast<std::size_t>(y) * width) + x] = value;
        }
    }
    return plane;
}

[[nodiscard]] bool planes_equal(
    const std::vector<float>& left,
    const std::vector<float>& right) {
    if (left.size() != right.size()) {
        return false;
    }
    for (std::size_t index = 0U; index < left.size(); ++index) {
        if (left[index] != right[index]) {
            return false;
        }
    }
    return true;
}

} // namespace

int main() {
    const std::vector<float> red = make_plane(0U);
    const std::vector<float> green = make_plane(83492791U);
    const std::vector<float> blue = make_plane(2654435769U);

    const std::vector<float> cpu_open = morphology::opening(red, width, height, 4U);
    const std::vector<float> cpu_close = morphology::closing(red, width, height, 4U);
    const std::vector<float> cpu_hat = morphology::bipolar_top_hat(red, width, height, 4U);
    const std::vector<float> cpu_hat_g = morphology::bipolar_top_hat(green, width, height, 4U);
    const std::vector<float> cpu_hat_b = morphology::bipolar_top_hat(blue, width, height, 4U);

    negaflow::pipeline::install_gpu_kernel_accelerator();
    if (!GpuAccelerator::shared().available()) {
        std::cout << "GPU unavailable — morphology product test skipped\n";
        return 0;
    }
    std::cout << "adapter: " << GpuAccelerator::shared().adapter_description() << '\n';

    std::vector<float> gpu_open(red.size());
    const bool ran_open = GpuAccelerator::shared().apply_morphology_plane(
        red.data(),
        gpu_open.data(),
        width,
        height,
        4U,
        negaflow::imaging::MorphologyKind::opening);
    expect(ran_open, "product opening must run on GPU");
    expect(planes_equal(cpu_open, gpu_open), "product opening must be bit-identical");

    std::vector<float> gpu_close(red.size());
    const bool ran_close = GpuAccelerator::shared().apply_morphology_plane(
        red.data(),
        gpu_close.data(),
        width,
        height,
        4U,
        negaflow::imaging::MorphologyKind::closing);
    expect(ran_close, "product closing must run on GPU");
    expect(planes_equal(cpu_close, gpu_close), "product closing must be bit-identical");

    std::vector<float> gpu_hat(red.size());
    const bool ran_hat = GpuAccelerator::shared().apply_morphology_plane(
        red.data(),
        gpu_hat.data(),
        width,
        height,
        4U,
        negaflow::imaging::MorphologyKind::bipolar_top_hat);
    expect(ran_hat, "product top-hat must run on GPU");
    expect(planes_equal(cpu_hat, gpu_hat), "product top-hat must be bit-identical");

    std::vector<float> out_r(red.size());
    std::vector<float> out_g(green.size());
    std::vector<float> out_b(blue.size());
    const bool ran_rgb = GpuAccelerator::shared().apply_morphology_bipolar_top_hat_rgb(
        red.data(),
        green.data(),
        blue.data(),
        out_r.data(),
        out_g.data(),
        out_b.data(),
        width,
        height,
        4U);
    expect(ran_rgb, "RGB top-hat orchestrator must run on GPU");
    expect(planes_equal(cpu_hat, out_r), "RGB top-hat red must match CPU");
    expect(planes_equal(cpu_hat_g, out_g), "RGB top-hat green must match CPU");
    expect(planes_equal(cpu_hat_b, out_b), "RGB top-hat blue must match CPU");

    const std::vector<float> cpu_open_g = morphology::opening(green, width, height, 3U);
    const std::vector<float> cpu_open_b = morphology::opening(blue, width, height, 3U);
    std::vector<float> open_r(red.size());
    std::vector<float> open_g(green.size());
    std::vector<float> open_b(blue.size());
    const bool ran_open_rgb = GpuAccelerator::shared().apply_morphology_rgb(
        red.data(),
        green.data(),
        blue.data(),
        open_r.data(),
        open_g.data(),
        open_b.data(),
        width,
        height,
        3U,
        negaflow::imaging::MorphologyKind::opening);
    expect(ran_open_rgb, "RGB opening orchestrator must run on GPU");
    expect(
        planes_equal(morphology::opening(red, width, height, 3U), open_r),
        "RGB opening red must match CPU");
    expect(planes_equal(cpu_open_g, open_g), "RGB opening green must match CPU");
    expect(planes_equal(cpu_open_b, open_b), "RGB opening blue must match CPU");

    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return 1;
    }
    std::cout << "gpu morphology product tests passed\n";
    return 0;
}
