#include "negaflow/abi/infrared_detect.h"

#include "detect/infrared_file_detection.h"
#include "negaflow/imaging/infrared_defect_detector.h"
#include "negaflow/pipeline/gpu_accelerator.h"
#include "negaflow/pipeline/stage_timing.h"

#include <cstdio>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <limits>
#include <new>
#include <span>
#include <vector>

struct nf_infrared_detection_handle_v1 final {
    negaflow::imaging::InfraredDetection detection{};
};

namespace {

[[nodiscard]] negaflow::imaging::InfraredDetectorParameters infrared_parameters(
    const nf_infrared_detector_parameters_v1& source) noexcept {
    negaflow::imaging::InfraredDetectorParameters result{};
    result.sensitivity = source.sensitivity;
    result.dilate_radius = source.dilate_radius;
    result.minimum_area = source.minimum_area;
    result.maximum_coverage = source.maximum_coverage;
    result.alignment_search_radius = source.alignment_search_radius;
    result.cluster_tile = source.cluster_tile;
    result.cluster_padding = source.cluster_padding;
    return result;
}

[[nodiscard]] std::uint32_t infrared_status(
    const negaflow::imaging::InfraredDetectionStatus value) noexcept {
    switch (value) {
        case negaflow::imaging::InfraredDetectionStatus::ok:
            return NF_INFRARED_DETECTION_OK;
        case negaflow::imaging::InfraredDetectionStatus::unreadable:
            return NF_INFRARED_DETECTION_UNREADABLE;
        case negaflow::imaging::InfraredDetectionStatus::too_small:
            return NF_INFRARED_DETECTION_TOO_SMALL;
        case negaflow::imaging::InfraredDetectionStatus::no_defects:
            return NF_INFRARED_DETECTION_NO_DEFECTS;
        case negaflow::imaging::InfraredDetectionStatus::coverage_too_high:
            return NF_INFRARED_DETECTION_COVERAGE_TOO_HIGH;
        case negaflow::imaging::InfraredDetectionStatus::cancelled:
            return NF_INFRARED_DETECTION_CANCELLED;
        case negaflow::imaging::InfraredDetectionStatus::allocation_failed:
            return NF_INFRARED_DETECTION_ALLOCATION_FAILED;
    }
    return NF_INFRARED_DETECTION_UNREADABLE;
}

[[nodiscard]] std::uint32_t infrared_alignment_status(
    const negaflow::imaging::InfraredAlignmentStatus value) noexcept {
    switch (value) {
        case negaflow::imaging::InfraredAlignmentStatus::not_requested:
            return NF_INFRARED_ALIGNMENT_NOT_REQUESTED;
        case negaflow::imaging::InfraredAlignmentStatus::aligned:
            return NF_INFRARED_ALIGNMENT_ALIGNED;
        case negaflow::imaging::InfraredAlignmentStatus::insufficient_texture:
            return NF_INFRARED_ALIGNMENT_INSUFFICIENT_TEXTURE;
        case negaflow::imaging::InfraredAlignmentStatus::weak_correlation:
            return NF_INFRARED_ALIGNMENT_WEAK_CORRELATION;
        case negaflow::imaging::InfraredAlignmentStatus::search_limit_reached:
            return NF_INFRARED_ALIGNMENT_SEARCH_LIMIT_REACHED;
    }
    return NF_INFRARED_ALIGNMENT_INSUFFICIENT_TEXTURE;
}

[[nodiscard]] nf_status_t publish_infrared_detection(
    negaflow::imaging::InfraredDetectionResult&& detection,
    nf_infrared_detection_summary_v1* const summary,
    nf_infrared_detection_handle_v1** const handle) noexcept {
    if (negaflow::pipeline::stage_timing_enabled()) {
        const auto& timing = detection.timings;
        const auto transfers = negaflow::pipeline::gpu_host_transfer_stats();
        (void)std::fprintf(
            stderr,
            "[infrared timing] validation=%llu alignment=%llu preparation=%llu "
            "ir_signal=%llu candidates=%llu visible_signal=%llu confirmation=%llu "
            "attenuation=%llu output=%llu total=%llu us gpu_up=%llu gpu_down=%llu\n",
            static_cast<unsigned long long>(timing.validation_microseconds),
            static_cast<unsigned long long>(timing.alignment_microseconds),
            static_cast<unsigned long long>(timing.preparation_microseconds),
            static_cast<unsigned long long>(timing.infrared_signal_microseconds),
            static_cast<unsigned long long>(timing.candidates_microseconds),
            static_cast<unsigned long long>(timing.visible_signal_microseconds),
            static_cast<unsigned long long>(timing.confirmation_microseconds),
            static_cast<unsigned long long>(timing.attenuation_microseconds),
            static_cast<unsigned long long>(timing.output_microseconds),
            static_cast<unsigned long long>(timing.total_microseconds),
            static_cast<unsigned long long>(transfers.uploads),
            static_cast<unsigned long long>(transfers.downloads));
        // `NEGA_GPU_TIMING=1` 일 때만 커널 구간 GPU 시간을 함께 찍습니다. CPU 벽시계로는
        // 이 크기의 차이를 못 가르기 때문입니다(체크포인트 §18.3).
        negaflow::pipeline::dump_gpu_kernel_timings();
    }
    summary->status = infrared_status(detection.status);
    // 실패한 자리입니다. `reserved2` 는 지금까지 늘 0 이었으므로 구조체 크기도 뜻도
    // 바뀌지 않습니다 - 옛 읽는 쪽은 그대로 무시합니다.
    summary->reserved2 = detection.failure_detail;
    summary->width = detection.detection.width;
    summary->height = detection.detection.height;
    summary->offset_x = detection.detection.offset_x;
    summary->offset_y = detection.detection.offset_y;
    summary->alignment_status = infrared_alignment_status(detection.detection.alignment.status);
    summary->alignment_search_radius = detection.detection.alignment.search_radius;
    summary->alignment_downsample_factor = detection.detection.alignment.downsample_factor;
    summary->coverage = detection.detection.coverage;
    summary->median_gain = detection.detection.median_gain;
    summary->alignment_peak_correlation = detection.detection.alignment.peak_correlation;
    summary->alignment_runner_up_correlation =
        detection.detection.alignment.runner_up_correlation;
    summary->candidate_count = detection.detection.candidate_count;
    summary->confirmed_count = detection.detection.confirmed_count;
    summary->cluster_count = detection.detection.clusters.size();
    summary->component_count = detection.detection.components.size();
    if (detection.status != negaflow::imaging::InfraredDetectionStatus::ok) {
        return NF_STATUS_OK;
    }
    auto* const owned = new (std::nothrow) nf_infrared_detection_handle_v1{};
    if (owned == nullptr) {
        summary->status = NF_INFRARED_DETECTION_ALLOCATION_FAILED;
        return NF_STATUS_OK;
    }
    owned->detection = std::move(detection.detection);
    *handle = owned;
    return NF_STATUS_OK;
}

[[nodiscard]] nf_status_t detect_infrared_files(
    const wchar_t* const visible_path,
    const wchar_t* const infrared_path,
    const negaflow::abi::detail::InfraredVisibleSourceKind visible_source_kind,
    const nf_infrared_detector_parameters_v1* const parameters,
    const uint32_t* const cancel_requested,
    nf_infrared_detection_summary_v1* const summary,
    nf_infrared_detection_handle_v1** const handle) {
    if (summary == nullptr || handle == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    *handle = nullptr;
    if (summary->struct_size < static_cast<std::uint32_t>(sizeof(*summary))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    if (visible_path == nullptr || visible_path[0] == L'\0' ||
        infrared_path == nullptr || infrared_path[0] == L'\0' ||
        parameters == nullptr ||
        parameters->struct_size < static_cast<std::uint32_t>(sizeof(*parameters)) ||
        parameters->reserved != 0U || parameters->reserved2 != 0U) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    const std::uint32_t declared_size = summary->struct_size;
    std::memset(summary, 0, sizeof(*summary));
    summary->struct_size = declared_size;
    negaflow::pipeline::install_gpu_kernel_accelerator();
    negaflow::pipeline::reset_gpu_host_transfer_stats();
    auto detection = negaflow::abi::detail::detect_infrared_defects_from_files(
        std::filesystem::path{visible_path},
        std::filesystem::path{infrared_path},
        visible_source_kind,
        infrared_parameters(*parameters),
        negaflow::core::CancelFlag{cancel_requested});
    return publish_infrared_detection(std::move(detection), summary, handle);
}

}  // namespace

// 적외선 검출 C ABI 입니다. 핸들 수명과 TIFF 평면 읽기를 이 번역 단위가 소유합니다.

nf_status_t NF_CALL nf_detect_infrared_defects_v1(
    const float* const infrared,
    const uint32_t infrared_stride_bytes,
    const float* const red,
    const uint32_t red_stride_bytes,
    const uint32_t width,
    const uint32_t height,
    const nf_infrared_detector_parameters_v1* const parameters,
    const uint32_t* const cancel_requested,
    nf_infrared_detection_summary_v1* const summary,
    nf_infrared_detection_handle_v1** const handle) {
    if (summary == nullptr || handle == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    *handle = nullptr;
    if (summary->struct_size < static_cast<std::uint32_t>(sizeof(*summary))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    if (infrared == nullptr || red == nullptr || parameters == nullptr ||
        parameters->struct_size < static_cast<std::uint32_t>(sizeof(*parameters)) ||
        parameters->reserved != 0U || parameters->reserved2 != 0U ||
        width == 0U || height == 0U) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    const std::uint64_t row_bytes = static_cast<std::uint64_t>(width) * sizeof(float);
    if (row_bytes > std::numeric_limits<std::uint32_t>::max() ||
        infrared_stride_bytes < row_bytes || red_stride_bytes < row_bytes) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    const std::uint32_t declared_size = summary->struct_size;
    std::memset(summary, 0, sizeof(*summary));
    summary->struct_size = declared_size;
    negaflow::pipeline::install_gpu_kernel_accelerator();
    negaflow::pipeline::reset_gpu_host_transfer_stats();
    try {
        const std::size_t area = static_cast<std::size_t>(width) * height;
        if (height != 0U && area / height != width) {
            return NF_STATUS_INVALID_ARGUMENT;
        }
        std::vector<float> infrared_copy{};
        std::vector<float> red_copy{};
        std::span<const float> infrared_plane{};
        std::span<const float> red_plane{};
        if (infrared_stride_bytes == row_bytes) {
            infrared_plane = std::span<const float>(infrared, area);
        } else {
            infrared_copy.resize(area);
            const auto* bytes = reinterpret_cast<const std::uint8_t*>(infrared);
            for (std::uint32_t y = 0U; y < height; ++y) {
                std::memcpy(
                    infrared_copy.data() + static_cast<std::size_t>(y) * width,
                    bytes + static_cast<std::size_t>(y) * infrared_stride_bytes,
                    static_cast<std::size_t>(row_bytes));
            }
            infrared_plane = infrared_copy;
        }
        if (red_stride_bytes == row_bytes) {
            red_plane = std::span<const float>(red, area);
        } else {
            red_copy.resize(area);
            const auto* bytes = reinterpret_cast<const std::uint8_t*>(red);
            for (std::uint32_t y = 0U; y < height; ++y) {
                std::memcpy(
                    red_copy.data() + static_cast<std::size_t>(y) * width,
                    bytes + static_cast<std::size_t>(y) * red_stride_bytes,
                    static_cast<std::size_t>(row_bytes));
            }
            red_plane = red_copy;
        }

        auto detection = negaflow::imaging::detect_infrared_defects(
            infrared_plane,
            red_plane,
            width,
            height,
            infrared_parameters(*parameters),
            negaflow::core::CancelFlag{cancel_requested});
        return publish_infrared_detection(std::move(detection), summary, handle);
    } catch (const std::bad_alloc&) {
        summary->status = NF_INFRARED_DETECTION_ALLOCATION_FAILED;
        return NF_STATUS_OK;
    }
}

nf_status_t NF_CALL nf_detect_infrared_defects_from_tiff_v1(
    const wchar_t* const visible_path,
    const wchar_t* const infrared_path,
    const nf_infrared_detector_parameters_v1* const parameters,
    const uint32_t* const cancel_requested,
    nf_infrared_detection_summary_v1* const summary,
    nf_infrared_detection_handle_v1** const handle) {
    return detect_infrared_files(
        visible_path,
        infrared_path,
        negaflow::abi::detail::InfraredVisibleSourceKind::infer_from_extension,
        parameters,
        cancel_requested,
        summary,
        handle);
}

nf_status_t NF_CALL nf_detect_infrared_defects_from_files_v2(
    const wchar_t* const visible_path,
    const wchar_t* const infrared_path,
    const uint32_t visible_source_kind,
    const nf_infrared_detector_parameters_v1* const parameters,
    const uint32_t* const cancel_requested,
    nf_infrared_detection_summary_v1* const summary,
    nf_infrared_detection_handle_v1** const handle) {
    negaflow::abi::detail::InfraredVisibleSourceKind source_kind{};
    switch (visible_source_kind) {
        case NF_INFRARED_VISIBLE_SOURCE_SCANNER_TIFF:
            source_kind = negaflow::abi::detail::InfraredVisibleSourceKind::scanner_tiff;
            break;
        case NF_INFRARED_VISIBLE_SOURCE_IMPORTED_FILE:
            source_kind = negaflow::abi::detail::InfraredVisibleSourceKind::imported_file;
            break;
        default:
            return NF_STATUS_INVALID_ARGUMENT;
    }
    return detect_infrared_files(
        visible_path,
        infrared_path,
        source_kind,
        parameters,
        cancel_requested,
        summary,
        handle);
}

nf_status_t NF_CALL nf_infrared_detection_get_cluster_v1(
    const nf_infrared_detection_handle_v1* const handle,
    const uint64_t index,
    nf_infrared_cluster_v1* const cluster,
    uint8_t* const core_mask,
    const uint64_t core_mask_capacity_bytes,
    uint16_t* const attenuation_r16,
    const uint64_t attenuation_capacity_values) {
    if (handle == nullptr || cluster == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    if (cluster->struct_size < static_cast<std::uint32_t>(sizeof(*cluster))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    if (index >= handle->detection.clusters.size()) return NF_STATUS_INVALID_ARGUMENT;
    const auto& source = handle->detection.clusters[static_cast<std::size_t>(index)];
    const std::uint32_t declared_size = cluster->struct_size;
    std::memset(cluster, 0, sizeof(*cluster));
    cluster->struct_size = declared_size;
    cluster->roi_x = source.roi_x;
    cluster->roi_y_up = source.roi_y_up;
    cluster->width = source.width;
    cluster->height = source.height;
    cluster->core_mask_byte_count = source.core_mask.size();
    cluster->attenuation_value_count = source.attenuation_r16.size();
    if ((core_mask == nullptr) != (core_mask_capacity_bytes == 0U) ||
        (attenuation_r16 == nullptr) != (attenuation_capacity_values == 0U)) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (core_mask == nullptr && attenuation_r16 == nullptr) return NF_STATUS_OK;
    if (core_mask_capacity_bytes < source.core_mask.size() ||
        attenuation_capacity_values < source.attenuation_r16.size()) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (core_mask != nullptr) {
        std::memcpy(core_mask, source.core_mask.data(), source.core_mask.size());
    }
    if (attenuation_r16 != nullptr) {
        std::memcpy(
            attenuation_r16,
            source.attenuation_r16.data(),
            source.attenuation_r16.size() * sizeof(std::uint16_t));
    }
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_infrared_detection_get_component_v1(
    const nf_infrared_detection_handle_v1* const handle,
    const uint64_t index,
    nf_infrared_component_v1* const component,
    nf_infrared_preview_point_v1* const preview_points,
    const uint64_t preview_point_capacity) {
    if (handle == nullptr || component == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    if (component->struct_size < static_cast<std::uint32_t>(sizeof(*component))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    if (index >= handle->detection.components.size()) return NF_STATUS_INVALID_ARGUMENT;
    const auto& source = handle->detection.components[static_cast<std::size_t>(index)];
    const std::uint32_t declared_size = component->struct_size;
    std::memset(component, 0, sizeof(*component));
    component->struct_size = declared_size;
    component->classification = static_cast<std::uint32_t>(source.classification);
    component->confidence = source.confidence;
    component->area = source.area;
    component->preview_point_count = source.preview_points.size();
    if ((preview_points == nullptr) != (preview_point_capacity == 0U)) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (preview_points == nullptr) return NF_STATUS_OK;
    if (preview_point_capacity < source.preview_points.size()) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    for (std::size_t ordinal = 0U; ordinal < source.preview_points.size(); ++ordinal) {
        preview_points[ordinal] = nf_infrared_preview_point_v1{
            source.preview_points[ordinal].x,
            source.preview_points[ordinal].y};
    }
    return NF_STATUS_OK;
}

void NF_CALL nf_infrared_detection_destroy_v1(
    nf_infrared_detection_handle_v1* const handle) {
    delete handle;
}
