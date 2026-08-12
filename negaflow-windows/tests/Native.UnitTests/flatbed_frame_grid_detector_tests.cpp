#include "negaflow/imaging/flatbed_frame_grid_detector.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

struct Holder final {
    std::vector<float> pixels{};
    negaflow::imaging::FlatbedFramePreview preview{};
    std::uint32_t expected_frames{0U};
};

[[nodiscard]] Holder make_holder(
    const bool filled,
    const float gap_level = 0.90F,
    const std::uint32_t slots = 2U,
    const std::uint32_t frames_per_slot = 4U,
    const std::uint32_t frame_length_mm = 36U) {
    constexpr std::uint32_t pixels_per_mm = 8U;
    constexpr std::uint32_t width = 640U;
    constexpr std::uint32_t height = 1'680U;
    std::vector<float> pixels(static_cast<std::size_t>(width) * height, 0.05F);
    const auto noise = [](const std::uint32_t x, const std::uint32_t y) {
        const std::uint32_t bits = (x * 73'856'093U) ^ (y * 19'349'663U);
        return (static_cast<float>(bits & 0xffU) / 255.0F - 0.5F) * 0.002F;
    };
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            pixels[static_cast<std::size_t>(y) * width + x] += noise(x, y);
        }
    }
    constexpr std::uint32_t frame_width = 24U * pixels_per_mm;
    const std::uint32_t frame_height = frame_length_mm * pixels_per_mm;
    constexpr std::uint32_t gap = 2U * pixels_per_mm;
    for (std::uint32_t slot = 0U; slot < slots; ++slot) {
        const std::uint32_t x0 = 80U + slot * 260U;
        for (std::uint32_t y = 120U; y < 120U + frames_per_slot * (frame_height + gap); ++y) {
            for (std::uint32_t x = x0; x < x0 + frame_width; ++x) {
                pixels[static_cast<std::size_t>(y) * width + x] = gap_level + noise(x, y);
            }
        }
        if (!filled) continue;
        for (std::uint32_t frame = 0U; frame < frames_per_slot; ++frame) {
            const std::uint32_t top = 120U + frame * (frame_height + gap);
            for (std::uint32_t y = top; y < top + frame_height; ++y) {
                for (std::uint32_t x = x0; x < x0 + frame_width; ++x) {
                    const float coarse = std::sin(static_cast<float>(x) * 0.051F + frame) *
                        std::cos(static_cast<float>(y) * 0.041F + slot);
                    const float fine = std::sin(static_cast<float>(x) * 0.29F) *
                        std::sin(static_cast<float>(y) * 0.23F + frame);
                    pixels[static_cast<std::size_t>(y) * width + x] =
                        std::clamp(0.36F + 0.14F * coarse + 0.07F * fine + noise(x, y), 0.0F, 1.0F);
                }
            }
        }
    }
    Holder result{};
    result.expected_frames = filled ? slots * frames_per_slot : 0U;
    result.pixels = std::move(pixels);
    result.preview = {result.pixels, width, height, 80.0, 210.0};
    return result;
}

void test_finds_textured_frames_without_brightness_polarity() {
    Holder holder = make_holder(true);
    const auto result = negaflow::imaging::detect_flatbed_frame_grid(holder.preview);
    expect(result.status == negaflow::imaging::FlatbedFrameGridStatus::ok,
           "flatbed detector accepts a scaled preview");
    expect(result.detections.size() == holder.expected_frames,
           "flatbed detector finds every textured frame");
    for (const auto& detection : result.detections) {
        expect(std::abs(detection.width * 80.0 - 24.0) < 1.5 &&
                   std::abs(detection.height * 210.0 - 36.0) < 1.5,
               "flatbed detector uses physical aperture dimensions");
    }
}

void test_rejects_empty_bright_windows() {
    Holder holder = make_holder(false);
    const auto result = negaflow::imaging::detect_flatbed_frame_grid(holder.preview);
    expect(result.status == negaflow::imaging::FlatbedFrameGridStatus::ok &&
               result.detections.empty(),
           "flatbed detector does not turn empty bright holder windows into film");
}

void test_handles_dark_gap_polarity_and_cancellation() {
    Holder holder = make_holder(true, 0.04F);
    const auto result = negaflow::imaging::detect_flatbed_frame_grid(holder.preview);
    expect(result.status == negaflow::imaging::FlatbedFrameGridStatus::ok &&
               result.detections.size() == holder.expected_frames,
           "flatbed detector accepts dark slide or masked gaps");
    std::uint32_t cancel = 1U;
    const auto cancelled = negaflow::imaging::detect_flatbed_frame_grid(
        holder.preview,
        negaflow::imaging::FlatbedFrameFormat::full_frame_35mm,
        {&cancel});
    expect(cancelled.status == negaflow::imaging::FlatbedFrameGridStatus::cancelled &&
               cancelled.detections.empty(),
           "flatbed detector fails closed on cancellation");
}

void test_keeps_half_frame_axes_in_their_physical_order() {
    Holder holder = make_holder(true, 0.90F, 2U, 6U, 18U);
    const auto result = negaflow::imaging::detect_flatbed_frame_grid(
        holder.preview,
        negaflow::imaging::FlatbedFrameFormat::half_frame_35mm);
    expect(result.status == negaflow::imaging::FlatbedFrameGridStatus::ok &&
               result.detections.size() == holder.expected_frames,
           "flatbed detector keeps half-frame strip direction distinct from slot width");
    for (const auto& detection : result.detections) {
        expect(std::abs(detection.width * 80.0 - 24.0) < 1.5 &&
                   std::abs(detection.height * 210.0 - 18.0) < 1.5,
               "half-frame detections retain 24 by 18 millimetre geometry");
    }
}

void test_does_not_propagate_one_misleading_boundary() {
    Holder holder = make_holder(true, 0.28F, 1U, 4U);
    constexpr std::uint32_t width = 640U;
    constexpr std::uint32_t pixels_per_mm = 8U;
    constexpr std::uint32_t frame_height = 36U * pixels_per_mm;
    constexpr std::uint32_t gap = 2U * pixels_per_mm;
    constexpr std::uint32_t frame = 2U;
    const std::uint32_t top = 120U + frame * (frame_height + gap);
    for (std::uint32_t y = top; y < top + 7U * pixels_per_mm; ++y) {
        for (std::uint32_t x = 80U; x < 80U + 24U * pixels_per_mm; ++x) {
            holder.pixels[static_cast<std::size_t>(y) * width + x] = 0.045F;
        }
    }
    const auto result = negaflow::imaging::detect_flatbed_frame_grid(holder.preview);
    expect(result.status == negaflow::imaging::FlatbedFrameGridStatus::ok &&
               result.detections.size() == 4U,
           "flatbed detector keeps a strip across one misleading boundary");
    for (std::uint32_t index = 0U; index < result.detections.size(); ++index) {
        const double expected_top_mm = static_cast<double>(120U + index * (frame_height + gap)) / pixels_per_mm;
        expect(std::abs(result.detections[index].y * 210.0 - expected_top_mm) < 0.35,
               "flatbed detector keeps unaffected frames on their physical grid");
    }
}

}  // namespace

int main() {
    test_finds_textured_frames_without_brightness_polarity();
    test_rejects_empty_bright_windows();
    test_handles_dark_gap_polarity_and_cancellation();
    test_keeps_half_frame_axes_in_their_physical_order();
    test_does_not_propagate_one_misleading_boundary();
    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"flatbed_frame_grid\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
