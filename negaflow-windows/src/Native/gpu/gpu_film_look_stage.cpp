#include "negaflow/gpu/gpu_film_look_stage.h"

#include <new>

#include "negaflow/gpu/gpu_color_kernels.h"
#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_digital_film_color_preset.h"
#include "negaflow/gpu/gpu_digital_film_grain.h"
#include "negaflow/gpu/gpu_digital_halation.h"
#include "negaflow/gpu/gpu_film_emulation_acutance.h"
#include "negaflow/gpu/gpu_film_emulation_cube.h"
#include "negaflow/gpu/gpu_image_pool.h"
#include "negaflow/gpu/gpu_neighborhood.h"
#include "negaflow/gpu/gpu_working_image.h"

namespace negaflow::gpu {
namespace {

constexpr int scratch_first = GpuImagePool::scratch_first;

} // namespace

struct GpuFilmLookStage::State final {
    GpuGaussianBlur gaussian{};
    GpuDigitalHalation halation{};
    GpuFilmEmulationCube cube{};
    GpuFilmEmulationAcutance acutance{};
    GpuDigitalFilmColorPreset preset{};
    GpuDigitalFilmGrain grain{};
    GpuDigitalBwFilm bw_emulsion{};

};

GpuFilmLookStage::~GpuFilmLookStage() {
    delete state_;
    state_ = nullptr;
}

GpuKernelStatus GpuFilmLookStage::create(
    const GpuDevice& device,
    GpuFilmLookStage& stage) noexcept {
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
        GpuGaussianBlur::create(device, state->gaussian) == GpuKernelStatus::ok &&
        GpuDigitalHalation::create(device, state->halation) == GpuKernelStatus::ok &&
        GpuFilmEmulationCube::create(device, state->cube) == GpuKernelStatus::ok &&
        GpuFilmEmulationAcutance::create(device, state->acutance) == GpuKernelStatus::ok &&
        GpuDigitalFilmColorPreset::create(device, state->preset) == GpuKernelStatus::ok &&
        GpuDigitalFilmGrain::create(device, state->grain) == GpuKernelStatus::ok &&
        GpuDigitalBwFilm::create(device, state->bw_emulsion) == GpuKernelStatus::ok;
    if (!made) {
        delete state;
        return GpuKernelStatus::resource_creation_failed;
    }
    stage.state_ = state;
    return GpuKernelStatus::ok;
}

GpuFilmLookResult GpuFilmLookStage::apply(
    const GpuDevice& device,
    GpuImagePool& pool_holder,
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const imaging::DigitalFilmLookPlan& plan) const noexcept {
    GpuFilmLookResult result{};
    if (state_ == nullptr || !device.is_usable() || pixels == nullptr) {
        return result;
    }
    if (width == 0U || height == 0U || stride_pixels < width) {
        return result;
    }
    if (!pool_holder.ensure(device, width, height)) {
        return result;
    }

    auto* const rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    GpuWorkingImage* const pool = pool_holder.images();
    if (pool[0].upload_into(device, rgba, stride_pixels) != GpuImageStatus::ok) {
        return result;
    }
    // 지금 결과가 들어 있는 칸. 스크래치를 쓰는 단계는 이것이 0 이나 1 일 때만 옵니다
    // (사슬 순서상 색 프리셋 뒤에는 그레인만 남고, 그레인은 스크래치를 안 씁니다).
    int read = 0;
    const auto other = [&read]() noexcept { return read == 0 ? 1 : 0; };

    if (plan.halation_requested) {
        const GpuDigitalHalation::Parameters parameters = GpuDigitalHalation::resolve(
            plan.halation_material, plan.halation_strength, width, height);
        if (parameters.applied) {
            const int destination = other();
            if (state_->halation.dispatch(
                    device,
                    state_->gaussian,
                    pool[read],
                    &pool[scratch_first],
                    pool[destination],
                    parameters) != GpuKernelStatus::ok) {
                return result;
            }
            read = destination;
            result.applied.halation = true;
        }
    }

    if (plan.cube != nullptr) {
        const int destination = other();
        if (state_->cube.dispatch(device, pool[read], pool[destination], *plan.cube) !=
            GpuKernelStatus::ok) {
            return result;
        }
        read = destination;
        result.applied.color = true;
    }

    if (plan.acutance.applied) {
        const int destination = other();
        if (state_->acutance.dispatch(
                device,
                pool[read],
                &pool[scratch_first],
                pool[destination],
                plan.acutance) != GpuKernelStatus::ok) {
            return result;
        }
        read = destination;
        result.applied.acutance = true;
    }

    if (plan.preset != nullptr) {
        // 결과가 스크래치 두 칸 중 어디에 들어가는지는 프리셋이 무엇을 바꾸는지에
        // 따라 달라집니다. 그래서 어느 칸인지 돌려받아 그것을 다음 입력으로 씁니다.
        const GpuWorkingImage* preset_result = nullptr;
        if (state_->preset.dispatch(
                device,
                pool[read],
                &pool[scratch_first],
                preset_result,
                *plan.preset,
                plan.preset_strength) != GpuKernelStatus::ok ||
            preset_result == nullptr) {
            return result;
        }
        read = preset_result == &pool[scratch_first] ? scratch_first : scratch_first + 1;
        result.applied.preset = true;
    }

    if (plan.grain_requested) {
        const GpuDigitalFilmGrain::Parameters parameters =
            GpuDigitalFilmGrain::resolve(plan.grain, plan.grain_strength);
        if (parameters.applied) {
            // 색 프리셋 뒤에는 `read` 가 2 나 3 일 수 있습니다. 목적지는 늘 비어 있는
            // 핑퐁 칸 0 입니다 — 그레인은 스크래치를 쓰지 않으므로 충돌이 없습니다.
            const int destination = read == 0 ? 1 : 0;
            if (state_->grain.dispatch(
                    device, pool[read], pool[destination], parameters) !=
                GpuKernelStatus::ok) {
                return result;
            }
            read = destination;
            result.applied.grain = true;
        }
    }

    if (pool[read].download(device, rgba, stride_pixels) != GpuImageStatus::ok) {
        return result;
    }
    result.handled = true;
    return result;
}

GpuFilmLookStage::BwResult GpuFilmLookStage::apply_bw(
    const GpuDevice& device,
    GpuImagePool& pool_holder,
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const imaging::DigitalBwFilmLookPlan& plan) const noexcept {
    BwResult result{};
    if (state_ == nullptr || !device.is_usable() || pixels == nullptr) {
        return result;
    }
    if (width == 0U || height == 0U || stride_pixels < width) {
        return result;
    }
    if (!pool_holder.ensure(device, width, height)) {
        return result;
    }

    auto* const rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    GpuWorkingImage* const pool = pool_holder.images();
    if (pool[0].upload_into(device, rgba, stride_pixels) != GpuImageStatus::ok) {
        return result;
    }
    int read = 0;
    const auto other = [&read]() noexcept { return read == 0 ? 1 : 0; };

    if (plan.halation_requested) {
        const GpuDigitalHalation::Parameters parameters = GpuDigitalHalation::resolve(
            plan.halation_material, plan.halation_strength, width, height);
        if (parameters.applied) {
            const int destination = other();
            if (state_->halation.dispatch(
                    device,
                    state_->gaussian,
                    pool[read],
                    &pool[scratch_first],
                    pool[destination],
                    parameters) != GpuKernelStatus::ok) {
                return result;
            }
            read = destination;
            result.applied.halation = true;
        }
    }

    if (plan.emulsion.active) {
        const int destination = other();
        GpuDigitalBwFilmSetup setup{};
        for (int index = 0; index < 3; ++index) {
            setup.weights[index] = plan.emulsion.weights[index];
        }
        setup.contrast = plan.emulsion.contrast;
        setup.toe = plan.emulsion.toe;
        setup.shoulder = plan.emulsion.shoulder;
        setup.deepen = plan.emulsion.deepen;
        setup.black = plan.emulsion.black;
        setup.white = plan.emulsion.white;
        setup.intensity = plan.emulsion.intensity;
        setup.active = plan.emulsion.active;
        if (state_->bw_emulsion.dispatch(device, pool[read], pool[destination], setup) !=
            GpuKernelStatus::ok) {
            return result;
        }
        read = destination;
        result.applied.emulsion = true;
    }

    if (plan.acutance.applied) {
        const int destination = other();
        if (state_->acutance.dispatch(
                device,
                pool[read],
                &pool[scratch_first],
                pool[destination],
                plan.acutance) != GpuKernelStatus::ok) {
            return result;
        }
        read = destination;
        result.applied.acutance = true;
    }

    if (plan.grain_requested) {
        const GpuDigitalFilmGrain::Parameters parameters =
            GpuDigitalFilmGrain::resolve(plan.grain, plan.grain_strength);
        if (parameters.applied) {
            const int destination = read == 0 ? 1 : 0;
            if (state_->grain.dispatch(
                    device, pool[read], pool[destination], parameters) !=
                GpuKernelStatus::ok) {
                return result;
            }
            read = destination;
            result.applied.grain = true;
        }
    }

    if (pool[read].download(device, rgba, stride_pixels) != GpuImageStatus::ok) {
        return result;
    }
    result.handled = true;
    return result;
}

} // namespace negaflow::gpu
