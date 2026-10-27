import XCTest
import Foundation
import Chromabase
@testable import negaflowApp

@MainActor
final class AutoBalanceInteractionPerformanceTests: XCTestCase {
    func testRealToggleAndExportWhenRequested() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let source = env["NEGAFLOW_BALANCE_BENCH_SOURCE"],
              let destination = env["NEGAFLOW_BALANCE_BENCH_OUTPUT"] else {
            throw XCTSkip("Set NEGAFLOW_BALANCE_BENCH_SOURCE and NEGAFLOW_BALANCE_BENCH_OUTPUT.")
        }
        let root = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = AppModel(libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups"))
        await model.restoreLibraryOnLaunch()
        let frame = ScanFrame(scanIndex: 1, rawScanURL: URL(fileURLWithPath: source),
                              filmType: .colorNegative, sourceKind: .importedFile)
        model.frames = [frame]
        XCTAssertTrue(model.assignNewPersistentFrames([frame]))
        model.selectedFrameID = frame.id
        model.activeWorkspaceModule = .develop
        model.canvasDisplayTargetPixels = 2400
        defer { model.frames = [] }
        for on in [true, false, true, false, true] {
            frame.updateParams { $0.autoBalance = on }
            let start = ProcessInfo.processInfo.systemUptime
            await model.developFrame(frame)
            let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
            XCTAssertTrue(frame.hasDevelopedOnce)
            print("[balance-bench] on=\(on) ms=\(ms)")
        }
        if env["NEGAFLOW_BALANCE_BENCH_EXPORT"] == "1" {
            for format in [ExportFormat.tiff16, .dng] {
                let url = root.appendingPathComponent(UUID().uuidString).appendingPathExtension(format.fileExtension)
                let start = ProcessInfo.processInfo.systemUptime
                let outcome = await model.runExportFrameTransaction(frame, to: url, format: format,
                    writeSidecar: false, writeMainFlatMaster: false, writeOriginalRaw: false,
                    options: .standard, recipeIdentity: nil, reportsGlobalStatus: false)
                guard case .completed(let written, _) = outcome else { return XCTFail("\(outcome)") }
                XCTAssertEqual(written.deletingLastPathComponent(), root)
                let bytes = try written.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                XCTAssertGreaterThan(bytes, 0)
                print("[export-bench] format=\(format) ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000) bytes=\(bytes) path=\(written.path)")
            }
        }
    }
}
