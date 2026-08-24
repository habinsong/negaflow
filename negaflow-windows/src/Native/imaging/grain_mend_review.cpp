#include "negaflow/imaging/grain_mend_review.h"

#include "grain_mend_component_types.h"
#include "grain_mend_detection_image.h"
#include "grain_mend_mask_paint.h"

#include <algorithm>
#include <cstdlib>
#include <limits>
#include <new>
#include <utility>

namespace negaflow::imaging {

namespace {

constexpr std::size_t total_preview_budget = 24'000U;
constexpr std::size_t maximum_preview_per_component = 800U;

[[nodiscard]] std::size_t preview_stride(
    const std::size_t pixel_count,
    const std::size_t component_count) noexcept {
    const std::size_t per_component = std::max<std::size_t>(
        1U,
        std::min(
            maximum_preview_per_component,
            total_preview_budget / std::max<std::size_t>(1U, component_count)));
    return std::max<std::size_t>(
        1U,
        (pixel_count + per_component - 1U) / per_component);
}

[[nodiscard]] bool checked_area(
    const std::uint32_t width,
    const std::uint32_t height,
    std::size_t& area) noexcept {
    if (width == 0U || height == 0U ||
        static_cast<std::size_t>(width) >
            std::numeric_limits<std::size_t>::max() / height) {
        return false;
    }
    area = static_cast<std::size_t>(width) * height;
    return true;
}

}  // namespace

GrainMendReview::GrainMendReview(
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t source_width,
    const std::uint32_t source_height,
    const std::uint32_t roi_x,
    const std::uint32_t roi_y,
    const std::uint32_t roi_width,
    const std::uint32_t roi_height,
    std::vector<grain_mend_detail::ClassifiedComponent> components)
    : width_(width),
      height_(height),
      source_width_(source_width),
      source_height_(source_height),
      roi_x_(roi_x),
      roi_y_(roi_y),
      components_(std::move(components)) {
    std::size_t field_area = 0U;
    if (!checked_area(width_, height_, field_area) ||
        width_ != roi_width || height_ != roi_height ||
        source_width_ == 0U || source_height_ == 0U ||
        roi_x_ > source_width_ || roi_y_ > source_height_ ||
        roi_width > source_width_ - roi_x_ || roi_height > source_height_ - roi_y_ ||
        components_.size() > std::numeric_limits<std::uint32_t>::max()) {
        return;
    }

    std::size_t label_count = 0U;
    for (const auto& component : components_) {
        if (component.pixels.size() >
            std::numeric_limits<std::size_t>::max() - label_count) {
            return;
        }
        label_count += component.pixels.size();
    }
    labels_.reserve(label_count);
    for (std::size_t component_index = 0U;
         component_index < components_.size();
         ++component_index) {
        const auto& component = components_[component_index];
        if (component.pixels.empty() || component.minimum_x > component.maximum_x ||
            component.minimum_y > component.maximum_y ||
            component.maximum_x >= width_ || component.maximum_y >= height_) {
            labels_.clear();
            return;
        }
        for (const std::size_t pixel : component.pixels) {
            if (pixel >= field_area) {
                labels_.clear();
                return;
            }
            labels_.push_back(LabelEntry{
                pixel,
                static_cast<std::uint32_t>(component_index),
                component.is_scratch});
        }
    }
    std::sort(
        labels_.begin(),
        labels_.end(),
        [](const LabelEntry& first, const LabelEntry& second) noexcept {
            if (first.pixel != second.pixel) return first.pixel < second.pixel;
            // macOS builds dust labels first and lets scratches occupy only empty pixels.
            if (first.is_scratch != second.is_scratch) return !first.is_scratch;
            return first.component < second.component;
        });
    labels_.erase(
        std::unique(
            labels_.begin(),
            labels_.end(),
            [](const LabelEntry& first, const LabelEntry& second) noexcept {
                return first.pixel == second.pixel;
            }),
        labels_.end());
    valid_ = true;
}

std::size_t GrainMendReview::preview_point_count() const noexcept {
    std::size_t count = 0U;
    for (const auto& component : components_) {
        const std::size_t stride = preview_stride(
            component.pixels.size(), components_.size());
        const std::size_t taken =
            (component.pixels.size() + stride - 1U) / stride;
        if (taken > std::numeric_limits<std::size_t>::max() - count) {
            return std::numeric_limits<std::size_t>::max();
        }
        count += taken;
    }
    return count;
}

std::optional<std::size_t> GrainMendReview::owner(
    const std::size_t pixel) const noexcept {
    const auto found = std::lower_bound(
        labels_.begin(),
        labels_.end(),
        pixel,
        [](const LabelEntry& entry, const std::size_t value) noexcept {
            return entry.pixel < value;
        });
    if (found == labels_.end() || found->pixel != pixel) {
        return std::nullopt;
    }
    return found->component;
}

std::optional<std::size_t> GrainMendReview::nearest_component(
    const std::int32_t x,
    const std::int32_t y,
    const std::uint32_t radius) const noexcept {
    if (!valid_) return std::nullopt;
    const auto at = [&](const std::int64_t sample_x,
                        const std::int64_t sample_y) noexcept
        -> std::optional<std::size_t> {
        if (sample_x < 0 || sample_y < 0 ||
            sample_x >= width_ || sample_y >= height_) {
            return std::nullopt;
        }
        return owner(
            static_cast<std::size_t>(sample_y) * width_ +
            static_cast<std::size_t>(sample_x));
    };
    if (const auto exact = at(x, y)) return exact;

    const std::uint32_t bounded_radius = std::min(
        radius,
        std::max(width_, height_));
    for (std::uint32_t ring = 1U; ring <= bounded_radius; ++ring) {
        std::optional<std::size_t> best{};
        const std::int64_t distance = ring;
        for (std::int64_t dy = -distance; dy <= distance; ++dy) {
            for (std::int64_t dx = -distance; dx <= distance; ++dx) {
                if (std::max(std::abs(dx), std::abs(dy)) != distance) continue;
                if (const auto candidate = at(
                        static_cast<std::int64_t>(x) + dx,
                        static_cast<std::int64_t>(y) + dy)) {
                    best = candidate;
                }
            }
        }
        if (best) return best;
    }
    return std::nullopt;
}

GrainMendAcceptedRegion GrainMendReview::build_accepted(
    const std::span<const std::uint8_t> excluded) const noexcept {
    GrainMendAcceptedRegion result{};
    if (!valid_ || excluded.size() != components_.size()) {
        return result;
    }

    try {
        std::uint32_t minimum_x = width_;
        std::uint32_t minimum_y = height_;
        std::uint32_t maximum_x = 0U;
        std::uint32_t maximum_y = 0U;
        for (std::size_t index = 0U; index < components_.size(); ++index) {
            if (excluded[index] != 0U) continue;
            const auto& component = components_[index];
            minimum_x = std::min(minimum_x, component.minimum_x);
            minimum_y = std::min(minimum_y, component.minimum_y);
            maximum_x = std::max(maximum_x, component.maximum_x);
            maximum_y = std::max(maximum_y, component.maximum_y);
            ++result.included_component_count;
        }
        if (result.included_component_count == 0U) {
            result.status = GrainMendAcceptedRegionStatus::empty;
            return result;
        }

        const std::uint32_t x0 = minimum_x > grain_mend_review_window_padding
            ? minimum_x - grain_mend_review_window_padding
            : 0U;
        const std::uint32_t y0 = minimum_y > grain_mend_review_window_padding
            ? minimum_y - grain_mend_review_window_padding
            : 0U;
        const std::uint32_t x1 = static_cast<std::uint32_t>(std::min<std::uint64_t>(
            width_,
            static_cast<std::uint64_t>(maximum_x) + 1U +
                grain_mend_review_window_padding));
        const std::uint32_t y1 = static_cast<std::uint32_t>(std::min<std::uint64_t>(
            height_,
            static_cast<std::uint64_t>(maximum_y) + 1U +
                grain_mend_review_window_padding));
        result.width = x1 - x0;
        result.height = y1 - y0;
        std::size_t window_area = 0U;
        std::size_t field_area = 0U;
        if (!checked_area(result.width, result.height, window_area) ||
            !checked_area(width_, height_, field_area) ||
            window_area > std::numeric_limits<std::size_t>::max() / 4U) {
            return result;
        }

        grain_mend_detail::DetectionImage window{};
        window.width = result.width;
        window.height = result.height;
        std::vector<std::uint8_t> mono(window_area, 0U);
        for (std::size_t index = 0U; index < components_.size(); ++index) {
            if (excluded[index] != 0U) continue;
            const auto& source = components_[index];
            grain_mend_detail::Component local{};
            local.pixels.reserve(source.pixels.size());
            local.minimum_x = result.width;
            local.minimum_y = result.height;
            for (const std::size_t pixel : source.pixels) {
                const std::uint32_t x = static_cast<std::uint32_t>(pixel % width_);
                const std::uint32_t y = static_cast<std::uint32_t>(pixel / width_);
                const std::uint32_t local_x = x - x0;
                const std::uint32_t local_y = y - y0;
                local.pixels.push_back(
                    static_cast<std::size_t>(local_y) * result.width + local_x);
                local.minimum_x = std::min(local.minimum_x, local_x);
                local.minimum_y = std::min(local.minimum_y, local_y);
                local.maximum_x = std::max(local.maximum_x, local_x);
                local.maximum_y = std::max(local.maximum_y, local_y);
            }
            grain_mend_detail::paint_component(
                local,
                source.is_scratch
                    ? static_cast<int>(grain_mend_review_scratch_dilate_radius)
                    : static_cast<int>(grain_mend_review_dust_dilate_radius),
                window,
                mono);
            if (!source.is_scratch) {
                grain_mend_detail::fill_interior_holes(
                    local, window, field_area, mono);
            }
        }

        result.rgba.resize(window_area * 4U);
        for (std::size_t pixel = 0U; pixel < window_area; ++pixel) {
            if (mono[pixel] == 0U) continue;
            const std::size_t offset = pixel * 4U;
            result.rgba[offset] = 255U;
            result.rgba[offset + 1U] = 255U;
            result.rgba[offset + 2U] = 255U;
            result.rgba[offset + 3U] = 255U;
            ++result.marked_pixel_count;
        }
        result.roi_x = roi_x_ + x0;
        result.roi_y = roi_y_ + y0;
        result.status = GrainMendAcceptedRegionStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result = {};
        result.status = GrainMendAcceptedRegionStatus::allocation_failed;
        return result;
    } catch (...) {
        result = {};
        result.status = GrainMendAcceptedRegionStatus::allocation_failed;
        return result;
    }
}

}  // namespace negaflow::imaging
