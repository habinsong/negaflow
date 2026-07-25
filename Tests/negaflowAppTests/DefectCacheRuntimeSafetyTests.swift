import AppKit
import CoreGraphics
import ScannerKit
import XCTest
@testable import negaflowApp

@MainActor
final class DefectCacheRuntimeSafetyTests: XCTestCase {
    // cleaned-raw persist 가 사용자 머신의 실제/iCloud 폴더를 쓰지 않게 per-test temp 로 격리한다.
    nonisolated(unsafe) private var cleanedRawIsolation: CleanedRawFolderIsolation?

    override func setUp() {
        super.setUp()
        cleanedRawIsolation = CleanedRawFolderIsolation()
    }

    override func tearDown() {
        cleanedRawIsolation?.restore()
        cleanedRawIsolation = nil
        super.tearDown()
    }

    func testSparseRegionCachesOnlyChangedMaskBounds() throws {
        let width = 96, height = 72
        var mask = Data(repeating: 0, count: width * height * 4)
        for y in 30...32 {
            for x in 40...43 {
                let offset = (y * width + x) * 4
                mask[offset] = 255
                mask[offset + 1] = 255
                mask[offset + 2] = 255
                mask[offset + 3] = 255
            }
        }
        let edit = DefectEdit.region(
            mask: DefectCompressedData.raw(mask).compressed(),
            roi: CGRect(x: 0, y: 0, width: width, height: height),
            width: width,
            height: height
        )

        let patches = try XCTUnwrap(computeDefectPatches(
            edit,
            base: makeImage(width: width, height: height),
            shouldCancel: { false }
        ))
        let patch = try XCTUnwrap(patches.first)

        // 마스크 행 30~32(y-down) → y-up rect y = 72 - 33 = 39. 과거에는 y-down 값(30)을 그대로
        // 패치 rect 에 써서 rect 가 수직으로 반사됐다 — 중앙에서 벗어난 결함이 제거되지 않던 원인.
        XCTAssertEqual(patch.rect, CGRect(x: 40, y: 39, width: 4, height: 3))
        XCTAssertEqual(patch.image.width, 4)
        XCTAssertEqual(patch.image.height, 3)
    }

    func testSamePathSourceByteChangeInvalidatesBoundCacheAndPatchState() async throws {
        let root = temporaryDirectory("source-change")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("scan.tiff")
        try Data("AAAA".utf8).write(to: sourceURL)

        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        let frame = ScanFrame(scanIndex: 1, rawScanURL: sourceURL, filmType: .colorNegative)
        var edit = makeEdit()
        edit.cachedPatches = []
        frame.defectEdits = [edit]
        model.frames = [frame]

        let sourceIdentity = try AppModel.defectSourceIdentity(for: sourceURL)
        let snapshot = try DefectRecipeSnapshot(
            frameID: frame.id,
            revision: 1,
            sourceIdentity: sourceIdentity,
            items: [DefectEditItemRecord(item: edit)]
        )
        model.installDefectRecipeIdentity(snapshot.identity, on: frame)

        let cacheURL = CleanedRawCacheFile.makeBuildURL(frameID: frame.id)
        defer {
            try? FileManager.default.removeItem(at: cacheURL)
        }
        try Data("cleaned pixels".utf8).write(to: cacheURL)
        let image = try makeImage()
        frame.cleanedRawImage = image
        frame.cleanedRawMemoryIdentity = snapshot.identity
        frame.cleanedRawDiskURL = cacheURL
        frame.cleanedRawDiskIdentity = snapshot.identity
        frame.cleanedRawEditCount = 1
        frame.cleanedRawPreviousImage = image
        frame.cleanedRawPreviousEditCount = 0
        frame.cleanedRawPreviousIdentity = snapshot.identity

        // 파일 크기는 그대로 두고 바이트만 바꿔 path/size 기반 신뢰가 통과하는 경우를 재현한다.
        try Data("BBBB".utf8).write(to: sourceURL)

        let prepared = await model.prepareCleanedRawForConsumption(frame)
        XCTAssertFalse(prepared)
        let rebuild = frame.cleanRawTask
        await rebuild?.value

        XCTAssertNil(frame.cleanedRawImage)
        XCTAssertNil(frame.cleanedRawMemoryIdentity)
        XCTAssertNil(frame.cleanedRawDiskURL)
        XCTAssertNil(frame.cleanedRawDiskIdentity)
        XCTAssertNil(frame.cleanedRawPreviousImage)
        XCTAssertNil(frame.cleanedRawPreviousIdentity)
        XCTAssertNil(frame.defectEdits[0].cachedPatches)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertEqual(frame.defectRecipeIdentity?.revision, 2)
        XCTAssertNil(frame.defectRecipeIdentity?.sourceIdentity)
    }

    func testCleanedRawCommitDropsPreviousRawAndNeutralPreviewGeneration() async throws {
        let root = temporaryDirectory("preview-generation")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("scan.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: sourceURL)
        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        let frame = ScanFrame(scanIndex: 1, rawScanURL: sourceURL, filmType: .colorPositive)
        frame.defectEdits = [makeEdit()]
        model.frames = [frame]
        let oldRawPreview = NSImage(size: NSSize(width: 3, height: 3))
        let oldNeutralPreview = NSImage(size: NSSize(width: 4, height: 4))
        let oldMainPreview = NSImage(size: NSSize(width: 5, height: 5))
        frame.rawPreviewImage = oldRawPreview
        frame.neutralPreviewImage = oldNeutralPreview
        frame.mainPreviewImage = oldMainPreview
        frame.rawPreviewTransform = frame.imageTransform
        frame.neutralPreviewTransform = frame.imageTransform

        let snapshot = try XCTUnwrap(model.refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: false
        ))
        model.rebuildCleanedRaw(
            frame,
            recipeSnapshot: snapshot,
            persist: false,
            quiet: true
        )
        let task = try XCTUnwrap(frame.cleanRawTask)
        await task.value

        XCTAssertFalse(frame.rawPreviewImage === oldRawPreview)
        XCTAssertFalse(frame.neutralPreviewImage === oldNeutralPreview)
        XCTAssertFalse(frame.mainPreviewImage === oldMainPreview)
    }

    private func makeEdit() -> DefectEditItem {
        DefectEditItem(
            edit: .brush([DefectStroke(
                points: [CGPoint(x: 0.25, y: 0.5)],
                thickness: 0.03
            )]),
            label: .brush(strokeCount: 1),
            summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)),
            preview: [],
            baseSize: nil
        )
    }

    private func makeImage() throws -> CGImage {
        try makeImage(width: 1, height: 1)
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw NSError(domain: "DefectCacheRuntimeSafetyTests", code: 1)
        }
        return image
    }

    private func temporaryDirectory(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-defect-cache-\(suffix)-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
