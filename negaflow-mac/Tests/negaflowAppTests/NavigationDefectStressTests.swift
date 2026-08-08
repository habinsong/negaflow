import AppKit
import ScannerKit
import XCTest
@testable import negaflowApp

@MainActor
final class NavigationDefectStressTests: XCTestCase {

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func testRapidNavigationAcrossDefectFramesKeepsOnlyUsefulWork() async throws {
        guard ProcessInfo.processInfo.environment["NEGAFLOW_NAVIGATION_DEFECT_STRESS"] == "1" else {
            throw XCTSkip("Set NEGAFLOW_NAVIGATION_DEFECT_STRESS=1 to run the real-pixel defect-removal navigation stress.")
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-navigation-defect-stress-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 2_400, height: 1_600, to: sourceURL)

        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        model.canvasDisplayTargetPixels = 1_024
        let sourceIdentity = try AppModel.defectSourceIdentity(for: sourceURL)
        var ownedCacheURLs: [URL] = []
        defer {
            model.selectedFrameDevelopTask?.cancel()
            for url in ownedCacheURLs {
                try? FileManager.default.removeItem(at: url)
            }
            try? FileManager.default.removeItem(at: root)
        }

        let frames = try (0..<8).map { index -> ScanFrame in
            let frame = ScanFrame(
                scanIndex: index + 1,
                rawScanURL: sourceURL,
                filmType: .colorNegative,
                sourceKind: .scannerTIFF
            )
            let mask = DefectCompressedData.raw(Data([255, 255, 255, 255])).compressed()
            let item = DefectEditItem(
                edit: .region(mask: mask, roi: CGRect(x: 10, y: 10, width: 1, height: 1), width: 1, height: 1),
                label: .guided(count: 1),
                summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)),
                preview: [],
                baseSize: CGSize(width: 2_400, height: 1_600)
            )
            frame.defectEdits = [item]
            let snapshot = try DefectRecipeSnapshot(
                frameID: frame.id,
                revision: 1,
                sourceIdentity: sourceIdentity,
                items: [DefectEditItemRecord(item: item)]
            )
            model.installDefectRecipeIdentity(snapshot.identity, on: frame)

            let cacheURL = CleanedRawCacheFile.makeBuildURL(frameID: frame.id)
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: cacheURL)
            try FileManager.default.copyItem(at: sourceURL, to: cacheURL)
            ownedCacheURLs.append(cacheURL)
            frame.cleanedRawDiskURL = cacheURL
            frame.cleanedRawDiskIdentity = snapshot.identity
            frame.cleanedRawEditCount = 1
            frame.hasDevelopedOnce = true
            return frame
        }
        model.frames = frames

        let started = Date()
        for index in 0..<48 {
            model.selectedFrameID = frames[index % frames.count].id
            try await Task.sleep(nanoseconds: 15_000_000)
        }
        let finalFrame = frames.last!
        model.selectedFrameID = finalFrame.id
        await model.selectedFrameDevelopTask?.value
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertNotNil(finalFrame.developedImage)
        XCTAssertFalse(model.processingActive)
        XCTAssertTrue(frames.allSatisfy { $0.cleanedRawImage == nil })
        XCTAssertTrue(model.residentCleanedRawIDs.isEmpty)
        XCTAssertLessThanOrEqual(model.residentDevelopedIDs.count, model.maxResidentDeveloped)
        XCTAssertLessThan(elapsed, 20, "빠른 결함 제거 프레임 전환이 유휴 작업 때문에 장시간 정체됨")
    }
}
