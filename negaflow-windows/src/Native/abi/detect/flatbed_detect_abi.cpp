#include "negaflow/abi/flatbed_detect.h"

#include "negaflow/imaging/flatbed_frame_grid_detector.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <new>
#include <span>
#include <vector>

struct nf_flatbed_frame_grid_handle_v1 final {
    std::vector<negaflow::imaging::FlatbedFrameDetection> detections{};
};

namespace {

[[nodiscard]] std::uint32_t flatbed_frame_grid_status(
    const negaflow::imaging::FlatbedFrameGridStatus value) noexcept {
    switch (value) {
        case negaflow::imaging::FlatbedFrameGridStatus::ok:
            return NF_FLATBED_FRAME_GRID_OK;
        case negaflow::imaging::FlatbedFrameGridStatus::invalid_input:
            return NF_FLATBED_FRAME_GRID_INVALID_INPUT;
        case negaflow::imaging::FlatbedFrameGridStatus::cancelled:
            return NF_FLATBED_FRAME_GRID_CANCELLED;
        case negaflow::imaging::FlatbedFrameGridStatus::allocation_failed:
            return NF_FLATBED_FRAME_GRID_ALLOCATION_FAILED;
    }
    return NF_FLATBED_FRAME_GRID_INVALID_INPUT;
}

[[nodiscard]] bool flatbed_frame_dimensions(
    const std::uint32_t value,
    negaflow::imaging::FlatbedFrameDimensions& result) noexcept {
    if (value > NF_FLATBED_FRAME_PANORAMA_35MM_65X24) return false;
    const auto dimensions = negaflow::imaging::flatbed_frame_dimensions(
        static_cast<negaflow::imaging::FlatbedFrameFormat>(value));
    if (!dimensions) return false;
    result = *dimensions;
    return true;
}

// 호출자가 준 치수입니다. 수동 비율이 이리로 들어오므로 유한한 양수만 받습니다.
[[nodiscard]] bool flatbed_frame_dimensions(
    const nf_flatbed_frame_dimensions_v1* const value,
    negaflow::imaging::FlatbedFrameDimensions& result) noexcept {
    if (value == nullptr ||
        value->struct_size < static_cast<std::uint32_t>(sizeof(*value)) ||
        !std::isfinite(value->along_mm) || !std::isfinite(value->across_mm) ||
        value->along_mm <= 0.0 || value->across_mm <= 0.0 || value->is_35mm > 1U) {
        return false;
    }
    result = {value->along_mm, value->across_mm, value->is_35mm == 1U};
    return true;
}

// 네 입구가 같이 쓰는 몸통입니다. 입력 검사·줄 간격 복사·핸들 소유만 하고, 격자와 가장자리
// 중 무엇을 부를지는 `grid` 가 정합니다(가장자리는 물리 크기를 읽지 않습니다).
[[nodiscard]] nf_status_t detect(
    const float* const luminance,
    const std::uint32_t stride_bytes,
    const std::uint32_t width,
    const std::uint32_t height,
    const double physical_width_mm,
    const double physical_height_mm,
    const bool dimensions_valid,
    const negaflow::imaging::FlatbedFrameDimensions& dimensions,
    const bool grid,
    const std::uint32_t* const cancel_requested,
    nf_flatbed_frame_grid_summary_v1* const summary,
    nf_flatbed_frame_grid_handle_v1** const handle) {
    if (summary == nullptr || handle == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    *handle = nullptr;
    if (summary->struct_size < static_cast<std::uint32_t>(sizeof(*summary))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    const std::uint64_t row_bytes = static_cast<std::uint64_t>(width) * sizeof(float);
    if (luminance == nullptr || width == 0U || height == 0U ||
        (grid && (!std::isfinite(physical_width_mm) || !std::isfinite(physical_height_mm) ||
                  physical_width_mm <= 0.0 || physical_height_mm <= 0.0)) ||
        row_bytes > std::numeric_limits<std::uint32_t>::max() ||
        stride_bytes < row_bytes || !dimensions_valid) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    const std::uint32_t declared_size = summary->struct_size;
    std::memset(summary, 0, sizeof(*summary));
    summary->struct_size = declared_size;
    try {
        const std::size_t area = static_cast<std::size_t>(width) * height;
        if (area / height != width) return NF_STATUS_INVALID_ARGUMENT;
        std::vector<float> copy{};
        std::span<const float> plane{};
        if (stride_bytes == row_bytes) {
            plane = std::span<const float>(luminance, area);
        } else {
            copy.resize(area);
            const auto* const bytes = reinterpret_cast<const std::uint8_t*>(luminance);
            for (std::uint32_t y = 0U; y < height; ++y) {
                std::memcpy(copy.data() + static_cast<std::size_t>(y) * width,
                            bytes + static_cast<std::size_t>(y) * stride_bytes,
                            static_cast<std::size_t>(row_bytes));
            }
            plane = copy;
        }
        auto result = grid
            ? negaflow::imaging::detect_flatbed_frame_grid(
                  {plane, width, height, physical_width_mm, physical_height_mm},
                  dimensions,
                  {cancel_requested})
            : negaflow::imaging::detect_flatbed_frame_edges(
                  {plane, width, height, 0.0, 0.0},
                  dimensions,
                  {cancel_requested});
        summary->status = flatbed_frame_grid_status(result.status);
        summary->detection_count = result.detections.size();
        if (result.status != negaflow::imaging::FlatbedFrameGridStatus::ok) {
            return NF_STATUS_OK;
        }
        auto* const owned = new (std::nothrow) nf_flatbed_frame_grid_handle_v1{};
        if (owned == nullptr) {
            summary->status = NF_FLATBED_FRAME_GRID_ALLOCATION_FAILED;
            summary->detection_count = 0U;
            return NF_STATUS_OK;
        }
        owned->detections = std::move(result.detections);
        *handle = owned;
        return NF_STATUS_OK;
    } catch (const std::bad_alloc&) {
        summary->status = NF_FLATBED_FRAME_GRID_ALLOCATION_FAILED;
        return NF_STATUS_OK;
    }
}

}  // namespace

// 평판 프레임 격자 검출 C ABI 입니다. 핸들 수명을 이 번역 단위가 소유합니다.

nf_status_t NF_CALL nf_detect_flatbed_frame_grid_v1(
    const float* const luminance,
    const uint32_t stride_bytes,
    const uint32_t width,
    const uint32_t height,
    const double physical_width_mm,
    const double physical_height_mm,
    const uint32_t format,
    const uint32_t* const cancel_requested,
    nf_flatbed_frame_grid_summary_v1* const summary,
    nf_flatbed_frame_grid_handle_v1** const handle) {
    negaflow::imaging::FlatbedFrameDimensions dimensions{};
    const bool valid = flatbed_frame_dimensions(format, dimensions);
    return detect(luminance, stride_bytes, width, height, physical_width_mm,
                  physical_height_mm, valid, dimensions, true, cancel_requested, summary,
                  handle);
}

nf_status_t NF_CALL nf_detect_flatbed_frame_edges_v1(
    const float* const luminance,
    const uint32_t stride_bytes,
    const uint32_t width,
    const uint32_t height,
    const uint32_t format,
    const uint32_t* const cancel_requested,
    nf_flatbed_frame_grid_summary_v1* const summary,
    nf_flatbed_frame_grid_handle_v1** const handle) {
    negaflow::imaging::FlatbedFrameDimensions dimensions{};
    const bool valid = flatbed_frame_dimensions(format, dimensions);
    return detect(luminance, stride_bytes, width, height, 0.0, 0.0, valid, dimensions,
                  false, cancel_requested, summary, handle);
}

nf_status_t NF_CALL nf_detect_flatbed_frame_grid_dimensions_v1(
    const float* const luminance,
    const uint32_t stride_bytes,
    const uint32_t width,
    const uint32_t height,
    const double physical_width_mm,
    const double physical_height_mm,
    const nf_flatbed_frame_dimensions_v1* const dimensions,
    const uint32_t* const cancel_requested,
    nf_flatbed_frame_grid_summary_v1* const summary,
    nf_flatbed_frame_grid_handle_v1** const handle) {
    negaflow::imaging::FlatbedFrameDimensions native{};
    const bool valid = flatbed_frame_dimensions(dimensions, native);
    return detect(luminance, stride_bytes, width, height, physical_width_mm,
                  physical_height_mm, valid, native, true, cancel_requested, summary, handle);
}

nf_status_t NF_CALL nf_detect_flatbed_frame_edges_dimensions_v1(
    const float* const luminance,
    const uint32_t stride_bytes,
    const uint32_t width,
    const uint32_t height,
    const nf_flatbed_frame_dimensions_v1* const dimensions,
    const uint32_t* const cancel_requested,
    nf_flatbed_frame_grid_summary_v1* const summary,
    nf_flatbed_frame_grid_handle_v1** const handle) {
    negaflow::imaging::FlatbedFrameDimensions native{};
    const bool valid = flatbed_frame_dimensions(dimensions, native);
    return detect(luminance, stride_bytes, width, height, 0.0, 0.0, valid, native, false,
                  cancel_requested, summary, handle);
}

nf_status_t NF_CALL nf_flatbed_frame_grid_get_detection_v1(
    const nf_flatbed_frame_grid_handle_v1* const handle,
    const uint64_t index,
    nf_flatbed_frame_detection_v1* const detection) {
    if (handle == nullptr || detection == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    constexpr std::uint32_t minimum_size =
        static_cast<std::uint32_t>(offsetof(nf_flatbed_frame_detection_v1, straighten_angle));
    if (detection->struct_size < minimum_size) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    if (index >= handle->detections.size()) return NF_STATUS_INVALID_ARGUMENT;
    const auto& source = handle->detections[static_cast<std::size_t>(index)];
    const std::uint32_t declared_size = detection->struct_size;
    std::memset(detection, 0, std::min<std::size_t>(declared_size, sizeof(*detection)));
    detection->struct_size = declared_size;
    detection->row = source.row;
    detection->column = source.column;
    detection->x = source.x;
    detection->y = source.y;
    detection->width = source.width;
    detection->height = source.height;
    detection->confidence = source.confidence;
    if (declared_size >= sizeof(*detection)) {
        detection->straighten_angle = source.straighten_angle;
    }
    return NF_STATUS_OK;
}

void NF_CALL nf_flatbed_frame_grid_destroy_v1(
    nf_flatbed_frame_grid_handle_v1* const handle) {
    delete handle;
}
