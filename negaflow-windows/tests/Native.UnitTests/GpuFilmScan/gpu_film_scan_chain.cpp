#include "gpu_film_scan_chain.h"

#include <algorithm>
#include <cmath>
#include <iostream>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_film_scan.h"
#include "negaflow/gpu/gpu_neighborhood.h"
#include "negaflow/gpu/gpu_working_image.h"

namespace gpu_film_scan_tests {
namespace {

using negaflow::gpu::GpuBoxBlur;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuFilmScanShrink;
using negaflow::gpu::GpuGammaLift;
using negaflow::gpu::GpuGaussianBlur;
using negaflow::gpu::GpuGaussianEdgeMode;
using negaflow::gpu::GpuGuidedFilter;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuMedian3;
using negaflow::gpu::GpuWorkingImage;

// `film_scan_denoise_tile.cpp:32` `make_tile` 과 같은 셈입니다.
struct TileRect final {
    std::uint32_t source_x;
    std::uint32_t source_y;
    std::uint32_t width;
    std::uint32_t height;
    std::uint32_t core_x;
    std::uint32_t core_y;
    std::uint32_t core_width;
    std::uint32_t core_height;
};

[[nodiscard]] TileRect make_tile(
    const std::uint32_t image_width,
    const std::uint32_t image_height,
    const std::uint32_t core_x,
    const std::uint32_t core_y) noexcept {
    const std::uint32_t side = negaflow::imaging::film_scan_denoise_tile_side;
    const std::uint32_t apron = negaflow::imaging::film_scan_denoise_tile_apron;
    const std::uint32_t core_width = std::min(side, image_width - core_x);
    const std::uint32_t core_height = std::min(side, image_height - core_y);
    const std::uint32_t source_x = core_x > apron ? core_x - apron : 0U;
    const std::uint32_t source_y = core_y > apron ? core_y - apron : 0U;
    const std::uint32_t source_right = std::min(image_width, core_x + core_width + apron);
    const std::uint32_t source_bottom = std::min(image_height, core_y + core_height + apron);
    return {
        source_x,
        source_y,
        source_right - source_x,
        source_bottom - source_y,
        core_x - source_x,
        core_y - source_y,
        core_width,
        core_height};
}

// 커널 한 벌입니다. 타일마다 다시 만들면 그 비용이 커널보다 큽니다.
struct Kernels final {
    GpuGammaLift lift{};
    GpuGaussianBlur gaussian{};
    GpuBoxBlur box{};
    GpuGuidedFilter guided{};
    GpuMedian3 median{};
    GpuFilmScanShrink shrink{};

    [[nodiscard]] bool create(const GpuDevice& device) {
        return GpuGammaLift::create(device, lift) == GpuKernelStatus::ok &&
               GpuGaussianBlur::create(device, gaussian) == GpuKernelStatus::ok &&
               GpuBoxBlur::create(device, box) == GpuKernelStatus::ok &&
               GpuGuidedFilter::create(device, guided) == GpuKernelStatus::ok &&
               GpuMedian3::create(device, median) == GpuKernelStatus::ok &&
               GpuFilmScanShrink::create(device, shrink) == GpuKernelStatus::ok;
    }
};

// 타일 하나(또는 이미지 전체)를 처리합니다. `film_scan_denoise_tile.cpp:72-83` 의 순서입니다.
[[nodiscard]] bool process_region(
    const GpuDevice& device,
    const Kernels& kernels,
    const std::vector<Rgba32F>& region,
    const std::uint32_t width,
    const std::uint32_t height,
    const negaflow::imaging::FilmScanDenoiseParameters& parameters,
    const LiftSource lift_source,
    std::vector<Rgba32F>& out) {
    GpuWorkingImage source{};
    if (GpuWorkingImage::upload(device, region.data(), width, height, width, source) !=
        GpuImageStatus::ok) {
        expect(false, "region upload must succeed");
        return false;
    }

    GpuWorkingImage lifted{};
    GpuWorkingImage fine{};
    GpuWorkingImage packed{};
    GpuWorkingImage middle{};
    GpuWorkingImage coarse{};
    GpuWorkingImage median_three{};
    GpuWorkingImage median_five{};
    GpuWorkingImage destination{};
    GpuWorkingImage scratch[GpuGuidedFilter::scratch_count]{};
    GpuWorkingImage* const singles[] = {
        &lifted, &fine, &packed, &middle, &coarse, &median_three, &median_five, &destination};
    for (GpuWorkingImage* const image : singles) {
        if (GpuWorkingImage::create(device, width, height, *image) != GpuImageStatus::ok) {
            expect(false, "region scratch must be creatable");
            return false;
        }
    }
    for (GpuWorkingImage& image : scratch) {
        if (GpuWorkingImage::create(device, width, height, image) != GpuImageStatus::ok) {
            expect(false, "guided scratch must be creatable");
            return false;
        }
    }

    // 1. 감마 리프트 (`extract_lifted_tile`).
    if (kernels.lift.dispatch(
            device, source, lifted, negaflow::imaging::film_scan_denoise_gamma_lift_power) !=
        GpuKernelStatus::ok) {
        expect(false, "gamma lift dispatch must succeed");
        return false;
    }
    if (lift_source == LiftSource::cpu) {
        // CPU 와 **같은 리프트**를 올려 나머지 커널만 남깁니다. 통과하면 이식이 맞은 것이고,
        // 그런데도 GPU 리프트 쪽이 크면 그 차이는 `pow` 하나입니다.
        std::vector<Rgba32F> cpu_lift(region.size());
        for (std::size_t index = 0U; index < region.size(); ++index) {
            const Rgba32F& pixel = region[index];
            const float power = negaflow::imaging::film_scan_denoise_gamma_lift_power;
            cpu_lift[index] = {
                std::pow(std::clamp(pixel.red, 0.0F, 1.0F), power),
                std::pow(std::clamp(pixel.green, 0.0F, 1.0F), power),
                std::pow(std::clamp(pixel.blue, 0.0F, 1.0F), power),
                pixel.alpha};
        }
        if (GpuWorkingImage::upload(device, cpu_lift.data(), width, height, width, lifted) !=
            GpuImageStatus::ok) {
            expect(false, "cpu lift upload must succeed");
            return false;
        }
    }

    // 2. 가우시안 σ 1.3 (`gaussian_blur(source)`). 가장자리는 클램프, 알파는 그대로.
    //    지원 반경 하한 0 은 `film_scan_denoise_filters.cpp` 가 `max(1, …)` 를 쓰지 않기
    //    때문입니다 — `texture_stage` 판과 다른 유일한 곳입니다.
    const std::vector<float> weights = GpuGaussianBlur::weights_for_sigma(
        negaflow::imaging::film_scan_denoise_gaussian_radius, 0);
    if (kernels.gaussian.dispatch(
            device, lifted, scratch[0], fine, weights, GpuGaussianEdgeMode::clamp, false) !=
        GpuKernelStatus::ok) {
        expect(false, "gaussian dispatch must succeed");
        return false;
    }

    // 3. guide = luminance(fine), 그리고 가이드 필터가 요구하는 묶음 `(source.rgb, guide)`.
    //    이 한 걸음만 호스트에서 합니다 — 전용 커널은 파이프라인을 붙일 때 만듭니다.
    std::vector<Rgba32F> lifted_pixels(region.size());
    std::vector<Rgba32F> fine_pixels(region.size());
    if (lifted.download(device, lifted_pixels.data(), width) != GpuImageStatus::ok ||
        fine.download(device, fine_pixels.data(), width) != GpuImageStatus::ok) {
        expect(false, "guide download must succeed");
        return false;
    }
    std::vector<Rgba32F> packed_pixels(region.size());
    for (std::size_t index = 0U; index < packed_pixels.size(); ++index) {
        const Rgba32F& blurred = fine_pixels[index];
        packed_pixels[index] = {
            lifted_pixels[index].red,
            lifted_pixels[index].green,
            lifted_pixels[index].blue,
            ((blurred.red * 0.2126F) + (blurred.green * 0.7152F)) + (blurred.blue * 0.0722F)};
    }
    if (GpuWorkingImage::upload(device, packed_pixels.data(), width, height, width, packed) !=
        GpuImageStatus::ok) {
        expect(false, "packed guide upload must succeed");
        return false;
    }

    // 4. 가이드 필터 두 반경.
    const float epsilon = negaflow::imaging::film_scan_denoise_guided_epsilon;
    if (kernels.guided.dispatch(
            device,
            kernels.box,
            packed,
            scratch,
            middle,
            negaflow::imaging::film_scan_denoise_guided_radius_middle,
            epsilon) != GpuKernelStatus::ok ||
        kernels.guided.dispatch(
            device,
            kernels.box,
            packed,
            scratch,
            coarse,
            negaflow::imaging::film_scan_denoise_guided_radius_coarse,
            epsilon) != GpuKernelStatus::ok) {
        expect(false, "guided dispatch must succeed");
        return false;
    }

    // 5. 중앙값 두 번.
    if (kernels.median.dispatch(device, lifted, median_three) != GpuKernelStatus::ok ||
        kernels.median.dispatch(device, median_three, median_five) != GpuKernelStatus::ok) {
        expect(false, "median dispatch must succeed");
        return false;
    }

    // 6. 수축 + 되돌리기.
    if (kernels.shrink.dispatch(
            device,
            lifted,
            median_three,
            median_five,
            fine,
            middle,
            coarse,
            destination,
            GpuFilmScanShrink::resolve(parameters)) != GpuKernelStatus::ok) {
        expect(false, "film scan shrink dispatch must succeed");
        return false;
    }

    out.resize(region.size());
    if (destination.download(device, out.data(), width) != GpuImageStatus::ok) {
        expect(false, "region download must succeed");
        return false;
    }
    return true;
}

}  // namespace

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

std::vector<Rgba32F> run_chain_whole_image(
    const GpuDevice& device,
    const std::vector<Rgba32F>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const negaflow::imaging::FilmScanDenoiseParameters& parameters,
    const LiftSource lift_source) {
    Kernels kernels{};
    if (!kernels.create(device)) {
        expect(false, "film scan kernels must be creatable");
        return {};
    }
    std::vector<Rgba32F> result{};
    if (!process_region(
            device, kernels, source, width, height, parameters, lift_source, result)) {
        return {};
    }
    return result;
}

std::vector<Rgba32F> run_chain(
    const GpuDevice& device,
    const std::vector<Rgba32F>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const negaflow::imaging::FilmScanDenoiseParameters& parameters,
    const LiftSource lift_source) {
    Kernels kernels{};
    if (!kernels.create(device)) {
        expect(false, "film scan kernels must be creatable");
        return {};
    }

    std::vector<Rgba32F> result(source.size());
    const std::uint32_t side = negaflow::imaging::film_scan_denoise_tile_side;
    std::vector<Rgba32F> region{};
    std::vector<Rgba32F> processed{};
    for (std::uint32_t core_y = 0U; core_y < height; core_y += side) {
        for (std::uint32_t core_x = 0U; core_x < width; core_x += side) {
            const TileRect tile = make_tile(width, height, core_x, core_y);
            region.resize(static_cast<std::size_t>(tile.width) * tile.height);
            for (std::uint32_t y = 0U; y < tile.height; ++y) {
                for (std::uint32_t x = 0U; x < tile.width; ++x) {
                    region[(static_cast<std::size_t>(y) * tile.width) + x] =
                        source[(static_cast<std::size_t>(tile.source_y + y) * width) +
                               tile.source_x + x];
                }
            }
            if (!process_region(
                    device,
                    kernels,
                    region,
                    tile.width,
                    tile.height,
                    parameters,
                    lift_source,
                    processed)) {
                return {};
            }
            // core 만 옮겨 씁니다. 에이프런은 버립니다 — CPU 도 그렇게 합니다.
            for (std::uint32_t y = 0U; y < tile.core_height; ++y) {
                for (std::uint32_t x = 0U; x < tile.core_width; ++x) {
                    result[(static_cast<std::size_t>(core_y + y) * width) + core_x + x] =
                        processed
                            [(static_cast<std::size_t>(tile.core_y + y) * tile.width) +
                             tile.core_x + x];
                }
            }
        }
    }
    return result;
}

}  // namespace gpu_film_scan_tests
