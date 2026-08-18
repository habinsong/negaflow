#include "negaflow/abi/infrared_detect.h"

#include "negaflow/imaging/infrared_defect_detector.h"
#include "negaflow/imageio/wic_tiff_decoder.h"

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

class InfraredPlaneSink final : public negaflow::imageio::WicTiffRowSink {
public:
    InfraredPlaneSink(
        const bool allow_gray,
        const negaflow::core::CancelFlag cancel) noexcept
        : allow_gray_(allow_gray), cancel_(cancel) {}

    bool begin(const negaflow::imageio::WicTiffFrameView& frame) noexcept override {
        try {
            const bool valid_layout =
                frame.layout == negaflow::imageio::DecodedPixelLayout::rgb16 ||
                frame.layout == negaflow::imageio::DecodedPixelLayout::rgba16 ||
                (allow_gray_ &&
                 frame.layout == negaflow::imageio::DecodedPixelLayout::gray16);
            channels_ = negaflow::imageio::channel_count(frame.layout);
            const std::uint64_t area = static_cast<std::uint64_t>(frame.width) * frame.height;
            if (!valid_layout || channels_ == 0U || frame.width == 0U || frame.height == 0U ||
                area > std::numeric_limits<std::size_t>::max() || cancel_.requested()) {
                return false;
            }
            width_ = frame.width;
            height_ = frame.height;
            values_.assign(static_cast<std::size_t>(area), 0.0F);
            return true;
        } catch (...) {
            return false;
        }
    }

    bool write(const negaflow::imageio::WicTiffRowChunk& rows) noexcept override {
        if (cancel_.requested() || rows.first_row != next_row_ || rows.row_count == 0U ||
            rows.first_row > height_ || rows.row_count > height_ - rows.first_row ||
            rows.stride_bytes % sizeof(std::uint16_t) != 0U) {
            return false;
        }
        const std::size_t stride = rows.stride_bytes / sizeof(std::uint16_t);
        if (stride < static_cast<std::size_t>(width_) * channels_ ||
            rows.samples.size() != stride * rows.row_count) {
            return false;
        }
        constexpr float scale = 1.0F / 65'535.0F;
        for (std::uint32_t row = 0U; row < rows.row_count; ++row) {
            const std::uint16_t* const source = rows.samples.data() + row * stride;
            float* const destination = values_.data() +
                static_cast<std::size_t>(rows.first_row + row) * width_;
            for (std::uint32_t x = 0U; x < width_; ++x) {
                destination[x] = static_cast<float>(source[x * channels_]) * scale;
            }
        }
        next_row_ += rows.row_count;
        return true;
    }

    void complete(const negaflow::imageio::WicTiffDecodeStatus status) noexcept override {
        complete_ = status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            next_row_ == height_;
        if (!complete_) {
            std::vector<float>{}.swap(values_);
        }
    }

    [[nodiscard]] bool complete() const noexcept { return complete_; }
    [[nodiscard]] std::uint32_t width() const noexcept { return width_; }
    [[nodiscard]] std::uint32_t height() const noexcept { return height_; }
    [[nodiscard]] std::vector<float>& values() noexcept { return values_; }

private:
    bool allow_gray_{false};
    negaflow::core::CancelFlag cancel_{};
    std::uint8_t channels_{0U};
    std::uint32_t width_{0U};
    std::uint32_t height_{0U};
    std::uint32_t next_row_{0U};
    bool complete_{false};
    std::vector<float> values_{};
};

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
    summary->status = infrared_status(detection.status);
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
    if (summary == nullptr || handle == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
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
    const negaflow::core::CancelFlag cancel{cancel_requested};
    if (cancel.requested()) {
        summary->status = NF_INFRARED_DETECTION_CANCELLED;
        return NF_STATUS_OK;
    }
    try {
        negaflow::imageio::WicTiffDecodeControl control{};
        control.rows_per_copy = 32U;
        InfraredPlaneSink visible_sink{false, cancel};
        const auto visible = negaflow::imageio::decode_tiff_rows_with_wic(
            std::filesystem::path{visible_path}, visible_sink, {}, control);
        if (cancel.requested()) {
            summary->status = NF_INFRARED_DETECTION_CANCELLED;
            return NF_STATUS_OK;
        }
        if (visible.status != negaflow::imageio::WicTiffDecodeStatus::ok ||
            !visible_sink.complete()) {
            summary->status = NF_INFRARED_DETECTION_UNREADABLE;
            return NF_STATUS_OK;
        }

        InfraredPlaneSink infrared_sink{true, cancel};
        const auto infrared = negaflow::imageio::decode_tiff_rows_with_wic(
            std::filesystem::path{infrared_path}, infrared_sink, {}, control);
        if (cancel.requested()) {
            summary->status = NF_INFRARED_DETECTION_CANCELLED;
            return NF_STATUS_OK;
        }
        if (infrared.status != negaflow::imageio::WicTiffDecodeStatus::ok ||
            !infrared_sink.complete() ||
            infrared_sink.width() != visible_sink.width() ||
            infrared_sink.height() != visible_sink.height()) {
            summary->status = NF_INFRARED_DETECTION_UNREADABLE;
            return NF_STATUS_OK;
        }

        auto detection = negaflow::imaging::detect_infrared_defects(
            infrared_sink.values(),
            visible_sink.values(),
            visible_sink.width(),
            visible_sink.height(),
            infrared_parameters(*parameters),
            cancel);
        return publish_infrared_detection(std::move(detection), summary, handle);
    } catch (const std::bad_alloc&) {
        summary->status = NF_INFRARED_DETECTION_ALLOCATION_FAILED;
        return NF_STATUS_OK;
    } catch (...) {
        summary->status = NF_INFRARED_DETECTION_UNREADABLE;
        return NF_STATUS_OK;
    }
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
