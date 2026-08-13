import ScannerKit
import XCTest
@testable import negaflowApp

@MainActor
final class LibraryFolderDevelopmentTests: XCTestCase {
    func testFolderConfigurationAppliesProcessAndTargetToEveryOwnedFrame() {
        let model = AppModel()
        let first = makeFrame(index: 1)
        let second = makeFrame(index: 2)
        model.frames = [first, second]

        let configured = model.configureLibraryFolderDevelopment(
            process: .digitalBW,
            target: .hr,
            frames: [first, second]
        )

        XCTAssertEqual(configured.map(\.id), [first.id, second.id])
        for frame in configured {
            XCTAssertEqual(frame.filmType, .bwPositive)
            XCTAssertEqual(frame.params.filmType, .bwPositive)
            XCTAssertEqual(frame.params.isDigitalSource, true)
            XCTAssertEqual(frame.params.developTarget, .hr)
            XCTAssertNil(frame.params.scannerProfileID)
            XCTAssertTrue(frame.showDeveloped)
        }
    }

    func testFolderConfigurationIgnoresFramesOutsideCurrentLibrary() {
        let model = AppModel()
        let owned = makeFrame(index: 1)
        let stale = makeFrame(index: 2)
        model.frames = [owned]

        let configured = model.configureLibraryFolderDevelopment(
            process: .c41,
            target: .main,
            frames: [owned, stale]
        )

        XCTAssertEqual(configured.map(\.id), [owned.id])
        XCTAssertEqual(stale.filmType, .colorPositive)
    }

    func testFolderConfigurationReappliesProcessAndTargetToPreviouslyDevelopedFrame() {
        let model = AppModel()
        let frame = makeFrame(index: 1)
        frame.hasDevelopedOnce = true
        frame.showDeveloped = false
        frame.updateParams {
            $0.exposure = 0.42
            $0.contrast = -0.17
        }
        model.frames = [frame]

        let configured = model.configureLibraryFolderDevelopment(
            process: .c41,
            target: .main,
            frames: [frame]
        )

        XCTAssertEqual(configured.map(\.id), [frame.id])
        XCTAssertEqual(frame.filmType, .colorNegative)
        XCTAssertEqual(frame.params.filmType, .colorNegative)
        XCTAssertNil(frame.params.isDigitalSource)
        XCTAssertEqual(frame.params.developTarget, .main)
        XCTAssertEqual(frame.params.exposure, 0.42)
        XCTAssertEqual(frame.params.contrast, -0.17)
        XCTAssertTrue(frame.showDeveloped)
    }

    func testFolderApplyRerendersPreviouslyDevelopedFrameAndReportsProgress() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-folder-reapply-\(UUID().uuidString).tiff")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try MockScannerBackend.writeSyntheticNegative(width: 24, height: 16, to: sourceURL)
        let model = AppModel()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: sourceURL,
            filmType: .colorPositive,
            sourceKind: .importedFile
        )
        frame.hasDevelopedOnce = true
        model.frames = [frame]
        var updates: [LibraryTaskProgress] = []

        let task = model.applyLibraryFolderDevelopment(
            process: .c41,
            target: .hr,
            frames: [frame],
            progress: { updates.append($0) }
        )
        await task.value

        XCTAssertEqual(frame.filmType, .colorNegative)
        XCTAssertEqual(frame.params.developTarget, .hr)
        XCTAssertTrue(frame.hasDevelopedOnce)
        XCTAssertNotNil(frame.developedImage)
        XCTAssertNotNil(frame.thumbnailImage)
        XCTAssertEqual(updates.first, LibraryTaskProgress(completedCount: 0, totalCount: 1))
        XCTAssertEqual(updates.last, LibraryTaskProgress(completedCount: 1, totalCount: 1))
    }

    func testNewerDevelopSelectionWinsOverAnOlderQueuedFolderApply() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-folder-latest-selection-\(UUID().uuidString).tiff")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try MockScannerBackend.writeSyntheticNegative(width: 24, height: 16, to: sourceURL)
        let model = AppModel()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: sourceURL,
            filmType: .colorPositive,
            sourceKind: .importedFile
        )
        model.frames = [frame]
        XCTAssertTrue(model.developController.beginFrame(frame))

        let folderTask = model.applyLibraryFolderDevelopment(
            process: .c41,
            target: .hr,
            frames: [frame]
        )
        model.applyDevelopmentProcess(.digitalBW, to: frame)
        model.applyDevelopTarget(.main, to: frame)
        model.developController.endFrame(frame)
        await folderTask.value

        XCTAssertEqual(frame.filmType, .bwPositive)
        XCTAssertEqual(frame.params.isDigitalSource, true)
        XCTAssertEqual(frame.params.developTarget, .main)
        let restored = LibraryFrameRecord(frame: frame).makeFrame(presets: [])
        XCTAssertEqual(restored.filmType, .bwPositive)
        XCTAssertEqual(restored.params.isDigitalSource, true)
        XCTAssertEqual(restored.params.developTarget, .main)
    }

    private func makeFrame(index: Int) -> ScanFrame {
        ScanFrame(
            scanIndex: index,
            rawScanURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("negaflow-folder-develop-\(UUID().uuidString).tiff"),
            filmType: .colorPositive,
            sourceKind: .importedFile
        )
    }
}
