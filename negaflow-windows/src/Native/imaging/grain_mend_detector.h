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
    // macOS `buildLabeled(dustTrustedStrong:)` — 기존 보수 검출이나 큰 이물 검출이 직접
    // 확인한 화소입니다. 낮은 임계의 micro-only 후보와 구분해, 밀집 미세 입자는 그레인
    // 퓨즈로 버리면서 실제 고대비 먼지 여러 개는 살립니다. 확장 스케일이 꺼진 자동
    // 경로에서는 macOS 도 `nil` 을 넘기므로 비어 있습니다.
    std::vector<std::uint8_t> trusted_strong{};
    // macOS `DefectContrastField.valid` — 클리핑 명부와 순흑 평탄을 뺀 화소입니다. 미세 입자
    // 패스가 같은 것을 다시 만들지 않도록 들고 나갑니다.
    std::vector<std::uint8_t> valid{};
    // 이 타일에서 두 무거운 단계가 각각 얼마나 걸렸는지입니다. "자동이 몇 초"만으로는 어디를
    // 고쳐야 하는지 알 수 없습니다.
    std::uint64_t dust_morphology_microseconds{0U};
    std::uint64_t scratch_angles_microseconds{0U};
    std::uint64_t dust_components_collected{0U};
    std::uint64_t dust_dropped_no_strong{0U};
    std::uint64_t dust_dropped_strong_fraction{0U};
    std::uint64_t dust_dropped_gate{0U};
    std::uint64_t dust_dropped_isolation{0U};
    std::uint64_t dust_kept{0U};
    std::uint64_t dust_pixels_above_weak_abs{0U};
    std::uint64_t dust_pixels_above_abs{0U};
    std::uint64_t valid_pixels{0U};
    double dust_magnitude_sum{0.0};
    double dust_noise_sum{0.0};
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
// `extended_dust_scales` 는 macOS `DefectContrastField(extendedDustScales:)` 이며 가이드
// (부분 ROI) 경로에서만 참입니다. 참이면 미세 이물 채널(반경 4 top-hat 재사용 + 반경 8
// 잡음 바닥)과 큰 이물 채널(luma − 반경 80 박스평균)이 후보 판정에 함께 들어가고
// `trusted_strong` 이 채워집니다. 전체 프레임 자동은 macOS 도 거짓이라 기존과 같습니다.
[[nodiscard]] CandidateMaps find_candidates(
    const DetectionImage& image,
    double dust_sensitivity,
    double scratch_sensitivity,
    double protect_detail,
    bool labeled_detection = false,
    bool extended_dust_scales = false,
    negaflow::core::CancelFlag cancel = {});

void find_candidates(
    const DetectionImage& image,
    double dust_sensitivity,
    double scratch_sensitivity,
    double protect_detail,
    bool labeled_detection,
    bool extended_dust_scales,
    CandidateMaps& result,
    negaflow::core::CancelFlag cancel = {});

}  // namespace negaflow::imaging::grain_mend_detail
