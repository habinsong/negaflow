import SwiftUI
import AppKit
import Chromabase

enum InspectorSliderFocus: Hashable {
    case exposure
    case contrast
    case highlight
    case shadow
    case whites
    case blacks
    case density
    case curveHighlights
    case curveLights
    case curveDarks
    case curveShadows
    case warmth
    case tint
    case vibrance
    case saturation
    case colorDepth
    case redPrimary
    case greenPrimary
    case bluePrimary
    case noiseReduction
    case noiseReductionLuma
    case noiseReductionChroma
    case noiseReductionDarkTone
    case noiseReductionDetail
    case noiseReductionGrainProtect
    case grain
    case sharpness
    case clarity
    case halation
    case vignette
}

/// 우측 Develop 패널 공통 평면 카드 — 둥근 모서리 + 은은한 면, 그림자 없음.
/// 내부 컨트롤(특히 Slider)이 항상 좌우 풀폭이 되도록 Form 2단 레이아웃을 쓰지 않는다.
