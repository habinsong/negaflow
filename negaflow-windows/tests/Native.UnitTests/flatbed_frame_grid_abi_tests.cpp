#include "negaflow_abi.h"

#include <cmath>
#include <cstdint>
#include <iostream>
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
    static_assert(sizeof(nf_flatbed_frame_detection_v1) == 56U);
    expect(nf_get_abi_version() == 39U, "abi_minor_39");

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

}  // namespace

int main() {
    test_flatbed_grid_lifecycle();
    if (failures != 0) {
        std::cerr << failures << " flatbed ABI checks failed\n";
        return 1;
    }
    std::cout << "flatbed ABI checks passed\n";
    return 0;
}
