#pragma once

#include "negaflow/core/cancel_flag.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <array>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

struct DetectionImage final {
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::array<std::vector<float>, 3U> channels{};
    std::vector<float> luminance{};
    std::vector<float> brightest_channel{};
};

struct CandidateMaps final {
    // Bit 0 = dust response, bit 1 = directional scratch response.
    std::vector<std::uint8_t> weak{};
    std::vector<std::uint8_t> strong{};
    std::vector<float> scratch_response{};
    // 분류기가 읽는 국소 통계입니다. macOS `DefectContrastField` 의 같은 이름 배열이며,
    // 검출이 이미 계산해 둔 값을 버리지 않고 들고 있을 뿐이라 추가 비용이 없습니다.
    // 분류를 요청하지 않은 호출에서는 비어 있습니다.
    std::vector<float> dust_magnitude{};
    std::vector<float> thin_magnitude{};
    std::vector<float> noise_scale{};
};

[[nodiscard]] DetectionImage make_detection_image(const WorkingImage& image);

[[nodiscard]] DetectionImage make_detection_image_region(
    const WorkingImage& image,
    std::uint32_t origin_x,
    std::uint32_t origin_y,
    std::uint32_t width,
    std::uint32_t height);

void make_detection_image_region(
    const WorkingImage& image,
    std::uint32_t origin_x,
    std::uint32_t origin_y,
    std::uint32_t width,
    std::uint32_t height,
    DetectionImage& result);

// Cancellation is checked between the morphology passes and the directional scratch
// integration, which is where nearly all of the time goes. A cancelled call returns
// partial maps; the caller polls the same flag and discards them.
[[nodiscard]] CandidateMaps find_candidates(
    const DetectionImage& image,
    double dust_sensitivity,
    double scratch_sensitivity,
    double protect_detail,
    bool labeled_detection = false,
    negaflow::core::CancelFlag cancel = {});

void find_candidates(
    const DetectionImage& image,
    double dust_sensitivity,
    double scratch_sensitivity,
    double protect_detail,
    bool labeled_detection,
    CandidateMaps& result,
    negaflow::core::CancelFlag cancel = {});

}  // namespace negaflow::imaging::grain_mend_detail
