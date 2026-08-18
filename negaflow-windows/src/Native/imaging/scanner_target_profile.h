#pragma once

#include "negaflow/imaging/scanner_target_grade.h"

#include <array>
#include <cstddef>
#include <string_view>

namespace negaflow::imaging::scanner_target_detail {

// 스캐너 룩이 다루는 색 좌표들입니다. 프로파일 표·측정·응답·적용이 모두 같은 타입을
// 주고받아야 하므로 한 곳에 둡니다.
struct Rgb final { double red; double green; double blue; };
struct Lab final { double lightness; double a; double b; };

// 중성축이 이 밝기에서 어느 쪽으로 흐르는지의 표본입니다.
struct NeutralBin final { double luma; double a; double b; };

// 이 색상각을 얼마나 세게, 어느 쪽으로 돌리는지입니다.
struct HueAnchor final { double hue; double gain; double rotation; };

// 이 밝기에서 채도를 얼마나 살리는지입니다.
struct ChromaBand final { double luma; double gain; };

// 스캐너 한 대의 룩을 이루는 표 전부입니다. 중성·색상 항목은 고정 크기 배열에 담고
// 실제로 쓰는 개수를 따로 들고 있습니다 - 프로파일마다 항목 수가 다릅니다.
struct TargetProfile final {
    std::array<double, 9U> tone_xs;
    std::array<double, 9U> tone_delta;
    std::array<NeutralBin, 10U> neutral_bins;
    std::size_t neutral_count;
    std::array<HueAnchor, 8U> hue_anchors;
    std::size_t hue_count;
    std::array<ChromaBand, 3U> chroma_bands;
};

// 이 스캐너 룩의 절대 프로파일입니다.
[[nodiscard]] const TargetProfile& profile_for(ScannerTargetStyle target) noexcept;

// 스캐너 프로파일 ID 가 알려진 것이면 그 조합 전용 상대 프로파일을, 아니면 nullptr 을
// 냅니다. 상대 프로파일은 이미 그 스캐너로 찍힌 원본을 다시 그 룩으로 몰지 않게 합니다.
[[nodiscard]] const TargetProfile* relative_profile_for(
    ScannerTargetStyle target,
    std::wstring_view profile_id) noexcept;

}  // namespace negaflow::imaging::scanner_target_detail
