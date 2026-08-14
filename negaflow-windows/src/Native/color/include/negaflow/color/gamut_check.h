#pragma once

#include "negaflow/color/output_color_space.h"

#include <cstdint>
#include <vector>

namespace negaflow::color {

/// 색역 판정을 왜 못 했는지. 못 했으면 **표시하지 않습니다** — macOS 도 transform 을 만들지
/// 못하면 결과를 내지 않습니다. 근사로 대신하지 않는 것이 이 기능의 계약입니다.
enum class GamutCheckStatus : std::uint8_t {
    ok = 0,
    /// 프로파일을 열지 못했습니다.
    profile_unavailable = 1,
    /// ICM 이 이 프로파일로 gamut-check 변환을 만들지 못했습니다.
    transform_unavailable = 2,
    /// 판정 중 실패했습니다.
    check_failed = 3,
    /// 입력이 비었거나 크기가 맞지 않습니다.
    invalid_input = 4,
};

/// 화소당 1바이트. 0 이면 목표 색역 안, 그 외는 밖입니다.
struct GamutCheckResult final {
    GamutCheckStatus status{GamutCheckStatus::ok};
    std::vector<std::uint8_t> out_of_gamut;
    std::uint64_t out_of_gamut_count{0U};
    std::uint32_t native_error_code{0U};
};

/// 이 색공간으로 색역 판정을 할 수 있는지. 설정 화면이 토글을 켤 수 있는지 묻는 자리입니다.
[[nodiscard]] bool gamut_check_supported(OutputColorSpace destination) noexcept;

/// sRGB 로 부호화된 8-bit BGR 화소를 목표 색공간 기준으로 판정합니다.
///
/// Windows 의 ICM 이 하는 진짜 gamut-check 변환(`ENABLE_GAMUT_CHECKING` + `CheckBitmapBits`)을
/// 씁니다. **행렬 뒤 클리핑으로 근사하지 않습니다** — macOS 가 같은 이유로 그것을 거부하며,
/// 근사하면 같은 그림에서 다른 화소가 표시됩니다.
[[nodiscard]] GamutCheckResult check_gamut_bgr8(
    const std::uint8_t* pixels,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t stride_bytes,
    OutputColorSpace destination);

}  // namespace negaflow::color
