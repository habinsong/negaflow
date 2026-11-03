#pragma once

#include "negaflow/core/pixel.h"

#include <cstddef>
#include <cstdint>
#include <string_view>

namespace negaflow::imaging {

enum class ScannerTargetStyle : std::uint8_t {
    noritsu = 0,
    sp3000,
    f135,
    hr,
};

struct ScannerTargetGradeInfo final {
    bool applied{false};
    bool texture_applied{false};
    bool relative_signature_applied{false};
};

// 스캐너 렌더링(장면과 무관한 고정 변환)의 값 전부입니다 — macOS
// `ScannerTargetGrade+Rendering.swift` 의 `renderingKernelArguments` 와 같은 값입니다.
// 단조 3차 Hermite 의 기울기까지 호스트가 미리 계산해 담습니다. CPU 루프와 GPU 셰이더가
// **같은 것**을 씁니다 — 표를 두 곳에서 만들면 그 순간 두 벌이 됩니다.
struct ScannerRenderingSetup final {
    static constexpr std::size_t tone_knots = 11U;
    static constexpr std::size_t gain_knots = 4U;
    static constexpr std::size_t balance_knots = 3U;
    float tone_ys[tone_knots]{};
    float tone_ms[tone_knots]{};
    float gain_ys[gain_knots]{};
    float gain_ms[gain_knots]{};
    // (R←G, R←B, G←R, G←B, B←R, B←G)
    float crosstalk[6]{};
    float red_ys[balance_knots]{};
    float red_ms[balance_knots]{};
    float blue_ys[balance_knots]{};
    float blue_ms[balance_knots]{};
    // 1 = 네거티브, 0.5 = 포지티브(슬라이드는 절반만 싣습니다).
    float strength{1.0F};
    bool monochrome{false};
};

// 프로파일 그레이드가 화소 루프 **밖에서** 정하는 값 전부입니다. GPU 판이 이것을
// 그대로 받습니다 — 표를 두 곳에서 만들면 그 순간 두 벌이 되어 갈라집니다.
//
// **`double` 을 float 로 내려 담습니다.** CPU 판은 Lab 왕복을 `double` 로 돌지만
// (sRGB 왕복은 CPU 도 이미 float 입니다 — `scanner_target_color.cpp:23-29`),
// D3D11 의 double 은 선택 기능이라 내장 GPU 범용성이 보장되지 않습니다.
// 그래서 GPU 판은 **근사**이고, 오차는 동치 시험이 재서 적습니다.
//
// 배열 크기는 `scanner_target_profile.h` 의 고정 크기와 같아야 합니다.
struct ScannerTargetGradeSetup final {
    static constexpr std::size_t tone_knots = 9U;
    static constexpr std::size_t neutral_capacity = 10U;
    static constexpr std::size_t hue_capacity = 8U;
    static constexpr std::size_t chroma_capacity = 3U;

    float tone_xs[tone_knots]{};
    // 세기·장면 앵커까지 반영해 호스트가 이미 만든 출력값입니다.
    float tone_ys[tone_knots]{};
    // (luma, a, b)
    float neutral_bins[neutral_capacity][3]{};
    // (hue, gain, rotation)
    float hue_anchors[hue_capacity][3]{};
    // (luma, gain)
    float chroma_bands[chroma_capacity][2]{};
    std::uint32_t neutral_count{0U};
    std::uint32_t hue_count{0U};
    float strength{0.0F};
    float chroma_keep{0.0F};
    bool monochrome{false};
    // 세기·평탄 장면 감쇠 전의 색 밀도입니다. 셰이더가 `strength × chroma_keep` 을 곱합니다.
    float color_density{0.0F};
};

// NORITSU 장치 질감(감마 도메인 luminance USM)의 값들입니다.
//
// macOS `ScannerTargetGrade+Texture.swift` 에 대응합니다. σ 는 실기 출력 해상도(35mm 긴 변
// 3089px)에서 0.9px 이고, 다른 해상도에서는 긴 변 비율로 늘고 줍니다 — 프리뷰·원본·내보내기에서
// 같은 필름 면적에 같은 반경이 걸립니다. 가중치는 그 σ 의 표본 가우시안(정규화)입니다.
//
// **한 곳에만 둡니다.** CPU 루프와 GPU 셰이더가 같은 값을 봐야 합니다 —
// 셰이더에 숫자를 다시 적으면 그 순간 두 벌이 됩니다.
struct ScannerTargetTextureSetup final {
    // σ 4px(긴 변 약 13,700px)까지 ±3σ 를 담습니다. 그보다 크면 지지를 이 크기로 자릅니다.
    static constexpr std::size_t max_taps = 25U;
    float weights[max_taps]{};
    std::uint32_t tap_count{0U};
    float amount{0.0F};
    // macOS `noritsuTexture` 의 플로어·루마 게이트. 셰이더에 다시 적지 않습니다.
    float floor_ratio{0.0F};
    float floor_absolute{0.0F};
    float luma_gate{0.0F};
};

// 긴 변 `long_edge` px 영상에 맞춘 질감 값입니다. σ 가 너무 작아(0.05px 미만) 효과가 없으면
// `tap_count` 가 0 이고 호출부는 질감을 건너뜁니다(macOS 와 같은 규칙).
[[nodiscard]] ScannerTargetTextureSetup scanner_target_texture_setup(std::uint32_t long_edge) noexcept;

// NORITSU 전용 감마 도메인 luminance USM. 다른 타깃은 부르지 않습니다.
// 근사 GPU 판은 `ApproximateAcceleratorScope` 안에서만 돕니다.
[[nodiscard]] negaflow::core::KernelStatus apply_noritsu_texture(
    negaflow::core::ImageView image) noexcept;

// 스캐너 타깃: 고정 렌더링 → 사용자가 고른 필름 프로파일의 실측 상대 차분(있을 때만) →
// NORITSU 장치 질감 순서입니다(macOS `ScannerTargetGrade.apply`). 장면을 읽지 않으므로 같은
// 화소는 사진과 무관하게 같은 값이 됩니다. 포지티브는 렌더링을 절반만 싣고, 흑백은 luma 로
// 붕괴한 뒤 톤만 남습니다.
[[nodiscard]] negaflow::core::KernelStatus apply_scanner_target_grade(
    negaflow::core::ImageView image,
    ScannerTargetStyle target,
    bool monochrome,
    bool positive,
    std::wstring_view scanner_profile_id,
    ScannerTargetGradeInfo& info) noexcept;

// 이 단계가 GPU 로 갔는지 CPU 로 물러났는지 셉니다.
//
// 커널은 실패하면 **조용히** CPU 로 물러납니다 — 그래야 GPU 가 없는 기계에서도 결과가
// 나오기 때문입니다. 그런데 그 조용함 때문에 "GPU 를 쓴다"고 믿으면서 실제로는 CPU 로
// 도는 것을 알 방법이 없었습니다. `NEGA_TIMING` 표에 함께 찍습니다.
struct TargetGradeRouteCounts final {
    std::uint64_t gpu{0U};
    std::uint64_t cpu{0U};
};

void note_target_grade_route(bool used_gpu) noexcept;

[[nodiscard]] TargetGradeRouteCounts target_grade_route_counts() noexcept;

} // namespace negaflow::imaging
