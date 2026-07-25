import CoreGraphics
import CryptoKit
import Foundation

enum DefectRecipeFingerprint {
    // v2: 마스크 바이트를 canonical payload에 넣지 않는다. 레이어 마스크는 세션 안에서 항목
    // UUID별로 불변이므로 id + 형태(roi/크기/저장 바이트 수)만으로 recipe 상태가 유일하게
    // 결정된다. 기록은 세션을 넘어 보존되지 않으므로(종료 시 이미지에 굽기) 콘텐츠 해시가
    // 필요 없고, 수십 MB 마스크의 압축 해제·직렬화·해시가 편집 경로에서 사라진다.
    static let currentVersion = 2

    private struct Payload: Codable { var version: Int; var items: [Item] }
    private struct Item: Codable {
        var id: UUID
        var kind: String
        var enabled: Bool
        var strength: UInt64
        var strokes: [Stroke]?
        var region: Region?
        var clusters: [Cluster]?
        var clones: [Clone]?
    }
    private struct Point: Codable { var x: UInt64; var y: UInt64 }
    private struct Rect: Codable {
        var x: UInt64; var y: UInt64; var width: UInt64; var height: UInt64
    }
    private struct Stroke: Codable { var points: [Point]; var thickness: UInt64 }
    private struct Region: Codable {
        var maskByteCount: Int; var maskZlib: Bool
        var roi: Rect; var width: Int; var height: Int
    }
    private struct Cluster: Codable {
        var roi: Rect; var maskByteCount: Int; var maskZlib: Bool
        var width: Int; var height: Int
    }
    private struct Clone: Codable {
        var points: [Point]; var offsetX: UInt64; var offsetY: UInt64
        var diameter: UInt64; var hardness: UInt64
    }

    static func sha256(items: [DefectEditItemRecord]) throws -> String {
        SHA256.hash(data: try canonicalData(items: items))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func canonicalData(items: [DefectEditItemRecord]) throws -> Data {
        let payload = Payload(version: currentVersion, items: try items.map(canonicalItem))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    private static func canonicalItem(_ item: DefectEditItemRecord) throws -> Item {
        let strength = try canonicalStrength(item.strength)
        switch item.kind {
        case .brush:
            guard item.regionMask == nil, item.regionROI == nil,
                  item.regionWidth == nil, item.regionHeight == nil,
                  item.clusters == nil, item.cloneStrokes == nil else {
                throw DefectRecipeValidationError.invalidRecordShape
            }
            let strokes = try (item.strokes ?? []).map { stroke in
                guard stroke.thickness.isFinite, stroke.thickness >= 0 else {
                    throw DefectRecipeValidationError.invalidScalar
                }
                return Stroke(
                    points: try stroke.points.map(canonicalPoint),
                    thickness: try canonicalScalar(stroke.thickness)
                )
            }
            return Item(
                id: item.id, kind: item.kind.rawValue, enabled: item.enabled,
                strength: strength, strokes: strokes, region: nil, clusters: nil, clones: nil
            )
        case .region:
            guard item.strokes == nil, item.clusters == nil, item.cloneStrokes == nil,
                  let mask = item.regionMask, let roi = item.regionROI,
                  let width = item.regionWidth, let height = item.regionHeight else {
                throw DefectRecipeValidationError.invalidRecordShape
            }
            return Item(
                id: item.id, kind: item.kind.rawValue, enabled: item.enabled,
                strength: strength, strokes: nil,
                region: Region(
                    maskByteCount: try validatedMaskShape(mask, width: width, height: height),
                    maskZlib: mask.zlib,
                    roi: try canonicalRect(roi), width: width, height: height
                ),
                clusters: nil, clones: nil
            )
        case .infrared:
            guard item.strokes == nil, item.regionMask == nil,
                  item.regionROI == nil, item.regionWidth == nil,
                  item.regionHeight == nil, item.cloneStrokes == nil else {
                throw DefectRecipeValidationError.invalidRecordShape
            }
            let clusters = try (item.clusters ?? []).map { cluster in
                Cluster(
                    roi: try canonicalRect(cluster.roi),
                    maskByteCount: try validatedMaskShape(
                        cluster.mask,
                        width: cluster.width,
                        height: cluster.height
                    ),
                    maskZlib: cluster.mask.zlib,
                    width: cluster.width,
                    height: cluster.height
                )
            }
            return Item(
                id: item.id, kind: item.kind.rawValue, enabled: item.enabled,
                strength: strength, strokes: nil, region: nil, clusters: clusters, clones: nil
            )
        case .clone:
            guard item.strokes == nil, item.regionMask == nil,
                  item.regionROI == nil, item.regionWidth == nil,
                  item.regionHeight == nil, item.clusters == nil else {
                throw DefectRecipeValidationError.invalidRecordShape
            }
            let clones = try (item.cloneStrokes ?? []).map { stroke in
                guard stroke.diameter.isFinite, stroke.diameter > 0,
                      stroke.hardness.isFinite, (0...1).contains(stroke.hardness),
                      stroke.offsetX.isFinite, stroke.offsetY.isFinite else {
                    throw DefectRecipeValidationError.invalidScalar
                }
                return Clone(
                    points: try stroke.points.map(canonicalPoint),
                    offsetX: try canonicalScalar(stroke.offsetX),
                    offsetY: try canonicalScalar(stroke.offsetY),
                    diameter: try canonicalScalar(stroke.diameter),
                    hardness: try canonicalScalar(stroke.hardness)
                )
            }
            return Item(
                id: item.id, kind: item.kind.rawValue, enabled: item.enabled,
                strength: strength, strokes: nil, region: nil, clusters: nil, clones: clones
            )
        }
    }

    /// 마스크를 압축 해제하지 않고 형태만 검증한다. 비압축이면 바이트 수가 w×h×4와 정확히
    /// 일치해야 하고, zlib이면 비어 있지만 않으면 된다(내용은 항목 UUID가 대변한다).
    private static func validatedMaskShape(
        _ mask: DefectCompressedData,
        width: Int,
        height: Int
    ) throws -> Int {
        guard width > 0, height > 0 else { throw DefectRecipeValidationError.invalidMask }
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (byteCount, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        guard !pixelOverflow, !byteOverflow else {
            throw DefectRecipeValidationError.invalidMask
        }
        if mask.zlib {
            guard !mask.data.isEmpty else { throw DefectRecipeValidationError.invalidMask }
        } else {
            guard mask.data.count == byteCount else { throw DefectRecipeValidationError.invalidMask }
        }
        return mask.data.count
    }

    private static func canonicalPoint(_ point: CGPoint) throws -> Point {
        Point(
            x: try canonicalScalar(Double(point.x)),
            y: try canonicalScalar(Double(point.y))
        )
    }

    private static func canonicalRect(_ rect: CGRect) throws -> Rect {
        guard rect.width > 0, rect.height > 0 else {
            throw DefectRecipeValidationError.invalidScalar
        }
        return Rect(
            x: try canonicalScalar(Double(rect.origin.x)),
            y: try canonicalScalar(Double(rect.origin.y)),
            width: try canonicalScalar(Double(rect.width)),
            height: try canonicalScalar(Double(rect.height))
        )
    }

    private static func canonicalStrength(_ value: Double) throws -> UInt64 {
        guard value.isFinite, (0...1).contains(value) else {
            throw DefectRecipeValidationError.invalidStrength
        }
        return try canonicalScalar(value)
    }

    private static func canonicalScalar(_ value: Double) throws -> UInt64 {
        guard value.isFinite else { throw DefectRecipeValidationError.invalidScalar }
        return (value == 0 ? 0.0 : value).bitPattern
    }
}
