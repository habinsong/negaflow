import Foundation

// MARK: - Develop 고급 색/톤 조정 파라미터 (Lightroom 대응)
//
// DevelopParameters의 Codable 변경을 최소화하려고 기능별 서브구조체로 묶는다. 각 구조체는
// 멤버와이즈 기본값으로 "조정 없음(identity)"을 표현하고, 엔진은 isIdentity면 단계를 건너뛴다.

// MARK: 포인트 톤 커브 (DR/R/G/B)

public struct CurvePoint: Codable, Sendable, Equatable {
    public var x: Double   // 입력 0...1
    public var y: Double   // 출력 0...1
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Lightroom 포인트 커브 4채널: RGB(휘도·계조), Red, Green, Blue. 빈 배열 = 직선(identity).
public struct PointCurves: Codable, Sendable, Equatable {
    public var rgb: [CurvePoint] = []
    public var red: [CurvePoint] = []
    public var green: [CurvePoint] = []
    public var blue: [CurvePoint] = []
    public init() {}

    /// 끝점만 있거나 비어 있으면 직선으로 간주.
    public static func isLinear(_ pts: [CurvePoint]) -> Bool {
        guard pts.count >= 2 else { return true }
        // 모든 점이 y=x 위에 있으면 직선.
        return pts.allSatisfy { abs($0.y - $0.x) < 1e-4 }
    }

    public var isIdentity: Bool {
        Self.isLinear(rgb) && Self.isLinear(red) && Self.isLinear(green) && Self.isLinear(blue)
    }
}

// MARK: Color Mixer (HSL) — 8색

/// Lightroom HSL 8색 순서: 빨강·주황·노랑·초록·바다색(aqua)·파랑·자주(purple)·자홍(magenta).
public enum MixerBand: Int, CaseIterable, Sendable {
    case red, orange, yellow, green, aqua, blue, purple, magenta

    /// 색상환 중심 각도(도).
    public var hueCenter: Double {
        switch self {
        case .red: return 0
        case .orange: return 30
        case .yellow: return 60
        case .green: return 120
        case .aqua: return 180
        case .blue: return 240
        case .purple: return 270
        case .magenta: return 300
        }
    }
}

public struct ColorMixer: Codable, Sendable, Equatable {
    public var hue: [Double] = Array(repeating: 0, count: 8)        // -1...1 (색조 이동)
    public var saturation: [Double] = Array(repeating: 0, count: 8) // -1...1
    public var luminance: [Double] = Array(repeating: 0, count: 8)  // -1...1
    public init() {}

    public var isIdentity: Bool {
        (hue + saturation + luminance).allSatisfy { abs($0) < 1e-4 }
    }
}

// MARK: Color Grading — 3 영역(어두운/중간/밝은) 휠 + blending/balance

public struct ColorGradeRegion: Codable, Sendable, Equatable {
    public var hue: Double = 0          // 0...360 (휠 각도)
    public var saturation: Double = 0   // 0...1 (휠 반경)
    public var luminance: Double = 0    // -1...1
    public init() {}
    public var isActive: Bool { saturation > 1e-4 || abs(luminance) > 1e-4 }
}

public struct ColorGrading: Codable, Sendable, Equatable {
    public var shadows = ColorGradeRegion()
    public var midtones = ColorGradeRegion()
    public var highlights = ColorGradeRegion()
    public var blending: Double = 0.5   // 0...1 (영역 겹침 정도, 기본 0.5)
    public var balance: Double = 0      // -1...1 (영역 경계 이동)
    public init() {}

    public var isIdentity: Bool {
        !shadows.isActive && !midtones.isActive && !highlights.isActive
    }
}

// MARK: Calibration — Red/Green/Blue Primary 의 Hue/Saturation

public struct CalibrationAdjust: Codable, Sendable, Equatable {
    public var redHue: Double = 0;   public var redSat: Double = 0    // -1...1
    public var greenHue: Double = 0; public var greenSat: Double = 0
    public var blueHue: Double = 0;  public var blueSat: Double = 0
    public init() {}

    public var isIdentity: Bool {
        [redHue, redSat, greenHue, greenSat, blueHue, blueSat].allSatisfy { abs($0) < 1e-4 }
    }
}
