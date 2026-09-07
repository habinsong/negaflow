#include "negaflow/pipeline/gpu_accelerator.h"

#include "gpu_accelerator_state.h"

#include <chrono>
#include <cstdlib>
#include <ctime>
#include <io.h>
#include <mutex>
#include <new>

namespace negaflow::pipeline {


namespace {

[[nodiscard]] bool gpu_disabled_by_environment() noexcept {
    // `NEGA_GPU=0` 이면 GPU 를 아예 열지 않습니다. 문제를 가를 때와 전후를 잴 때 씁니다 —
    // 코드를 고쳐 끄면 무엇을 껐는지 기록이 안 남습니다.
    char value[8]{};
    std::size_t length = 0U;
    if (getenv_s(&length, value, sizeof(value), "NEGA_GPU") != 0 || length == 0U) {
        return false;
    }
    return value[0] == 48;  // 48 == 0
}

/// GPU 초기화 단계를 한 줄씩 남깁니다. `NEGA_GPU_INIT_TRACE=<경로>` 일 때만 씁니다.
///
/// **디스크까지 밀어넣습니다.** 실기에서 이 자리를 지나다 기기 전원이 통째로 끊겼고, 그때
/// 다른 로그는 파일 크기와 수정 시각만 남고 내용이 하나도 남지 않았습니다 - 버퍼에 있던
/// 것이 그대로 사라졌기 때문입니다. 여기서는 그러면 아무것도 못 건집니다. 그래서 줄마다
/// 열고 쓰고 `FlushFileBuffers` 까지 부르고 닫습니다. 느리지만, 느린 것이 이 계측의 값입니다.
void gpu_init_step(const char* what) noexcept {
    char path[512]{};
    std::size_t length = 0U;
    if (getenv_s(&length, path, sizeof(path), "NEGA_GPU_INIT_TRACE") != 0 || length == 0U) {
        return;
    }
    std::FILE* file = nullptr;
    if (fopen_s(&file, path, "a") != 0 || file == nullptr) {
        return;
    }
    const auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    std::tm parts{};
    (void)localtime_s(&parts, &now);
    (void)std::fprintf(file, "%02d:%02d:%02d %s\n", parts.tm_hour, parts.tm_min, parts.tm_sec, what);
    (void)std::fflush(file);
    const int descriptor = _fileno(file);
    if (descriptor >= 0) {
        (void)_commit(descriptor);
    }
    (void)std::fclose(file);
}

}  // namespace

GpuAccelerator::GpuAccelerator() noexcept {
    auto* const state = new (std::nothrow) State{};
    if (state == nullptr) {
        return;
    }
    if (gpu_disabled_by_environment()) {
        state_ = state;
        return;
    }
    // `automatic` — 하드웨어를 먼저 찾고 없으면 WARP 입니다. 벤더로 거르지 않습니다.
    gpu_init_step("device create begin");
    state->device = gpu::GpuDevice::create(gpu::GpuDevicePreference::automatic);
    gpu_init_step(state->device.is_usable() ? "device create ok" : "device create unusable");
    if (state->device.is_usable() &&
        gpu::GpuToneStage::create(state->device, state->tone) == gpu::GpuKernelStatus::ok &&
        gpu::GpuFilmScanDenoiseStage::create(state->device, state->denoise) ==
            gpu::GpuKernelStatus::ok) {
        gpu_init_step("usable begin");
        state->usable = true;
        gpu_init_step("custom_color_target_ready begin");
        state->custom_color_target_ready =
            gpu::GpuCustomColorTarget::create(state->device, state->custom_color_target) ==
            gpu::GpuKernelStatus::ok;
        gpu_init_step("adapter begin");
        state->adapter = state->device.capability().adapter.description.data();
        // 형태학은 따로 만듭니다. 이것만 실패해도 톤·디노이즈는 그대로 돕니다.
        gpu_init_step("morphology_ready begin");
        state->morphology_ready =
            gpu::GpuMorphology::create(state->device, state->morphology) ==
            gpu::GpuKernelStatus::ok;
        // 반전은 현상에서 가장 비싼 단계입니다(실측 41%). 따로 만들어 이것만 실패해도
        // 나머지가 그대로 돌게 합니다.
        gpu_init_step("invert_ready begin");
        state->invert_ready =
            gpu::GpuNegativeInvert::create(state->device, state->invert) ==
            gpu::GpuKernelStatus::ok;
        gpu_init_step("halation_ready begin");
        state->halation_ready =
            gpu::GpuGaussianBlur::create(state->device, state->gaussian) ==
                gpu::GpuKernelStatus::ok &&
            gpu::GpuDigitalHalation::create(state->device, state->halation) ==
                gpu::GpuKernelStatus::ok;
        gpu_init_step("grain_ready begin");
        state->grain_ready =
            gpu::GpuDigitalFilmGrain::create(state->device, state->grain) ==
            gpu::GpuKernelStatus::ok;
        gpu_init_step("preset_ready begin");
        state->preset_ready =
            gpu::GpuDigitalFilmColorPreset::create(state->device, state->preset) ==
            gpu::GpuKernelStatus::ok;
        gpu_init_step("cube_ready begin");
        state->cube_ready =
            gpu::GpuFilmEmulationCube::create(state->device, state->cube) ==
            gpu::GpuKernelStatus::ok;
        gpu_init_step("acutance_ready begin");
        state->acutance_ready =
            gpu::GpuFilmEmulationAcutance::create(state->device, state->acutance) ==
            gpu::GpuKernelStatus::ok;
        gpu_init_step("film_look_ready begin");
        state->film_look_ready =
            gpu::GpuFilmLookStage::create(state->device, state->film_look) ==
            gpu::GpuKernelStatus::ok;
        gpu_init_step("vibrance_ready begin");
        state->vibrance_ready =
            gpu::GpuVibranceTable::create(state->device, state->vibrance_table) ==
                gpu::GpuKernelStatus::ok &&
            gpu::GpuMutedSceneVibrance::create(state->device, state->muted_vibrance) ==
                gpu::GpuKernelStatus::ok &&
            gpu::GpuColorModel::create(state->device, state->color_model) ==
                gpu::GpuKernelStatus::ok;
        gpu_init_step("target_grade_ready begin");
        state->target_grade_ready =
            gpu::GpuScannerTargetGrade::create(state->device, state->target_grade) ==
            gpu::GpuKernelStatus::ok;
        gpu_init_step("noritsu_texture_ready begin");
        state->noritsu_texture_ready =
            gpu::GpuNoritsuTexture::create(state->device, state->noritsu_texture) ==
            gpu::GpuKernelStatus::ok;
        gpu_init_step("texture_grain_ready begin");
        state->texture_grain_ready =
            gpu::GpuTextureGrain::create(state->device, state->texture_grain) ==
            gpu::GpuKernelStatus::ok;
        gpu_init_step("clipping_overlay_ready begin");
        state->clipping_overlay_ready =
            gpu::GpuChannelClippingOverlay::create(
                state->device, state->clipping_overlay) ==
            gpu::GpuKernelStatus::ok;
        gpu_init_step("area_average_ready begin");
        state->area_average_ready =
            gpu::GpuAreaAverage::create(state->device, state->area_average) ==
            gpu::GpuKernelStatus::ok;
        gpu_init_step("scene_correction_ready begin");
        state->scene_correction_ready =
            gpu::GpuSceneCorrection::create(state->device, state->scene_correction) ==
            gpu::GpuKernelStatus::ok;
        gpu_init_step("mip_halve_ready begin");
        state->mip_halve_ready =
            gpu::GpuMipHalve::create(state->device, state->mip_halve) ==
            gpu::GpuKernelStatus::ok;
        gpu_init_step("scratch_angle_ready begin");
        state->scratch_angle_ready =
            gpu::GpuScratchAngle::create(state->device, state->scratch_angle) ==
            gpu::GpuKernelStatus::ok;
        gpu_init_step("finite_ready begin");
        state->finite_ready =
            gpu::GpuFiniteCheck::create(state->device, state->finite) ==
            gpu::GpuKernelStatus::ok;
        gpu_init_step("preview_encode_ready begin");
        state->preview_encode_ready =
            gpu::GpuPreviewDisplayEncode::create(
                state->device, state->preview_encode) ==
            gpu::GpuKernelStatus::ok;
    }
    state_ = state;
}

GpuAccelerator::~GpuAccelerator() {
    delete state_;
    state_ = nullptr;
}

GpuAccelerator& GpuAccelerator::shared() noexcept {
    // 함수 지역 정적이라 첫 사용 때 한 번만 만들어지고, 초기화가 스레드 안전합니다.
    static GpuAccelerator accelerator{};
    return accelerator;
}

bool GpuAccelerator::available() const noexcept {
    return state_ != nullptr && state_->usable;
}

const gpu::GpuDevice& GpuAccelerator::device() const noexcept {
    return state_->device;
}

const char* GpuAccelerator::adapter_description() const noexcept {
    return state_ != nullptr ? state_->adapter : "";
}

GpuToneOutcome GpuAccelerator::apply_working_tone_adjustments(
    const GpuUsePolicy policy,
    imaging::WorkingImage& image,
    const imaging::WorkingToneAdjustParameters& parameters,
    const imaging::ToneCurveMeasurementLimits& measurement_limits) noexcept {
    GpuToneOutcome outcome{};
    if (policy != GpuUsePolicy::allowed || !available()) {
        return outcome;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    gpu::GpuToneStageResult result{};
    if (state_->resident_matches(image.pixels.data(), image.width, image.height) &&
        state_->pool.images()[0].is_valid() && state_->pool.images()[1].is_valid()) {
        gpu::GpuWorkingImage* const pool = state_->pool.images();
        const int read = state_->resident.read_slot;
        const int write = 1 - read;
        result = state_->tone.apply_on(
            state_->device,
            pool[read],
            pool[write],
            image,
            parameters,
            measurement_limits,
            false);
        if (result.handled) {
            int applied = 0;
            if (result.info.exposure_applied) {
                ++applied;
            }
            if (result.info.basic_tone_applied) {
                ++applied;
            }
            if (result.info.parametric_curve_applied) {
                ++applied;
            }
            if (result.info.point_curve_applied) {
                ++applied;
            }
            if (result.info.color_mixer_applied) {
                ++applied;
            }
            if (result.info.color_grading_applied) {
                ++applied;
            }
            if (result.info.primary_calibration_applied) {
                ++applied;
            }
            const int slot = (applied % 2 == 0) ? read : write;
            state_->bind_resident(
                image.pixels.data(), image.width, image.height, image.stride_pixels, slot);
        }
    } else {
        result = state_->tone.apply(state_->device, image, parameters, measurement_limits);
    }
    if (!result.handled || result.status != imaging::WorkingToneAdjustStatus::ok) {
        return outcome;
    }
    outcome.handled = true;
    outcome.info = result.info;
    return outcome;
}

GpuDenoiseOutcome GpuAccelerator::apply_film_scan_denoise(
    const GpuUsePolicy policy,
    imaging::WorkingImage& image,
    const imaging::FilmScanDenoiseParameters& parameters) noexcept {
    GpuDenoiseOutcome outcome{};
    if (policy != GpuUsePolicy::allowed || !available()) {
        return outcome;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    const gpu::GpuFilmScanDenoiseResult result =
        state_->denoise.apply(state_->device, image, parameters);
    if (!result.handled || result.status != imaging::FilmScanDenoiseStatus::ok) {
        return outcome;
    }
    outcome.handled = true;
    outcome.info = result.info;
    return outcome;
}

bool GpuAccelerator::apply_morphology_plane(
    const float* const source,
    float* const destination,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius,
    const imaging::MorphologyKind kind) noexcept {
    if (!available() || source == nullptr || destination == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->morphology_ready) {
        return false;
    }
    const bool bipolar = kind == imaging::MorphologyKind::bipolar_top_hat;
    if (!state_->pool.ensure(state_->device, width, height, bipolar ? 6 : 3)) {
        return false;
    }

    gpu::GpuWorkingImage* const pool = state_->pool.images();
    if (pool[0].upload_planes_into(state_->device, source, nullptr, nullptr, width) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }

    gpu::GpuKernelStatus status = gpu::GpuKernelStatus::invalid_arguments;
    gpu::GpuWorkingImage* const scratch =
        bipolar ? &pool[gpu::GpuImagePool::scratch_first] : &pool[1];
    switch (kind) {
        case imaging::MorphologyKind::opening:
            status = state_->morphology.opening(state_->device, pool[0], scratch, pool[0], radius);
            break;
        case imaging::MorphologyKind::closing:
            status = state_->morphology.closing(state_->device, pool[0], scratch, pool[0], radius);
            break;
        case imaging::MorphologyKind::bipolar_top_hat:
            status = state_->morphology.bipolar_top_hat(
                state_->device, pool[0], scratch, pool[1], radius);
            break;
    }
    if (status != gpu::GpuKernelStatus::ok) {
        return false;
    }
    gpu::GpuWorkingImage& output = bipolar ? pool[1] : pool[0];
    return output.download_planes(
               state_->device, destination, nullptr, nullptr, width) ==
        gpu::GpuImageStatus::ok;
}

bool GpuAccelerator::apply_morphology_rgb(
    const float* const red,
    const float* const green,
    const float* const blue,
    float* const out_red,
    float* const out_green,
    float* const out_blue,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius,
    const imaging::MorphologyKind kind) noexcept {
    if (!available() || red == nullptr || green == nullptr || blue == nullptr ||
        out_red == nullptr || out_green == nullptr || out_blue == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->morphology_ready) {
        return false;
    }
    const bool bipolar = kind == imaging::MorphologyKind::bipolar_top_hat;
    if (!state_->pool.ensure(state_->device, width, height, bipolar ? 6 : 3)) {
        return false;
    }

    gpu::GpuWorkingImage* const pool = state_->pool.images();
    if (pool[0].upload_planes_into(state_->device, red, green, blue, width) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }
    gpu::GpuWorkingImage* const scratch =
        bipolar ? &pool[gpu::GpuImagePool::scratch_first] : &pool[1];
    gpu::GpuKernelStatus status = gpu::GpuKernelStatus::invalid_arguments;
    switch (kind) {
        case imaging::MorphologyKind::opening:
            status = state_->morphology.opening(state_->device, pool[0], scratch, pool[0], radius);
            break;
        case imaging::MorphologyKind::closing:
            status = state_->morphology.closing(state_->device, pool[0], scratch, pool[0], radius);
            break;
        case imaging::MorphologyKind::bipolar_top_hat:
            status = state_->morphology.bipolar_top_hat(
                state_->device, pool[0], scratch, pool[1], radius);
            break;
    }
    if (status != gpu::GpuKernelStatus::ok) {
        return false;
    }
    gpu::GpuWorkingImage& output = bipolar ? pool[1] : pool[0];
    return output.download_planes(
               state_->device, out_red, out_green, out_blue, width) ==
        gpu::GpuImageStatus::ok;
}

bool GpuAccelerator::apply_morphology_close_open_rgb(
    const float* const red,
    const float* const green,
    const float* const blue,
    float* const out_red,
    float* const out_green,
    float* const out_blue,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) noexcept {
    if (!available() || red == nullptr || green == nullptr || blue == nullptr ||
        out_red == nullptr || out_green == nullptr || out_blue == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U || radius == 0U) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->morphology_ready || !state_->pool.ensure(state_->device, width, height, 3)) {
        return false;
    }

    gpu::GpuWorkingImage* const pool = state_->pool.images();
    if (pool[0].upload_planes_into(state_->device, red, green, blue, width) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }
    gpu::GpuWorkingImage* const scratch = &pool[1];
    if (state_->morphology.closing(
            state_->device, pool[0], scratch, pool[0], radius) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    if (state_->morphology.opening(
            state_->device, pool[0], scratch, pool[0], radius) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    return pool[0].download_planes(
               state_->device, out_red, out_green, out_blue, width) ==
        gpu::GpuImageStatus::ok;
}

bool GpuAccelerator::apply_morphology_bipolar_top_hat_rgb(
    const float* const red,
    const float* const green,
    const float* const blue,
    float* const out_red,
    float* const out_green,
    float* const out_blue,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) noexcept {
    return apply_morphology_rgb(
        red,
        green,
        blue,
        out_red,
        out_green,
        out_blue,
        width,
        height,
        radius,
        imaging::MorphologyKind::bipolar_top_hat);
}

bool GpuAccelerator::apply_negative_inversion(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const float* const dmin,
    const float* const dmax_normalized,
    const float* const response) noexcept {
    if (!available() || pixels == nullptr || dmin == nullptr || dmax_normalized == nullptr ||
        response == nullptr) {
        return false;
    }
    if (width == 0U || height == 0U || stride_pixels < width) {
        return false;
    }
    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->invert_ready) {
        return false;
    }

    if (!state_->pool.ensure(state_->device, width, height)) {
        return false;
    }
    gpu::GpuWorkingImage* const pool = state_->pool.images();
    auto* const rgba = reinterpret_cast<core::Rgba32F*>(pixels);
    int read_slot = 0;
    int write_slot = 1;
    if (state_->resident_matches(pixels, width, height) && !state_->resident.host_stale) {
        read_slot = state_->resident.read_slot;
        write_slot = 1 - read_slot;
    } else if (
        pool[0].upload_into(state_->device, rgba, stride_pixels) != gpu::GpuImageStatus::ok) {
        return false;
    }

    gpu::GpuNegativeInvertParameters parameters{};
    for (int channel = 0; channel < 3; ++channel) {
        parameters.dmin[channel] = dmin[channel];
        parameters.dmax_normalized[channel] = dmax_normalized[channel];
    }
    parameters.response_y_ceiling = response[0];
    parameters.response_amplitude = response[1];
    parameters.response_rate = response[2];
    parameters.response_shape = response[3];

    if (state_->invert.dispatch(
            state_->device, pool[read_slot], pool[write_slot], parameters) !=
        gpu::GpuKernelStatus::ok) {
        return false;
    }
    if (state_->resident.scope_depth > 0) {
        state_->bind_resident(pixels, width, height, stride_pixels, write_slot);
        return true;
    }
    return pool[write_slot].download(state_->device, rgba, stride_pixels) ==
        gpu::GpuImageStatus::ok;
}

}  // namespace negaflow::pipeline
