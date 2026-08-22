#pragma once

#include "negaflow/imaging/scanner_to_working.h"

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

struct ImageTransformParameters final {
    ImageRotation rotation{ImageRotation::degrees_0};
    bool flip_horizontal{false};
    bool flip_vertical{false};
    bool has_crop{false};
    NormalizedCropRect crop{};
    double straighten_angle{0.0};
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
// 기울이기(`straighten_angle`)는 이중선형이라 여기 담을 수 없습니다. 그때는 `false` 를
// 돌려주고 호출부가 CPU `apply_image_transform` 을 그대로 씁니다.
struct ImageTransformGather final {
    std::uint32_t output_width{0};
    std::uint32_t output_height{0};
    // 방위를 적용한 좌표계에서의 자르기 시작점입니다.
    std::uint32_t crop_left{0};
    std::uint32_t crop_top{0};
    ImageRotation rotation{ImageRotation::degrees_0};
    bool flip_horizontal{false};
    bool flip_vertical{false};
};

[[nodiscard]] bool plan_image_transform_gather(
    const ImageTransformParameters& parameters,
    std::uint32_t source_width,
    std::uint32_t source_height,
    ImageTransformGather& out) noexcept;

[[nodiscard]] bool valid_image_transform_parameters(
    const ImageTransformParameters& parameters) noexcept;

// Fixed macOS geometry order: flip H, flip V, quarter-turn rotation,
// straighten with an inscribed same-aspect crop, then normalized y-up crop.
[[nodiscard]] ImageTransformResult apply_image_transform(
    WorkingImage image,
    const ImageTransformParameters& parameters) noexcept;

[[nodiscard]] const char* image_transform_status_name(
    ImageTransformStatus status) noexcept;

} // namespace negaflow::imaging
