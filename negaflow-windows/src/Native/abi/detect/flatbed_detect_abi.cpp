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

[[nodiscard]] bool flatbed_frame_format(
    const std::uint32_t value,
    negaflow::imaging::FlatbedFrameFormat& result) noexcept {
    if (value > NF_FLATBED_FRAME_MEDIUM_617) return false;
    result = static_cast<negaflow::imaging::FlatbedFrameFormat>(value);
    return true;
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
    if (summary == nullptr || handle == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    *handle = nullptr;
    if (summary->struct_size < static_cast<std::uint32_t>(sizeof(*summary))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    negaflow::imaging::FlatbedFrameFormat native_format{};
    const std::uint64_t row_bytes = static_cast<std::uint64_t>(width) * sizeof(float);
    if (luminance == nullptr || width == 0U || height == 0U ||
        !std::isfinite(physical_width_mm) || !std::isfinite(physical_height_mm) ||
        physical_width_mm <= 0.0 || physical_height_mm <= 0.0 ||
        row_bytes > std::numeric_limits<std::uint32_t>::max() ||
        stride_bytes < row_bytes || !flatbed_frame_format(format, native_format)) {
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
        auto result = negaflow::imaging::detect_flatbed_frame_grid(
            {plane, width, height, physical_width_mm, physical_height_mm},
            native_format,
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

nf_status_t NF_CALL nf_detect_flatbed_frame_edges_v1(
    const float* const luminance,
    const uint32_t stride_bytes,
    const uint32_t width,
    const uint32_t height,
    const uint32_t format,
    const uint32_t* const cancel_requested,
    nf_flatbed_frame_grid_summary_v1* const summary,
    nf_flatbed_frame_grid_handle_v1** const handle) {
    if (summary == nullptr || handle == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    *handle = nullptr;
    if (summary->struct_size < static_cast<std::uint32_t>(sizeof(*summary))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    negaflow::imaging::FlatbedFrameFormat native_format{};
    const std::uint64_t row_bytes = static_cast<std::uint64_t>(width) * sizeof(float);
    if (luminance == nullptr || width == 0U || height == 0U ||
        row_bytes > std::numeric_limits<std::uint32_t>::max() ||
        stride_bytes < row_bytes || !flatbed_frame_format(format, native_format)) {
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
        auto result = negaflow::imaging::detect_flatbed_frame_edges(
            {plane, width, height, 0.0, 0.0},
            native_format,
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
