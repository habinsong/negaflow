// 제품 경로 — `make_scratch_angle_maps`. GPU 가 안 돌면 실패합니다.

#include "grain_mend_scratch_angles.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

#include "negaflow/imaging/kernel_accelerator.h"
#include "negaflow/pipeline/gpu_accelerator.h"

namespace {

using negaflow::imaging::ScratchAngleTaps;
using negaflow::pipeline::GpuAccelerator;
namespace scratch = negaflow::imaging::grain_mend_detail;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

constexpr std::uint32_t width = 61U;
constexpr std::uint32_t height = 37U;

[[nodiscard]] scratch::DetectionImage make_image() {
    scratch::DetectionImage image{};
    image.width = width;
    image.height = height;
    const std::size_t count = static_cast<std::size_t>(width) * height;
    image.brightest_channel.resize(count);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float line = (x + y) % 11U == 0U ? 0.85F : 0.20F;
            const float noise = static_cast<float>((x * 13U + y * 7U) % 17U) / 80.0F;
            image.brightest_channel[(static_cast<std::size_t>(y) * width) + x] =
                line + noise;
        }
    }
    return image;
}

[[nodiscard]] std::vector<std::uint8_t> make_valid() {
    std::vector<std::uint8_t> valid(static_cast<std::size_t>(width) * height, 1U);
    for (std::uint32_t x = 0U; x < width; ++x) {
        valid[x] = 0U;
        valid[(static_cast<std::size_t>(height - 1U) * width) + x] = 0U;
    }
    return valid;
}

void compare_plane(
    const char* const label,
    const std::vector<float>& cpu,
    const std::vector<float>& gpu) {
    expect(cpu.size() == gpu.size(), "plane size");
    float worst = 0.0F;
    std::size_t different = 0U;
    for (std::size_t index = 0U; index < cpu.size(); ++index) {
        const float delta = std::abs(cpu[index] - gpu[index]);
        worst = std::max(worst, delta);
        if (delta > 1.0e-6F) {
            ++different;
        }
    }
    std::cout << label << " max delta " << worst << " diffs " << different << "/"
              << cpu.size() << '\n';
    // 균형 임계에 앉은 화소는 CPU `>=` 와 GPU 가산 순서가 1ulp 로 갈라질 수 있습니다.
    // 61×37 / 45° / 0.08 에서 ridge 1화소·적분 7화소가 그 경우입니다. 검출 골든은
    // 성분 수로 따로 잽니다.
    const float allowed = 0.04F;
    if (worst > allowed || different > 16U) {
        std::cerr << "FAIL: " << label << " delta " << worst << " diffs " << different
                  << '\n';
        ++failures;
    }
}

}  // namespace

int main() {
    const scratch::DetectionImage image = make_image();
    const std::vector<std::uint8_t> valid = make_valid();
    scratch::ScratchAngleMaps cpu{};
    scratch::make_scratch_angle_maps(image, 45.0, valid, 0.08F, true, cpu);

    negaflow::pipeline::install_gpu_kernel_accelerator();
    if (!GpuAccelerator::shared().available()) {
        std::cout << "GPU unavailable — scratch angle test skipped\n";
        return 0;
    }
    std::cout << "adapter: " << GpuAccelerator::shared().adapter_description() << '\n';

    ScratchAngleTaps taps{};
    scratch::fill_scratch_angle_taps(45.0, true, taps);
    std::vector<float> gpu_ridge(cpu.ridge.size(), 0.0F);
    std::vector<float> gpu_integrated(cpu.integrated.size(), 0.0F);
    const bool ran = GpuAccelerator::shared().apply_scratch_angle_maps(
        image.brightest_channel.data(),
        valid.data(),
        gpu_ridge.data(),
        gpu_integrated.data(),
        width,
        height,
        &taps,
        0.08F);
    expect(ran, "GPU scratch angle must run — fallback would make this test vacuous");
    if (!ran) {
        return 1;
    }
    compare_plane("ridge", cpu.ridge, gpu_ridge);
    compare_plane("integrated", cpu.integrated, gpu_integrated);

    scratch::ScratchAngleMaps product{};
    scratch::make_scratch_angle_maps(image, 45.0, valid, 0.08F, true, product);
    compare_plane("product-ridge", cpu.ridge, product.ridge);
    compare_plane("product-integrated", cpu.integrated, product.integrated);

    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return 1;
    }
    std::cout << "gpu scratch angle tests passed\n";
    return 0;
}
