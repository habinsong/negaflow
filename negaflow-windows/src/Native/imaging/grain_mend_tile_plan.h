#pragma once

#include "grain_mend_component_types.h"
#include "grain_mend_detection_image.h"
#include "grain_mend_detector.h"

#include "negaflow/imaging/grain_mend.h"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// 타일 자르기와 타일 결과를 전역 좌표로 옮기는 일입니다. 실행 순서(배치·병렬·stitch)는
// grain_mend_tiled.cpp 가 소유합니다.

inline constexpr std::uint32_t automatic_tile_maximum = 1'400U;
// The macOS detector raises the public 48px request to its largest fixed
// context support (80px) before tiling. Keeping the effective halo here avoids
// clipping far-texture statistics at a core boundary.
inline constexpr std::uint32_t automatic_tile_halo = 80U;
inline constexpr double base_maximum_dust_area = 150.0;
// macOS `detectComponents` runs at most four tiles at once: every tile holds
// full-size float planes, so starting them all peaks memory and stalls the UI.
inline constexpr std::size_t maximum_concurrent_tiles = 4U;

// 타일 한 장이 쓰는 작업 공간입니다. 배치 안에서 타일마다 하나씩 가집니다.
struct TileWorkspace {
    DetectionImage tile{};
    CandidateMaps candidates{};
    std::vector<std::uint8_t> evidence{};
    std::vector<std::uint8_t> specks{};
    std::vector<float> speck_confidence{};
    std::uint64_t image_microseconds{0U};
    std::uint64_t evidence_microseconds{0U};
    std::uint64_t speck_microseconds{0U};
};

// 타일 한 장이 어디를 읽고 어디를 쓰는지입니다. detect 는 halo 를 포함한 읽기 범위,
// core 는 실제로 결과를 쓰는 범위입니다.
struct TilePlacement {
    std::uint32_t core_x0 = 0U;
    std::uint32_t core_y0 = 0U;
    std::uint32_t core_x1 = 0U;
    std::uint32_t core_y1 = 0U;
    std::uint32_t detect_x0 = 0U;
    std::uint32_t detect_y0 = 0U;
    std::uint32_t detect_x1 = 0U;
    std::uint32_t detect_y1 = 0U;
};

[[nodiscard]] std::uint32_t ceil_divide(
    std::uint32_t value,
    std::uint32_t divisor) noexcept;

/// macOS `detectComponents` 의 먼지 면적 상한입니다. **원본 프레임 긴 변**을 기준으로 재므로
/// ROI 를 작게 그리든 크게 그리든 같은 물리 먼지 크기가 됩니다.
[[nodiscard]] double base_dust_area(const WorkingImage& image) noexcept;

/// macOS `detectLabeledWithResponse`: `max(6, max(w, h) / (120 + s * 120))`.
[[nodiscard]] std::uint32_t minimum_scratch_length(
    const DetectionImage& tile,
    double dust_sensitivity) noexcept;

[[nodiscard]] Component to_raw_component(const ClassifiedComponent& source);

// macOS 타일 `detectLabeled`: 게이트가 끝난 evidence 에서 성분을 모으고 그 타일에서
// 분류한 뒤, core 화소만 전역 좌표로 옮긴다. stitch 가 이 목록을 union 한다.
void append_mapped_core_components(
    const TileWorkspace& workspace,
    const TilePlacement& placement,
    std::uint32_t region_width,
    std::size_t classification_dust_area,
    std::vector<ClassifiedComponent>& mapped);

}  // namespace negaflow::imaging::grain_mend_detail
