#pragma once

#include <array>
#include <optional>

namespace negaflow::imaging {

// 변환(원근) 보정 값입니다. macOS `PerspectiveCorrection` 과 같은 이름·범위입니다.
// 모드와 안내선은 앱이 풀어서 `solved_*` 로 넘기므로 엔진은 값만 받습니다.
struct PerspectiveParameters final {
    bool active{false};
    double solved_vertical{0.0};
    double solved_horizontal{0.0};
    double solved_rotate{0.0};
    double vertical{0.0};
    double horizontal{0.0};
    double rotate{0.0};
    double aspect{0.0};
    double scale{100.0};
    double offset_x{0.0};
    double offset_y{0.0};
    bool constrain_crop{false};
};

struct PerspectivePoint final {
    double x{0.0};
    double y{0.0};
};

// 한 크기의 그림에 대한 정역 호모그래피와 남길 사각형입니다. 좌표는 픽셀(y 아래)이고 입력과
// 출력 캔버스는 같은 크기입니다.
struct PerspectiveMapping final {
    double width{0.0};
    double height{0.0};
    std::array<double, 9> forward{};
    std::array<double, 9> inverse{};
    double output_left{0.0};
    double output_top{0.0};
    double output_width{0.0};
    double output_height{0.0};
    std::array<PerspectivePoint, 4> corners{};
};

[[nodiscard]] bool valid_perspective_parameters(const PerspectiveParameters& parameters) noexcept;

// 그림을 바꾸는가. 값이 모두 중립이면 false 입니다.
[[nodiscard]] bool perspective_changes_geometry(const PerspectiveParameters& parameters) noexcept;

// 원본이 닿지 않는 빈 곳이 결과에 남는가. 자르기 제한을 켜면 그림 안의 사각형만 남아 빈 곳이
// 없습니다(macOS `PerspectiveCorrection.leavesUncoveredArea`).
[[nodiscard]] bool perspective_leaves_uncovered_area(const PerspectiveParameters& parameters) noexcept;

// macOS `PerspectiveGeometry.mapping(for:size:)` 와 같은 식입니다. 보정이 없거나 모서리가
// 카메라 뒤로 넘어가 그릴 수 없는 값이면 nullopt(그림을 그대로 둡니다).
[[nodiscard]] std::optional<PerspectiveMapping> make_perspective_mapping(
    const PerspectiveParameters& parameters, double width, double height) noexcept;

[[nodiscard]] std::optional<PerspectivePoint> apply_homography(
    const std::array<double, 9>& matrix, PerspectivePoint point) noexcept;

} // namespace negaflow::imaging
