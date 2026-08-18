// CPU/GPU 동치 시험 — 이웃 원시연산.
//
// macOS 는 이 자리를 Apple 내장 필터(`CIBoxBlur`)가 채웁니다. Windows 에는 없어서
// 우리가 만들어야 하고, 가이드 필터 4커널과 `filmScanShrink` 가 여기 물려 있습니다.
//
// CPU 판은 `imaging/film_scan_denoise_filters.cpp` 의 `box_blur` 인데 내부 함수라
// 여기서 직접 부를 수 없습니다. 그래서 **CPU 판과 같은 순서로 도는 참조 구현**을 시험 안에
// 두고 비교합니다 — 러닝 섬, 가장자리 좌표 클램프까지 같습니다.
//
// ⚠️ 이 참조 구현은 `film_scan_denoise_filters.cpp` 의 `box_blur` 를 그대로 옮긴 것입니다.
//    그 파일이 바뀌면 여기도 같이 바꿔야 합니다. 두 벌이라는 것을 알고 두는 것이고,
//    `box_blur` 가 공개되면 이 참조를 지우고 그것을 부르십시오.

#include "negaflow/gpu/gpu_neighborhood.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_working_image.h"

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

using negaflow::core::Rgba32F;
using negaflow::gpu::GpuBoxBlur;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuWorkingImage;

constexpr float tolerance = 1.0e-5F;
constexpr std::uint32_t width = 61U;   // 스레드 그룹 64 의 배수가 아닌 값으로 경계를 봅니다.
constexpr std::uint32_t height = 37U;

[[nodiscard]] std::size_t index_of(
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t stride) noexcept {
    return (static_cast<std::size_t>(y) * stride) + x;
}

// `film_scan_denoise_filters.cpp` `box_blur` 를 그대로 옮긴 참조입니다.
[[nodiscard]] std::vector<Rgba32F> reference_box_blur(
    const std::vector<Rgba32F>& source,
    const int radius) {
    std::vector<Rgba32F> horizontal(source.size());
    std::vector<Rgba32F> result(source.size());
    const float inverse = 1.0F / static_cast<float>((radius * 2) + 1);
    const int last_x = static_cast<int>(width) - 1;
    const int last_y = static_cast<int>(height) - 1;

    for (std::uint32_t y = 0U; y < height; ++y) {
        float red = 0.0F;
        float green = 0.0F;
        float blue = 0.0F;
        for (int offset = -radius; offset <= radius; ++offset) {
            const auto sample_x = static_cast<std::uint32_t>(std::clamp(offset, 0, last_x));
            const Rgba32F& pixel = source[index_of(sample_x, y, width)];
            red += pixel.red;
            green += pixel.green;
            blue += pixel.blue;
        }
        for (std::uint32_t x = 0U; x < width; ++x) {
            horizontal[index_of(x, y, width)] = {
                red * inverse, green * inverse, blue * inverse, source[index_of(x, y, width)].alpha};
            const auto remove_x =
                static_cast<std::uint32_t>(std::clamp(static_cast<int>(x) - radius, 0, last_x));
            const auto add_x = static_cast<std::uint32_t>(
                std::clamp(static_cast<int>(x) + radius + 1, 0, last_x));
            const Rgba32F& added = source[index_of(add_x, y, width)];
            const Rgba32F& removed = source[index_of(remove_x, y, width)];
            red += added.red - removed.red;
            green += added.green - removed.green;
            blue += added.blue - removed.blue;
        }
    }

    for (std::uint32_t x = 0U; x < width; ++x) {
        float red = 0.0F;
        float green = 0.0F;
        float blue = 0.0F;
        for (int offset = -radius; offset <= radius; ++offset) {
            const auto sample_y = static_cast<std::uint32_t>(std::clamp(offset, 0, last_y));
            const Rgba32F& pixel = horizontal[index_of(x, sample_y, width)];
            red += pixel.red;
            green += pixel.green;
            blue += pixel.blue;
        }
        for (std::uint32_t y = 0U; y < height; ++y) {
            result[index_of(x, y, width)] = {
                red * inverse,
                green * inverse,
                blue * inverse,
                horizontal[index_of(x, y, width)].alpha};
            const auto remove_y =
                static_cast<std::uint32_t>(std::clamp(static_cast<int>(y) - radius, 0, last_y));
            const auto add_y = static_cast<std::uint32_t>(
                std::clamp(static_cast<int>(y) + radius + 1, 0, last_y));
            const Rgba32F& added = horizontal[index_of(x, add_y, width)];
            const Rgba32F& removed = horizontal[index_of(x, remove_y, width)];
            red += added.red - removed.red;
            green += added.green - removed.green;
            blue += added.blue - removed.blue;
        }
    }
    return result;
}

// 흐림이 실제로 무언가를 하도록 값이 자주 바뀌는 무늬를 씁니다.
[[nodiscard]] std::vector<Rgba32F> make_pattern() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const bool checker = ((x / 3U) + (y / 5U)) % 2U == 0U;
            const float u = static_cast<float>(x) / static_cast<float>(width - 1U);
            pixels[index_of(x, y, width)] = Rgba32F{
                checker ? 0.90F : 0.05F,
                u,
                checker ? 0.15F : 0.75F,
                1.0F};
        }
    }
    return pixels;
}

void box_blur_matches_reference(const GpuDevice& device, const char* const label) {
    GpuBoxBlur kernel{};
    if (GpuBoxBlur::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "box blur kernel must be creatable");
        return;
    }

    const std::vector<Rgba32F> source = make_pattern();
    GpuWorkingImage input{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
        GpuImageStatus::ok) {
        expect(false, "box blur source upload must succeed");
        return;
    }
    GpuWorkingImage scratch{};
    GpuWorkingImage output{};
    if (GpuWorkingImage::create(device, width, height, scratch) != GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "box blur scratch and destination must be creatable");
        return;
    }

    // 반경 0(그대로) 부터 이미지보다 큰 반경(전 구간 클램프)까지 봅니다.
    const int radii[] = {0, 1, 2, 5, 13, 40};
    for (const int radius : radii) {
        if (kernel.dispatch(device, input, scratch, output, radius) != GpuKernelStatus::ok) {
            expect(false, "box blur dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "box blur download must succeed");
            continue;
        }

        const std::vector<Rgba32F> reference =
            radius == 0 ? source : reference_box_blur(source, radius);

        float worst = 0.0F;
        for (std::size_t index = 0U; index < reference.size(); ++index) {
            worst = std::max(worst, std::abs(reference[index].red - gpu_pixels[index].red));
            worst = std::max(worst, std::abs(reference[index].green - gpu_pixels[index].green));
            worst = std::max(worst, std::abs(reference[index].blue - gpu_pixels[index].blue));
            worst = std::max(worst, std::abs(reference[index].alpha - gpu_pixels[index].alpha));
        }
        if (worst > tolerance) {
            std::cerr << "FAIL: " << label << " box blur radius " << radius << " max delta "
                      << worst << '\n';
            ++failures;
        } else {
            std::cout << "[gpu] " << label << " box blur radius " << radius << " max delta "
                      << worst << '\n';
        }
    }

    expect(
        kernel.dispatch(device, input, scratch, output, -1) == GpuKernelStatus::invalid_arguments,
        "a negative radius is rejected");
    // 같은 자원을 두 역할로 넘기면 D3D11 이 조용히 무시합니다. 거절해야 합니다.
    expect(
        kernel.dispatch(device, input, scratch, scratch, 3) == GpuKernelStatus::invalid_arguments,
        "scratch and destination must differ");
}

}  // namespace

int main() {
    const GpuDevice warp = GpuDevice::create(GpuDevicePreference::warp_only);
    if (!warp.is_usable()) {
        std::cerr << "FAIL: WARP device is required for these checks\n";
        return 1;
    }
    box_blur_matches_reference(warp, "warp");

    const GpuDevice hardware = GpuDevice::create(GpuDevicePreference::hardware_only);
    if (hardware.is_usable()) {
        std::cout << "[gpu] hardware: " << hardware.capability().adapter.description.data() << '\n';
        box_blur_matches_reference(hardware, "hardware");
    } else {
        std::cout << "[gpu] hardware absent, WARP only\n";
    }

    if (failures != 0) {
        std::cerr << failures << " gpu neighborhood check(s) failed\n";
        return 1;
    }
    std::cout << "gpu neighborhood checks passed\n";
    return 0;
}
