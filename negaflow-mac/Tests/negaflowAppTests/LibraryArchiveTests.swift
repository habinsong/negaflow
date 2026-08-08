import Foundation
import XCTest
@testable import negaflowApp

@MainActor
final class LibraryArchiveTests: XCTestCase {
    func testArchiveActionsHaveEverySupportedTranslation() {
        for language in AppLanguage.allCases where language != .system {
            for key in [AppArchiveText.create, .save, .created, .failed] {
                XCTAssertFalse(AppLocalization.archiveText(key, language: language).isEmpty)
            }
        }
    }

    func testBagItArchivePreservesCatalogSourcesRecipeAndVirtualCopySharing() throws {
        let fixture = try LibraryArchiveTestFixture()
        defer { fixture.remove() }

        let report = try LibraryArchiveBuilder.create(
            catalogURL: fixture.catalogURL,
            defectDirectory: fixture.defectDirectory,
            destinationURL: fixture.archiveURL,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(report.frameCount, 2)
        XCTAssertEqual(report.payloadCount, 4)
        XCTAssertEqual(
            try Data(contentsOf: fixture.originalURL),
            try Data(contentsOf: fixture.archiveURL.appendingPathComponent(
                "data/original/original-000001.tiff"
            ))
        )
        let manifest = try LibraryArchiveBagIt.decodeArchiveManifest(
            Data(contentsOf: fixture.archiveURL.appendingPathComponent("negaflow-archive.json"))
        )
        XCTAssertEqual(Set(manifest.frames.map(\.originalPayloadID)), ["original-000001"])
        XCTAssertEqual(
            manifest.frames.first(where: { $0.frameID == fixture.originalFrameID })?
                .defectRecipePayloadID,
            "defect-\(fixture.originalFrameID.uuidString.lowercased())"
        )
        XCTAssertNoThrow(try LibraryArchiveValidator.validate(at: fixture.archiveURL))
    }

    func testBagItArchiveExportsSQLiteCatalogAsPortableJSON() throws {
        let fixture = try LibraryArchiveTestFixture(usesSQLiteCatalog: true)
        defer { fixture.remove() }

        _ = try LibraryArchiveBuilder.create(
            catalogURL: fixture.catalogURL,
            defectDirectory: fixture.defectDirectory,
            destinationURL: fixture.archiveURL
        )

        let archivedCatalogURL = fixture.archiveURL.appendingPathComponent(
            "data/catalog/library.json"
        )
        let archivedCatalog = try XCTUnwrap(
            LibraryCatalogFile.decode(Data(contentsOf: archivedCatalogURL))
        )
        XCTAssertEqual(
            Set(archivedCatalog.frames.map(\.id)),
            [fixture.originalFrameID, fixture.virtualFrameID]
        )
        XCTAssertNoThrow(try LibraryArchiveValidator.validate(at: fixture.archiveURL))
    }

    func testTamperedPayloadFailsValidation() throws {
        let fixture = try LibraryArchiveTestFixture()
        defer { fixture.remove() }
        _ = try LibraryArchiveBuilder.create(
            catalogURL: fixture.catalogURL,
            defectDirectory: fixture.defectDirectory,
            destinationURL: fixture.archiveURL
        )
        try Data("tampered".utf8).write(
            to: fixture.archiveURL.appendingPathComponent("data/original/original-000001.tiff")
        )

        XCTAssertThrowsError(try LibraryArchiveValidator.validate(at: fixture.archiveURL))
    }

    func testUnexpectedPayloadFailsValidation() throws {
        let fixture = try LibraryArchiveTestFixture()
        defer { fixture.remove() }
        _ = try LibraryArchiveBuilder.create(
            catalogURL: fixture.catalogURL,
            defectDirectory: fixture.defectDirectory,
            destinationURL: fixture.archiveURL
        )
        try Data("untracked".utf8).write(
            to: fixture.archiveURL.appendingPathComponent("data/untracked.bin")
        )

        XCTAssertThrowsError(try LibraryArchiveValidator.validate(at: fixture.archiveURL))
    }

    func testMissingSourceLeavesNoDestinationOrStagingDirectory() throws {
        let fixture = try LibraryArchiveTestFixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.originalURL)

        XCTAssertThrowsError(try LibraryArchiveBuilder.create(
            catalogURL: fixture.catalogURL,
            defectDirectory: fixture.defectDirectory,
            destinationURL: fixture.archiveURL
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.archiveURL.path))
        let leftovers = try FileManager.default.contentsOfDirectory(
            at: fixture.root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains("staging") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testMissingDefectRecipeLeavesNoDestination() throws {
        let fixture = try LibraryArchiveTestFixture(includeDefectRecipe: false)
        defer { fixture.remove() }

        XCTAssertThrowsError(try LibraryArchiveBuilder.create(
            catalogURL: fixture.catalogURL,
            defectDirectory: fixture.defectDirectory,
            destinationURL: fixture.archiveURL
        )) { error in
            XCTAssertEqual(
                error as? LibraryArchiveError,
                .missingDefectRecipe(fixture.originalFrameID)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.archiveURL.path))
    }

    func testExistingDestinationIsNeverOverwritten() throws {
        let fixture = try LibraryArchiveTestFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.archiveURL,
            withIntermediateDirectories: true
        )
        let sentinel = fixture.archiveURL.appendingPathComponent("sentinel")
        try Data("keep".utf8).write(to: sentinel)

        XCTAssertThrowsError(try LibraryArchiveBuilder.create(
            catalogURL: fixture.catalogURL,
            defectDirectory: fixture.defectDirectory,
            destinationURL: fixture.archiveURL
        )) { error in
            XCTAssertEqual(error as? LibraryArchiveError, .destinationExists)
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
    }
}
