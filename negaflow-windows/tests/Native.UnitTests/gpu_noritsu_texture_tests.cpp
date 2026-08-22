// CPU/GPU 동치 시험 — NORITSU 장치 질감(감마 도메인 luminance USM).
//
// **참조를 옮겨 적지 않습니다.** 진짜 CPU 함수 `apply_noritsu_texture` 를
// 스코프 밖에서 돌리고, GPU 는 `GpuAccelerator::apply_noritsu_texture` 가
// **true 를 돌려준 경우만** 겨룹니다. false 면 폴백이라 시험이 아무것도
// 증명하지 않습니다.
//
// 하드 게이트가 있습니다 (`lo < 0 || hi > 1`, `luma <= 1e-5`).
// 경계 화소의 차이는 누적이 아니라 질감의 크기이므로 최대 오차와
// 이탈 화소 비율을 같이 겁니다. 게이트에 걸린 화소는 원본과 **비트 단위**로
// 같아야 합니다.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_noritsu_texture.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/imaging/kernel_accelerator.h"
#include "negaflow/imaging/scanner_target_grade.h"
#include "negaflow/pipeline/gpu_accelerator.h"

namespace {

using negaflow::core::Rgba32F;
using negaflow::imaging::ScannerTargetTextureSetup;
using negaflow::pipeline::GpuAccelerator;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

// 5탭 누적은 float vs double 이라 내부 화소는 작다. 게이트 뒤집힘은 질감 진폭.
constexpr float accumulation_tolerance = 1.0e-4F;
constexpr float gate_flip_tolerance = 5.0e-3F;
constexpr double gate_flip_pixel_fraction = 0.02;
constexpr std::uint32_t width = 97U;
constexpr std::uint32_t height = 53U;

[[nodiscard]] bool is_gated(const Rgba32F& pixel) noexcept {
    const float low = std::min({pixel.red, pixel.green, pixel.blue});
    const float high = std::max({pixel.red, pixel.green, pixel.blue});
    const float luma =
        (0.2126F * pixel.red) + (0.7152F * pixel.green) + (0.0722F * pixel.blue);
    const ScannerTargetTextureSetup setup =
        negaflow::imaging::scanner_target_texture_setup();
    return low < 0.0F || high > 1.0F || luma <= setup.luma_gate;
}

[[nodiscard]] std::vector<Rgba32F> make_pattern() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::uint32_t seed = (x * 73856093U) ^ (y * 19349663U);
            const std::uint32_t mixed = (seed ^ (seed >> 13U)) * 1274126177U;
            const float noise = static_cast<float>(mixed >> 8U) / 16777216.0F;
            const bool edge = ((x / 7U) + (y / 5U)) % 3U == 0U;
            const float base = edge ? 0.92F : 0.08F;
            Rgba32F pixel{
                base + (noise * 0.05F),
                base * 0.8F,
                base * 0.55F + (noise * 0.02F),
                0.25F + (0.5F * noise)};
            // 왼쪽 띠: 확장값(음수) — 게이트 ①
            if (x < 4U) {
                pixel.red = -0.02F - (noise * 0.01F);
            }
            // 오른쪽 띠: 확장값(1 초과) — 게이트 ①
            if (x + 4U >= width) {
                pixel.blue = 1.04F + (noise * 0.02F);
            }
            // 맨 위 두 줄: 거의 검정 — 게이트 ②
            if (y < 2U && x >= 8U && x + 8U < width) {
                pixel.red = 1.0e-6F;
                pixel.green = 2.0e-6F;
                pixel.blue = 1.0e-6F;
            }
            pixels[(static_cast<std::size_t>(y) * width) + x] = pixel;
        }
    }
    return pixels;
}

[[nodiscard]] float channel_delta(const Rgba32F& left, const Rgba32F& right) noexcept {
    return std::max(
        {std::abs(left.red - right.red),
         std::abs(left.green - right.green),
         std::abs(left.blue - right.blue),
         std::abs(left.alpha - right.alpha)});
}

void compare_against_cpu(
    const char* const label,
    const std::vector<Rgba32F>& source,
    const std::vector<Rgba32F>& cpu,
    const std::vector<Rgba32F>& gpu) {
    float worst = 0.0F;
    std::size_t worst_index = 0U;
    std::size_t outliers = 0U;
    std::size_t gated = 0U;
    std::size_t gated_changed = 0U;
    std::size_t cpu_changed = 0U;
    for (std::size_t index = 0U; index < gpu.size(); ++index) {
        const float here = channel_delta(cpu[index], gpu[index]);
        if (here > worst) {
            worst = here;
            worst_index = index;
        }
        if (here > accumulation_tolerance) {
            ++outliers;
        }
        if (channel_delta(cpu[index], source[index]) > 0.0F) {
            ++cpu_changed;
        }
        if (is_gated(source[index])) {
            ++gated;
            if (channel_delta(gpu[index], source[index]) > 0.0F ||
                channel_delta(cpu[index], source[index]) > 0.0F) {
                ++gated_changed;
            }
        }
    }

    expect(cpu_changed > 0U, "CPU texture must change some interior pixels");
    expect(gated > 0U, "pattern must include gated pixels");
    expect(gated_changed == 0U, "gated pixels must stay at the source value");

    const float source_luma =
        (0.2126F * source[worst_index].red) + (0.7152F * source[worst_index].green) +
        (0.0722F * source[worst_index].blue);
    const double fraction =
        static_cast<double>(outliers) / static_cast<double>(gpu.size());
    bool failed = false;
    if (worst > gate_flip_tolerance) {
        std::cerr << "FAIL: " << label << " noritsu texture delta " << worst
                  << " exceeds " << gate_flip_tolerance << " at source luma " << source_luma
                  << '\n';
        failed = true;
    }
    if (fraction > gate_flip_pixel_fraction) {
        std::cerr << "FAIL: " << label << " noritsu texture has " << outliers << " / "
                  << gpu.size() << " pixels above 1e-4 (allowed fraction "
                  << gate_flip_pixel_fraction << ")\n";
        failed = true;
    }
    if (failed) {
        ++failures;
    } else {
        std::cout << label << " noritsu texture max delta " << worst << " (source luma "
                  << source_luma << ", >1e-4 pixels " << outliers << " / " << gpu.size()
                  << ", gated " << gated << ", cpu changed " << cpu_changed << ")\n";
    }
}

} // namespace

void warp_matches_cpu(
    const std::vector<Rgba32F>& source,
    const std::vector<Rgba32F>& cpu) {
    using negaflow::gpu::GpuDevice;
    using negaflow::gpu::GpuDevicePreference;
    using negaflow::gpu::GpuImageStatus;
    using negaflow::gpu::GpuKernelStatus;
    using negaflow::gpu::GpuNoritsuTexture;
    using negaflow::gpu::GpuWorkingImage;

    const GpuDevice warp = GpuDevice::create(GpuDevicePreference::warp_only);
    if (!warp.is_usable()) {
        std::cout << "WARP unavailable — skipped\n";
        return;
    }
    GpuNoritsuTexture kernel{};
    if (GpuNoritsuTexture::create(warp, kernel) != GpuKernelStatus::ok) {
        expect(false, "WARP noritsu kernel must be creatable");
        return;
    }
    GpuWorkingImage uploaded{};
    GpuWorkingImage scratch[GpuNoritsuTexture::scratch_count]{};
    GpuWorkingImage destination{};
    if (GpuWorkingImage::upload(warp, source.data(), width, height, width, uploaded) !=
            GpuImageStatus::ok ||
        GpuWorkingImage::create(warp, width, height, scratch[0]) != GpuImageStatus::ok ||
        GpuWorkingImage::create(warp, width, height, destination) != GpuImageStatus::ok) {
        expect(false, "WARP images must be creatable");
        return;
    }
    const ScannerTargetTextureSetup setup =
        negaflow::imaging::scanner_target_texture_setup();
    if (kernel.dispatch(warp, uploaded, scratch, destination, setup) != GpuKernelStatus::ok) {
        expect(false, "WARP noritsu dispatch must succeed");
        return;
    }
    std::vector<Rgba32F> gpu(source.size());
    if (destination.download(warp, gpu.data(), width) != GpuImageStatus::ok) {
        expect(false, "WARP noritsu download must succeed");
        return;
    }
    compare_against_cpu("WARP", source, cpu, gpu);
}

int main() {
    negaflow::pipeline::install_gpu_kernel_accelerator();
    if (!GpuAccelerator::shared().available()) {
        std::cout << "GPU unavailable — noritsu texture test skipped\n";
        return 0;
    }
    std::cout << "adapter: " << GpuAccelerator::shared().adapter_description() << '\n';

    const std::vector<Rgba32F> source = make_pattern();

    std::vector<Rgba32F> cpu = source;
    const negaflow::core::ImageView cpu_view{cpu.data(), cpu.size(), width, height, width};
    if (negaflow::imaging::apply_noritsu_texture(cpu_view) !=
        negaflow::core::KernelStatus::ok) {
        expect(false, "CPU noritsu texture must succeed");
        return 1;
    }

    std::vector<Rgba32F> gpu = source;
    const ScannerTargetTextureSetup setup =
        negaflow::imaging::scanner_target_texture_setup();
    const bool ran = GpuAccelerator::shared().apply_noritsu_texture(
        reinterpret_cast<float*>(gpu.data()), width, height, width, &setup);
    expect(ran, "GPU noritsu texture must run — fallback would make this test vacuous");
    if (!ran) {
        return 1;
    }
    compare_against_cpu("direct", source, cpu, gpu);

    std::vector<Rgba32F> product = source;
    {
        const negaflow::imaging::ApproximateAcceleratorScope scope{};
        const negaflow::core::ImageView product_view{
            product.data(), product.size(), width, height, width};
        if (negaflow::imaging::apply_noritsu_texture(product_view) !=
            negaflow::core::KernelStatus::ok) {
            expect(false, "product-path noritsu texture must succeed");
            return 1;
        }
    }
    compare_against_cpu("product", source, cpu, product);
    warp_matches_cpu(source, cpu);

    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return 1;
    }
    std::cout << "gpu noritsu texture tests passed\n";
    return 0;
}
