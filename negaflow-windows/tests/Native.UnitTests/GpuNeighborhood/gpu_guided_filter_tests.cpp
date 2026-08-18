// 가이드 필터 — macOS `gfProduct`(`:466`)·`gfCoeffA`(`:470`)·`gfCoeffB`(`:482`)·
// `gfApply`(`:486`), Windows CPU `imaging/film_scan_denoise_filters.cpp` `guided_base`.
//
// `guided_base` 도 내부 함수라 여기 참조를 둡니다. 박스 블러 참조와 같은 사정입니다.

#include "gpu_guided_filter_tests.h"

#include <algorithm>
#include <cstdint>
#include <iostream>

#include "gpu_box_blur_tests.h"
#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_neighborhood.h"
#include "negaflow/gpu/gpu_working_image.h"

namespace gpu_neighborhood_tests {

using negaflow::gpu::GpuBoxBlur;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuGuidedFilter;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuWorkingImage;

std::vector<Rgba32F> reference_guided(const std::vector<Rgba32F>& packed, const int radius) {
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
        const float a_red =
            (mean_product[index].red - (mean_packed[index].red * mean_guide)) * scale;
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

void guided_filter_matches_reference(const GpuDevice& device, const char* const label) {
    GpuBoxBlur blur{};
    GpuGuidedFilter guided{};
    if (GpuBoxBlur::create(device, blur) != GpuKernelStatus::ok ||
        GpuGuidedFilter::create(device, guided) != GpuKernelStatus::ok) {
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

    GpuWorkingImage scratch[GpuGuidedFilter::scratch_count]{};
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
        report(label, "guided", radius, worst_delta(reference, gpu_pixels));
    }

    expect(
        guided.dispatch(device, blur, packed, nullptr, output, 3, reference_guided_epsilon) ==
            GpuKernelStatus::invalid_arguments,
        "a null scratch array is rejected");
}

}  // namespace gpu_neighborhood_tests
