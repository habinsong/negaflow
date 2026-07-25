import CoreGraphics
import Foundation
import XCTest
@testable import negaflowApp

@MainActor
final class DefectSidecarResourceLimitTests: XCTestCase {
    func testBoundedZlibDecoderStopsCompressionBombAtOutputLimit() throws {
        let raw = Data(repeating: 0x7F, count: 2 * 1_024 * 1_024)
        let compressed = try XCTUnwrap(
            try (raw as NSData).compressed(using: .zlib) as Data
        )

        XCTAssertThrowsError(try BoundedZlibDecoder.decode(
            compressed,
            maximumOutputBytes: 64 * 1_024
        )) { error in
            XCTAssertEqual(
                error as? DefectBoundedDecompressionError,
                .outputLimitExceeded
            )
        }
    }

    func testRecipeCapsRejectItemsStrokesClustersMaskPixelsAndDecodedBytes() {
        assertLimit(.items, items: [brush(), brush()]) {
            $0.maxItems = 1
        }
        assertLimit(.strokes, items: [brush(strokeCount: 2)]) {
            $0.maxStrokesPerItem = 1
        }
        assertLimit(.clusters, items: [infrared(clusterCount: 2)]) {
            $0.maxClustersPerItem = 1
        }
        assertLimit(.maskPixels, items: [region(width: 2, height: 2)]) {
            $0.maxMaskPixels = 3
        }
        assertLimit(.decompressedBytes, items: [region(width: 32, height: 32)]) {
            $0.maxDecompressedBytesPerRecipe = 4_095
        }
    }

    func testFileSizeCapRejectsBeforePropertyListDecode() throws {
        let root = temporaryDirectory("file-cap")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let frameID = UUID()
        let data = try PropertyListEncoder().encode(DefectSidecar(items: [brush()]))
        try data.write(to: DefectSidecarFile.url(for: frameID, in: root))
        var limits = DefectSidecarResourceLimits.standard
        limits.maxFileBytes = data.count - 1

        XCTAssertEqual(
            DefectSidecarFile.read(
                for: frameID,
                in: root,
                limits: limits,
                fileManager: .default
            ),
            .invalid(rawData: nil)
        )
    }

    private func assertLimit(
        _ resource: DefectSidecarResource,
        items: [DefectEditItemRecord],
        configure: (inout DefectSidecarResourceLimits) -> Void
    ) {
        var limits = DefectSidecarResourceLimits.standard
        configure(&limits)
        XCTAssertThrowsError(try DefectSidecarResourcePolicy.normalizedItems(
            items,
            limits: limits
        )) { error in
            XCTAssertEqual(
                error as? DefectRecipeValidationError,
                .resourceLimitExceeded(resource)
            )
        }
    }

    private func brush(strokeCount: Int = 1) -> DefectEditItemRecord {
        record(kind: .brush, strokes: Array(repeating: DefectStrokeRecord(
            points: [CGPoint(x: 0.2, y: 0.3)],
            thickness: 0.02
        ), count: strokeCount))
    }

    private func region(width: Int, height: Int) -> DefectEditItemRecord {
        var item = record(kind: .region)
        item.regionMask = .raw(Data(repeating: 255, count: width * height * 4)).compressed()
        item.regionROI = CGRect(x: 0, y: 0, width: width, height: height)
        item.regionWidth = width
        item.regionHeight = height
        return item
    }

    private func infrared(clusterCount: Int) -> DefectEditItemRecord {
        var item = record(kind: .infrared)
        item.clusters = Array(repeating: DefectClusterRecord(
            roi: CGRect(x: 0, y: 0, width: 1, height: 1),
            mask: .raw(Data(repeating: 255, count: 4)),
            width: 1,
            height: 1
        ), count: clusterCount)
        return item
    }

    private func record(
        kind: DefectEditItemRecord.Kind,
        strokes: [DefectStrokeRecord]? = nil
    ) -> DefectEditItemRecord {
        DefectEditItemRecord(
            id: UUID(), kind: kind, enabled: true, strength: 1,
            label: .brush(strokeCount: 0), summaryKind: .brush, baseSize: nil, preview: [],
            strokes: strokes, regionMask: nil, regionROI: nil,
            regionWidth: nil, regionHeight: nil, clusters: nil
        )
    }

    private func temporaryDirectory(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-sidecar-limits-\(suffix)-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
