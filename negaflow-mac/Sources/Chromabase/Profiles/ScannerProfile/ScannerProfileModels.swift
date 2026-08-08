import Foundation

public enum ScannerProfileValidationStatus: String, Codable, Sendable, CaseIterable {
    case draft
    case realOnly
    case pairedSmoke
    case pairedValidated

    /// 자동 선택은 실제 입력/타깃 쌍으로 품질 기준을 통과한 프로파일만 허용한다.
    /// 그 외 상태도 사용자가 명시적으로 선택하는 수동 경로에서는 계속 사용할 수 있다.
    public var allowsAutomaticUse: Bool {
        self == .pairedValidated
    }

    /// NORITSU/FUJI 타깃을 사용자가 직접 선택한 경우에는 REAL 스캔에서 측정한 프로파일도
    /// 스캐너 공통 시그니처에 사용할 수 있다. 자동 필름 매칭과 달리 명시적 opt-in 경로다.
    public var allowsExplicitTargetUse: Bool {
        self != .draft
    }
}

public struct ScannerProfileStat: Codable, Sendable, Equatable {
    public var count: Double
    public var mean: Double
    public var median: Double
    public var p10: Double
    public var p90: Double
    public var min: Double
    public var max: Double
}

public struct ScannerProfileCandidate: Codable, Sendable, Equatable {
    public var stem: String
    public var realFile: String
    public var p50: Double
    public var contrastP90P10: Double
    public var midChroma: Double
}

public struct ScannerProfileCoverageAxis: Codable, Sendable, Equatable {
    public var axis: String
    public var candidates: [ScannerProfileCandidate]
}

public struct ScannerProfileSceneBucket: Codable, Sendable, Equatable {
    public var family: String
    public var name: String
    public var imageCount: Int
    public var tone: [String: ScannerProfileStat]
    public var color: [String: ScannerProfileStat]
    public var texture: [String: ScannerProfileStat]
    public var representativeCandidates: [ScannerProfileCandidate]
}

/// 중립축(HSV sat<0.08 픽셀) luma bin 별 Lab a*/b* 실측 드리프트 — 스캐너의 중립 렌더링 시그니처.
public struct ScannerProfileNeutralBin: Codable, Sendable, Equatable, Hashable {
    public var lumaCenter: Double
    public var coveragePct: Double
    public var labA: Double
    public var labB: Double
}

/// 스캐너 간 roll-label matched group의 hue별 채도 비율/hue 회전 시그니처.
/// source frame ID/hash가 없어 정확한 프레임 쌍을 뜻하지 않는다. 기하평균 중심 대칭 분배,
/// bin 간 기하평균 1 정규화(전역 채도 베이스라인과 분리) 후 번들에 포함한다.
public struct ScannerProfileHueResponseBin: Codable, Sendable, Equatable, Hashable {
    public var labHueDegrees: Double
    public var chromaGain: Double
    public var hueRotateDegrees: Double
    public var weight: Double
}

public struct ScannerProfile: Codable, Sendable, Identifiable, Equatable {
    public var schemaVersion: Int
    public var id: String
    public var displayName: String
    public var scanner: String
    public var kind: String
    public var filmKey: String
    public var validationStatus: ScannerProfileValidationStatus
    public var rollCount: Int
    public var imageCount: Int
    public var singleRollLimited: Bool
    public var sourceProfiles: [String]
    public var tone: [String: ScannerProfileStat]
    public var color: [String: ScannerProfileStat]
    public var neutralAxis: [String: ScannerProfileStat]
    // schemaVersion 2 필드 — 구버전 JSON 은 nil 로 디코드된다.
    public var neutralAxisBins: [ScannerProfileNeutralBin]?
    public var hueResponse: [ScannerProfileHueResponseBin]?
    public var texture: [String: ScannerProfileStat]
    public var sceneBuckets: [ScannerProfileSceneBucket]
    public var coverageCandidates: [ScannerProfileCoverageAxis]
    public var profileHash: String
}
