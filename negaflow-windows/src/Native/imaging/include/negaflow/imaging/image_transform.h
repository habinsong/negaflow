#pragma once

#include "negaflow/imaging/perspective_geometry.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <array>
#include <cstdint>

namespace negaflow::imaging {

inline constexpr char image_transform_algorithm_version[] =
    "chromabase-image-transform-cpu-v1";

enum class ImageRotation : std::uint8_t {
    degrees_0 = 0,
    degrees_90,
    degrees_180,
    degrees_270,
};

struct NormalizedCropRect final {
    double x{0.0};
    double y{0.0};
    double width{1.0};
    double height{1.0};
};

// 변환(원근)으로 원본이 닿지 않는 자리를 무엇으로 둘지. 이 자리는 "데이터 없음"입니다.
// 내보내기는 알파를 담는 형식도 있으므로 불투명한 흰색으로 굽습니다(macOS `.white`). 프리뷰는
// 같은 흰색에 커버리지(알파) 0 을 실어, 알파를 보는 쪽(히스토그램·클리핑 경고·자동 보정)이 빈
// 곳을 진짜 흰 화소로 세지 않게 합니다. 알파를 무시하는 쪽은 지금처럼 흰색을 봅니다.
enum class UncoveredFill : std::uint8_t {
    opaque_white = 0,
    white_without_coverage,
};

struct ImageTransformParameters final {
    ImageRotation rotation{ImageRotation::degrees_0};
    bool flip_horizontal{false};
    bool flip_vertical{false};
    bool has_crop{false};
    NormalizedCropRect crop{};
    double straighten_angle{0.0};
    // 회전·뒤집기 뒤, 수평 보정 앞에 거는 변환(원근)입니다.
    PerspectiveParameters perspective{};
    // 맨 뒤에 둡니다 — 옛 ABI 요청이 위 필드들을 순서대로 채웁니다.
    UncoveredFill uncovered_fill{UncoveredFill::opaque_white};
};

enum class ImageTransformStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    invalid_image,
    allocation_failed,
};

struct ImageTransformInfo final {
    bool applied{false};
    bool resampled{false};
};

struct ImageTransformResult final {
    ImageTransformStatus status{ImageTransformStatus::invalid_parameter};
    ImageTransformInfo info{};
    WorkingImage image{};
};

// 기울이기가 없는 변환은 **정수 자리 옮김뿐**입니다 — 회전·뒤집기는 좌표 치환이고
// 자르기는 부분 사각형입니다. 그래서 화소를 옮겨 담는 대신 "목표 화소가 원본의 어디를
// 읽는가" 만 적어 두면, 읽는 쪽(프리뷰 발행)이 그 자리에서 바로 가져갈 수 있습니다.
//
// 왜 필요한가 — 프리뷰 사슬은 GPU 에 머무는데 `apply_image_transform` 은 호스트 버퍼를
// 새로 만듭니다. 그 한 자리 때문에 사슬이 끊기고 발행이 CPU 로 떨어졌습니다
// (`docs/performance-optimization/04-adjustment-latency.md`). 이 계획을 발행 커널에
// 넘기면 자르기가 있는 사진도 사슬이 GPU 에 머뭅니다.
//
// 기울이기(`straighten_angle`)는 CPU 가 원근 다음에 한 번 더 이중선형으로 읽으므로 여기 담지
// 않습니다. 그때는 `false` 를 돌려주고 호출부가 CPU `apply_image_transform` 을 그대로 씁니다.
// 원근만 있으면 담습니다(위 `perspective`).
struct ImageTransformGather final {
    std::uint32_t output_width{0};
    std::uint32_t output_height{0};
    // 방위를 적용한 좌표계에서의 자르기 시작점입니다. 원근이 있으면 원근 출력 위의 자리입니다.
    std::uint32_t crop_left{0};
    std::uint32_t crop_top{0};
    ImageRotation rotation{ImageRotation::degrees_0};
    bool flip_horizontal{false};
    bool flip_vertical{false};
    // 원근(변환). 수평 보정이 없을 때만 담습니다. 출력(원근 출력 사각형) 화소 중심을
    // 역호모그래피로 방위 적용 좌표에 되돌려 이중선형으로 **한 번** 읽습니다 — CPU
    // `perspective_warp` 와 같은 식입니다. 자리 옮김만 하는 방위·자르기는 그 앞뒤에서
    // 정확히 같은 화소를 고르므로, 두 단계로 나눈 CPU 결과와 같은 그림이 됩니다(셈은 float).
    bool perspective{false};
    PerspectiveParameters perspective_parameters{};
    std::array<double, 9> perspective_inverse{};
    double perspective_left{0.0};
    double perspective_top{0.0};
    std::uint32_t oriented_width{0};
    std::uint32_t oriented_height{0};
    UncoveredFill uncovered_fill{UncoveredFill::opaque_white};
};

[[nodiscard]] bool plan_image_transform_gather(
    const ImageTransformParameters& parameters,
    std::uint32_t source_width,
    std::uint32_t source_height,
    ImageTransformGather& out) noexcept;

[[nodiscard]] bool valid_image_transform_parameters(
    const ImageTransformParameters& parameters) noexcept;

// Fixed macOS geometry order: flip H, flip V, quarter-turn rotation, perspective,
// straighten with an inscribed same-aspect crop, then normalized y-up crop.
[[nodiscard]] ImageTransformResult apply_image_transform(
    WorkingImage image,
    const ImageTransformParameters& parameters) noexcept;

[[nodiscard]] const char* image_transform_status_name(
    ImageTransformStatus status) noexcept;

} // namespace negaflow::imaging
