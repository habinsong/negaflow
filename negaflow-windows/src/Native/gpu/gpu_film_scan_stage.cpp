#include "negaflow/gpu/gpu_film_scan_stage.h"

#include <algorithm>
#include <new>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_film_scan.h"
#include "negaflow/gpu/gpu_neighborhood.h"
#include "negaflow/gpu/gpu_working_image.h"

namespace negaflow::gpu {
namespace {

using negaflow::core::Rgba32F;

// `film_scan_denoise_tile.cpp:32` `make_tile` 과 같은 셈입니다. 숫자는 공개 상수를 씁니다.
struct TileRect final {
    std::uint32_t source_x{0U};
    std::uint32_t source_y{0U};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::uint32_t core_x{0U};
    std::uint32_t core_y{0U};
    std::uint32_t core_width{0U};
    std::uint32_t core_height{0U};
};

[[nodiscard]] TileRect make_tile(
    const std::uint32_t image_width,
    const std::uint32_t image_height,
    const std::uint32_t core_x,
    const std::uint32_t core_y) noexcept {
    const std::uint32_t side = imaging::film_scan_denoise_tile_side;
    const std::uint32_t apron = imaging::film_scan_denoise_tile_apron;
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

} // namespace

// 커널 한 벌과 타일 크기의 중간 텍스처들입니다. 타일 크기는 이미지마다 최대 네 가지
// (안쪽·오른쪽 끝·아래쪽 끝·모서리)뿐이라, 크기가 바뀔 때만 다시 만듭니다.
struct GpuFilmScanDenoiseStage::State final {
    GpuGammaLift lift{};
    GpuGaussianBlur gaussian{};
    GpuBoxBlur box{};
    GpuGuidedFilter guided{};
    GpuMedian3 median{};
    GpuGuidePack pack{};
    GpuFilmScanShrink shrink{};

    static constexpr int guided_scratch = GpuGuidedFilter::scratch_count;

    mutable GpuWorkingImage source{};
    mutable GpuWorkingImage lifted{};
    mutable GpuWorkingImage fine{};
    mutable GpuWorkingImage packed{};
    mutable GpuWorkingImage middle{};
    mutable GpuWorkingImage coarse{};
    mutable GpuWorkingImage median_three{};
    mutable GpuWorkingImage median_five{};
    mutable GpuWorkingImage destination{};
    mutable GpuWorkingImage scratch[guided_scratch]{};
    mutable std::uint32_t width{0U};
    mutable std::uint32_t height{0U};
    mutable std::vector<Rgba32F> host_tile{};

    [[nodiscard]] bool ensure_tile(
        const GpuDevice& device,
        const std::uint32_t tile_width,
        const std::uint32_t tile_height) const noexcept {
        if (source.is_valid() && width == tile_width && height == tile_height) {
            return true;
        }
        GpuWorkingImage* const singles[] = {
            &source, &lifted, &fine, &packed, &middle,
            &coarse, &median_three, &median_five, &destination};
        for (GpuWorkingImage* const image : singles) {
            if (GpuWorkingImage::create(device, tile_width, tile_height, *image) !=
                GpuImageStatus::ok) {
                width = 0U;
                height = 0U;
                return false;
            }
        }
        for (GpuWorkingImage& image : scratch) {
            if (GpuWorkingImage::create(device, tile_width, tile_height, image) !=
                GpuImageStatus::ok) {
                width = 0U;
                height = 0U;
                return false;
            }
        }
        width = tile_width;
        height = tile_height;
        return true;
    }
};

GpuFilmScanDenoiseStage::~GpuFilmScanDenoiseStage() {
    delete state_;
    state_ = nullptr;
}

GpuKernelStatus GpuFilmScanDenoiseStage::create(
    const GpuDevice& device,
    GpuFilmScanDenoiseStage& stage) noexcept {
    delete stage.state_;
    stage.state_ = nullptr;
    if (!device.is_usable()) {
        return GpuKernelStatus::device_unavailable;
    }
    auto* const state = new (std::nothrow) State{};
    if (state == nullptr) {
        return GpuKernelStatus::resource_creation_failed;
    }
    const bool made =
        GpuGammaLift::create(device, state->lift) == GpuKernelStatus::ok &&
        GpuGaussianBlur::create(device, state->gaussian) == GpuKernelStatus::ok &&
        GpuBoxBlur::create(device, state->box) == GpuKernelStatus::ok &&
        GpuGuidedFilter::create(device, state->guided) == GpuKernelStatus::ok &&
        GpuMedian3::create(device, state->median) == GpuKernelStatus::ok &&
        GpuGuidePack::create(device, state->pack) == GpuKernelStatus::ok &&
        GpuFilmScanShrink::create(device, state->shrink) == GpuKernelStatus::ok;
    if (!made) {
        delete state;
        return GpuKernelStatus::resource_creation_failed;
    }
    stage.state_ = state;
    return GpuKernelStatus::ok;
}

GpuFilmScanDenoiseResult GpuFilmScanDenoiseStage::apply(
    const GpuDevice& device,
    imaging::WorkingImage& image,
    const imaging::FilmScanDenoiseParameters& parameters) const noexcept {
    GpuFilmScanDenoiseResult result{};
    if (state_ == nullptr || !device.is_usable()) {
        return result;
    }
    // 검증도 조기 반환도 CPU 판과 **같은 함수·같은 상수**를 씁니다.
    if (!imaging::valid_film_scan_denoise_parameters(parameters)) {
        return result;
    }
    if (image.width == 0U || image.height == 0U || image.stride_pixels < image.width) {
        return result;
    }
    const negaflow::core::ConstImageView view{
        image.pixels.data(), image.pixels.size(), image.width, image.height,
        image.stride_pixels};
    if (negaflow::core::validate_finite_pixels(view) != negaflow::core::KernelStatus::ok) {
        // CPU 판이 같은 판정으로 실패 처리합니다. 그쪽에 맡깁니다.
        return result;
    }
    if (parameters.strength <= imaging::film_scan_denoise_identity_threshold) {
        // 세기가 임계 아래면 CPU 는 원본을 그대로 냅니다. 올릴 이유가 없습니다.
        result.handled = true;
        result.status = imaging::FilmScanDenoiseStatus::ok;
        result.info.kernel_status = negaflow::core::KernelStatus::ok;
        return result;
    }

    const GpuFilmScanShrink::Parameters resolved = GpuFilmScanShrink::resolve(parameters);
    const std::vector<float> weights = GpuGaussianBlur::weights_for_sigma(
        imaging::film_scan_denoise_gaussian_radius, 0);
    const float epsilon = imaging::film_scan_denoise_guided_epsilon;
    const float lift_power = imaging::film_scan_denoise_gamma_lift_power;

    // 결과는 **원본과 따로** 모읍니다. CPU 도 그렇게 합니다 — 타일이 원본을 읽는
    // 동안 다른 타일이 그 자리를 덮으면 에이프런이 오염됩니다.
    std::vector<Rgba32F> output{};
    try {
        output.assign(
            static_cast<std::size_t>(image.width) * static_cast<std::size_t>(image.height),
            Rgba32F{});
    } catch (...) {
        return result;
    }

    const std::uint32_t side = imaging::film_scan_denoise_tile_side;
    std::uint32_t tiles = 0U;
    for (std::uint32_t core_y = 0U; core_y < image.height; core_y += side) {
        for (std::uint32_t core_x = 0U; core_x < image.width; core_x += side) {
            const TileRect tile = make_tile(image.width, image.height, core_x, core_y);
            if (!state_->ensure_tile(device, tile.width, tile.height)) {
                return result;
            }

            try {
                state_->host_tile.resize(
                    static_cast<std::size_t>(tile.width) * tile.height);
            } catch (...) {
                return result;
            }
            for (std::uint32_t y = 0U; y < tile.height; ++y) {
                const Rgba32F* const row = image.pixels.data() +
                    (static_cast<std::size_t>(tile.source_y + y) * image.stride_pixels);
                Rgba32F* const destination_row =
                    state_->host_tile.data() + (static_cast<std::size_t>(y) * tile.width);
                for (std::uint32_t x = 0U; x < tile.width; ++x) {
                    destination_row[x] = row[tile.source_x + x];
                }
            }
            if (state_->source.upload_into(
                    device, state_->host_tile.data(), tile.width) != GpuImageStatus::ok) {
                return result;
            }

            // `film_scan_denoise_tile.cpp:72-83` 과 같은 순서입니다.
            if (state_->lift.dispatch(
                    device, state_->source, state_->lifted, lift_power) !=
                GpuKernelStatus::ok) {
                return result;
            }
            if (state_->gaussian.dispatch(
                    device,
                    state_->lifted,
                    state_->scratch[0],
                    state_->fine,
                    weights,
                    GpuGaussianEdgeMode::clamp,
                    false) != GpuKernelStatus::ok) {
                return result;
            }
            if (state_->pack.dispatch(
                    device, state_->lifted, state_->fine, state_->packed) !=
                GpuKernelStatus::ok) {
                return result;
            }
            if (state_->guided.dispatch(
                    device,
                    state_->box,
                    state_->packed,
                    state_->scratch,
                    state_->middle,
                    imaging::film_scan_denoise_guided_radius_middle,
                    epsilon) != GpuKernelStatus::ok ||
                state_->guided.dispatch(
                    device,
                    state_->box,
                    state_->packed,
                    state_->scratch,
                    state_->coarse,
                    imaging::film_scan_denoise_guided_radius_coarse,
                    epsilon) != GpuKernelStatus::ok) {
                return result;
            }
            if (state_->median.dispatch(device, state_->lifted, state_->median_three) !=
                    GpuKernelStatus::ok ||
                state_->median.dispatch(
                    device, state_->median_three, state_->median_five) !=
                    GpuKernelStatus::ok) {
                return result;
            }
            if (state_->shrink.dispatch(
                    device,
                    state_->lifted,
                    state_->median_three,
                    state_->median_five,
                    state_->fine,
                    state_->middle,
                    state_->coarse,
                    state_->destination,
                    resolved) != GpuKernelStatus::ok) {
                return result;
            }
            if (state_->destination.download(
                    device, state_->host_tile.data(), tile.width) != GpuImageStatus::ok) {
                return result;
            }

            // core 만 옮겨 씁니다. 에이프런은 버립니다 — CPU 도 그렇게 합니다.
            for (std::uint32_t y = 0U; y < tile.core_height; ++y) {
                const Rgba32F* const source_row = state_->host_tile.data() +
                    (static_cast<std::size_t>(tile.core_y + y) * tile.width);
                Rgba32F* const destination_row = output.data() +
                    (static_cast<std::size_t>(core_y + y) * image.width);
                for (std::uint32_t x = 0U; x < tile.core_width; ++x) {
                    destination_row[core_x + x] = source_row[tile.core_x + x];
                }
            }
            ++tiles;
        }
    }

    // 알파는 CPU 가 손대지 않습니다 — `film_scan_denoise.cpp:156` 은 rgb 만 씁니다.
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        Rgba32F* const row =
            image.pixels.data() + (static_cast<std::size_t>(y) * image.stride_pixels);
        const Rgba32F* const source_row =
            output.data() + (static_cast<std::size_t>(y) * image.width);
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            row[x].red = source_row[x].red;
            row[x].green = source_row[x].green;
            row[x].blue = source_row[x].blue;
        }
    }

    result.handled = true;
    result.status = imaging::FilmScanDenoiseStatus::ok;
    result.info.applied = true;
    result.info.tiles_processed = tiles;
    result.info.kernel_status = negaflow::core::KernelStatus::ok;
    return result;
}

} // namespace negaflow::gpu
