#pragma once

#include <array>
#include <cstdint>
#include <span>
#include <vector>

namespace negaflow::color {

// The colour space a published file is encoded in. The develop pipeline always works in
// linear light with sRGB/Rec.709 primaries; this is the last step before quantization.
enum class OutputColorSpace : std::uint8_t {
    srgb = 0,
    display_p3,
    adobe_rgb,
};

// Row-major 3x3, applied to linear RGB.
using ColorMatrix = std::array<float, 9>;

// Linear sRGB primaries into the target's linear primaries. Identity for sRGB.
//
// All three spaces are D65, so no chromatic adaptation happens here - only a change of
// primaries. Adapting to D50 belongs in the profile, not in the pixels.
[[nodiscard]] ColorMatrix linear_srgb_to(OutputColorSpace space) noexcept;

// XYZ (D65 white, Y = 1) into the target's linear RGB, row-major. This is the inverse of the
// space's RGB-to-XYZ matrix; the DNG writer stores it as ColorMatrix1 so a reader recovers the
// colours of the space the linear samples are in.
[[nodiscard]] std::array<double, 9> d65_xyz_to_linear_rgb(OutputColorSpace space) noexcept;

// The target's encoding curve. Display P3 shares the sRGB curve; Adobe RGB is gamma
// 563/256, which is the value the Adobe RGB (1998) specification states.
[[nodiscard]] float encode_output_component(float linear, OutputColorSpace space) noexcept;

// A v2 matrix/TRC ICC profile for the space. Windows ships a usable sRGB profile but not
// Display P3 or Adobe RGB, so the bytes are built here rather than read from the system -
// a file that may not exist cannot be a dependency of an export.
//
// `linear_transfer` is supported for sRGB primaries only and is used by the defect bake TIFF.
// Returns an empty vector if the space is unknown or the requested combination is unsupported.
[[nodiscard]] std::vector<std::uint8_t> build_icc_profile(
    OutputColorSpace space,
    bool linear_transfer = false);

// 임베디드 ICC 가 있는 입력을 옮길 **내부 중간 공간**입니다(Rec.2020 기본색, sRGB 곡선,
// 16비트). macOS 는 원본 색공간에서 선형 확장 작업 공간으로 곧장 옮겨 sRGB 밖 색을 남기는데,
// 16비트 sRGB 를 중간 공간으로 쓰던 앞 판은 Display P3·Adobe RGB 원본과 넓은 스캐너
// 프로파일의 색을 sRGB 에서 잘랐습니다. 게시 색공간이 아니므로 파일에 박지 않습니다.
[[nodiscard]] std::vector<std::uint8_t> build_working_intermediate_icc_profile();

// 위 중간 공간의 선형 값 → 선형 sRGB 기본색(행 우선). 결과는 음수·1 초과를 그대로 둡니다.
[[nodiscard]] ColorMatrix working_intermediate_to_linear_srgb() noexcept;

// Gray ICC(데이터 공간 'GRAY', `kTRC`)를 같은 회색 축을 갖는 RGB 행렬/TRC 프로파일로 옮깁니다.
// R=G=B 로 편 흑백 화소를 이 프로파일로 읽으면 Gray 프로파일로 읽은 것과 같은 XYZ 가 나옵니다
// (색소 합이 D50, 세 TRC 가 `kTRC`). Windows ICM 의 RGB 16비트 경로를 그대로 쓰려는 것입니다 —
// macOS 는 Core Image 가 Gray 프로파일을 그대로 받습니다. `para` 곡선은 1024 점 `curv` 로
// 펼칩니다. Gray 프로파일이 아니거나 곡선을 읽지 못하면 빈 벡터입니다.
[[nodiscard]] std::vector<std::uint8_t> rgb_profile_for_gray_profile(
    std::span<const std::uint8_t> gray_profile);

[[nodiscard]] const char* output_color_space_name(OutputColorSpace space) noexcept;

}  // namespace negaflow::color
