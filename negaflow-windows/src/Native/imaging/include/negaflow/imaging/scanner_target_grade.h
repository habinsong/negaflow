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
    float scene_anchor_weight{0.0F};
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
};

// NORITSU 장치 질감(감마 도메인 luminance USM)의 값들입니다.
//
// macOS `ScannerTargetGrade+Texture.swift` 의 `noritsuSharpenRadius = 0.9` ·
// `noritsuSharpenAmount = 0.6` 에 대응합니다. 5탭 가중치는 그 σ 의 이산 가우시안입니다.
//
// **한 곳에만 둡니다.** CPU 루프와 GPU 셰이더가 같은 값을 봐야 합니다 —
// 셰이더에 숫자를 다시 적으면 그 순간 두 벌이 됩니다.
struct ScannerTargetTextureSetup final {
    static constexpr std::size_t taps = 5U;
    float weights[taps]{};
    float amount{0.0F};
    // macOS `noritsuTexture` 의 플로어·루마 게이트. 셰이더에 다시 적지 않습니다.
    float floor_ratio{0.0F};
    float floor_absolute{0.0F};
    float luma_gate{0.0F};
};

[[nodiscard]] ScannerTargetTextureSetup scanner_target_texture_setup() noexcept;

// NORITSU 전용 감마 도메인 luminance USM. 다른 타깃은 부르지 않습니다.
// 근사 GPU 판은 `ApproximateAcceleratorScope` 안에서만 돕니다.
[[nodiscard]] negaflow::core::KernelStatus apply_noritsu_texture(
    negaflow::core::ImageView image) noexcept;

// Applies the macOS documented target character and, where provenance permits,
// the matched NORITSU/SP-3000 relative signature in gamma-domain tone and Lab
// color, then the NORITSU-only bounded luminance texture. Positive sources use
// half documented strength and monochrome sources retain only tone and texture.
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
