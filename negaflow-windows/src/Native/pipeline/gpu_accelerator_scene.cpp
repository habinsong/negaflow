#include "negaflow/pipeline/gpu_accelerator.h"

// 자동 레벨 · 자동 중성 균형의 GPU 진입점입니다.
//
// 왜 따로 뗐나 — 이 진입점은 다른 커널과 달리 **한 번의 디스패치가 아닙니다.**
// 표본을 모으고, 호스트가 계수를 정하고, 적용하고, 다시 표본을 모으고, 다시 적용합니다.
// 그 순서 자체가 규칙이라 다른 진입점 사이에 끼워 두면 읽히지 않습니다. 500줄 규칙도 있습니다.
//
// **이 단계가 GPU 에서 돌지 않으면 뒤가 전부 호스트로 내려옵니다.**
// 예전에는 `grade.cpp` 가 여기서 `flush_resident()` 를 불렀고, 그 한 번 때문에
// 톤·필름룩·마무리·발행이 모두 CPU 경로였습니다. 실측(1536x1026 8틱 드래그):
// 다운로드 1,374 MB. 사슬을 묶어 두는 것이 이 파일이 있는 이유입니다.

#include "gpu_accelerator_state.h"

#include <mutex>

namespace negaflow::pipeline {

bool GpuAccelerator::apply_scene_correction(
    const GpuUsePolicy policy,
    imaging::WorkingImage& image,
    const imaging::SceneCorrectionParameters& parameters,
    imaging::SceneCorrectionInfo& info) noexcept {
    info = {};
    if (policy != GpuUsePolicy::allowed || !available()) {
        return false;
    }
    if (image.pixels.empty() || image.width == 0U || image.height == 0U ||
        image.stride_pixels < image.width) {
        return false;
    }
    const bool wants_levels = parameters.auto_levels;
    const bool wants_balance =
        parameters.auto_neutral_balance && parameters.negative_source;
    if (!wants_levels && !wants_balance) {
        return false;
    }

    const std::lock_guard<std::recursive_mutex> guard{state_->lock};
    if (!state_->scene_correction_ready ||
        !state_->pool.ensure(state_->device, image.width, image.height)) {
        return false;
    }
    gpu::GpuWorkingImage* const pool = state_->pool.images();
    auto* const rgba = image.pixels.data();
    float* const host = reinterpret_cast<float*>(rgba);
    int read_slot = 0;
    if (state_->resident_matches(host, image.width, image.height)) {
        read_slot = state_->resident.read_slot;
    } else if (
        pool[0].upload_into(state_->device, rgba, image.stride_pixels) !=
        gpu::GpuImageStatus::ok) {
        return false;
    }

    // **어느 갈래로 빠지든 화소는 손대지 않은 상태여야 합니다.** 표본을 모으다 실패하면
    // 호출부가 CPU 판을 그대로 부를 수 있어야 하는데, 그때 이미 반쯤 적용돼 있으면
    // 두 번 적용된 사진이 나옵니다. 그래서 적용 디스패치는 판정을 마친 뒤에만 합니다.
    bool touched = false;
    if (wants_levels) {
        imaging::SceneSampleGrid samples{};
        if (state_->scene_correction.collect_samples(
                state_->device,
                pool[read_slot],
                imaging::scene_auto_levels_sample_width,
                samples) != gpu::GpuKernelStatus::ok) {
            // 아직 아무것도 적용하지 않았습니다. 호출부가 CPU 판을 그대로 부르면 됩니다.
            return false;
        }
        info.sampled_pixels += samples.red.size();
        const imaging::SceneAutoLevelsPlan plan =
            imaging::plan_scene_auto_levels(samples, parameters.negative_source);
        if (plan.apply) {
            const int write_slot = 1 - read_slot;
            if (state_->scene_correction.apply_auto_levels(
                    state_->device, pool[read_slot], pool[write_slot], plan) !=
                gpu::GpuKernelStatus::ok) {
                return false;
            }
            read_slot = write_slot;
            touched = true;
            info.auto_levels_applied = true;
        }
    }

    // CPU 판과 같은 순서입니다 — 중성 균형은 **레벨이 적용된 화상**을 표본합니다.
    if (wants_balance && image.width > 8U && image.height > 8U) {
        imaging::SceneSampleGrid samples{};
        if (state_->scene_correction.collect_samples(
                state_->device,
                pool[read_slot],
                imaging::scene_neutral_balance_sample_width,
                samples) == gpu::GpuKernelStatus::ok) {
            info.sampled_pixels += samples.red.size();
            const imaging::SceneNeutralBalancePlan plan =
                imaging::plan_scene_neutral_balance(samples);
            if (plan.apply) {
                const int write_slot = 1 - read_slot;
                if (state_->scene_correction.apply_neutral_balance(
                        state_->device, pool[read_slot], pool[write_slot], plan) !=
                    gpu::GpuKernelStatus::ok) {
                    return false;
                }
                read_slot = write_slot;
                touched = true;
                info.neutral_balance_applied = true;
            }
        } else if (!touched) {
            // 아직 아무것도 적용하지 않았으므로 호출부가 CPU 로 가면 됩니다.
            return false;
        }
        // 레벨은 이미 GPU 에서 적용됐습니다. 여기서 false 를 돌려주면 호출부가 CPU 판을
        // 처음부터 다시 돌려 **레벨이 두 번** 걸립니다. 균형만 포기하고 성공으로 답합니다.
    }

    if (!touched) {
        // 판정이 "보정 없음" 이었습니다. 호스트 화소는 그대로가 정답이므로 묶지도,
        // 내리지도 않습니다. 처리했다고 답해야 호출부가 CPU 판을 또 돌리지 않습니다.
        return true;
    }
    if (state_->resident.scope_depth > 0) {
        state_->bind_resident(
            host, image.width, image.height, image.stride_pixels, read_slot);
        return true;
    }
    // 상주 스코프 밖(단발 프리뷰)이면 결과를 내려 주어야 합니다.
    return pool[read_slot].download(state_->device, rgba, image.stride_pixels) ==
        gpu::GpuImageStatus::ok;
}

} // namespace negaflow::pipeline
