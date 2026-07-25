import XCTest
import Chromabase
import ScannerKit
@testable import negaflowApp

@MainActor
final class AppMetadataOverlayModelTests: XCTestCase {
    func testVirtualCopyStartsWithIndependentOverlayValue() throws {
        let source = temporaryURL("source.tif")
        defer { try? FileManager.default.removeItem(at: source) }
        try MockScannerBackend.writeSyntheticNegative(width: 8, height: 8, to: source)
        let metadata = SourceMetadataReader.read(from: source)
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: source,
            filmType: .colorPositive,
            sourceMetadata: metadata
        )
        frame.setAppMetadataOverlay(AppMetadataOverlay(
            title: "Original",
            keywords: ["film"],
            sourceMetadataSHA256: metadata.appMetadataIdentitySHA256(),
            revision: 1
        ))

        let copy = frame.makeVirtualCopy(copyNumber: 1)
        copy.setAppMetadataOverlay(AppMetadataOverlay(
            title: "Copy",
            sourceMetadataSHA256: metadata.appMetadataIdentitySHA256(),
            revision: 2
        ))

        XCTAssertEqual(frame.appMetadataOverlay?.title, "Original")
        XCTAssertEqual(copy.appMetadataOverlay?.title, "Copy")
        XCTAssertEqual(frame.appMetadataOverlay?.revision, 1)
        XCTAssertEqual(copy.appMetadataOverlay?.revision, 2)
    }

    func testCatalogRecordRoundTripPreservesOverlay() throws {
        let source = temporaryURL("catalog-source.tif")
        defer { try? FileManager.default.removeItem(at: source) }
        try MockScannerBackend.writeSyntheticNegative(width: 8, height: 8, to: source)
        let metadata = SourceMetadataReader.read(from: source)
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: source,
            filmType: .colorPositive,
            sourceMetadata: metadata,
            appMetadataOverlay: AppMetadataOverlay(
                title: "Archive",
                caption: "Frame caption",
                keywords: ["film", "archive"],
                copyright: "Copyright 2026",
                sourceMetadataSHA256: metadata.appMetadataIdentitySHA256(),
                revision: 3,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )

        let encoded = try JSONEncoder().encode(LibraryFrameRecord(frame: frame))
        let decoded = try JSONDecoder().decode(LibraryFrameRecord.self, from: encoded)
        let restored = decoded.makeFrame(presets: [])

        XCTAssertEqual(restored.appMetadataOverlay, frame.appMetadataOverlay)
    }

    func testOverlayConflictTracksSourceMetadataFingerprint() {
        var source = SourceMetadataSnapshot(fileSizeBytes: 10)
        let overlay = AppMetadataOverlay(
            title: "Title",
            sourceMetadataSHA256: source.appMetadataIdentitySHA256(),
            revision: 1
        )
        XCTAssertFalse(overlay.conflicts(with: source))
        source.discardedInvalidValues = true
        XCTAssertTrue(overlay.conflicts(with: source))
    }

    func testInvalidOverlayMakesCatalogHealthFailClosed() throws {
        let source = temporaryURL("invalid-overlay.tif")
        defer { try? FileManager.default.removeItem(at: source) }
        try MockScannerBackend.writeSyntheticNegative(width: 8, height: 8, to: source)
        var overlay = AppMetadataOverlay(
            title: "Title",
            sourceMetadataSHA256: nil,
            revision: 1
        )
        overlay.version = AppMetadataOverlay.currentVersion + 1
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: source,
            filmType: .colorPositive,
            appMetadataOverlay: overlay
        )
        let report = LibraryCatalogHealthInspector.inspect(
            LibraryCatalog(frames: [LibraryFrameRecord(frame: frame)])
        )

        XCTAssertTrue(report.issues.contains { $0.code == .invalidAppMetadataOverlay })
        XCTAssertFalse(report.canOpenSafely)
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-overlay-\(UUID().uuidString)-\(name)")
    }
}
