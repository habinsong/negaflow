import Chromabase
import CoreGraphics
import Foundation

extension DefectEditItemRecord {
    @MainActor
    init(item: DefectEditItem) {
        id = item.id
        enabled = item.enabled
        strength = item.strength
        label = item.label
        summaryKind = item.summaryKind
        baseSize = item.baseSize
        preview = item.preview.map {
            DefectPreviewComponentRecord(
                classification: $0.classification,
                confidence: $0.confidence,
                points: $0.points
            )
        }
        switch item.edit {
        case .brush(let strokes):
            kind = .brush
            self.strokes = strokes.map {
                DefectStrokeRecord(points: $0.points, thickness: Double($0.thickness))
            }
        case .region(let mask, let roi, let width, let height):
            kind = .region
            regionMask = mask
            regionROI = roi
            regionWidth = width
            regionHeight = height
        case .infrared(let clusters):
            kind = .infrared
            self.clusters = clusters.map {
                DefectClusterRecord(
                    roi: $0.roiYup,
                    mask: .raw($0.maskRGBA8),
                    attenuation: $0.attenuationR16.map { .raw($0) },
                    width: $0.width,
                    height: $0.height
                )
            }
        case .clone(let strokes):
            kind = .clone
            cloneStrokes = strokes.map {
                CloneStrokeRecord(
                    points: $0.points,
                    offsetX: Double($0.offset.dx),
                    offsetY: Double($0.offset.dy),
                    diameter: Double($0.diameter),
                    hardness: Double($0.hardness)
                )
            }
        }
    }

    func compressedForStorage() -> DefectEditItemRecord {
        var copy = self
        copy.regionMask = regionMask?.compressed()
        copy.clusters = clusters?.map {
            var cluster = $0
            cluster.mask = cluster.mask.compressed()
            cluster.attenuation = cluster.attenuation?.compressed()
            return cluster
        }
        return copy
    }

    /// v3 기록 파일용. 메모리에서 비압축인 적외선 마스크·감쇠 창(장당 수십 MB, 대부분 0)을
    /// 압축한다. 이미 압축된 값은 그대로 두므로 읽을 때 메모리 표현이 정확히 돌아온다.
    func packedForStorage() -> DefectEditItemRecord {
        var copy = self
        copy.regionMask = regionMask?.packedForStorage()
        copy.clusters = clusters?.map {
            var cluster = $0
            cluster.mask = cluster.mask.packedForStorage()
            cluster.attenuation = cluster.attenuation?.packedForStorage()
            return cluster
        }
        return copy
    }

    var hasStoragePackedPayload: Bool {
        regionMask?.storagePacked != nil
            || (clusters ?? []).contains {
                $0.mask.storagePacked != nil || $0.attenuation?.storagePacked != nil
            }
    }

    /// `packedForStorage()`의 역. 푼 바이트의 합은 v2 파일이 비압축으로 담을 수 있던 크기를 넘지
    /// 못하게 `remainingBytes`에서 깎는다.
    func unpackedFromStorage(
        remainingBytes: inout Int,
        limits: DefectSidecarResourceLimits
    ) throws -> DefectEditItemRecord {
        var copy = self
        if let regionMask {
            guard let regionWidth, let regionHeight else {
                throw DefectRecipeValidationError.invalidRecordShape
            }
            copy.regionMask = try Self.unpacked(
                regionMask, width: regionWidth, height: regionHeight, bytesPerPixel: 4,
                remainingBytes: &remainingBytes, limits: limits
            )
        }
        copy.clusters = try clusters?.map { cluster in
            var unpacked = cluster
            unpacked.mask = try Self.unpacked(
                cluster.mask, width: cluster.width, height: cluster.height, bytesPerPixel: 4,
                remainingBytes: &remainingBytes, limits: limits
            )
            if let attenuation = cluster.attenuation {
                unpacked.attenuation = try Self.unpacked(
                    attenuation, width: cluster.width, height: cluster.height, bytesPerPixel: 2,
                    remainingBytes: &remainingBytes, limits: limits
                )
            }
            return unpacked
        }
        return copy
    }

    private static func unpacked(
        _ value: DefectCompressedData,
        width: Int,
        height: Int,
        bytesPerPixel: Int,
        remainingBytes: inout Int,
        limits: DefectSidecarResourceLimits
    ) throws -> DefectCompressedData {
        guard value.storagePacked != nil else { return value }
        guard width > 0, height > 0 else { throw DefectRecipeValidationError.invalidMask }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixels <= limits.maxMaskPixels else {
            throw DefectRecipeValidationError.resourceLimitExceeded(.maskPixels)
        }
        let byteCount = pixels * bytesPerPixel
        guard byteCount <= remainingBytes else {
            throw DefectRecipeValidationError.resourceLimitExceeded(.decompressedBytes)
        }
        remainingBytes -= byteCount
        return try value.unpackedFromStorage(rawByteCount: byteCount)
    }

    func decompressedFromStorage() -> DefectEditItemRecord {
        let limit = DefectSidecarResourceLimits.standard.maxDecompressedBytesPerRecipe
        var copy = self
        copy.regionMask = regionMask?.decompressed(maximumOutputBytes: limit)
        copy.clusters = clusters?.map {
            var cluster = $0
            cluster.mask = cluster.mask.decompressed(maximumOutputBytes: limit)
            cluster.attenuation = cluster.attenuation?.decompressed(maximumOutputBytes: limit)
            return cluster
        }
        return copy
    }

    func validatedDecompressedForRecipe() throws -> DefectEditItemRecord {
        try DefectSidecarResourcePolicy.normalizedItems([self])[0]
    }

    func makeItem() -> DefectEditItem? {
        let edit: DefectEdit
        switch kind {
        case .brush:
            edit = .brush((strokes ?? []).map {
                DefectStroke(points: $0.points, thickness: CGFloat($0.thickness))
            })
        case .region:
            guard let regionMask, let regionROI,
                  let regionWidth, let regionHeight else { return nil }
            edit = .region(
                mask: regionMask.compressed(),
                roi: regionROI,
                width: regionWidth,
                height: regionHeight
            )
        case .infrared:
            edit = .infrared(clusters: (clusters ?? []).map {
                InfraredDefectRemoval.Cluster(
                    roiYup: $0.roi,
                    maskRGBA8: $0.mask.rawBytes,
                    attenuationR16: $0.attenuation?.rawBytes,
                    width: $0.width,
                    height: $0.height
                )
            })
        case .clone:
            edit = .clone((cloneStrokes ?? []).map {
                CloneStampStroke(
                    points: $0.points,
                    offset: CGVector(dx: $0.offsetX, dy: $0.offsetY),
                    diameter: CGFloat($0.diameter),
                    hardness: CGFloat($0.hardness)
                )
            })
        }
        return DefectEditItem(
            id: id,
            edit: edit,
            enabled: enabled,
            strength: strength,
            label: label,
            summaryKind: summaryKind,
            preview: preview.map {
                DefectMaskPreviewComponent(
                    classification: $0.classification,
                    confidence: $0.confidence,
                    points: $0.points
                )
            },
            baseSize: baseSize
        )
    }
}
