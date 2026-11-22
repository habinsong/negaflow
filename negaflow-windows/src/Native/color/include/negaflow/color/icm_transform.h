#pragma once

#include <Windows.h>
#include <icm.h>

#include <cstdint>

namespace negaflow::color {

/// Windows ICM 변환을 만듭니다.
///
/// 1순위는 기존 고속 ICC 경로(상대 색도 + BEST_MODE, 왕복 프루프면 USE_RELATIVE_COLORIMETRIC
/// 포함)입니다. A2B0/B2A0 전용 LUT 프로파일이나 구형 ICM2 CMM 이 거절하는 ICC v4 LUT 프로파일은
/// 지각 의도 및 WCS_ALWAYS 경로로 단계적으로 물러납니다.
[[nodiscard]] HTRANSFORM create_icm_transform(
    HPROFILE* profiles,
    DWORD profile_count,
    bool round_trip_proof,
    std::uint32_t& native_error_code) noexcept;

}  // namespace negaflow::color
