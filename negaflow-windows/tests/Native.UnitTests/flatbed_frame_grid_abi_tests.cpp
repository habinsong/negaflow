#include "negaflow/abi/build_info.h"
#include "negaflow/abi/flatbed_detect.h"
#include "negaflow/imageio/wic_tiff_decoder.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        ++failures;
        std::cerr << "FAIL: " << message << '\n';
    }
}

void test_flatbed_grid_lifecycle() {
    static_assert(sizeof(nf_flatbed_frame_grid_summary_v1) == 24U);
    static_assert(sizeof(nf_flatbed_frame_detection_v1) == 64U);
    expect(nf_get_abi_version() == NF_ABI_VERSION, "abi_version_matches_public_header");

    constexpr std::uint32_t width = 640U;
    constexpr std::uint32_t height = 1'680U;
    std::vector<float> luminance(static_cast<std::size_t>(width) * height, 0.05F);
    for (std::uint32_t y = 120U; y < 1'304U; ++y) {
        for (std::uint32_t x = 80U; x < 272U; ++x) {
            const float texture = std::sin(static_cast<float>(x) * 0.051F) *
                std::cos(static_cast<float>(y) * 0.041F);
            luminance[static_cast<std::size_t>(y) * width + x] = 0.42F + texture * 0.18F;
        }
    }
    nf_flatbed_frame_grid_summary_v1 summary{};
    summary.struct_size = sizeof(summary);
    nf_flatbed_frame_grid_handle_v1* handle = nullptr;
    expect(nf_detect_flatbed_frame_grid_v1(
               luminance.data(), width * sizeof(float), width, height, 80.0, 210.0,
               NF_FLATBED_FRAME_FULL_FRAME_35MM, nullptr, &summary, &handle) == NF_STATUS_OK,
           "flatbed_call_ok");
    expect(summary.status == NF_FLATBED_FRAME_GRID_OK && summary.detection_count != 0U &&
               handle != nullptr,
           "flatbed_returns_owned_detections");
    if (handle != nullptr) {
        nf_flatbed_frame_detection_v1 detection{};
        detection.struct_size = sizeof(detection);
        expect(nf_flatbed_frame_grid_get_detection_v1(handle, 0U, &detection) == NF_STATUS_OK,
               "flatbed_detection_read");
        expect(detection.width > 0.0 && detection.height > 0.0 &&
                   detection.confidence >= 0.0 && detection.confidence <= 1.0,
               "flatbed_detection_shape");
        nf_flatbed_frame_grid_destroy_v1(handle);
    }

    summary = {};
    summary.struct_size = sizeof(summary);
    handle = nullptr;
    expect(nf_detect_flatbed_frame_edges_v1(
               luminance.data(), width * sizeof(float), width, height,
               NF_FLATBED_FRAME_FULL_FRAME_35MM, nullptr, &summary, &handle) == NF_STATUS_OK,
           "flatbed_edge_call_ok");
    expect(summary.status == NF_FLATBED_FRAME_GRID_OK,
           "flatbed_edge_reports_detector_status");
    if (handle != nullptr) nf_flatbed_frame_grid_destroy_v1(handle);

    std::uint32_t cancel = 1U;
    summary = {};
    summary.struct_size = sizeof(summary);
    handle = nullptr;
    expect(nf_detect_flatbed_frame_grid_v1(
               luminance.data(), width * sizeof(float), width, height, 80.0, 210.0,
               NF_FLATBED_FRAME_FULL_FRAME_35MM, &cancel, &summary, &handle) == NF_STATUS_OK &&
               summary.status == NF_FLATBED_FRAME_GRID_CANCELLED && handle == nullptr,
           "flatbed_cancelled_no_handle");
}

std::vector<float> make_luminance(const negaflow::imageio::DecodedImage& image) {
    const std::size_t row_samples = image.stride_bytes / sizeof(std::uint16_t);
    const std::size_t channels = negaflow::imageio::channel_count(image.layout);
    std::vector<float> luminance(static_cast<std::size_t>(image.width) * image.height);
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const std::size_t source = static_cast<std::size_t>(y) * row_samples +
                static_cast<std::size_t>(x) * channels;
            const float red = image.samples[source] / 65'535.0F;
            const float green = channels == 1U ? red : image.samples[source + 1U] / 65'535.0F;
            const float blue = channels == 1U ? red : image.samples[source + 2U] / 65'535.0F;
            luminance[static_cast<std::size_t>(y) * image.width + x] =
                std::clamp(0.2126F * red + 0.7152F * green + 0.0722F * blue, 0.0F, 1.0F);
        }
    }
    return luminance;
}

std::vector<nf_flatbed_frame_detection_v1> detect_edges(
    const std::vector<float>& luminance,
    const std::uint32_t width,
    const std::uint32_t height,
    const char* const label) {
    nf_flatbed_frame_grid_summary_v1 summary{};
    summary.struct_size = sizeof(summary);
    nf_flatbed_frame_grid_handle_v1* handle = nullptr;
    const nf_status_t status = nf_detect_flatbed_frame_edges_v1(
        luminance.data(), width * sizeof(float), width, height,
        NF_FLATBED_FRAME_FULL_FRAME_35MM, nullptr, &summary, &handle);
    if (status != NF_STATUS_OK || summary.status != NF_FLATBED_FRAME_GRID_OK ||
        handle == nullptr) {
        ++failures;
        std::cerr << "FAIL: " << label << " status=" << status
                  << " detector_status=" << summary.status << '\n';
        if (handle != nullptr) nf_flatbed_frame_grid_destroy_v1(handle);
        return {};
    }
    std::vector<nf_flatbed_frame_detection_v1> detections(
        static_cast<std::size_t>(summary.detection_count));
    for (std::uint64_t index = 0U; index < summary.detection_count; ++index) {
        detections[static_cast<std::size_t>(index)].struct_size =
            sizeof(nf_flatbed_frame_detection_v1);
        expect(nf_flatbed_frame_grid_get_detection_v1(
                   handle, index, &detections[static_cast<std::size_t>(index)]) == NF_STATUS_OK,
               "flatbed_fixture_detection_read");
    }
    nf_flatbed_frame_grid_destroy_v1(handle);
    return detections;
}

std::vector<float> rotate_counter_clockwise(
    const std::vector<float>& source,
    const std::uint32_t width,
    const std::uint32_t height) {
    std::vector<float> target(source.size(), 1.0F);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::uint32_t target_x = y;
            const std::uint32_t target_y = width - 1U - x;
            target[static_cast<std::size_t>(target_y) * height + target_x] =
                source[static_cast<std::size_t>(y) * width + x];
        }
    }
    return target;
}

struct LuminanceImage final {
    std::vector<float> pixels{};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
};

LuminanceImage rotate_and_pad(
    const std::vector<float>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const double degrees,
    const std::uint32_t left,
    const std::uint32_t top,
    const std::uint32_t right,
    const std::uint32_t bottom) {
    const double radians = degrees * 3.14159265358979323846 / 180.0;
    const double cosine = std::cos(radians);
    const double sine = std::sin(radians);
    const std::uint32_t rotated_width = static_cast<std::uint32_t>(std::ceil(
        std::abs(width * cosine) + std::abs(height * sine)));
    const std::uint32_t rotated_height = static_cast<std::uint32_t>(std::ceil(
        std::abs(width * sine) + std::abs(height * cosine)));
    LuminanceImage target{};
    target.width = rotated_width + left + right;
    target.height = rotated_height + top + bottom;
    target.pixels.assign(static_cast<std::size_t>(target.width) * target.height, 1.0F);
    const double source_center_x = static_cast<double>(width - 1U) * 0.5;
    const double source_center_y = static_cast<double>(height - 1U) * 0.5;
    const double target_center_x = static_cast<double>(rotated_width - 1U) * 0.5;
    const double target_center_y = static_cast<double>(rotated_height - 1U) * 0.5;
    for (std::uint32_t y = 0U; y < rotated_height; ++y) {
        for (std::uint32_t x = 0U; x < rotated_width; ++x) {
            const double dx = x - target_center_x;
            const double dy = y - target_center_y;
            const long source_x = std::lround(cosine * dx + sine * dy + source_center_x);
            const long source_y = std::lround(-sine * dx + cosine * dy + source_center_y);
            if (source_x < 0L || source_y < 0L ||
                source_x >= static_cast<long>(width) ||
                source_y >= static_cast<long>(height)) continue;
            target.pixels[static_cast<std::size_t>(y + top) * target.width + x + left] =
                source[static_cast<std::size_t>(source_y) * width + source_x];
        }
    }
    return target;
}

void test_scanner_simulator_fixture(
    const std::filesystem::path& path,
    const std::uint32_t expected_rows,
    const std::uint32_t expected_columns,
    const std::vector<double>& expected_angles) {
    const auto decoded = negaflow::imageio::decode_tiff_with_wic(path);
    expect(decoded.status == negaflow::imageio::WicTiffDecodeStatus::ok,
           "flatbed_fixture_decode_ok");
    if (decoded.status != negaflow::imageio::WicTiffDecodeStatus::ok) return;

    const auto luminance = make_luminance(decoded.image);
    const auto detections = detect_edges(
        luminance, decoded.image.width, decoded.image.height,
        "flatbed_fixture_edge_call");

    const std::uint64_t expected_count =
        static_cast<std::uint64_t>(expected_rows) * expected_columns;
    if (detections.size() != expected_count) {
        ++failures;
        std::cerr << "FAIL: flatbed_fixture_detection_count path=" << path.string()
                  << " expected=" << expected_count
                  << " actual=" << detections.size() << '\n';
    }
    std::vector<std::uint32_t> row_counts(expected_rows, 0U);
    for (const auto& detection : detections) {
        if (detection.row < row_counts.size()) ++row_counts[detection.row];
        if (detection.row < expected_angles.size() &&
            std::abs(detection.straighten_angle - expected_angles[detection.row]) > 0.35) {
            ++failures;
            std::cerr << "FAIL: flatbed_fixture_angle path=" << path.string()
                      << " row=" << detection.row
                      << " expected=" << expected_angles[detection.row]
                      << " actual=" << detection.straighten_angle << '\n';
        }
    }
    for (std::uint32_t row = 0U; row < expected_rows; ++row) {
        if (row_counts[row] != expected_columns) {
            ++failures;
            std::cerr << "FAIL: flatbed_fixture_row_count path=" << path.string()
                      << " row=" << row << " expected=" << expected_columns
                      << " actual=" << row_counts[row] << '\n';
        }
    }
}

void test_scanner_simulator_transforms(const std::filesystem::path& path) {
    const auto decoded = negaflow::imageio::decode_tiff_with_wic(path);
    expect(decoded.status == negaflow::imageio::WicTiffDecodeStatus::ok,
           "flatbed_transform_fixture_decode_ok");
    if (decoded.status != negaflow::imageio::WicTiffDecodeStatus::ok) return;
    const auto luminance = make_luminance(decoded.image);

    const auto counter_clockwise = rotate_counter_clockwise(
        luminance, decoded.image.width, decoded.image.height);
    const auto vertical = detect_edges(
        counter_clockwise, decoded.image.height, decoded.image.width,
        "flatbed_counter_clockwise_edge_call");
    if (vertical.size() != 6U) {
        ++failures;
        std::cerr << "FAIL: flatbed_counter_clockwise_count expected=6 actual="
                  << vertical.size() << '\n';
    }
    for (std::size_t index = 0U; index < vertical.size(); ++index) {
        expect(vertical[index].row == index && vertical[index].column == 0U,
               "flatbed_counter_clockwise_topology");
    }

    const auto skewed = rotate_and_pad(
        luminance, decoded.image.width, decoded.image.height,
        2.0, 37U, 83U, 211U, 29U);
    const auto offset = detect_edges(
        skewed.pixels, skewed.width, skewed.height,
        "flatbed_offset_skew_edge_call");
    if (offset.size() != 6U) {
        ++failures;
        std::cerr << "FAIL: flatbed_offset_skew_count expected=6 actual="
                  << offset.size() << '\n';
    }
    for (std::size_t index = 0U; index < offset.size(); ++index) {
        expect(offset[index].row == 0U && offset[index].column == index,
               "flatbed_offset_skew_topology");
        expect(std::abs(offset[index].straighten_angle) >= 0.5,
               "flatbed_offset_skew_angle");
    }
}

}  // namespace

int main(const int argc, const char* const argv[]) {
    test_flatbed_grid_lifecycle();
    if (argc >= 3) {
        test_scanner_simulator_fixture(argv[1], 1U, 6U, {0.087});
        test_scanner_simulator_fixture(argv[2], 3U, 6U, {-0.092, 0.120, 0.084});
        test_scanner_simulator_transforms(argv[1]);
    } else {
        expect(false, "flatbed_fixture_paths_required");
    }
    if (failures != 0) {
        std::cerr << failures << " flatbed ABI checks failed\n";
        return 1;
    }
    std::cout << "flatbed ABI checks passed\n";
    return 0;
}
