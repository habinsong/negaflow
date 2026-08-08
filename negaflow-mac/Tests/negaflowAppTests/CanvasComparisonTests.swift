import AppKit
import ScannerKit
import XCTest
@testable import negaflowApp

@MainActor
final class CanvasComparisonTests: XCTestCase {
    func testBeforeSourcesStartWithMainThenUneditedAndRaw() {
        XCTAssertEqual(CompareBeforeContent.allCases, [.main, .unedited, .raw])
    }

    func testNonMainTargetBuildsMainComparisonPreview() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-main-comparison-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("scan.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 64, height: 48, to: sourceURL)
        let model = AppModel(
            libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: sourceURL,
            filmType: .colorNegative
        )
        frame.updateParams { $0.developTarget = .noritsu }
        model.frames = [frame]
        model.beforeAfterCompareActive = true
        model.beforeAfterMainCompareActive = true

        await model.developFrame(frame)

        XCTAssertEqual(frame.params.developTarget, .noritsu)
        XCTAssertNotNil(frame.mainPreviewImage)
        XCTAssertNotNil(frame.cachedMainBase)
        XCTAssertEqual(frame.mainPreviewTransform, frame.imageTransform)
        XCTAssertEqual(frame.mainPreviewDevelopRevision, frame.developRevision)
    }
}
