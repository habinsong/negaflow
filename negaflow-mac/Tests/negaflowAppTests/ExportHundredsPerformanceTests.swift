import Chromabase
import Foundation
import ImageIO
import ScannerKit
import XCTest
@testable import negaflowApp

/// 현상/인화의 일반·빠른 내보내기를 가상 사진 300장으로 끝까지 통과시키는 opt-in 스트레스 벤치.
///
///     NEGAFLOW_EXPORT_HUNDREDS=1 swift test --filter ExportHundredsPerformanceTests
@MainActor
final class ExportHundredsPerformanceTests: XCTestCase {
    func testThreeHundredVirtualPhotoExportsWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["NEGAFLOW_EXPORT_HUNDREDS"] == "1" else {
            throw XCTSkip(
                "Set NEGAFLOW_EXPORT_HUNDREDS=1 to run the 300-frame export benchmark."
            )
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-export-hundreds-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "negaflow-export-hundreds-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let sourceURL = root.appendingPathComponent("virtual-source.tiff")
        try MockScannerBackend.writeSyntheticNegative(
            width: 1_200,
            height: 800,
            to: sourceURL
        )
        let frames = (1...300).map { index -> ScanFrame in
            let frame = ScanFrame(
                scanIndex: index,
                rawScanURL: sourceURL,
                filmType: .colorPositive,
                sourcePixelWidth: 1_200,
                sourcePixelHeight: 800
            )
            frame.customDisplayName = String(format: "virtual-%03d", index)
            frame.hasDevelopedOnce = true
            frame.displayPixelSize = CGSize(width: 1_200, height: 800)
            return frame
        }

        let developExportRoot = root.appendingPathComponent("DevelopExports", isDirectory: true)
        let developQuickRoot = root.appendingPathComponent(
            "DevelopQuickExports",
            isDirectory: true
        )
        let printExportRoot = root.appendingPathComponent("PrintExports", isDirectory: true)
        let printQuickRoot = root.appendingPathComponent("PrintQuickExports", isDirectory: true)
        let diskStore = DiskStorageStore(defaults: defaults)
        diskStore.exportPath = developExportRoot.path
        diskStore.quickExportPath = developQuickRoot.path
        let exportStore = ExportSettingsStore(defaults: defaults)
        let printStore = PrintWorkspaceSettingsStore(defaults: defaults)
        printStore.layoutMode = .singleImage
        printStore.paperSize = .fourBySix
        printStore.orientation = .landscape
        printStore.marginMM = 5
        let model = AppModel(
            exportSettingsStore: exportStore,
            printWorkspaceSettingsStore: printStore,
            diskStorageStore: diskStore,
            libraryCatalogURL: root.appendingPathComponent("library.sqlite"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups")
        )
        await model.restoreLibraryOnLaunch()
        model.frames = frames
        XCTAssertTrue(model.assignNewPersistentFrames(frames))
        model.updateInteractionScope(frames.map(\.id))
        model.selectedFrameIDs = Set(frames.map(\.id))
        model.exportFormat = .jpeg
        model.exportDPI = 300
        model.exportLongEdge = 0
        model.exportWriteSidecar = false
        model.exportWriteMainFlatMaster = false
        model.exportWriteOriginalRaw = false
        model.quickExportFormat = .jpeg
        model.quickExportDPI = 300
        model.quickExportLongEdge = 2_048

        let developExportSeconds = try await measureBatch {
            model.exportSelectionToFolder()
        } waitingFor: {
            !model.exportBatchStore.isRunning
        }
        try assertBatchSucceeded(model, expectedCount: 300)
        let developExportFiles = jpegFiles(below: developExportRoot)
        XCTAssertEqual(developExportFiles.count, 300)
        try assertPixelSize(try XCTUnwrap(developExportFiles.first), width: 1_200, height: 800)

        let developQuickSeconds = try await measureBatch {
            model.quickExportSelection()
        } waitingFor: {
            !model.exportBatchStore.isRunning
        }
        try assertBatchSucceeded(model, expectedCount: 300)
        let developQuickFiles = jpegFiles(below: developQuickRoot)
        XCTAssertEqual(developQuickFiles.count, 300)
        try assertPixelSize(try XCTUnwrap(developQuickFiles.first), width: 1_200, height: 800)

        diskStore.exportPath = printExportRoot.path
        let printSettings = printStore.compositionSettings(dpi: 300)
        let printExportSeconds = try await measureBatch {
            model.exportPrintSelectionToFolder(settings: printSettings)
        } waitingFor: {
            !model.exportBatchStore.isRunning
        }
        try assertBatchSucceeded(model, expectedCount: 300)
        let printExportFiles = jpegFiles(below: printExportRoot)
        XCTAssertEqual(printExportFiles.count, 300)
        try assertPixelSize(try XCTUnwrap(printExportFiles.first), width: 1_800, height: 1_200)

        diskStore.quickExportPath = printQuickRoot.path
        let printQuickSeconds = try await measureBatch {
            model.quickExportPrintSelection(settings: printSettings)
        } waitingFor: {
            !model.exportBatchStore.isRunning
        }
        try assertBatchSucceeded(model, expectedCount: 300)
        let printQuickFiles = jpegFiles(below: printQuickRoot)
        XCTAssertEqual(printQuickFiles.count, 300)
        try assertPixelSize(try XCTUnwrap(printQuickFiles.first), width: 1_800, height: 1_200)

        print(String(
            format: """
            [export-hundreds-perf] virtual=300 source=1200x800 output=JPEG
              develop export  300 -> 300: %.3f s
              develop quick   300 -> 300: %.3f s
              print export    300 -> 300 @300dpi: %.3f s
              print quick     300 -> 300 @300dpi: %.3f s
            """,
            developExportSeconds,
            developQuickSeconds,
            printExportSeconds,
            printQuickSeconds
        ))
    }

    private func measureBatch(
        start: () -> Void,
        waitingFor completion: @escaping @MainActor () -> Bool
    ) async throws -> Double {
        let startedAt = Date()
        start()
        try await waitUntil(timeoutSeconds: 900, condition: completion)
        return Date().timeIntervalSince(startedAt)
    }

    private func waitUntil(
        timeoutSeconds: Double,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "300-frame export benchmark timed out")
    }

    private func assertBatchSucceeded(
        _ model: AppModel,
        expectedCount: Int
    ) throws {
        XCTAssertEqual(model.exportBatchStore.items.count, expectedCount)
        XCTAssertEqual(
            model.exportBatchStore.completedCount,
            expectedCount,
            "status=\(model.statusMessage)"
        )
        XCTAssertEqual(model.exportBatchStore.failedCount, 0, "status=\(model.statusMessage)")
    }

    private func jpegFiles(below directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.pathExtension == "jpg",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            return url
        }
    }

    private func assertPixelSize(
        _ url: URL,
        width: Int,
        height: Int
    ) throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, width)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, height)
    }
}
