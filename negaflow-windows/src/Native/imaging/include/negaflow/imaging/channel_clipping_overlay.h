#pragma once

// 현상 결과의 RGB 경계(≤0 / ≥1)를 표시하는 **프리뷰 전용** 오버레이입니다.
//
// macOS : `Imaging/ChannelClippingOverlay.swift` + `channelClippingOverlay` 커널
// 원본·현상·내보내기 화소는 바꾸지 않습니다. 투명 레이어만 냅니다.
//
// Windows 작업 이미지는 프리멀티가 **아닙니다.** macOS 커널의 `rgb / src.a` 는
// 빼야 합니다 — 나누면 알파가 1이 아닌 화소의 경계가 틀어집니다.
// 경계는 `<= 0` / `>= 1` 입니다. `< 0` / `> 1` 로 바꾸면 정확히 0/1 이 빠집니다.

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstdint>

namespace negaflow::imaging {

inline constexpr float channel_clipping_overlay_opacity = 0.62F;
inline constexpr float channel_clipping_overlay_shadow[3]{0.055F, 0.24F, 0.82F};
inline constexpr float channel_clipping_overlay_highlight[3]{0.90F, 0.07F, 0.055F};
inline constexpr float channel_clipping_overlay_mixed[3]{0.64F, 0.10F, 0.70F};

struct ChannelClippingOverlayPixel final {
    float red{0.0F};
    float green{0.0F};
    float blue{0.0F};
    float alpha{0.0F};
};

// 한 화소의 오버레이. 알파가 거의 0 이거나 경계가 없으면 전부 0 입니다.
// 반환 RGB 는 이미 opacity 가 곱해진 프리멀티입니다(macOS 커널과 같음).
[[nodiscard]] inline ChannelClippingOverlayPixel channel_clipping_overlay_pixel(
    const negaflow::core::Rgba32F& source) noexcept {
    ChannelClippingOverlayPixel overlay{};
    if (source.alpha <= 1.0e-6F) {
        return overlay;
    }
    const bool shadow =
        source.red <= 0.0F || source.green <= 0.0F || source.blue <= 0.0F;
    const bool highlight =
        source.red >= 1.0F || source.green >= 1.0F || source.blue >= 1.0F;
    if (!shadow && !highlight) {
        return overlay;
    }
    const float* color = shadow && highlight
        ? channel_clipping_overlay_mixed
        : (highlight ? channel_clipping_overlay_highlight
                     : channel_clipping_overlay_shadow);
    overlay.red = color[0] * channel_clipping_overlay_opacity;
    overlay.green = color[1] * channel_clipping_overlay_opacity;
    overlay.blue = color[2] * channel_clipping_overlay_opacity;
    overlay.alpha = channel_clipping_overlay_opacity;
    return overlay;
}

// `destination` 에 오버레이를 씁니다. 원본은 건드리지 않습니다.
// 처리했으면 `true`.
[[nodiscard]] bool apply_channel_clipping_overlay(
    const WorkingImage& source,
    WorkingImage& destination) noexcept;

} // namespace negaflow::imaging
