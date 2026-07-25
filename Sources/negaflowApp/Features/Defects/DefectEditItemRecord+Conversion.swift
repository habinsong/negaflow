import Chromabase
import CoreGraphics
import Foundation

extension DefectEditItemRecord {
    @MainActor
    init(item: DefectEditItem) {
        id = item.id
        enabled = item.enabled
        strength = item.strength
        title = item.title
        summary = item.summary
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
            return cluster
        }
        return copy
    }

    func decompressedFromStorage() -> DefectEditItemRecord {
        let limit = DefectSidecarResourceLimits.standard.maxDecompressedBytesPerRecipe
        var copy = self
        copy.regionMask = regionMask?.decompressed(maximumOutputBytes: limit)
        copy.clusters = clusters?.map {
            var cluster = $0
            cluster.mask = cluster.mask.decompressed(maximumOutputBytes: limit)
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
            title: title,
            summary: summary,
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
