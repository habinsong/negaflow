// 박스 블러 — macOS `CIBoxBlur`(`FilmScanDenoise.swift:154`),
// Windows CPU `imaging/film_scan_denoise_filters.cpp` 의 `box_blur`.
//
// ☠️ **CPU 는 `box_blur` 를 두 벌 갖고 있고 둘의 누적 괄호가 다릅니다.** 앞 판은 이것을
//    놓쳐서 참조가 틀렸고, 그 틀린 참조에 GPU 가 delta 0 으로 맞아 "비트 단위 일치" 로
//    보고됐습니다. 실제 CPU 는 이렇습니다:
//
//      `film_scan_denoise_filters.cpp:145` box_blur(std::vector<float>&)
//          sum += source[add] - source[remove];         →  sum + (a - b)
//      `film_scan_denoise_filters.cpp:203` box_blur(std::vector<Rgb>&)
//          sum = sum + source[add] - source[remove];    → (sum + a) - b
//
//    `Rgb` 의 `operator+`·`operator-`(`film_scan_denoise_math.h:49,57`)가 각각 따로 도는
//    이항 연산이라 왼쪽부터 묶입니다. `guided_base` 는 둘을 섞어 씁니다 —
//    guide·guide² 는 float 판, source·guide×source·a·b 는 Rgb 판.
//    아래 두 참조는 그 구분을 그대로 지킵니다.

#include "gpu_box_blur_tests.h"

#include <algorithm>
#include <cstdint>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_neighborhood.h"
#include "negaflow/gpu/gpu_working_image.h"

namespace gpu_neighborhood_tests {

using negaflow::gpu::GpuBoxBlur;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuWorkingImage;

std::vector<Rgba32F> reference_box_blur(const std::vector<Rgba32F>& source, const int radius) {
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
                red * inverse,
                green * inverse,
                blue * inverse,
                source[index_of(x, y, width)].alpha};
            const auto remove_x =
                static_cast<std::uint32_t>(std::clamp(static_cast<int>(x) - radius, 0, last_x));
            const auto add_x =
                static_cast<std::uint32_t>(std::clamp(static_cast<int>(x) + radius + 1, 0, last_x));
            const Rgba32F& added = source[index_of(add_x, y, width)];
            const Rgba32F& removed = source[index_of(remove_x, y, width)];
            red = (red + added.red) - removed.red;
            green = (green + added.green) - removed.green;
            blue = (blue + added.blue) - removed.blue;
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
            const auto add_y =
                static_cast<std::uint32_t>(std::clamp(static_cast<int>(y) + radius + 1, 0, last_y));
            const Rgba32F& added = horizontal[index_of(x, add_y, width)];
            const Rgba32F& removed = horizontal[index_of(x, remove_y, width)];
            red = (red + added.red) - removed.red;
            green = (green + added.green) - removed.green;
            blue = (blue + added.blue) - removed.blue;
        }
    }
    return result;
}

std::vector<Rgba32F> reference_box_blur_four(
    const std::vector<Rgba32F>& source,
    const int radius) {
    std::vector<Rgba32F> horizontal(source.size());
    std::vector<Rgba32F> result(source.size());
    const float inverse = 1.0F / static_cast<float>((radius * 2) + 1);
    const int last_x = static_cast<int>(width) - 1;
    const int last_y = static_cast<int>(height) - 1;

    for (std::uint32_t y = 0U; y < height; ++y) {
        Rgba32F sum{0.0F, 0.0F, 0.0F, 0.0F};
        for (int offset = -radius; offset <= radius; ++offset) {
            const auto sample_x = static_cast<std::uint32_t>(std::clamp(offset, 0, last_x));
            const Rgba32F& pixel = source[index_of(sample_x, y, width)];
            sum = {sum.red + pixel.red,
                   sum.green + pixel.green,
                   sum.blue + pixel.blue,
                   sum.alpha + pixel.alpha};
        }
        for (std::uint32_t x = 0U; x < width; ++x) {
            horizontal[index_of(x, y, width)] = {
                sum.red * inverse, sum.green * inverse, sum.blue * inverse, sum.alpha * inverse};
            const auto remove_x =
                static_cast<std::uint32_t>(std::clamp(static_cast<int>(x) - radius, 0, last_x));
            const auto add_x =
                static_cast<std::uint32_t>(std::clamp(static_cast<int>(x) + radius + 1, 0, last_x));
            const Rgba32F& added = source[index_of(add_x, y, width)];
            const Rgba32F& removed = source[index_of(remove_x, y, width)];
            sum = {(sum.red + added.red) - removed.red,
                   (sum.green + added.green) - removed.green,
                   (sum.blue + added.blue) - removed.blue,
                   sum.alpha + (added.alpha - removed.alpha)};
        }
    }

    for (std::uint32_t x = 0U; x < width; ++x) {
        Rgba32F sum{0.0F, 0.0F, 0.0F, 0.0F};
        for (int offset = -radius; offset <= radius; ++offset) {
            const auto sample_y = static_cast<std::uint32_t>(std::clamp(offset, 0, last_y));
            const Rgba32F& pixel = horizontal[index_of(x, sample_y, width)];
            sum = {sum.red + pixel.red,
                   sum.green + pixel.green,
                   sum.blue + pixel.blue,
                   sum.alpha + pixel.alpha};
        }
        for (std::uint32_t y = 0U; y < height; ++y) {
            result[index_of(x, y, width)] = {
                sum.red * inverse, sum.green * inverse, sum.blue * inverse, sum.alpha * inverse};
            const auto remove_y =
                static_cast<std::uint32_t>(std::clamp(static_cast<int>(y) - radius, 0, last_y));
            const auto add_y =
                static_cast<std::uint32_t>(std::clamp(static_cast<int>(y) + radius + 1, 0, last_y));
            const Rgba32F& added = horizontal[index_of(x, add_y, width)];
            const Rgba32F& removed = horizontal[index_of(x, remove_y, width)];
            sum = {(sum.red + added.red) - removed.red,
                   (sum.green + added.green) - removed.green,
                   (sum.blue + added.blue) - removed.blue,
                   sum.alpha + (added.alpha - removed.alpha)};
        }
    }
    return result;
}

void box_blur_matches_reference(const GpuDevice& device, const char* const label) {
    GpuBoxBlur kernel{};
    if (GpuBoxBlur::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "box blur kernel must be creatable");
        return;
    }

    const std::vector<Rgba32F> source = make_pattern();
    GpuWorkingImage input{};
    GpuWorkingImage scratch{};
    GpuWorkingImage output{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
            GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, scratch) != GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "box blur images must be creatable");
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
        report(label, "box blur", radius, worst_delta(reference, gpu_pixels));
    }

    expect(
        kernel.dispatch(device, input, scratch, output, -1) == GpuKernelStatus::invalid_arguments,
        "a negative radius is rejected");
    // 같은 자원을 두 역할로 넘기면 D3D11 이 조용히 무시합니다. 거절해야 합니다.
    expect(
        kernel.dispatch(device, input, scratch, scratch, 3) == GpuKernelStatus::invalid_arguments,
        "scratch and destination must differ");
}

// ☠️ `blur_alpha = true` 경로에 시험이 없었습니다. 그래서 RGB·알파의 누적 순서가 다르다는
//    것을 아무도 못 잡았고, 가이드 필터에 가서야 `1e-5` 를 넘겼습니다. 가이드 필터가 쓰는
//    바로 그 경로이므로 여기서 따로 못 박습니다.
void box_blur_alpha_matches_reference(const GpuDevice& device, const char* const label) {
    GpuBoxBlur kernel{};
    if (GpuBoxBlur::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "box blur kernel must be creatable");
        return;
    }

    // 알파가 화소마다 바뀌어야 의미가 있습니다. `make_pattern` 의 알파는 전부 1 입니다.
    const std::vector<Rgba32F> source = make_guided_input();
    GpuWorkingImage input{};
    GpuWorkingImage scratch{};
    GpuWorkingImage output{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
            GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, scratch) != GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "alpha box blur images must be creatable");
        return;
    }

    const int radii[] = {1, 3, 7};
    for (const int radius : radii) {
        if (kernel.dispatch(device, input, scratch, output, radius, true) != GpuKernelStatus::ok) {
            expect(false, "alpha box blur dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "alpha box blur download must succeed");
            continue;
        }
        const std::vector<Rgba32F> reference = reference_box_blur_four(source, radius);
        report(label, "alpha box blur", radius, worst_delta(reference, gpu_pixels));
    }
}

}  // namespace gpu_neighborhood_tests
