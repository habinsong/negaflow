#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/image_transform.h"

#include <cstdint>
#include <optional>

namespace negaflow::imaging {

// 장면 측정(반전 Dmax, 자동 레벨·색상, 뮤트 채도, 커브 대역, 스캐너 타깃 기준값)을 할 영역입니다.
// macOS `AnalysisRegion` 과 같은 뜻입니다 — 사용자가 크롭한 사진 영역을 변형 전 원본 좌표로
// 되돌린 정규 사각형입니다.
//
// 왜: 디지털 카메라 스캔은 필름보다 넓게 찍혀 백라이트·홀더·리베이트·이웃 프레임이 함께
// 들어옵니다. 측정이 크롭 전 전체를 보면 홀더 가장자리 혼합 화소가 최농부를 차지해 Dmax 가
// 채널마다 다르게 잡히고(2026-10-14 실측 R/B 0.72~0.98 캐스트), 자동 레벨은 홀더를
// 화이트포인트로 잡습니다. 베이스는 여기서 찾지 않습니다 — 크롭 안에는 필름 베이스가 없습니다.
//
// **y-down**(행 0 = 위)으로 둡니다. Windows 버퍼의 행 순서와 같아 쓰는 쪽마다 뒤집지
// 않습니다(macOS 는 Core Image 의 y-up 입니다).
struct AnalysisRegion final {
    double left{0.0};
    double top{0.0};
    double width{1.0};
    double height{1.0};
};

// 화소 사각형(y-down)입니다.
struct AnalysisPixelRect final {
    std::uint32_t x{0U};
    std::uint32_t y{0U};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
};

// 단위 사각형으로 자른 영역입니다. 너무 작으면(2% 이하) 또는 사실상 전체면 없습니다 —
// 그때는 기존 측정(전체 프레임, 가장자리 인셋)을 그대로 씁니다.
[[nodiscard]] std::optional<AnalysisRegion> make_analysis_region(
    double left,
    double top,
    double width,
    double height) noexcept;

// 크롭·수평 보정이 있을 때만 영역이 생깁니다. 회전·뒤집기만으로는 보이는 내용이 같습니다.
// `source_width`·`source_height` 는 변형 전 원본의 화소 크기입니다(비율만 씁니다 — 수평
// 보정 역변환에 필요합니다).
[[nodiscard]] std::optional<AnalysisRegion> analysis_region_from_transform(
    const ImageTransformParameters& transform,
    std::uint32_t source_width,
    std::uint32_t source_height) noexcept;

// 표시 정규 좌표(변형 후, y-down) → 변형 전 원본 정규 좌표(y-down). macOS
// `ImageTransform.displayUnitToBase(_:baseSize:)` 와 같은 순서로 풉니다.
struct NormalizedPoint final {
    double x{0.0};
    double y{0.0};
};

[[nodiscard]] NormalizedPoint display_unit_to_base(
    const ImageTransformParameters& transform,
    NormalizedPoint display,
    std::uint32_t source_width,
    std::uint32_t source_height) noexcept;

// 측정에 쓸 화소 사각형입니다. 영역이 없거나 사각형이 가로·세로 8 화소 이하이면 없습니다 —
// 호출부가 전체 화상을 잽니다(macOS `measurementImage` 와 같은 판정).
[[nodiscard]] std::optional<AnalysisPixelRect> analysis_measurement_rect(
    const std::optional<AnalysisRegion>& region,
    std::uint32_t image_width,
    std::uint32_t image_height) noexcept;

// 사각형만 보는 부분 뷰입니다. 호스트 화소가 최신일 때만 쓰십시오 — GPU 에 상주한 화상의
// 호스트 사본은 낡았을 수 있습니다(`downsample_region_for_statistics` 참고).
[[nodiscard]] negaflow::core::ConstImageView analysis_subview(
    negaflow::core::ConstImageView image,
    const AnalysisPixelRect& rect) noexcept;

} // namespace negaflow::imaging
