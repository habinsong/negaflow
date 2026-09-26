import Foundation

/// 프레임 한 장의 공칭 치수(mm). 프리셋 규격에서 오거나, 수동 비율을 흔한 필름 폭에 대어
/// 만든다. 검출기는 mm를 프리뷰 픽셀로 바꿔 쓰므로 실제 길이가 필요하다.
public struct FilmFrameSize: FilmFrameDimensions, Codable, Hashable {
    /// 35mm 필름 폭(35mm)을 넘는 세로 길이는 35mm 필름에 들어갈 수 없다. 그 안이면 퍼포레이션
    /// 이송(좁은 간격·고정 피치)으로 본다.
    public static let maximum35mmAcrossMM: Double = 35

    public let stripWidthMM: Double
    public let stripHeightMM: Double
    public let is35mm: Bool

    public init(_ format: FilmFrameFormat) {
        stripWidthMM = format.stripWidthMM
        stripHeightMM = format.stripHeightMM
        is35mm = format.is35mm
    }

    /// 비율을 필름 폭 방향 길이 `acrossMM` 에 맞춰 세운다.
    public init(ratio: FilmFrameRatio, acrossMM: Double) {
        stripWidthMM = acrossMM * ratio.aspect
        stripHeightMM = acrossMM
        is35mm = acrossMM <= Self.maximum35mmAcrossMM
    }
}

/// 수동 비율(가로 : 세로). 단위가 없다 — 4 : 5 는 4mm × 5mm 가 아니다. 가로는 필름이
/// 나아가는 방향, 세로는 필름 폭 방향이다. 사용자가 그리는 프레임은 이 비율로 붙고 크기는
/// 자유롭다.
public struct FilmFrameRatio: Codable, Hashable, Sendable {
    /// 한 쪽 숫자의 범위. 0이나 음수, 터무니없이 큰 값은 오타로 본다.
    public static let valueRange: ClosedRange<Double> = 0.1...1_000
    /// 가로 ÷ 세로의 범위. 6×17 파노라마(약 2.8)를 넉넉히 넘는 1:10–10:1 까지 받는다.
    public static let aspectRange: ClosedRange<Double> = 0.1...10

    /// 비율만으로는 실제 크기를 모르므로 자동 검출은 흔한 필름 폭에 대어 본다:
    /// 35mm 필름의 화면 폭(24mm), 120 필름의 화면 폭(56mm).
    public static let candidateAcrossMM: [Double] = [24, 56]

    public let width: Double
    public let height: Double

    public init?(width: Double, height: Double) {
        guard width.isFinite, height.isFinite,
              Self.valueRange.contains(width),
              Self.valueRange.contains(height),
              Self.aspectRange.contains(width / height) else { return nil }
        self.width = width
        self.height = height
    }

    public var aspect: Double { width / height }

    public var candidateSizes: [FilmFrameSize] {
        Self.candidateAcrossMM.map { FilmFrameSize(ratio: self, acrossMM: $0) }
    }

    /// 입력한 그대로의 표기(가로 : 세로). 번역하지 않는 기술 표기다.
    public var displayName: String {
        "\(Self.number(width)) : \(Self.number(height))"
    }

    public static func number(_ value: Double) -> String {
        value.rounded() == value
            ? String(Int(value))
            : String(format: "%g", value)
    }
}
