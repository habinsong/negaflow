import AppKit
import Chromabase
import CoreImage
import ImageIO
import XCTest
@testable import negaflowApp

/// Opt-in measurements with an existing catalog's parameters. The catalog is only read;
/// model persistence uses a temporary directory. No source or recipe is modified.
@MainActor
final class RasterSelectionTimingDiagnosticsTests: XCTestCase {
    func testColdCatalogSelections() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["NEGAFLOW_RASTER_TIMING_CATALOG"],
              let ids = environment["NEGAFLOW_RASTER_TIMING_IDS"] else {
            throw XCTSkip("Set NEGAFLOW_RASTER_TIMING_CATALOG and NEGAFLOW_RASTER_TIMING_IDS")
        }
        let catalog = try XCTUnwrap(LibraryCatalogFile.load(from: URL(fileURLWithPath: path)))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(libraryCatalogURL: root.appendingPathComponent("library.sqlite"),
            libraryDefectDirectoryURL: root.appendingPathComponent("Defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("Backups"))
        await model.restoreLibraryOnLaunch()
        model.activeWorkspaceModule = .develop
        model.canvasDisplayTargetPixels = 2560
        let requestedIDs = ids.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        let records = try requestedIDs.map { id in
            try XCTUnwrap(catalog.frames.first { $0.id == id && $0.hasDefectEdits != true })
        }
        let frames = records.map { $0.makeFrame(presets: model.presets) }
        model.frames = frames
        XCTAssertTrue(model.assignNewPersistentFrames(frames))
        defer { model.cancelNeighborCameraRAWPrefetch() }
        for frame in frames {
            model.interactionScopeFrameIDs = [frame.id]
            let start = Date()
            model.activateFrame(frame.id)
            let support = Task { await model.checkInputGammaSupport(for: frame) }
            var first: Double?
            while !frame.developedIsSettled || frame.developedImage == nil {
                if first == nil, frame.developedImage != nil { first = -start.timeIntervalSinceNow }
                guard -start.timeIntervalSinceNow < 120 else { return XCTFail("Selection timed out") }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            let settled = -start.timeIntervalSinceNow
            await model.selectedFrameDevelopTask?.value
            await support.value
            print(String(format: "[raster-selection] %@ first %.0f ms settled %.0f ms gamma-source %@",
                frame.id.uuidString, (first ?? settled) * 1000, settled * 1000,
                frame.inputGammaPreviewSource == nil ? "no" : "yes"))
            if let output = environment["NEGAFLOW_RASTER_TIMING_OUTPUT"],
               let image = frame.developedImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let directory = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let file = directory.appendingPathComponent(frame.id.uuidString + ".tiff")
                let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL,
                    "public.tiff" as CFString, 1, nil))
                CGImageDestinationAddImage(destination, image, nil)
                XCTAssertTrue(CGImageDestinationFinalize(destination))
            }
        }
    }
}
