import Foundation
import XCTest
@testable import negaflowApp

@MainActor
struct LibraryArchiveTestFixture {
    let root: URL
    let catalogURL: URL
    let defectDirectory: URL
    let archiveURL: URL
    let originalURL: URL
    let infraredURL: URL
    let originalFrameID: UUID
    let virtualFrameID: UUID

    init(includeDefectRecipe: Bool = true, usesSQLiteCatalog: Bool = false) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-archive-tests-\(UUID().uuidString)", isDirectory: true)
        catalogURL = root.appendingPathComponent(
            usesSQLiteCatalog ? "live/library.sqlite" : "live/library.json"
        )
        defectDirectory = root.appendingPathComponent("live/defects", isDirectory: true)
        archiveURL = root.appendingPathComponent("preservation.negaflowarchive", isDirectory: true)
        originalURL = root.appendingPathComponent("sources/original scan.tiff")
        infraredURL = root.appendingPathComponent("sources/infrared.tiff")
        originalFrameID = UUID()
        virtualFrameID = UUID()

        try FileManager.default.createDirectory(
            at: originalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("unaltered original bytes".utf8).write(to: originalURL)
        try Data("infrared channel bytes".utf8).write(to: infraredURL)

        let original = ScanFrame(
            scanIndex: 1,
            rawScanURL: originalURL,
            filmType: .colorNegative,
            infraredScanURL: infraredURL,
            id: originalFrameID
        )
        let virtual = ScanFrame(
            scanIndex: 1,
            rawScanURL: originalURL,
            filmType: .colorNegative,
            sourceFrameID: originalFrameID,
            virtualCopyNumber: 1,
            id: virtualFrameID
        )
        var firstRecord = LibraryFrameRecord(frame: original)
        firstRecord.hasDefectEdits = true
        let catalog = LibraryCatalog(frames: [firstRecord, LibraryFrameRecord(frame: virtual)])
        try FileManager.default.createDirectory(
            at: catalogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if usesSQLiteCatalog {
            XCTAssertTrue(LibraryCatalogFile.writeCatalogSync(catalog, to: catalogURL))
        } else {
            try XCTUnwrap(LibraryCatalogFile.encode(catalog)).write(to: catalogURL)
        }
        if includeDefectRecipe {
            try DefectSidecarFile.write([], for: originalFrameID, in: defectDirectory)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
