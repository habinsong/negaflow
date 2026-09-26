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

// 한 슬롯에 `frames` 컷을 놓은 홀더입니다. 치수는 mm 이고 8 px/mm 로 그립니다. 캔버스는
// 내용에 맞춰 잡습니다 — 65mm 파노라마 세 컷은 기존 210mm 캔버스에 들어가지 않습니다.
[[nodiscard]] Holder make_sized_holder(
    const double along_mm,
    const double across_mm,
    const double gap_mm,
    const std::uint32_t frames) {
    constexpr double pixels_per_mm = 8.0;
    constexpr std::uint32_t left = 80U;
    constexpr std::uint32_t top = 120U;
    const auto frame_width = static_cast<std::uint32_t>(std::lround(across_mm * pixels_per_mm));
    const auto frame_height = static_cast<std::uint32_t>(std::lround(along_mm * pixels_per_mm));
    const auto gap = static_cast<std::uint32_t>(std::lround(gap_mm * pixels_per_mm));
    const std::uint32_t width = frame_width + left * 2U;
    const std::uint32_t height = top * 2U + frames * (frame_height + gap);
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
    for (std::uint32_t y = top; y < top + frames * (frame_height + gap); ++y) {
        for (std::uint32_t x = left; x < left + frame_width; ++x) {
            pixels[static_cast<std::size_t>(y) * width + x] = 0.90F + noise(x, y);
        }
    }
    for (std::uint32_t frame = 0U; frame < frames; ++frame) {
        const std::uint32_t frame_top = top + frame * (frame_height + gap);
        for (std::uint32_t y = frame_top; y < frame_top + frame_height; ++y) {
            for (std::uint32_t x = left; x < left + frame_width; ++x) {
                const float coarse = std::sin(static_cast<float>(x) * 0.051F + frame) *
                    std::cos(static_cast<float>(y) * 0.041F);
                const float fine = std::sin(static_cast<float>(x) * 0.29F) *
                    std::sin(static_cast<float>(y) * 0.23F + frame);
                pixels[static_cast<std::size_t>(y) * width + x] =
                    std::clamp(0.36F + 0.14F * coarse + 0.07F * fine + noise(x, y), 0.0F, 1.0F);
            }
        }
    }
    Holder result{};
    result.expected_frames = frames;
    result.pixels = std::move(pixels);
    result.preview = {result.pixels, width, height,
                      static_cast<double>(width) / pixels_per_mm,
                      static_cast<double>(height) / pixels_per_mm};
    return result;
}

void expect_sized_detections(
    const Holder& holder,
    const negaflow::imaging::FlatbedFrameGridResult& result,
    const negaflow::imaging::FlatbedFrameDimensions& dimensions,
    const char* const count_message,
    const char* const size_message) {
    expect(result.status == negaflow::imaging::FlatbedFrameGridStatus::ok &&
               result.detections.size() == holder.expected_frames,
           count_message);
    if (result.detections.size() != holder.expected_frames) {
        std::cerr << "  along=" << dimensions.along_mm << " across=" << dimensions.across_mm
                  << " expected=" << holder.expected_frames
                  << " actual=" << result.detections.size() << '\n';
    }
    for (const auto& detection : result.detections) {
        expect(std::abs(detection.width * holder.preview.physical_width_mm -
                        dimensions.across_mm) < 2.5 &&
                   std::abs(detection.height * holder.preview.physical_height_mm -
                            dimensions.along_mm) < 2.5,
               size_message);
    }
}

// macOS `FilmFrameFormat` 의 치수·35mm 여부와 같아야 합니다. 35mm 여부는 enum 차례가 아니라
// 표가 정합니다 — 끝에 붙인 파노라마 두 규격이 enum 차례로는 120 뒤라, 차례로 가르면 120 의
// 넓은 간격(2–9mm)과 느슨한 피치로 잘못 찾습니다.
void test_frame_dimension_table_matches_macos() {
    using negaflow::imaging::FlatbedFrameFormat;
    struct Row final {
        FlatbedFrameFormat format;
        double along;
        double across;
        bool is_35mm;
    };
    constexpr Row rows[] = {
        {FlatbedFrameFormat::full_frame_35mm, 36.0, 24.0, true},
        {FlatbedFrameFormat::square_35mm, 24.0, 24.0, true},
        {FlatbedFrameFormat::half_frame_35mm, 18.0, 24.0, true},
        {FlatbedFrameFormat::panorama_35mm_56x24, 56.0, 24.0, true},
        {FlatbedFrameFormat::panorama_35mm_65x24, 65.0, 24.0, true},
        {FlatbedFrameFormat::medium_645, 41.5, 56.0, false},
        {FlatbedFrameFormat::medium_66, 56.0, 56.0, false},
        {FlatbedFrameFormat::medium_67, 69.0, 55.0, false},
        {FlatbedFrameFormat::medium_68, 76.0, 56.0, false},
        {FlatbedFrameFormat::medium_69, 84.0, 56.0, false},
        {FlatbedFrameFormat::medium_612, 112.0, 56.0, false},
        {FlatbedFrameFormat::medium_617, 168.0, 56.0, false},
    };
    for (const Row& row : rows) {
        const auto dimensions = negaflow::imaging::flatbed_frame_dimensions(row.format);
        expect(dimensions.has_value() && dimensions->along_mm == row.along &&
                   dimensions->across_mm == row.across && dimensions->is_35mm == row.is_35mm,
               "flatbed frame dimensions match the macOS table");
    }
    expect(!negaflow::imaging::flatbed_frame_dimensions(
               static_cast<FlatbedFrameFormat>(12U)).has_value(),
           "flatbed frame dimensions refuse an unknown format");
}

// macOS `testMockFlatbedSelectedFilmFormatsAutomaticallyDetectAndFullScan` 의 두 파노라마
// (각 3컷). 35mm 이송이라 간격은 2mm 입니다.
void test_finds_panoramic_35mm_frames() {
    using negaflow::imaging::FlatbedFrameFormat;
    for (const FlatbedFrameFormat format :
         {FlatbedFrameFormat::panorama_35mm_56x24, FlatbedFrameFormat::panorama_35mm_65x24}) {
        const auto dimensions = *negaflow::imaging::flatbed_frame_dimensions(format);
        Holder holder = make_sized_holder(dimensions.along_mm, dimensions.across_mm, 2.0, 3U);
        expect_sized_detections(
            holder,
            negaflow::imaging::detect_flatbed_frame_grid(holder.preview, format),
            dimensions,
            "flatbed detector finds three panoramic 35 mm frames",
            "panoramic detections keep their physical size");
    }
}

// macOS `testFindsFramesOfACustomSize` — 규격 목록에 없는 치수도 치수 입구로 찾습니다.
// 58×24 는 35mm(간격 2mm), 8:6 을 56mm 폭에 댄 것은 120(간격 4mm)입니다.
void test_finds_frames_of_a_custom_size() {
    const negaflow::imaging::FlatbedFrameDimensions horizon{58.0, 24.0, true};
    const negaflow::imaging::FlatbedFrameDimensions six_by_eight{56.0 * 8.0 / 6.0, 56.0, false};
    struct Case final {
        negaflow::imaging::FlatbedFrameDimensions dimensions;
        double gap_mm;
        std::uint32_t frames;
    };
    for (const Case& test_case : {Case{horizon, 2.0, 3U}, Case{six_by_eight, 4.0, 2U}}) {
        Holder holder = make_sized_holder(
            test_case.dimensions.along_mm, test_case.dimensions.across_mm,
            test_case.gap_mm, test_case.frames);
        expect_sized_detections(
            holder,
            negaflow::imaging::detect_flatbed_frame_grid(holder.preview, test_case.dimensions),
            test_case.dimensions,
            "flatbed detector finds frames of a custom size",
            "custom-size detections keep their physical size");
    }
    Holder holder = make_sized_holder(58.0, 24.0, 2.0, 3U);
    expect(negaflow::imaging::detect_flatbed_frame_grid(
               holder.preview, negaflow::imaging::FlatbedFrameDimensions{0.0, 24.0, true})
                   .status == negaflow::imaging::FlatbedFrameGridStatus::invalid_input &&
               negaflow::imaging::detect_flatbed_frame_edges(
                   holder.preview,
                   negaflow::imaging::FlatbedFrameDimensions{58.0, std::nan(""), true})
                       .status == negaflow::imaging::FlatbedFrameGridStatus::invalid_input,
           "flatbed detector refuses degenerate custom dimensions");
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
    test_frame_dimension_table_matches_macos();
    test_finds_panoramic_35mm_frames();
    test_finds_frames_of_a_custom_size();
    std::cout << "{\"status\":\"" << (failures == 0 ? "ok" : "error")
              << "\",\"suite\":\"flatbed_frame_grid\",\"failures\":"
              << failures << "}\n";
    return failures == 0 ? 0 : 1;
}
