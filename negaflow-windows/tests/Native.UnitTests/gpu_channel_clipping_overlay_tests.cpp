// CPU/GPU 동치 — 프리뷰 전용 채널 클리핑 오버레이.
//
// GPU 가 안 돌면 실패합니다. 현상 결과는 바꾸지 않고 오버레이만 겨룹니다.

#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

#include "negaflow/imaging/channel_clipping_overlay.h"
#include "negaflow/imaging/kernel_accelerator.h"
#include "negaflow/pipeline/gpu_accelerator.h"

namespace {

using negaflow::core::Rgba32F;
using negaflow::imaging::WorkingImage;
using negaflow::pipeline::GpuAccelerator;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

constexpr std::uint32_t width = 16U;
constexpr std::uint32_t height = 8U;

[[nodiscard]] WorkingImage make_source() {
    WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            Rgba32F pixel{0.4F, 0.5F, 0.6F, 1.0F};
            if (x == 0U) {
                pixel.red = -0.02F;
            }
            if (x == 1U) {
                pixel.blue = 1.0F;
            }
            if (x == 2U) {
                pixel.green = 0.0F;
                pixel.red = 1.04F;
            }
            if (x == 3U) {
                pixel.alpha = 0.0F;
                pixel.red = -1.0F;
            }
            if (x == 4U) {
                pixel.red = 0.0F;
                pixel.green = 0.0F;
                pixel.blue = 0.0F;
            }
            image.pixels[(static_cast<std::size_t>(y) * width) + x] = pixel;
        }
    }
    return image;
}

[[nodiscard]] bool pixels_equal(const Rgba32F& left, const Rgba32F& right) noexcept {
    return left.red == right.red && left.green == right.green && left.blue == right.blue &&
        left.alpha == right.alpha;
}

} // namespace

int main() {
    const WorkingImage source = make_source();
    WorkingImage cpu{};
    expect(
        negaflow::imaging::apply_channel_clipping_overlay(source, cpu),
        "CPU overlay must succeed");

    const auto& interior = cpu.pixels[(static_cast<std::size_t>(1) * width) + 5U];
    expect(interior.alpha == 0.0F, "uncipped pixels must be transparent");

    const auto& shadow = cpu.pixels[0];
    expect(shadow.alpha == negaflow::imaging::channel_clipping_overlay_opacity, "shadow alpha");
    expect(
        shadow.red ==
            negaflow::imaging::channel_clipping_overlay_shadow[0] *
                negaflow::imaging::channel_clipping_overlay_opacity,
        "shadow red");

    const auto& highlight = cpu.pixels[1];
    expect(
        highlight.red ==
            negaflow::imaging::channel_clipping_overlay_highlight[0] *
                negaflow::imaging::channel_clipping_overlay_opacity,
        "highlight red");

    const auto& mixed = cpu.pixels[2];
    expect(
        mixed.red ==
            negaflow::imaging::channel_clipping_overlay_mixed[0] *
                negaflow::imaging::channel_clipping_overlay_opacity,
        "mixed red");

    const auto& transparent = cpu.pixels[3];
    expect(transparent.alpha == 0.0F, "zero-alpha source must stay empty");

    const auto& exact_black = cpu.pixels[4];
    expect(exact_black.alpha == negaflow::imaging::channel_clipping_overlay_opacity,
        "exact 0 must clip as shadow");

    negaflow::pipeline::install_gpu_kernel_accelerator();
    if (!GpuAccelerator::shared().available()) {
        std::cout << "GPU unavailable — clipping overlay test skipped\n";
        return failures == 0 ? 0 : 1;
    }
    std::cout << "adapter: " << GpuAccelerator::shared().adapter_description() << '\n';

    std::vector<Rgba32F> gpu(source.pixels.size());
    const bool ran = GpuAccelerator::shared().apply_channel_clipping_overlay(
        reinterpret_cast<const float*>(source.pixels.data()),
        reinterpret_cast<float*>(gpu.data()),
        width,
        height,
        width,
        width);
    expect(ran, "GPU clipping overlay must run");
    if (!ran) {
        return 1;
    }
    std::size_t mismatches = 0U;
    for (std::size_t index = 0U; index < gpu.size(); ++index) {
        if (!pixels_equal(cpu.pixels[index], gpu[index])) {
            ++mismatches;
        }
    }
    expect(mismatches == 0U, "GPU overlay must be bit-identical to CPU");

    WorkingImage product{};
    {
        const negaflow::imaging::ApproximateAcceleratorScope scope{};
        expect(
            negaflow::imaging::apply_channel_clipping_overlay(source, product),
            "product overlay must succeed");
    }
    mismatches = 0U;
    for (std::size_t index = 0U; index < product.pixels.size(); ++index) {
        if (!pixels_equal(cpu.pixels[index], product.pixels[index])) {
            ++mismatches;
        }
    }
    expect(mismatches == 0U, "product overlay must be bit-identical");

    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return 1;
    }
    std::cout << "gpu channel clipping overlay tests passed\n";
    return 0;
}
