import Foundation

enum DefectSidecarResource: String, Equatable, Sendable {
    case fileBytes
    case items
    case strokes
    case strokePoints
    case previewComponents
    case previewPoints
    case clusters
    case maskPixels
    case decompressedBytes
}

struct DefectSidecarResourceLimits: Equatable, Sendable {
    /// `.r7200` 35 mm 입력의 약 75 MP 프레임을 수용하되 비정상 recipe는 유한하게 막는다.
    static let standard = DefectSidecarResourceLimits()

    /// 아래 상한들이 허용하는 가장 큰 recipe 를 담을 수 있어야 한다. 쓰기가 받아들인 기록을
    /// 읽기가 거부하면 메모리 recipe 만 남아 카탈로그 저장·스캔·종료가 전부 막힌다(고해상도
    /// 적외선 타일은 원본 크기 그대로 기록돼 128MB 를 넘었다). 마스크 예산 512MiB + 적외선 감쇠
    /// 창(마스크의 절반) 256MiB + 점 1천만 개 × 실측 40바이트에 여유를 더한다.
    var maxFileBytes = 1_536 * 1_024 * 1_024
    var maxItems = 4_096
    var maxStrokesPerItem = 50_000
    var maxStrokesPerRecipe = 100_000
    var maxPointsPerStroke = 1_000_000
    var maxPointsPerRecipe = 5_000_000
    var maxPreviewComponentsPerItem = 100_000
    var maxPreviewPointsPerRecipe = 5_000_000
    var maxClustersPerItem = 100_000
    var maxClustersPerRecipe = 100_000
    var maxMaskPixels = 100_000_000
    var maxDecompressedBytesPerRecipe = 512 * 1_024 * 1_024
}

enum DefectSidecarResourcePolicy {
    /// 개수/크기 상한과 마스크 형태만 검증하고 record를 그대로 돌려준다(압축 해제 없음).
    /// 세션 안에서 만들어진 recipe의 fingerprint 계산 경로가 사용한다.
    static func checkedItems(
        _ items: [DefectEditItemRecord],
        limits: DefectSidecarResourceLimits = .standard
    ) throws -> [DefectEditItemRecord] {
        guard items.count <= limits.maxItems else {
            throw DefectRecipeValidationError.resourceLimitExceeded(.items)
        }
        var strokeCount = 0
        var strokePointCount = 0
        var previewPointCount = 0
        var clusterCount = 0
        // 읽기(normalizedItems)의 압축 해제 예산과 같은 계산이다. 여기서 막지 않으면 기록은 쓰이고
        // 읽기만 거부해 메모리 recipe 가 저장되지 못한다.
        var remainingMaskBytes = limits.maxDecompressedBytesPerRecipe

        for item in items {
            let strokes = item.strokes ?? []
            guard strokes.count <= limits.maxStrokesPerItem else {
                throw DefectRecipeValidationError.resourceLimitExceeded(.strokes)
            }
            strokeCount = try adding(
                strokes.count,
                to: strokeCount,
                maximum: limits.maxStrokesPerRecipe,
                resource: .strokes
            )
            for stroke in strokes {
                guard stroke.points.count <= limits.maxPointsPerStroke else {
                    throw DefectRecipeValidationError.resourceLimitExceeded(.strokePoints)
                }
                strokePointCount = try adding(
                    stroke.points.count,
                    to: strokePointCount,
                    maximum: limits.maxPointsPerRecipe,
                    resource: .strokePoints
                )
            }
            let cloneStrokes = item.cloneStrokes ?? []
            guard cloneStrokes.count <= limits.maxStrokesPerItem else {
                throw DefectRecipeValidationError.resourceLimitExceeded(.strokes)
            }
            strokeCount = try adding(
                cloneStrokes.count,
                to: strokeCount,
                maximum: limits.maxStrokesPerRecipe,
                resource: .strokes
            )
            for stroke in cloneStrokes {
                guard stroke.points.count <= limits.maxPointsPerStroke else {
                    throw DefectRecipeValidationError.resourceLimitExceeded(.strokePoints)
                }
                strokePointCount = try adding(
                    stroke.points.count,
                    to: strokePointCount,
                    maximum: limits.maxPointsPerRecipe,
                    resource: .strokePoints
                )
            }
            guard item.preview.count <= limits.maxPreviewComponentsPerItem else {
                throw DefectRecipeValidationError.resourceLimitExceeded(.previewComponents)
            }
            for component in item.preview {
                previewPointCount = try adding(
                    component.points.count,
                    to: previewPointCount,
                    maximum: limits.maxPreviewPointsPerRecipe,
                    resource: .previewPoints
                )
            }
            let clusters = item.clusters ?? []
            guard clusters.count <= limits.maxClustersPerItem else {
                throw DefectRecipeValidationError.resourceLimitExceeded(.clusters)
            }
            clusterCount = try adding(
                clusters.count,
                to: clusterCount,
                maximum: limits.maxClustersPerRecipe,
                resource: .clusters
            )
            if let width = item.regionWidth, let height = item.regionHeight {
                try checkMaskPixelCap(width: width, height: height, limits: limits)
                if item.regionMask != nil {
                    try consumeMaskBytes(width: width, height: height, remaining: &remainingMaskBytes)
                }
            }
            if item.regionMask != nil,
               (item.regionWidth == nil || item.regionHeight == nil) {
                throw DefectRecipeValidationError.invalidRecordShape
            }
            for cluster in clusters {
                try checkMaskPixelCap(
                    width: cluster.width,
                    height: cluster.height,
                    limits: limits
                )
                try consumeMaskBytes(
                    width: cluster.width,
                    height: cluster.height,
                    remaining: &remainingMaskBytes
                )
                if let attenuation = cluster.attenuation {
                    try checkAttenuationShape(attenuation, width: cluster.width, height: cluster.height)
                }
            }
        }
        // kind별 field shape와 scalar 유효성까지 fingerprint 경계에서 확정한다.
        _ = try DefectRecipeFingerprint.canonicalData(items: items)
        return items
    }

    private static func consumeMaskBytes(width: Int, height: Int, remaining: inout Int) throws {
        let (bytes, overflow) = (width * height).multipliedReportingOverflow(by: 4)
        guard !overflow else { throw DefectRecipeValidationError.invalidMask }
        guard bytes <= remaining else {
            throw DefectRecipeValidationError.resourceLimitExceeded(.decompressedBytes)
        }
        remaining -= bytes
    }

    /// 적외선 감쇠 창은 픽셀당 16bit 다. 크기를 묶어 두어야 기록 파일 상한이 성립한다.
    private static func checkAttenuationShape(
        _ attenuation: DefectCompressedData,
        width: Int,
        height: Int
    ) throws {
        if attenuation.zlib {
            guard !attenuation.data.isEmpty else { throw DefectRecipeValidationError.invalidMask }
        } else {
            guard attenuation.data.count == width * height * 2 else {
                throw DefectRecipeValidationError.invalidMask
            }
        }
    }

    private static func checkMaskPixelCap(
        width: Int,
        height: Int,
        limits: DefectSidecarResourceLimits
    ) throws {
        guard width > 0, height > 0 else {
            throw DefectRecipeValidationError.invalidMask
        }
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        guard !pixelOverflow, pixels <= limits.maxMaskPixels else {
            throw DefectRecipeValidationError.resourceLimitExceeded(.maskPixels)
        }
    }

    static func normalizedItems(
        _ items: [DefectEditItemRecord],
        limits: DefectSidecarResourceLimits = .standard
    ) throws -> [DefectEditItemRecord] {
        guard items.count <= limits.maxItems else {
            throw DefectRecipeValidationError.resourceLimitExceeded(.items)
        }
        var strokeCount = 0
        var strokePointCount = 0
        var previewPointCount = 0
        var clusterCount = 0
        var remainingDecodedBytes = limits.maxDecompressedBytesPerRecipe
        var normalized: [DefectEditItemRecord] = []
        normalized.reserveCapacity(items.count)

        for item in items {
            let strokes = item.strokes ?? []
            guard strokes.count <= limits.maxStrokesPerItem else {
                throw DefectRecipeValidationError.resourceLimitExceeded(.strokes)
            }
            strokeCount = try adding(
                strokes.count,
                to: strokeCount,
                maximum: limits.maxStrokesPerRecipe,
                resource: .strokes
            )
            for stroke in strokes {
                guard stroke.points.count <= limits.maxPointsPerStroke else {
                    throw DefectRecipeValidationError.resourceLimitExceeded(.strokePoints)
                }
                strokePointCount = try adding(
                    stroke.points.count,
                    to: strokePointCount,
                    maximum: limits.maxPointsPerRecipe,
                    resource: .strokePoints
                )
            }
            let cloneStrokes = item.cloneStrokes ?? []
            guard cloneStrokes.count <= limits.maxStrokesPerItem else {
                throw DefectRecipeValidationError.resourceLimitExceeded(.strokes)
            }
            strokeCount = try adding(
                cloneStrokes.count,
                to: strokeCount,
                maximum: limits.maxStrokesPerRecipe,
                resource: .strokes
            )
            for stroke in cloneStrokes {
                guard stroke.points.count <= limits.maxPointsPerStroke else {
                    throw DefectRecipeValidationError.resourceLimitExceeded(.strokePoints)
                }
                strokePointCount = try adding(
                    stroke.points.count,
                    to: strokePointCount,
                    maximum: limits.maxPointsPerRecipe,
                    resource: .strokePoints
                )
            }
            guard item.preview.count <= limits.maxPreviewComponentsPerItem else {
                throw DefectRecipeValidationError.resourceLimitExceeded(.previewComponents)
            }
            for component in item.preview {
                previewPointCount = try adding(
                    component.points.count,
                    to: previewPointCount,
                    maximum: limits.maxPreviewPointsPerRecipe,
                    resource: .previewPoints
                )
            }
            let clusters = item.clusters ?? []
            guard clusters.count <= limits.maxClustersPerItem else {
                throw DefectRecipeValidationError.resourceLimitExceeded(.clusters)
            }
            clusterCount = try adding(
                clusters.count,
                to: clusterCount,
                maximum: limits.maxClustersPerRecipe,
                resource: .clusters
            )

            var copy = item
            if let mask = item.regionMask,
               let width = item.regionWidth,
               let height = item.regionHeight {
                copy.regionMask = .raw(try decodedMask(
                    mask,
                    width: width,
                    height: height,
                    limits: limits,
                    remainingBytes: &remainingDecodedBytes
                ))
            }
            if item.regionMask != nil,
               (item.regionWidth == nil || item.regionHeight == nil) {
                throw DefectRecipeValidationError.invalidRecordShape
            }
            copy.clusters = try item.clusters?.map { cluster in
                var normalizedCluster = cluster
                normalizedCluster.mask = .raw(try decodedMask(
                    cluster.mask,
                    width: cluster.width,
                    height: cluster.height,
                    limits: limits,
                    remainingBytes: &remainingDecodedBytes
                ))
                if let attenuation = cluster.attenuation {
                    try checkAttenuationShape(attenuation, width: cluster.width, height: cluster.height)
                    if attenuation.zlib {
                        let expected = cluster.width * cluster.height * 2
                        guard (try? attenuation.validatedRawBytes(maximumOutputBytes: expected))?
                            .count == expected else {
                            throw DefectRecipeValidationError.invalidMask
                        }
                    }
                }
                return normalizedCluster
            }
            normalized.append(copy)
        }
        // kind별 field shape와 scalar 유효성까지 decode 경계에서 확정한다.
        _ = try DefectRecipeFingerprint.canonicalData(items: normalized)
        return normalized
    }

    private static func decodedMask(
        _ mask: DefectCompressedData,
        width: Int,
        height: Int,
        limits: DefectSidecarResourceLimits,
        remainingBytes: inout Int
    ) throws -> Data {
        guard width > 0, height > 0 else {
            throw DefectRecipeValidationError.invalidMask
        }
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        guard !pixelOverflow, pixels <= limits.maxMaskPixels else {
            throw DefectRecipeValidationError.resourceLimitExceeded(.maskPixels)
        }
        let (expectedBytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        guard !byteOverflow else { throw DefectRecipeValidationError.invalidMask }
        guard expectedBytes <= remainingBytes else {
            throw DefectRecipeValidationError.resourceLimitExceeded(.decompressedBytes)
        }
        let decoded: Data
        do {
            decoded = try mask.validatedRawBytes(maximumOutputBytes: expectedBytes)
        } catch DefectBoundedDecompressionError.outputLimitExceeded {
            throw DefectRecipeValidationError.resourceLimitExceeded(.decompressedBytes)
        } catch {
            throw DefectRecipeValidationError.invalidMask
        }
        guard decoded.count == expectedBytes else {
            throw DefectRecipeValidationError.invalidMask
        }
        remainingBytes -= decoded.count
        return decoded
    }

    private static func adding(
        _ value: Int,
        to total: Int,
        maximum: Int,
        resource: DefectSidecarResource
    ) throws -> Int {
        let (sum, overflow) = total.addingReportingOverflow(value)
        guard !overflow, sum <= maximum else {
            throw DefectRecipeValidationError.resourceLimitExceeded(resource)
        }
        return sum
    }
}
