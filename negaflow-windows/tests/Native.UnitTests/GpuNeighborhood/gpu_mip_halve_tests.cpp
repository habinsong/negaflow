#include "gpu_mip_halve_tests.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

#include "gpu_neighborhood_test_support.h"
#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_neighborhood.h"
#include "negaflow/gpu/gpu_working_image.h"

namespace gpu_neighborhood_tests {
namespace {

using negaflow::core::Rgba32F;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuMipHalve;
using negaflow::gpu::GpuWorkingImage;

// `imaging/mipmap_downsampler.cpp` 의 `halve` 를 그대로 옮긴 참조입니다.
// 그 함수는 내부라 여기서 직접 부를 수 없습니다 — 그 파일이 바뀌면 여기도 같이 바꾸십시오.
//
// 이 축소의 결과가 파라메트릭 톤 커브의 밴드 백분위로 가므로 **비트 단위로** 같아야 합니다.
// 허용 오차가 아니라 **완전 일치**를 봅니다.
[[nodiscard]] std::vector<Rgba32F> reference_halve(
    const std::vector<Rgba32F>& parent,
    const std::uint32_t parent_width,
    const std::uint32_t parent_height,
    std::uint32_t& child_width,
    std::uint32_t& child_height) {
    child_width = std::max(1U, parent_width / 2U);
    child_height = std::max(1U, parent_height / 2U);
    std::vector<Rgba32F> child(
        static_cast<std::size_t>(child_width) * child_height);
    for (std::uint32_t y = 0U; y < child_height; ++y) {
        for (std::uint32_t x = 0U; x < child_width; ++x) {
            const std::uint32_t sx = std::min(x * 2U, parent_width - 1U);
            const std::uint32_t sy = std::min(y * 2U, parent_height - 1U);
            const std::uint32_t sx1 = std::min(sx + 1U, parent_width - 1U);
            const std::uint32_t sy1 = std::min(sy + 1U, parent_height - 1U);
            const Rgba32F a = parent[(static_cast<std::size_t>(sy) * parent_width) + sx];
            const Rgba32F b = parent[(static_cast<std::size_t>(sy) * parent_width) + sx1];
            const Rgba32F c = parent[(static_cast<std::size_t>(sy1) * parent_width) + sx];
            const Rgba32F d = parent[(static_cast<std::size_t>(sy1) * parent_width) + sx1];
            child[(static_cast<std::size_t>(y) * child_width) + x] = {
                (a.red + b.red + c.red + d.red) * 0.25F,
                (a.green + b.green + c.green + d.green) * 0.25F,
                (a.blue + b.blue + c.blue + d.blue) * 0.25F,
                1.0F,
            };
        }
    }
    return child;
}

[[nodiscard]] std::vector<Rgba32F> make_source(
    const std::uint32_t image_width,
    const std::uint32_t image_height) {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(image_width) * image_height);
    for (std::uint32_t y = 0U; y < image_height; ++y) {
        for (std::uint32_t x = 0U; x < image_width; ++x) {
            // 값이 화소마다 다르고 반올림이 실제로 일어나도록 나눗셈으로 만듭니다.
            const float u = static_cast<float>(x) / 7.0F;
            const float v = static_cast<float>(y) / 11.0F;
            pixels[(static_cast<std::size_t>(y) * image_width) + x] = Rgba32F{
                u - std::floor(u) + 0.013F,
                v - std::floor(v) + 0.027F,
                ((u * v) / 3.0F) + 0.041F,
                1.0F};
        }
    }
    return pixels;
}

void check_one(
    const GpuDevice& device,
    const char* const label,
    const std::uint32_t image_width,
    const std::uint32_t image_height) {
    GpuMipHalve kernel{};
    if (GpuMipHalve::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "mip halve kernel must be creatable");
        return;
    }

    const std::vector<Rgba32F> source = make_source(image_width, image_height);
    GpuWorkingImage input{};
    if (GpuWorkingImage::upload(device, source.data(), image_width, image_height, image_width, input) !=
        GpuImageStatus::ok) {
        expect(false, "mip halve source upload must succeed");
        return;
    }

    std::uint32_t child_width = 0U;
    std::uint32_t child_height = 0U;
    const std::vector<Rgba32F> reference =
        reference_halve(source, image_width, image_height, child_width, child_height);

    GpuWorkingImage output{};
    if (GpuWorkingImage::create(device, child_width, child_height, output) !=
        GpuImageStatus::ok) {
        expect(false, "mip halve destination must be creatable");
        return;
    }
    if (kernel.dispatch(device, input, output) != GpuKernelStatus::ok) {
        expect(false, "mip halve dispatch must succeed");
        return;
    }
    std::vector<Rgba32F> gpu_pixels(reference.size());
    if (output.download(device, gpu_pixels.data(), child_width) != GpuImageStatus::ok) {
        expect(false, "mip halve download must succeed");
        return;
    }

    bool identical = true;
    std::size_t first_bad = 0U;
    for (std::size_t index = 0U; index < reference.size(); ++index) {
        if (reference[index].red != gpu_pixels[index].red ||
            reference[index].green != gpu_pixels[index].green ||
            reference[index].blue != gpu_pixels[index].blue ||
            reference[index].alpha != gpu_pixels[index].alpha) {
            identical = false;
            first_bad = index;
            break;
        }
    }
    if (!identical) {
        std::cerr << "FAIL: " << label << " mip halve " << image_width << 'x' << image_height
                  << " differs at " << first_bad << " ref " << reference[first_bad].red
                  << " gpu " << gpu_pixels[first_bad].red << '\n';
        ++failures;
    } else {
        std::cout << "[gpu] " << label << " mip halve " << image_width << 'x' << image_height << " -> "
                  << child_width << 'x' << child_height << " bit-exact\n";
    }
}

} // namespace

void mip_halve_matches_reference(const GpuDevice& device, const char* const label) {
    // 짝수·홀수 변을 모두 봅니다 — 홀수에서 마지막 화소를 두 번 읽는 것이 CPU 와 같아야 합니다.
    check_one(device, label, 64U, 48U);
    check_one(device, label, 61U, 37U);
    check_one(device, label, 5U, 3U);
    check_one(device, label, 1U, 9U);

    // 단계 수 계산이 CPU 판과 같은지. `floor(log2(5100/320)) == 3`.
    expect(GpuMipHalve::wanted_level_count(5100U, 320U) == 3, "level count for 5100 -> 320");
    expect(GpuMipHalve::wanted_level_count(320U, 320U) == 0, "no levels when no shrink");
    expect(GpuMipHalve::wanted_level_count(100U, 320U) == 0, "no levels when enlarging");
    expect(GpuMipHalve::wanted_level_count(0U, 320U) == 0, "zero width yields no levels");
}

} // namespace gpu_neighborhood_tests
