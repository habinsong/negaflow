import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class DefectBakeTests: XCTestCase {
    private var tempDir: URL!
    // cleaned-raw persist 가 사용자 머신의 실제/iCloud 폴더를 쓰지 않게 per-test temp 로 격리한다.
    private var cleanedRawIsolation: CleanedRawFolderIsolation?

    override func setUp() async throws {
        try await super.setUp()
        cleanedRawIsolation = CleanedRawFolderIsolation()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-defect-persistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        cleanedRawIsolation?.restore()
        cleanedRawIsolation = nil
        try await super.tearDown()
    }

    func testDefectSidecarRoundTripPreservesRecipeKinds() throws {
        let frameID = UUID()
        let mask = Data(repeating: 0, count: 32 * 24 * 4)
        let brush = DefectEditItem(
            edit: .brush([DefectStroke(
                points: [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.3, y: 0.4)],
                thickness: 0.05
            )]),
            title: "brush",
            summary: "b",
            preview: [],
            baseSize: nil
        )
        var region = DefectEditItem(
            edit: .region(
                mask: .raw(mask),
                roi: CGRect(x: 3, y: 4, width: 32, height: 24),
                width: 32,
                height: 24
            ),
            title: "region",
            summary: "r",
            preview: [],
            baseSize: CGSize(width: 80, height: 60)
        )
        region.enabled = false
        region.strength = 0.4

        try DefectSidecarFile.write(
            [brush, region].map { DefectEditItemRecord(item: $0) },
            for: frameID,
            in: tempDir
        )
        let records = try XCTUnwrap(DefectSidecarFile.load(for: frameID, in: tempDir))
        let restored = records.compactMap { $0.makeItem() }

        XCTAssertEqual(restored.map(\.id), [brush.id, region.id])
        XCTAssertEqual(restored[1].enabled, false)
        XCTAssertEqual(restored[1].strength, 0.4, accuracy: 1e-9)
        guard case .region(let restoredMask, let roi, let width, let height) = restored[1].edit else {
            return XCTFail("region recipe was not restored")
        }
        XCTAssertEqual(restoredMask.rawBytes, mask)
        XCTAssertTrue(restoredMask.zlib)
        XCTAssertLessThan(restoredMask.data.count, mask.count)
        XCTAssertEqual(roi, CGRect(x: 3, y: 4, width: 32, height: 24))
        XCTAssertEqual(width, 32)
        XCTAssertEqual(height, 24)
    }

    func testCatalogRecordsNoDefectStateForFramesWithEdits() {
        let original = tempDir.appendingPathComponent("scan.tiff")
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: original,
            filmType: .colorNegative,
            sourceKind: .scannerTIFF
        )
        let cache = CleanedRawCacheFile.makeBuildURL(frameID: frame.id)
        defer { try? FileManager.default.removeItem(at: cache) }
        frame.cleanedRawDiskURL = cache
        frame.cleanedRawEditCount = 2
        frame.defectEdits = [
            DefectEditItem(edit: .brush([]), title: "brush", summary: "", preview: [], baseSize: nil)
        ]

        let record = LibraryFrameRecord(frame: frame)
        let restored = record.makeFrame(presets: [])

        // 기록은 세션 전용이다 — catalog에는 결함 상태가 남지 않는다(종료 시 이미지에 굽힘).
        XCTAssertEqual(record.rawScanPath, original.path)
        XCTAssertNil(record.cleanedRawPath)
        XCTAssertNil(record.cleanedRawEditCount)
        XCTAssertNil(record.hasDefectEdits)
        XCTAssertEqual(restored.rawScanURL, original)
    }

    func testDiscardCleanedRawNeverDeletesOriginal() throws {
        let original = tempDir.appendingPathComponent("scan.tiff")
        try Data("ORIGINAL".utf8).write(to: original)
        let frame = ScanFrame(scanIndex: 1, rawScanURL: original, filmType: .colorNegative)
        let cache = CleanedRawCacheFile.makeBuildURL(frameID: frame.id)
        try Data("CACHE".utf8).write(to: cache)
        frame.cleanedRawDiskURL = cache
        frame.defectEdits = [
            DefectEditItem(edit: .brush([]), title: "brush", summary: "", preview: [], baseSize: nil)
        ]
        let model = AppModel()

        model.discardCleanedRaw(frame)

        XCTAssertEqual(try Data(contentsOf: original), Data("ORIGINAL".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertNil(frame.cleanedRawDiskURL)
    }

    func testDiscardClearsForeignCacheReferenceWithoutDeletingForeignFile() throws {
        let original = tempDir.appendingPathComponent("foreign-source.tiff")
        let foreign = tempDir.appendingPathComponent("foreign-user-file.tiff")
        try Data("ORIGINAL".utf8).write(to: original)
        let foreignBytes = Data("FOREIGN".utf8)
        try foreignBytes.write(to: foreign)
        let frame = ScanFrame(scanIndex: 1, rawScanURL: original, filmType: .colorNegative)
        frame.cleanedRawDiskURL = foreign
        let model = AppModel()

        model.discardCleanedRaw(frame)

        XCTAssertEqual(try Data(contentsOf: foreign), foreignBytes)
        XCTAssertNil(frame.cleanedRawDiskURL)
    }

    func testCompressedDataDegradesCorruptPayloadToEmptyMask() {
        let corrupt = DefectCompressedData(zlib: true, data: Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(corrupt.rawBytes, Data())
    }
}
