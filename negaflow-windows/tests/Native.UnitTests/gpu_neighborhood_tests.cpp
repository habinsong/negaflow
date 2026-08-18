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

// `film_scan_denoise_filters.cpp:175` `box_blur(std::vector<Rgb>&)` 를 그대로 옮긴 참조입니다.
// 누적은 `(sum + a) - b` — `Rgb` 이항 연산자가 왼쪽부터 묶이기 때문입니다.
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
            const auto add_y = static_cast<std::uint32_t>(
                std::clamp(static_cast<int>(y) + radius + 1, 0, last_y));
            const Rgba32F& added = horizontal[index_of(x, add_y, width)];
            const Rgba32F& removed = horizontal[index_of(x, remove_y, width)];
            red = (red + added.red) - removed.red;
            green = (green + added.green) - removed.green;
            blue = (blue + added.blue) - removed.blue;
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

// 가이드 필터 — macOS `gfProduct`/`gfCoeffA`/`gfCoeffB`/`gfApply`,
// Windows CPU `imaging/film_scan_denoise_filters.cpp` `guided_base`.
//
// `guided_base` 도 내부 함수라 여기 참조를 둡니다. 위 박스 블러 참조와 같은 사정입니다.
// `guided_epsilon` 은 `film_scan_denoise_types.h:14` 의 `0.001F` 입니다.
constexpr float reference_guided_epsilon = 0.001F;

// 알파에 담긴 스칼라까지 흐리는 참조입니다(GPU 의 `blur_alpha = true` 에 해당).
//
// ☠️ RGB 와 알파의 괄호가 다릅니다. `guided_base` 가 RGB 자리에는 `Rgb` 판을, 알파 자리
//    (guide·guide²)에는 `float` 판을 쓰기 때문입니다. 통일하면 가이드 필터 결과가 반경 1 에서
//    3.8e-05 까지 벌어집니다 — 실측입니다.
[[nodiscard]] std::vector<Rgba32F> reference_box_blur_four(
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
            const auto add_x = static_cast<std::uint32_t>(
                std::clamp(static_cast<int>(x) + radius + 1, 0, last_x));
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
            const auto add_y = static_cast<std::uint32_t>(
                std::clamp(static_cast<int>(y) + radius + 1, 0, last_y));
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

// `guided_base` 를 그대로 옮긴 참조입니다. 입력은 GPU 와 같은 묶음
// `(source.r, source.g, source.b, guide)` 를 씁니다.
[[nodiscard]] std::vector<Rgba32F> reference_guided(
    const std::vector<Rgba32F>& packed,
    const int radius) {
    std::vector<Rgba32F> product(packed.size());
    for (std::size_t index = 0U; index < packed.size(); ++index) {
        const float guide = packed[index].alpha;
        product[index] = {
            packed[index].red * guide,
            packed[index].green * guide,
            packed[index].blue * guide,
            guide * guide};
    }

    const std::vector<Rgba32F> mean_packed = reference_box_blur_four(packed, radius);
    const std::vector<Rgba32F> mean_product = reference_box_blur_four(product, radius);

    std::vector<Rgba32F> coefficient_a(packed.size());
    std::vector<Rgba32F> coefficient_b(packed.size());
    for (std::size_t index = 0U; index < packed.size(); ++index) {
        const float mean_guide = mean_packed[index].alpha;
        const float variance =
            std::max(0.0F, mean_product[index].alpha - (mean_guide * mean_guide));
        const float scale = 1.0F / (variance + reference_guided_epsilon);
        const float a_red = (mean_product[index].red - (mean_packed[index].red * mean_guide)) * scale;
        const float a_green =
            (mean_product[index].green - (mean_packed[index].green * mean_guide)) * scale;
        const float a_blue =
            (mean_product[index].blue - (mean_packed[index].blue * mean_guide)) * scale;
        coefficient_a[index] = {a_red, a_green, a_blue, 0.0F};
        coefficient_b[index] = {
            mean_packed[index].red - (a_red * mean_guide),
            mean_packed[index].green - (a_green * mean_guide),
            mean_packed[index].blue - (a_blue * mean_guide),
            0.0F};
    }

    const std::vector<Rgba32F> mean_a = reference_box_blur_four(coefficient_a, radius);
    const std::vector<Rgba32F> mean_b = reference_box_blur_four(coefficient_b, radius);

    std::vector<Rgba32F> result(packed.size());
    for (std::size_t index = 0U; index < packed.size(); ++index) {
        const float guide = packed[index].alpha;
        result[index] = {
            std::clamp((mean_a[index].red * guide) + mean_b[index].red, 0.0F, 1.0F),
            std::clamp((mean_a[index].green * guide) + mean_b[index].green, 0.0F, 1.0F),
            std::clamp((mean_a[index].blue * guide) + mean_b[index].blue, 0.0F, 1.0F),
            guide};
    }
    return result;
}

// 가이드는 알파에 담습니다. 여기서는 휘도를 가이드로 씁니다 — 실제 디노이즈도 그렇습니다.
[[nodiscard]] std::vector<Rgba32F> make_guided_input() {
    std::vector<Rgba32F> pixels = make_pattern();
    for (Rgba32F& pixel : pixels) {
        pixel.alpha =
            (pixel.red * 0.2126F) + (pixel.green * 0.7152F) + (pixel.blue * 0.0722F);
    }
    return pixels;
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
        float worst = 0.0F;
        for (std::size_t index = 0U; index < reference.size(); ++index) {
            worst = std::max(worst, std::abs(reference[index].red - gpu_pixels[index].red));
            worst = std::max(worst, std::abs(reference[index].green - gpu_pixels[index].green));
            worst = std::max(worst, std::abs(reference[index].blue - gpu_pixels[index].blue));
            worst = std::max(worst, std::abs(reference[index].alpha - gpu_pixels[index].alpha));
        }
        if (worst > tolerance) {
            std::cerr << "FAIL: " << label << " alpha box blur radius " << radius << " max delta "
                      << worst << '\n';
            ++failures;
        } else {
            std::cout << "[gpu] " << label << " alpha box blur radius " << radius << " max delta "
                      << worst << '\n';
        }
    }
}

void guided_filter_matches_reference(const GpuDevice& device, const char* const label) {
    GpuBoxBlur blur{};
    negaflow::gpu::GpuGuidedFilter guided{};
    if (GpuBoxBlur::create(device, blur) != GpuKernelStatus::ok ||
        negaflow::gpu::GpuGuidedFilter::create(device, guided) != GpuKernelStatus::ok) {
        expect(false, "guided filter kernels must be creatable");
        return;
    }

    const std::vector<Rgba32F> source = make_guided_input();
    GpuWorkingImage packed{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, packed) !=
        GpuImageStatus::ok) {
        expect(false, "guided source upload must succeed");
        return;
    }

    GpuWorkingImage scratch[negaflow::gpu::GpuGuidedFilter::scratch_count]{};
    for (GpuWorkingImage& image : scratch) {
        if (GpuWorkingImage::create(device, width, height, image) != GpuImageStatus::ok) {
            expect(false, "guided scratch must be creatable");
            return;
        }
    }
    GpuWorkingImage output{};
    if (GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "guided destination must be creatable");
        return;
    }

    // CPU 판이 실제로 쓰는 반경 둘(`film_scan_denoise_tile.cpp:79,81`)을 반드시 봅니다.
    const int radii[] = {3, 7, 1};
    for (const int radius : radii) {
        if (guided.dispatch(
                device, blur, packed, scratch, output, radius, reference_guided_epsilon) !=
            GpuKernelStatus::ok) {
            expect(false, "guided dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "guided download must succeed");
            continue;
        }

        const std::vector<Rgba32F> reference = reference_guided(source, radius);

        float worst = 0.0F;
        std::size_t worst_index = 0U;
        for (std::size_t index = 0U; index < reference.size(); ++index) {
            const float largest = std::max(
                std::abs(reference[index].red - gpu_pixels[index].red),
                std::max(
                    std::abs(reference[index].green - gpu_pixels[index].green),
                    std::abs(reference[index].blue - gpu_pixels[index].blue)));
            if (largest > worst) {
                worst = largest;
                worst_index = index;
            }
        }
        if (worst > tolerance) {
            std::cerr << "FAIL: " << label << " guided radius " << radius << " max delta " << worst
                      << " at (" << (worst_index % width) << ',' << (worst_index / width)
                      << ") ref " << reference[worst_index].red << ','
                      << reference[worst_index].green << ',' << reference[worst_index].blue
                      << " gpu " << gpu_pixels[worst_index].red << ','
                      << gpu_pixels[worst_index].green << ',' << gpu_pixels[worst_index].blue
                      << '\n';
            ++failures;
        } else {
            std::cout << "[gpu] " << label << " guided radius " << radius << " max delta " << worst
                      << '\n';
        }
    }

    expect(
        guided.dispatch(device, blur, packed, nullptr, output, 3, reference_guided_epsilon) ==
            GpuKernelStatus::invalid_arguments,
        "a null scratch array is rejected");
}

}  // namespace

int main() {
    const GpuDevice warp = GpuDevice::create(GpuDevicePreference::warp_only);
    if (!warp.is_usable()) {
        std::cerr << "FAIL: WARP device is required for these checks\n";
        return 1;
    }
    box_blur_matches_reference(warp, "warp");
    box_blur_alpha_matches_reference(warp, "warp");
    guided_filter_matches_reference(warp, "warp");

    const GpuDevice hardware = GpuDevice::create(GpuDevicePreference::hardware_only);
    if (hardware.is_usable()) {
        std::cout << "[gpu] hardware: " << hardware.capability().adapter.description.data() << '\n';
        box_blur_matches_reference(hardware, "hardware");
        box_blur_alpha_matches_reference(hardware, "hardware");
        guided_filter_matches_reference(hardware, "hardware");
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
