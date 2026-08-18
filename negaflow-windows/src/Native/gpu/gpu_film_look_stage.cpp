#include "negaflow/gpu/gpu_film_look_stage.h"

#include <new>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_digital_film_color_preset.h"
#include "negaflow/gpu/gpu_digital_film_grain.h"
#include "negaflow/gpu/gpu_digital_halation.h"
#include "negaflow/gpu/gpu_film_emulation_acutance.h"
#include "negaflow/gpu/gpu_film_emulation_cube.h"
#include "negaflow/gpu/gpu_neighborhood.h"
#include "negaflow/gpu/gpu_working_image.h"

namespace negaflow::gpu {
namespace {

// 핑퐁 둘 + 스크래치 넷. 헐레이션이 스크래치 넷을 한꺼번에 쓰므로 그것이 최대치입니다.
constexpr int pool_size = 6;
constexpr int scratch_first = 2;

}  // namespace

struct GpuFilmLookStage::State final {
    GpuGaussianBlur gaussian{};
    GpuDigitalHalation halation{};
    GpuFilmEmulationCube cube{};
    GpuFilmEmulationAcutance acutance{};
    GpuDigitalFilmColorPreset preset{};
    GpuDigitalFilmGrain grain{};

    // 크기가 바뀔 때만 다시 만듭니다. 프레임마다 만들면 그 비용이 커널보다 큽니다.
    mutable GpuWorkingImage pool[pool_size]{};
    mutable std::uint32_t width{0U};
    mutable std::uint32_t height{0U};

    [[nodiscard]] bool ensure_pool(
        const GpuDevice& device,
        const std::uint32_t needed_width,
        const std::uint32_t needed_height) const noexcept {
        if (pool[0].is_valid() && width == needed_width && height == needed_height) {
            return true;
        }
        for (int index = 0; index < pool_size; ++index) {
            if (GpuWorkingImage::create(device, needed_width, needed_height, pool[index]) !=
                GpuImageStatus::ok) {
                // 못 잡으면 전부 놓습니다 — 반쯤 잡은 상태로 두면 다음 호출이
                // 크기가 맞는다고 믿고 씁니다.
                for (int reset = 0; reset < pool_size; ++reset) {
                    pool[reset] = GpuWorkingImage{};
                }
                width = 0U;
                height = 0U;
                return false;
            }
        }
        width = needed_width;
        height = needed_height;
        return true;
    }
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
        GpuDigitalFilmGrain::create(device, state->grain) == GpuKernelStatus::ok;
    if (!made) {
        delete state;
        return GpuKernelStatus::resource_creation_failed;
    }
    stage.state_ = state;
    return GpuKernelStatus::ok;
}

GpuFilmLookResult GpuFilmLookStage::apply(
    const GpuDevice& device,
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
    if (!state_->ensure_pool(device, width, height)) {
        return result;
    }

    auto* const rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    GpuWorkingImage* const pool = state_->pool;
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
        // ☠️ 결과가 스크래치 두 칸 중 어디에 들어가는지는 프리셋이 무엇을 바꾸는지에
        //    따라 달라집니다. 그래서 어느 칸인지 돌려받아 그것을 다음 입력으로 씁니다.
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

}  // namespace negaflow::gpu
