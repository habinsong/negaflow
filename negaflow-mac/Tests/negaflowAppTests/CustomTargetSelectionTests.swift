import Chromabase
import ScannerKit
import XCTest
@testable import negaflowApp

@MainActor
final class CustomTargetSelectionTests: XCTestCase {
    func testCapsuleFamiliesAndEntryRules() {
        XCTAssertEqual(DevelopTargetFamily.allCases.map(\.displayName), ["MAIN", "HS", "SP", "F135", "HR", "CS"])
        XCTAssertEqual(DevelopTarget.customGroups.map(\.count), [11, 4, 3])
        XCTAssertEqual(DevelopTargetFamily.custom.selection(from: .main), .emulsion)
        XCTAssertEqual(DevelopTargetFamily.custom.selection(from: .noritsu), .emulsion)
        XCTAssertEqual(DevelopTargetFamily.main.selection(from: .print), .print)
        XCTAssertEqual(DevelopTargetFamily.main.selection(from: .rescue), .rescue)
        XCTAssertEqual(DevelopTargetFamily.main.selection(from: .classic), .main)
        for target in DevelopTarget.customTargets {
            XCTAssertEqual(DevelopTargetFamily(target: target), .custom)
            XCTAssertEqual(DevelopTargetFamily.custom.selection(from: target), target)
            XCTAssertNil(WorkflowShortcutAction.developTargetAction(target))
        }
        for target in DevelopTarget.standardTargets {
            XCTAssertNotNil(WorkflowShortcutAction.developTargetAction(target))
        }
    }

    func testNamesRemainEnglishAcrossAllLanguages() {
        for language in AppLanguage.allCases {
            for target in DevelopTarget.customTargets {
                XCTAssertEqual(target.displayName(language: language), target.displayName)
            }
        }
    }

    func testTwoColumnNavigationRespectsGroupBreaksAndEmptyCells() {
        XCTAssertEqual(CustomTargetNavigation.rows.count, 10)
        XCTAssertEqual(CustomTargetNavigation.rows[5], [.dichroic])
        XCTAssertEqual(CustomTargetNavigation.rows[6], [.wetzlar, .classic])
        XCTAssertEqual(CustomTargetNavigation.rows[7], [.studio, .rochester])
        XCTAssertEqual(CustomTargetNavigation.rows[8], [.slideShow, .cinema])
        XCTAssertEqual(CustomTargetNavigation.rows[9], [.pointAndShoot])
        XCTAssertEqual(CustomTargetNavigation.moved(from: .dichroic, direction: .right), .dichroic)
        XCTAssertEqual(CustomTargetNavigation.moved(from: .dichroic, direction: .down), .wetzlar)
        XCTAssertEqual(CustomTargetNavigation.moved(from: .rochester, direction: .down), .cinema)
        XCTAssertEqual(CustomTargetNavigation.moved(from: .cinema, direction: .down), .pointAndShoot)
        XCTAssertEqual(CustomTargetNavigation.moved(from: .emulsion, direction: .up), .emulsion)
    }

    func testAllCustomTargetsPersistWithoutOverwritingOtherSettings() throws {
        let model = AppModel()
        let frame = makeFrame()
        model.frames = [frame]
        frame.updateParams {
            $0.filmType = .colorPositive
            $0.exposure = 0.45
            $0.warmth = -0.3
            $0.grain = 0.2
            $0.manualBaseRGB = SIMD3(0.8, 0.7, 0.6)
            $0.scannerProfileID = "unused-profile"
        }
        let original = frame.params
        let sourceURL = frame.rawScanURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var fingerprints = Set<String>()
        for target in DevelopTarget.customTargets {
            _ = model.configureLibraryFolderDevelopment(process: .e6, target: target, frames: [frame])
            let restored = LibraryFrameRecord(frame: frame).makeFrame(presets: [])
            var expected = original
            expected.developTarget = target
            expected.scannerProfileID = nil
            XCTAssertEqual(try encoder.encode(restored.params), try encoder.encode(expected))
            XCTAssertEqual(restored.rawScanURL, sourceURL)
            XCTAssertEqual(DevelopTargetFamily(target: restored.params.developTarget), .custom)
            fingerprints.insert(try XCTUnwrap(frame.currentLibraryDevelopRecipeSHA256()))
        }
        XCTAssertEqual(fingerprints.count, 18)
    }

    func testFolderApplyRendersEveryCustomTargetAndThumbnail() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("custom-folder-\(UUID().uuidString).tiff")
        defer { try? FileManager.default.removeItem(at: url) }
        try MockScannerBackend.writeSyntheticNegative(width: 24, height: 16, to: url)
        let original = try Data(contentsOf: url)
        let model = AppModel()
        let frame = ScanFrame(scanIndex: 1, rawScanURL: url, filmType: .colorPositive, sourceKind: .importedFile)
        model.frames = [frame]
        for target in DevelopTarget.customTargets {
            var progress: [LibraryTaskProgress] = []
            await model.applyLibraryFolderDevelopment(process: .e6, target: target, frames: [frame],
                                                       progress: { progress.append($0) }).value
            XCTAssertEqual(frame.params.developTarget, target)
            XCTAssertNotNil(frame.developedImage, target.rawValue)
            XCTAssertNotNil(frame.thumbnailImage, target.rawValue)
            XCTAssertEqual(progress.last, LibraryTaskProgress(completedCount: 1, totalCount: 1))
        }
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    private func makeFrame() -> ScanFrame {
        ScanFrame(scanIndex: 1,
                  rawScanURL: FileManager.default.temporaryDirectory.appendingPathComponent("custom-state-\(UUID().uuidString).tiff"),
                  filmType: .colorPositive, sourceKind: .importedFile)
    }
}
