// 가우시안 — macOS `CIGaussianBlur`(Apple 내장, 네 곳),
// Windows CPU `imaging/film_scan_denoise_filters.cpp:13` `gaussian_blur` 와
// `imaging/texture_stage_gaussian.h:22` `gaussian_transform`.
//
// 두 CPU 판은 수식과 누적 순서가 같고 **가장자리 처리와 지원 반경 하한만** 다릅니다.
// 아래 참조는 그 둘을 매개변수로 받아 한 벌로 둡니다.
//
// ☠️ 가중치를 시험이 따로 만들지 않고 `GpuGaussianBlur::weights_for_sigma` 가 준 것을
//    씁니다. 그것이 곧 CPU 와 같은 코드이고, 두 벌을 두면 시험이 자기 자신을 검증하게
//    됩니다 — 앞서 박스 블러에서 그렇게 틀린 참조가 통과했습니다.

#include "gpu_gaussian_tests.h"

#include <algorithm>
#include <cstdint>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_neighborhood.h"
#include "negaflow/gpu/gpu_working_image.h"

namespace gpu_neighborhood_tests {
namespace {

using negaflow::gpu::GpuGaussianEdgeMode;

// `texture_stage_gaussian.h:43-52` 의 `coordinate` 람다입니다.
[[nodiscard]] int fold_coordinate(
    const int candidate,
    const int limit,
    const GpuGaussianEdgeMode edge_mode) noexcept {
    if (edge_mode != GpuGaussianEdgeMode::mirror || limit <= 1) {
        return std::clamp(candidate, 0, limit - 1);
    }
    const int period = limit * 2;
    int folded = candidate % period;
    if (folded < 0) {
        folded += period;
    }
    return folded < limit ? folded : period - 1 - folded;
}

// 한 축 패스입니다. CPU 두 판 모두 `value = value + sample * weight` 를 offset `-R`→`+R`
// 순서로 돕니다.
[[nodiscard]] std::vector<Rgba32F> blur_axis(
    const std::vector<Rgba32F>& source,
    const std::vector<float>& weights,
    const GpuGaussianEdgeMode edge_mode,
    const bool blur_alpha,
    const bool horizontal) {
    const int radius = static_cast<int>((weights.size() - 1U) / 2U);
    std::vector<Rgba32F> result(source.size());
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const int limit = horizontal ? static_cast<int>(width) : static_cast<int>(height);
            const int position = horizontal ? static_cast<int>(x) : static_cast<int>(y);
            float red = 0.0F;
            float green = 0.0F;
            float blue = 0.0F;
            float alpha = 0.0F;
            for (int offset = -radius; offset <= radius; ++offset) {
                const int candidate = position + offset;
                if (edge_mode == GpuGaussianEdgeMode::transparent &&
                    (candidate < 0 || candidate >= limit)) {
                    continue;
                }
                const auto folded =
                    static_cast<std::uint32_t>(fold_coordinate(candidate, limit, edge_mode));
                const Rgba32F& sample = horizontal ? source[index_of(folded, y, width)]
                                                   : source[index_of(x, folded, width)];
                const float weight = weights[static_cast<std::size_t>(offset + radius)];
                red = red + sample.red * weight;
                green = green + sample.green * weight;
                blue = blue + sample.blue * weight;
                alpha = alpha + sample.alpha * weight;
            }
            result[index_of(x, y, width)] = {
                red, green, blue, blur_alpha ? alpha : source[index_of(x, y, width)].alpha};
        }
    }
    return result;
}

}  // namespace

std::vector<Rgba32F> reference_gaussian(
    const std::vector<Rgba32F>& source,
    const std::vector<float>& weights,
    const GpuGaussianEdgeMode edge_mode,
    const bool blur_alpha) {
    const std::vector<Rgba32F> horizontal =
        blur_axis(source, weights, edge_mode, blur_alpha, true);
    return blur_axis(horizontal, weights, edge_mode, blur_alpha, false);
}

void gaussian_matches_reference(
    const negaflow::gpu::GpuDevice& device,
    const char* const label) {
    using negaflow::gpu::GpuGaussianBlur;
    using negaflow::gpu::GpuImageStatus;
    using negaflow::gpu::GpuKernelStatus;
    using negaflow::gpu::GpuWorkingImage;

    GpuGaussianBlur kernel{};
    if (GpuGaussianBlur::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "gaussian kernel must be creatable");
        return;
    }

    // 알파가 화소마다 바뀌는 입력이라야 `blur_alpha` 경로가 의미를 갖습니다.
    const std::vector<Rgba32F> source = make_guided_input();
    GpuWorkingImage input{};
    GpuWorkingImage scratch{};
    GpuWorkingImage output{};
    if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
            GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, scratch) != GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
        expect(false, "gaussian images must be creatable");
        return;
    }

    struct Case final {
        float sigma;
        int minimum_support;
        GpuGaussianEdgeMode edge_mode;
        bool blur_alpha;
        const char* what;
    };

    // 첫 줄이 `film_scan_denoise` 가 실제로 쓰는 값입니다
    // (`film_scan_denoise_types.h:16` `gaussian_radius = 1.3`, 지원 하한 없음, 클램프, Rgb).
    // 나머지는 `texture_stage_effects.cpp` 의 세 가장자리를 각각 봅니다.
    const Case cases[] = {
        {1.3F, 0, GpuGaussianEdgeMode::clamp, false, "gaussian denoise-clamp"},
        {1.3F, 1, GpuGaussianEdgeMode::mirror, true, "gaussian mirror"},
        {2.5F, 1, GpuGaussianEdgeMode::transparent, true, "gaussian transparent"},
        {6.0F, 1, GpuGaussianEdgeMode::clamp, true, "gaussian wide-clamp"},
        // 이미지보다 넓은 지원 반경 — 접기·클램프가 전 구간에서 걸립니다.
        {20.0F, 1, GpuGaussianEdgeMode::mirror, true, "gaussian over-wide-mirror"},
    };

    for (const Case& item : cases) {
        const std::vector<float> weights =
            GpuGaussianBlur::weights_for_sigma(item.sigma, item.minimum_support);
        if (kernel.dispatch(
                device, input, scratch, output, weights, item.edge_mode, item.blur_alpha) !=
            GpuKernelStatus::ok) {
            expect(false, "gaussian dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "gaussian download must succeed");
            continue;
        }
        const std::vector<Rgba32F> reference =
            reference_gaussian(source, weights, item.edge_mode, item.blur_alpha);
        report(
            label,
            item.what,
            static_cast<int>((weights.size() - 1U) / 2U),
            worst_delta(reference, gpu_pixels));
    }

    // 탭 수가 짝수면 중심이 없습니다 — 거절해야 합니다.
    const std::vector<float> even_weights = {0.5F, 0.5F};
    expect(
        kernel.dispatch(
            device,
            input,
            scratch,
            output,
            even_weights,
            GpuGaussianEdgeMode::clamp,
            false) == GpuKernelStatus::invalid_arguments,
        "an even tap count is rejected");
    // 같은 자원을 두 역할로 넘기면 D3D11 이 조용히 무시합니다.
    expect(
        kernel.dispatch(
            device,
            input,
            scratch,
            scratch,
            GpuGaussianBlur::weights_for_sigma(1.3F, 0),
            GpuGaussianEdgeMode::clamp,
            false) == GpuKernelStatus::invalid_arguments,
        "gaussian scratch and destination must differ");
    // 탭 하나는 흐림이 없습니다. 1 을 곱해도 반올림이 붙으므로 복사여야 합니다.
    const std::vector<float> single = {1.0F};
    if (kernel.dispatch(
            device, input, scratch, output, single, GpuGaussianEdgeMode::clamp, true) ==
        GpuKernelStatus::ok) {
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) == GpuImageStatus::ok) {
            expect(worst_delta(source, gpu_pixels) == 0.0F, "a single tap copies the source");
        } else {
            expect(false, "single tap download must succeed");
        }
    } else {
        expect(false, "a single tap dispatch must succeed");
    }
}

}  // namespace gpu_neighborhood_tests
