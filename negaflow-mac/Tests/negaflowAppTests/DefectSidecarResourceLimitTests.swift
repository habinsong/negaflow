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

    /// 쓰기(recipe 생성)와 읽기(기록 검증)는 같은 상한을 써야 한다. 한쪽만 거부하면 쓰인
    /// 기록을 읽지 못해 메모리 recipe 만 남는다.
    func testRecipeCreationRejectsWhatTheReaderWouldReject() {
        var budget = DefectSidecarResourceLimits.standard
        budget.maxDecompressedBytesPerRecipe = 4 * 4 * 4 * 2 - 1
        assertBothSidesReject(
            .resourceLimitExceeded(.decompressedBytes),
            items: [region(width: 4, height: 4), region(width: 4, height: 4)],
            limits: budget
        )

        var wrongAttenuation = infrared(clusterCount: 1)
        wrongAttenuation.clusters?[0].attenuation = .raw(Data(count: 3))
        assertBothSidesReject(.invalidMask, items: [wrongAttenuation], limits: .standard)
    }

    /// 파일 상한은 다른 상한이 허용하는 가장 큰 recipe 를 담아야 한다. 마스크(RGBA8) 예산,
    /// 그 절반인 적외선 감쇠 창, 점 하나당 binary plist 40바이트(5백만 개 실측)를 더한 값이다.
    func testFileCapCoversTheLargestRecipeTheOtherCapsAllow() {
        let limits = DefectSidecarResourceLimits.standard
        let masks = limits.maxDecompressedBytesPerRecipe
        let attenuation = masks / 2
        let points = (limits.maxPointsPerRecipe + limits.maxPreviewPointsPerRecipe) * 40
        XCTAssertGreaterThanOrEqual(limits.maxFileBytes, masks + attenuation + points)
    }

    /// 고해상도 적외선 스캔의 먼지 타일(768+여백 40)이 프레임을 넓게 덮는 recipe 가
    /// v2 기록으로 쓰이고 다시 읽혀야 한다. 쓰기가 받아들인 기록을 읽기가 거부하면 메모리
    /// recipe 만 남아 카탈로그 저장·스캔·종료가 전부 막힌다.
    func testLargeInfraredRecipeRoundTripsThroughV2Sidecar() throws {
        let root = temporaryDirectory("large-infrared")
        defer { try? FileManager.default.removeItem(at: root) }
        let side = 848
        var item = record(kind: .infrared)
        // 타일마다 내용이 달라야 한다. 같은 Data 를 공유하면 binary plist 가 한 번만 저장해
        // 실제 크기가 재현되지 않는다.
        item.clusters = (0..<32).map { index in
            var mask = Data(count: side * side * 4)
            mask[index] = 255
            var attenuation = Data(count: side * side * 2)
            attenuation[index] = 1
            return DefectClusterRecord(
                roi: CGRect(x: index * 768, y: 0, width: side, height: side),
                mask: .raw(mask),
                attenuation: .raw(attenuation),
                width: side,
                height: side
            )
        }
        let snapshot = try DefectRecipeSnapshot(
            frameID: UUID(), revision: 1, sourceIdentity: nil, items: [item]
        )

        XCTAssertEqual(
            try DefectSidecarFile.write(snapshot, in: root),
            .written(DefectSidecarFile.url(for: snapshot.frameID, in: root))
        )
        guard case .loaded(.currentV2(_, let stored)) = DefectSidecarFile.read(
            for: snapshot.frameID, in: root
        ) else {
            return XCTFail("large infrared recipe must read back")
        }
        XCTAssertEqual(stored, snapshot)
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

    private func assertBothSidesReject(
        _ expected: DefectRecipeValidationError,
        items: [DefectEditItemRecord],
        limits: DefectSidecarResourceLimits,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try DefectRecipeSnapshot(
            frameID: UUID(), revision: 1, sourceIdentity: nil, items: items, limits: limits
        ), line: line) { error in
            XCTAssertEqual(error as? DefectRecipeValidationError, expected, line: line)
        }
        XCTAssertThrowsError(try DefectSidecarResourcePolicy.normalizedItems(
            items, limits: limits
        ), line: line) { error in
            XCTAssertEqual(error as? DefectRecipeValidationError, expected, line: line)
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
