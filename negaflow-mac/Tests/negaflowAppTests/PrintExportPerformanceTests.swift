import Chromabase
import ScannerKit
import XCTest
@testable import negaflowApp

/// 실제 12MP 원본 39장과 300dpi 산출물을 쓰는 인화 내보내기 벤치.
///
///     NEGAFLOW_PRINT_EXPORT_PERF=1 swift test --filter PrintExportPerformanceTests
@MainActor
final class PrintExportPerformanceTests: XCTestCase {
    func testThirtyNineFramePrintExportWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["NEGAFLOW_PRINT_EXPORT_PERF"] == "1" else {
            throw XCTSkip(
                "Set NEGAFLOW_PRINT_EXPORT_PERF=1 to run the 39-frame print export benchmark."
            )
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-print-export-benchmark-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "negaflow-print-export-benchmark-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fixtureURL = root.appendingPathComponent("fixture.tiff")
        try MockScannerBackend.writeSyntheticNegative(
            width: 4_000,
            height: 3_000,
            to: fixtureURL
        )
        let sourceDirectory = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        let frames = try (1...39).map { index -> ScanFrame in
            let sourceURL = sourceDirectory.appendingPathComponent("frame-\(index).tiff")
            try FileManager.default.copyItem(at: fixtureURL, to: sourceURL)
            let frame = ScanFrame(
                scanIndex: index,
                rawScanURL: sourceURL,
                filmType: .colorPositive,
                sourcePixelWidth: 4_000,
                sourcePixelHeight: 3_000
            )
            frame.hasDevelopedOnce = true
            frame.displayPixelSize = CGSize(width: 4_000, height: 3_000)
            return frame
        }

        let exportRoot = root.appendingPathComponent("Exports", isDirectory: true)
        let quickRoot = root.appendingPathComponent("QuickExports", isDirectory: true)
        let diskStore = DiskStorageStore(defaults: defaults)
        diskStore.exportPath = exportRoot.path
        diskStore.quickExportPath = quickRoot.path
        let printStore = PrintWorkspaceSettingsStore(defaults: defaults)
        printStore.layoutMode = .contactSheet
        printStore.paperSize = .a4
        printStore.orientation = .landscape
        printStore.marginMM = 5
        printStore.packageSettings = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 6,
            contactColumns: 7,
            horizontalSpacingMM: 1,
            verticalSpacingMM: 1
        )
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            printWorkspaceSettingsStore: printStore,
            diskStorageStore: diskStore,
            libraryCatalogURL: root.appendingPathComponent("library.json"),
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

        let contactStartedAt = Date()
        model.exportPrintSelectionToFolder(settings: printStore.compositionSettings(dpi: 300))
        try await waitUntil(timeoutSeconds: 300) { !model.isPrintPackageExporting }
        let contactSeconds = Date().timeIntervalSince(contactStartedAt)
        let contactOutputs = regularFiles(below: exportRoot).filter {
            $0.pathExtension == "jpg"
        }
        XCTAssertEqual(contactOutputs.count, 1, "status=\(model.statusMessage)")

        printStore.layoutMode = .singleImage
        printStore.paperSize = .fourBySix
        printStore.orientation = .landscape
        model.quickExportFormat = .jpeg
        model.quickExportDPI = 300
        let singleStartedAt = Date()
        model.quickExportPrintSelection(settings: printStore.compositionSettings(dpi: 300))
        try await waitUntil(timeoutSeconds: 600) { !model.exportBatchStore.isRunning }
        let singleSeconds = Date().timeIntervalSince(singleStartedAt)
        let singleOutputs = regularFiles(below: quickRoot).filter {
            $0.pathExtension == "jpg"
        }
        XCTAssertEqual(model.exportBatchStore.completedCount, 39, "status=\(model.statusMessage)")
        XCTAssertEqual(model.exportBatchStore.failedCount, 0, "status=\(model.statusMessage)")
        XCTAssertEqual(singleOutputs.count, 39, "status=\(model.statusMessage)")

        let historicalModes: [(String, PrintWorkspaceLayoutMode)] = [
            ("cyanotype", .cyanotype),
            ("glass-plate", .glassPlate),
            ("gelatin", .gelatin),
        ]
        var historicalDurations: [(name: String, export: Double, quick: Double)] = []
        for (name, mode) in historicalModes {
            printStore.layoutMode = mode
            XCTAssertEqual(model.printExportOutputCount, 39)

            let modeExportRoot = root.appendingPathComponent(
                "\(name)-Exports",
                isDirectory: true
            )
            diskStore.exportPath = modeExportRoot.path
            let exportStartedAt = Date()
            model.exportPrintSelectionToFolder(settings: printStore.compositionSettings(dpi: 300))
            try await waitUntil(timeoutSeconds: 600) { !model.exportBatchStore.isRunning }
            let exportSeconds = Date().timeIntervalSince(exportStartedAt)
            XCTAssertEqual(model.exportBatchStore.completedCount, 39, "status=\(model.statusMessage)")
            XCTAssertEqual(model.exportBatchStore.failedCount, 0, "status=\(model.statusMessage)")
            XCTAssertEqual(
                regularFiles(below: modeExportRoot).filter { $0.pathExtension == "jpg" }.count,
                39,
                "status=\(model.statusMessage)"
            )

            let modeQuickRoot = root.appendingPathComponent(
                "\(name)-QuickExports",
                isDirectory: true
            )
            diskStore.quickExportPath = modeQuickRoot.path
            let quickStartedAt = Date()
            model.quickExportPrintSelection(settings: printStore.compositionSettings(dpi: 300))
            try await waitUntil(timeoutSeconds: 600) { !model.exportBatchStore.isRunning }
            let quickSeconds = Date().timeIntervalSince(quickStartedAt)
            XCTAssertEqual(model.exportBatchStore.completedCount, 39, "status=\(model.statusMessage)")
            XCTAssertEqual(model.exportBatchStore.failedCount, 0, "status=\(model.statusMessage)")
            XCTAssertEqual(
                regularFiles(below: modeQuickRoot).filter { $0.pathExtension == "jpg" }.count,
                39,
                "status=\(model.statusMessage)"
            )
            historicalDurations.append((name, exportSeconds, quickSeconds))
        }

        let sourceBytes = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: fixtureURL.path)[.size] as? NSNumber
        ).doubleValue
        print(String(
            format: """
            [print-export-perf] sources=39 source=4000x3000 %.1fMB output=300dpi
              contact-sheet 39 -> 1: %.3f s
              single-image  39 -> 39: %.3f s
            """,
            sourceBytes / 1_048_576,
            contactSeconds,
            singleSeconds
        ))
        for duration in historicalDurations {
            print(String(
                format: "  %@ 39 -> 39: export %.3f s / quick %.3f s",
                duration.name,
                duration.export,
                duration.quick
            ))
        }
    }

    private func waitUntil(
        timeoutSeconds: Double,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "print export benchmark timed out")
    }

    private func regularFiles(below directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            return url
        }
    }
}
