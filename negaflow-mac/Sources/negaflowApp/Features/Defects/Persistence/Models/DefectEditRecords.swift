import Foundation
import CoreGraphics
import Chromabase

// MARK: - Defect edit persistence

struct DefectSidecar: Codable, Sendable {
    var version: Int = 1
    var items: [DefectEditItemRecord]
}

struct DefectStrokeRecord: Codable, Equatable, Sendable {
    var points: [CGPoint]
    var thickness: Double
}

struct CloneStrokeRecord: Codable, Equatable, Sendable {
    var points: [CGPoint]
    var offsetX: Double
    var offsetY: Double
    var diameter: Double
    var hardness: Double
}

struct DefectPreviewComponentRecord: Codable, Equatable, Sendable {
    var classification: DefectClass
    var confidence: Double
    var points: [CGPoint]
}

struct DefectClusterRecord: Codable, Equatable, Sendable {
    var roi: CGRect
    var mask: DefectCompressedData
    /// 가시광 감쇠 창(16bit). 부분 폐색을 나눗셈으로 되돌리는 데 쓴다. 이 필드가 없는
    /// 예전 기록은 마스크 복원 경로로 그대로 재생된다.
    var attenuation: DefectCompressedData? = nil
    var width: Int
    var height: Int
}

struct DefectEditItemRecord: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case brush
        case region
        case infrared
        case clone
    }

    var id: UUID
    var kind: Kind
    var enabled: Bool
    var strength: Double
    /// 레이어 이름·요약은 값으로 보관한다 — 문자열로 저장하면 언어가 굳는다.
    var label: DefectEditLabel
    var summaryKind: DefectEditSummary
    var baseSize: CGSize?
    var preview: [DefectPreviewComponentRecord]
    var strokes: [DefectStrokeRecord]?
    var cloneStrokes: [CloneStrokeRecord]?
    var regionMask: DefectCompressedData?
    var regionROI: CGRect?
    var regionWidth: Int?
    var regionHeight: Int?
    var clusters: [DefectClusterRecord]?
}
