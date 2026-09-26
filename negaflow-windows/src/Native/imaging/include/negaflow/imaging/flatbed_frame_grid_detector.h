#pragma once

#include "negaflow/core/cancel_flag.h"

#include <cstdint>
#include <optional>
#include <span>
#include <vector>

namespace negaflow::imaging {

// Aperture dimensions are expressed in the strip direction first. The detector does not infer
// an aperture from image brightness: it needs the selected physical format and scan size.
//
// 값은 C ABI 번호와 같습니다. 새 규격은 끝에 붙입니다 — 선언 차례가 목록 차례도, 35mm
// 여부도 아닙니다(표시 차례는 셸의 목록이 정하고, 35mm 여부는 flatbed_frame_dimensions 가
// 명시합니다).
enum class FlatbedFrameFormat : std::uint8_t {
    full_frame_35mm = 0,
    square_35mm = 1,
    half_frame_35mm = 2,
    medium_645 = 3,
    medium_66 = 4,
    medium_67 = 5,
    medium_68 = 6,
    medium_69 = 7,
    medium_612 = 8,
    medium_617 = 9,
    panorama_35mm_56x24 = 10,
    panorama_35mm_65x24 = 11,
};

// 프레임 한 장의 공칭 치수(mm)입니다. macOS `FilmFrameSize` 와 같습니다 — 규격에서 오거나,
// 수동 비율을 흔한 필름 폭에 대어 만듭니다. 검출기는 이것만 읽습니다.
struct FlatbedFrameDimensions final {
    // 필름 스트립을 가로로 놓았을 때 프레임이 진행되는 축의 공칭 길이입니다.
    double along_mm{36.0};
    // 필름 스트립 폭 방향의 공칭 이미지 길이입니다.
    double across_mm{24.0};
    // 퍼포레이션 이송(35mm)이면 프레임 피치가 사실상 고정이고 간격이 좁습니다.
    bool is_35mm{true};
};

// 규격의 치수입니다. 모르는 값이면 답하지 않습니다.
[[nodiscard]] std::optional<FlatbedFrameDimensions> flatbed_frame_dimensions(
    FlatbedFrameFormat format) noexcept;

enum class FlatbedFrameGridStatus : std::uint8_t {
    ok = 0,
    invalid_input,
    cancelled,
    allocation_failed,
};

struct FlatbedFramePreview final {
    std::span<const float> luminance{};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    double physical_width_mm{0.0};
    double physical_height_mm{0.0};
};

struct FlatbedFrameDetection final {
    // Source-image normalized coordinates with top-left origin.
    double x{0.0};
    double y{0.0};
    double width{0.0};
    double height{0.0};
    double straighten_angle{0.0};
    double confidence{0.0};
    std::uint32_t row{0U};
    std::uint32_t column{0U};
};

struct FlatbedFrameGridResult final {
    FlatbedFrameGridStatus status{FlatbedFrameGridStatus::invalid_input};
    std::vector<FlatbedFrameDetection> detections{};
};

[[nodiscard]] FlatbedFrameGridResult detect_flatbed_frame_grid(
    const FlatbedFramePreview& preview,
    FlatbedFrameFormat format = FlatbedFrameFormat::full_frame_35mm,
    negaflow::core::CancelFlag cancel = {}) noexcept;

// 수동 비율처럼 규격 목록에 없는 치수로 찾습니다. 규격 입구는 치수로 바꿔 이리로 넘깁니다.
[[nodiscard]] FlatbedFrameGridResult detect_flatbed_frame_grid(
    const FlatbedFramePreview& preview,
    const FlatbedFrameDimensions& dimensions,
    negaflow::core::CancelFlag cancel = {}) noexcept;

// Physical dimensions are intentionally not required. This is the macOS
// FlatbedFrameDetector fallback used when the physical grid has no result.
[[nodiscard]] FlatbedFrameGridResult detect_flatbed_frame_edges(
    const FlatbedFramePreview& preview,
    FlatbedFrameFormat format = FlatbedFrameFormat::full_frame_35mm,
    negaflow::core::CancelFlag cancel = {}) noexcept;

// 가장자리 검출은 치수의 비율만 씁니다.
[[nodiscard]] FlatbedFrameGridResult detect_flatbed_frame_edges(
    const FlatbedFramePreview& preview,
    const FlatbedFrameDimensions& dimensions,
    negaflow::core::CancelFlag cancel = {}) noexcept;

[[nodiscard]] const char* flatbed_frame_grid_status_name(
    FlatbedFrameGridStatus status) noexcept;

}  // namespace negaflow::imaging
