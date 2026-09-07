#include "negaflow/imaging/custom_color_target.h"
#include "negaflow/pipeline/gpu_accelerator.h"
#include "Fixtures/custom_color_target_samples.h"
#include <algorithm>
#include <cmath>
#include <iostream>
#include <numbers>
#include <vector>

int main() {
    using namespace negaflow;
    auto& gpu = pipeline::GpuAccelerator::shared();
    if (!gpu.available()) { std::cout << "GPU unavailable\n"; return 77; }
    std::vector<core::Rgba32F> source;
    for (const auto& sample : custom_target_samples) {
        const double angle = sample.lch[2] * std::numbers::pi / 180;
        const auto rgb = imaging::custom_target_lab_to_linear(
            {sample.lch[0], sample.lch[1] * std::cos(angle), sample.lch[1] * std::sin(angle)});
        const float alpha = source.size() % 3U == 0U ? 0.0F : (source.size() % 3U == 1U ? 0.25F : 1.0F);
        source.push_back({static_cast<float>(rgb[0]), static_cast<float>(rgb[1]), static_cast<float>(rgb[2]), alpha});
    }
    const auto width = static_cast<std::uint32_t>(source.size());
    int failures = 0;
    float worst = 0;
    for (std::uint32_t target = 7; target <= 24; ++target) {
        std::vector<core::Rgba32F> expected(source.size()), actual = source;
        if (imaging::apply_custom_color_target({source.data(), source.size(), width, 1, width},
            {expected.data(), expected.size(), width, 1, width}, target) != core::KernelStatus::ok) { return 1; }
        if (!gpu.begin_resident()) { return 1; }
        const bool handled = gpu.apply_custom_color_target(reinterpret_cast<float*>(actual.data()), width, 1, width, target);
        const bool resident = gpu.has_resident_image(reinterpret_cast<float*>(actual.data()), width, 1);
        gpu.end_resident();
        if (!handled || !resident) { std::cerr << "custom GPU route failed: " << target << '\n'; ++failures; continue; }
        for (std::size_t i = 0; i < actual.size(); ++i) {
            const float error = std::max({std::abs(actual[i].red - expected[i].red),
                std::abs(actual[i].green - expected[i].green), std::abs(actual[i].blue - expected[i].blue)});
            worst = std::max(worst, error);
            // macOS CustomColorTargetTests의 CPU/Metal 허용 오차와 같습니다.
            if (!std::isfinite(error) || error > 0.0003F || actual[i].alpha != expected[i].alpha) { ++failures; }
        }
    }
    std::cout << "gpu_custom_color_target: max_rgb_error=" << worst << " failures=" << failures << '\n';
    return failures == 0 ? 0 : 1;
}
