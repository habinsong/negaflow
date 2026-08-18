#include "negaflow/imaging/flatbed_frame_grid_detector.h"

#include "flatbed_frame_bands.h"
#include "flatbed_frame_grid_fit.h"
#include "flatbed_frame_grid_types.h"
#include "flatbed_frame_profiles.h"
#include "flatbed_frame_signal.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

using namespace negaflow::imaging::flatbed_detail;

[[nodiscard]] bool valid_preview(const FlatbedFramePreview& preview) noexcept {
    if (preview.width <= 32U || preview.height <= 32U ||
        !std::isfinite(preview.physical_width_mm) || !std::isfinite(preview.physical_height_mm) ||
        preview.physical_width_mm <= 0.0 || preview.physical_height_mm <= 0.0 ||
        preview.luminance.size() != static_cast<std::size_t>(preview.width) * preview.height) {
        return false;
    }
    return std::all_of(preview.luminance.begin(), preview.luminance.end(), [](const float value) {
        return std::isfinite(value) && value >= 0.0F && value <= 1.0F;
    });
}

}  // namespace

FlatbedFrameGridResult detect_flatbed_frame_grid(
    const FlatbedFramePreview& preview,
    const FlatbedFrameFormat format,
    const negaflow::core::CancelFlag cancel) noexcept {
    FlatbedFrameGridResult result{};
    if (!valid_preview(preview)) {
        result.status = FlatbedFrameGridStatus::invalid_input;
        return result;
    }
    if (cancel.requested()) {
        result.status = FlatbedFrameGridStatus::cancelled;
        return result;
    }
    try {
        const auto geometry = make_geometry(preview, format);
        if (!geometry || geometry->along_pixels_y() < 8.0 || geometry->across_pixels_x() < 8.0) {
            result.status = FlatbedFrameGridStatus::invalid_input;
            return result;
        }
        const ColumnProfiles columns = column_profiles(preview);
        const std::vector<Slot> detected_slots = slots(preview, columns, *geometry);
        if (cancel.requested()) {
            result.status = FlatbedFrameGridStatus::cancelled;
            return result;
        }
        const double floor = noise_floor(columns, detected_slots);
        for (std::size_t row = 0U; row < detected_slots.size(); ++row) {
            const RowProfiles rows = row_profiles(preview, detected_slots[row].measured);
            const std::vector<IntRange> bands = film_bands(preview, rows, *geometry);
            std::uint32_t column = 0U;
            for (const IntRange band : bands) {
                if (cancel.requested()) {
                    result.detections.clear();
                    result.status = FlatbedFrameGridStatus::cancelled;
                    return result;
                }
                const auto grid = fit_grid(gap_evidence(rows, band, *geometry), *geometry, cancel);
                if (cancel.requested()) {
                    result.detections.clear();
                    result.status = FlatbedFrameGridStatus::cancelled;
                    return result;
                }
                if (!grid) continue;
                for (const DoubleRange span : occupied(frame_spans(*grid, band, *geometry), rows, floor, preview.height)) {
                    result.detections.push_back({
                        static_cast<double>(detected_slots[row].snapped.first) / preview.width,
                        span.first / preview.height,
                        static_cast<double>(detected_slots[row].snapped.count()) / preview.width,
                        (span.last - span.first) / preview.height,
                        grid->confidence,
                        static_cast<std::uint32_t>(row),
                        column++,
                    });
                }
            }
        }
        result.status = FlatbedFrameGridStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.detections.clear();
        result.status = FlatbedFrameGridStatus::allocation_failed;
        return result;
    } catch (...) {
        result.detections.clear();
        result.status = FlatbedFrameGridStatus::invalid_input;
        return result;
    }
}

const char* flatbed_frame_grid_status_name(const FlatbedFrameGridStatus status) noexcept {
    switch (status) {
        case FlatbedFrameGridStatus::ok: return "ok";
        case FlatbedFrameGridStatus::invalid_input: return "invalid_input";
        case FlatbedFrameGridStatus::cancelled: return "cancelled";
        case FlatbedFrameGridStatus::allocation_failed: return "allocation_failed";
    }
    return "unknown";
}


}  // namespace negaflow::imaging
