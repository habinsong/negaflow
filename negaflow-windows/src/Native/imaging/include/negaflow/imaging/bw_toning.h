#pragma once

#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstdint>

namespace negaflow::imaging {

inline constexpr char bw_toning_algorithm_version[] =
    "chromabase-bw-toning-cpu-v1";

enum class BwToningMode : std::uint8_t {
    none = 0,
    selenium,
    sepia,
};

struct BwToningParameters final {
    BwToningMode mode{BwToningMode::none};
    double shadow_hue{285.0};
    double highlight_hue{34.0};
    double strength{0.0};
};

enum class BwToningStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    invalid_image,
};

struct BwToningInfo final {
    bool neutralized{false};
    bool toned{false};
};

struct BwToningResult final {
    BwToningStatus status{BwToningStatus::invalid_parameter};
    BwToningInfo info{};
    WorkingImage image{};
};

// 화소마다 같은 값이라 한 번만 계산합니다. GPU 경로가 이것을 상수 버퍼로 올립니다 —
// **다시 구현하지 마십시오.** 두 벌이 되면 조용히 갈라집니다.
struct BwToningSetup final {
    // `hsv_tint(shadow_hue)` / `hsv_tint(highlight_hue)` — 채도는 0.78 고정입니다.
    float shadow_tint[3]{1.0F, 1.0F, 1.0F};
    float highlight_tint[3]{1.0F, 1.0F, 1.0F};
    float strength{0.0F};
    // 세피아 1.0, 셀레늄 0.0. macOS 커널의 `control.y` 와 같습니다.
    float mode{0.0F};
    // 모드가 `none` 이거나 강도가 임계 이하이면 거짓입니다. 그때는 중성화만 하고 조색은 건너뜁니다.
    bool tone{false};
};

[[nodiscard]] BwToningSetup prepare_bw_toning(
    const BwToningParameters& parameters) noexcept;

[[nodiscard]] bool valid_bw_toning_parameters(
    const BwToningParameters& parameters) noexcept;

// Matches the fixed macOS post-pipeline boundary: color film is an exact no-op;
// B&W is first neutralized with Rec.709 coefficients and then optionally toned.
[[nodiscard]] BwToningResult apply_bw_toning(
    WorkingImage image,
    NegativeFilmType film_type,
    const BwToningParameters& parameters) noexcept;

[[nodiscard]] const char* bw_toning_status_name(BwToningStatus status) noexcept;

}  // namespace negaflow::imaging
