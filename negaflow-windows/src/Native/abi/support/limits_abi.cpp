#include "negaflow/abi/limits.h"

#include "negaflow/gpu/gpu_cache_budget.h"
#include "negaflow/gpu/gpu_device.h"
#include "negaflow/pipeline/gpu_accelerator.h"
#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "negaflow/pipeline/frame_cache_limits.h"

#include <algorithm>
#include <cstdint>
#include <cstring>

// 톤·네거티브 수동 입력의 허용 범위를 돌려줍니다.

nf_status_t NF_CALL nf_get_tone_limits_v1(nf_tone_limits_v1* const output) {
    if (output == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (output->struct_size < static_cast<std::uint32_t>(sizeof(*output))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }

    const std::uint32_t declared_size = output->struct_size;
    output->maximum_exposure_stops = negaflow::imaging::maximum_exposure_stops;
    output->maximum_tone_control = negaflow::imaging::maximum_tone_control;
    output->maximum_endpoint_tone_control =
        negaflow::imaging::maximum_endpoint_tone_control;
    output->minimum_film_emulation_intensity = 0.0;
    output->maximum_film_emulation_intensity = 1.0;
    output->struct_size = declared_size;
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_get_negative_limits_v1(nf_negative_limits_v1* const output) {
    if (output == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (output->struct_size < static_cast<std::uint32_t>(sizeof(*output))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }

    const std::uint32_t declared_size = output->struct_size;
    output->minimum_manual_dmin = negaflow::imaging::minimum_manual_dmin;
    output->maximum_manual_dmin = negaflow::imaging::maximum_manual_dmin;
    output->struct_size = declared_size;
    return NF_STATUS_OK;
}

// 설정 창이 고른 상주 한도를 엔진 캐시에 겁니다. macOS
// `FrameCacheResidencyStore.onLimitsChange` → `FrameCacheManager` 와 같은 자리입니다.
nf_status_t NF_CALL nf_set_frame_cache_limits_v1(
    const nf_frame_cache_limits_v1* const limits) {
    if (limits == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (limits->struct_size < static_cast<std::uint32_t>(sizeof(*limits))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }

    negaflow::pipeline::set_frame_cache_residency_limits(
        negaflow::pipeline::FrameCacheResidencyLimits{
            limits->cleaned_raw_frames,
            limits->developed_frames,
        });
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_set_gpu_cache_limit_v1(const nf_gpu_cache_limit_v1* const limit) {
    if (limit == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (limit->struct_size < static_cast<std::uint32_t>(sizeof(*limit))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    negaflow::gpu::set_gpu_cache_limit_bytes(limit->limit_bytes);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_get_gpu_cache_info_v1(nf_gpu_cache_info_v1* const output) {
    if (output == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (output->struct_size < static_cast<std::uint32_t>(sizeof(*output))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }

    const std::uint32_t declared_size = output->struct_size;
    *output = nf_gpu_cache_info_v1{};
    output->struct_size = declared_size;

    // 가속기가 실제로 쓰는 장치를 봅니다. `GpuDevice::shared()` 는 가속기 것과 **다른**
    // 장치라, 설정 창을 열 때 D3D11 장치가 하나 더 생깁니다.
    const negaflow::gpu::GpuDevice& device =
        negaflow::pipeline::GpuAccelerator::shared().device();
    output->resident_bytes = negaflow::gpu::gpu_pool_resident_bytes();
    if (!device.is_usable()) {
        return NF_STATUS_OK;
    }

    const negaflow::gpu::GpuCapability& capability = device.capability();
    output->has_gpu = 1U;
    output->is_integrated = capability.adapter.is_integrated ? 1U : 0U;
    const std::size_t room = sizeof(output->adapter_description) - 1U;
    const std::size_t length = std::min(
        room, std::strlen(capability.adapter.description.data()));
    std::memcpy(output->adapter_description, capability.adapter.description.data(), length);
    output->adapter_description[length] = '\0';
    output->dedicated_video_memory_bytes = capability.adapter.dedicated_video_memory;

    negaflow::gpu::GpuVideoMemoryInfo memory{};
    if (device.query_local_video_memory_info(memory)) {
        output->video_memory_budget_bytes = memory.budget;
    }
    output->automatic_limit_bytes = negaflow::gpu::GpuCacheBudget::automatic_bytes(device);
    output->effective_limit_bytes = negaflow::gpu::GpuCacheBudget::effective_bytes(device);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_get_memory_report_v1(nf_memory_report_v1* const output) {
    if (output == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (output->struct_size < static_cast<std::uint32_t>(sizeof(*output))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    const std::uint32_t declared_size = output->struct_size;
    const negaflow::pipeline::FrameCacheMemoryReport report =
        negaflow::pipeline::frame_cache_memory_report();
    *output = nf_memory_report_v1{};
    output->struct_size = declared_size;
    output->process_private_bytes = report.process_private_bytes;
    output->decoded_source_resident_bytes = report.decoded_source_resident_bytes;
    output->decoded_source_budget_bytes = report.decoded_source_budget_bytes;
    output->preview_proxy_resident_bytes = report.preview_proxy_resident_bytes;
    output->preview_proxy_budget_bytes = report.preview_proxy_budget_bytes;
    output->developed_display_resident_bytes = report.developed_display_resident_bytes;
    output->developed_display_budget_bytes = report.developed_display_budget_bytes;
    output->gpu_pool_resident_bytes = report.gpu_pool_resident_bytes;
    output->gpu_pool_limit_bytes = report.gpu_pool_limit_bytes;
    output->gpu_system_memory_bytes = report.gpu_system_memory_bytes;
    output->non_cache_overhead_bytes = report.non_cache_overhead_bytes;
    output->automatic_process_ceiling_bytes = report.automatic_process_ceiling_bytes;
    output->engine_cleaned_raw_frames = report.engine_cleaned_raw_frames;
    output->engine_developed_frames = report.engine_developed_frames;
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_sync_display_cache_v1(
    const std::uint64_t resident_bytes, std::uint64_t* const budget_bytes) {
    if (budget_bytes == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    *budget_bytes = negaflow::pipeline::sync_display_cache_budget(resident_bytes);
    return NF_STATUS_OK;
}
