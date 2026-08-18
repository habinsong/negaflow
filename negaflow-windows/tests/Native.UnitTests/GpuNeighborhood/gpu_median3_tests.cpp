// 3×3 중앙값 — macOS `CIMedianFilter`(`FilmScanDenoise.swift:171`),
// Windows CPU `imaging/film_scan_denoise_filters.cpp:77` `median3`.
//
// 참조는 CPU 와 **같은 도구**(`std::nth_element`)를 씁니다. 중앙값은 아홉 개 중 하나를
// 고르는 일이라 고르는 방법이 달라도 값이 같아야 하고, 그래서 이 시험은 셰이더의 정렬
// 네트워크가 실제로 중앙을 고르는지를 봅니다 — 허용치가 아니라 **정확히 0** 을 요구합니다.

#include "gpu_median3_tests.h"

#include <algorithm>
#include <array>
#include <cstdint>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_neighborhood.h"
#include "negaflow/gpu/gpu_working_image.h"

namespace gpu_neighborhood_tests {
namespace {

// `film_scan_denoise_filters.cpp:72` `median9` 그대로입니다.
[[nodiscard]] float median9(std::array<float, 9U> values) noexcept {
    std::nth_element(values.begin(), values.begin() + 4, values.end());
    return values[4];
}

// 중앙값을 제대로 시험하려면 이웃 아홉 개가 서로 달라야 합니다. `make_pattern` 은 채널당
// 값이 두세 개뿐이라 어떤 네트워크든 통과합니다 — 여기서는 결정적 해시로 흩뜨리고,
// 고립 임펄스(중앙값이 잡아야 하는 것)와 동점(정렬 네트워크가 흔들릴 수 있는 것)을
// 일부러 섞습니다.
[[nodiscard]] std::vector<Rgba32F> make_scattered_pattern() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::uint32_t seed = (x * 73856093U) ^ (y * 19349663U);
            const std::uint32_t mixed = (seed ^ (seed >> 13U)) * 1274126177U;
            const float noise = static_cast<float>(mixed >> 8U) / 16777216.0F;
            const bool impulse = ((x * 7U) + (y * 11U)) % 53U == 0U;
            const bool tie = ((x / 4U) + (y / 4U)) % 3U == 0U;
            pixels[index_of(x, y, width)] = Rgba32F{
                impulse ? 1.0F : noise,
                tie ? 0.5F : (1.0F - noise),
                impulse ? 0.0F : (noise * 0.5F + 0.25F),
                noise};
        }
    }
    return pixels;
}

[[nodiscard]] std::vector<Rgba32F> reference_median3(const std::vector<Rgba32F>& source) {
    std::vector<Rgba32F> result(source.size());
    const int last_x = static_cast<int>(width) - 1;
    const int last_y = static_cast<int>(height) - 1;
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            std::array<float, 9U> red{};
            std::array<float, 9U> green{};
            std::array<float, 9U> blue{};
            std::size_t cursor = 0U;
            for (int dy = -1; dy <= 1; ++dy) {
                const auto sample_y = static_cast<std::uint32_t>(
                    std::clamp(static_cast<int>(y) + dy, 0, last_y));
                for (int dx = -1; dx <= 1; ++dx) {
                    const auto sample_x = static_cast<std::uint32_t>(
                        std::clamp(static_cast<int>(x) + dx, 0, last_x));
                    const Rgba32F& sample = source[index_of(sample_x, sample_y, width)];
                    red[cursor] = sample.red;
                    green[cursor] = sample.green;
                    blue[cursor] = sample.blue;
                    ++cursor;
                }
            }
            result[index_of(x, y, width)] = {
                median9(red), median9(green), median9(blue), source[index_of(x, y, width)].alpha};
        }
    }
    return result;
}

}  // namespace

void median3_matches_reference(
    const negaflow::gpu::GpuDevice& device,
    const char* const label) {
    using negaflow::gpu::GpuImageStatus;
    using negaflow::gpu::GpuKernelStatus;
    using negaflow::gpu::GpuMedian3;
    using negaflow::gpu::GpuWorkingImage;

    GpuMedian3 kernel{};
    if (GpuMedian3::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "median3 kernel must be creatable");
        return;
    }

    const std::vector<Rgba32F> source = make_scattered_pattern();
    GpuWorkingImage input{};
    GpuWorkingImage output{};
    GpuWorkingImage second{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
            GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, second) != GpuImageStatus::ok) {
        expect(false, "median3 images must be creatable");
        return;
    }

    if (kernel.dispatch(device, input, output) != GpuKernelStatus::ok) {
        expect(false, "median3 dispatch must succeed");
        return;
    }
    std::vector<Rgba32F> gpu_pixels(source.size());
    if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
        expect(false, "median3 download must succeed");
        return;
    }
    const std::vector<Rgba32F> med3 = reference_median3(source);
    report(label, "median3", 1, worst_delta(med3, gpu_pixels));

    // `film_scan_denoise_tile.cpp:83` 은 중앙값을 두 번 겁니다(≈5×5). 두 번째 패스가
    // 첫 결과를 그대로 받는지까지 봅니다 — 알파 보존이 여기서 깨지면 med5 가 틀어집니다.
    if (kernel.dispatch(device, output, second) != GpuKernelStatus::ok) {
        expect(false, "median3 second pass must succeed");
        return;
    }
    if (second.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
        expect(false, "median3 second download must succeed");
        return;
    }
    report(label, "median5 (median3 twice)", 2, worst_delta(reference_median3(med3), gpu_pixels));

    expect(
        kernel.dispatch(device, input, input) == GpuKernelStatus::invalid_arguments,
        "median3 source and destination must differ");
}

}  // namespace gpu_neighborhood_tests
