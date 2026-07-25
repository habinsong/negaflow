import XCTest
@testable import negaflowApp

@MainActor
final class LibraryBackupDestinationTests: XCTestCase {
    func testDestinationStatesDistinguishVolumeConnectionWriteAccessAndCapacity() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let source = volume(id: "source", available: 1_000_000_000)
        let ready = volume(id: "external", available: 1_000_000_000)
        let catalog = fixture.support.appendingPathComponent("library.json")

        XCTAssertEqual(
            LibraryBackupDestinationValidator.evaluate(
                catalogURL: catalog,
                destinationURL: fixture.external,
                requiredBytes: 100,
                inspectVolume: { $0.path.contains("external") ? ready : source }
            ),
            .ready(ready)
        )
        XCTAssertEqual(
            LibraryBackupDestinationValidator.evaluate(
                catalogURL: catalog,
                destinationURL: fixture.external,
                requiredBytes: 100,
                inspectVolume: { _ in source }
            ),
            .sameVolume(source)
        )
        let readOnly = LibraryBackupVolumeInfo(
            identifier: "external",
            name: "External",
            availableBytes: 1_000_000_000,
            totalBytes: 2_000_000_000,
            isWritable: false
        )
        XCTAssertEqual(
            LibraryBackupDestinationValidator.evaluate(
                catalogURL: catalog,
                destinationURL: fixture.external,
                requiredBytes: 100,
                inspectVolume: { $0.path.contains("external") ? readOnly : source }
            ),
            .readOnly(readOnly)
        )
        let small = volume(id: "external", available: 50)
        XCTAssertEqual(
            LibraryBackupDestinationValidator.evaluate(
                catalogURL: catalog,
                destinationURL: fixture.external,
                requiredBytes: 100,
                inspectVolume: { $0.path.contains("external") ? small : source }
            ),
            .insufficientCapacity(info: small, requiredBytes: 100)
        )
        try FileManager.default.removeItem(at: fixture.external)
        if case .disconnected = LibraryBackupDestinationValidator.evaluate(
            catalogURL: catalog,
            destinationURL: fixture.external,
            requiredBytes: 0,
            inspectVolume: { _ in ready }
        ) {} else {
            XCTFail("missing destination must be disconnected")
        }
    }

    func testStorePersistsBookmarkPathAndLastSuccess() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let defaults = try makeDefaults()
        let inspector = inspector(externalPath: fixture.external.path)
        let first = LibraryBackupDestinationStore(defaults: defaults, inspectVolume: inspector)
        first.configure(fixture.external)
        XCTAssertNotNil(first.refresh(catalogURL: fixture.support.appendingPathComponent("library.json")).readyInfo)
        let success = Date(timeIntervalSince1970: 1234)
        first.markSuccess(at: success)

        let restored = LibraryBackupDestinationStore(defaults: defaults, inspectVolume: inspector)
        XCTAssertEqual(restored.configuredPath, fixture.external.path)
        XCTAssertEqual(restored.lastSuccessAt, success)
        XCTAssertNotNil(restored.refresh(catalogURL: fixture.support.appendingPathComponent("library.json")).readyInfo)
    }

    func testConfiguredExternalBackupPublishesOnlyExternallyAndRecordsSuccess() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let defaults = try makeDefaults()
        let destinationStore = LibraryBackupDestinationStore(
            defaults: defaults,
            inspectVolume: inspector(externalPath: fixture.external.path)
        )
        destinationStore.configure(fixture.external)
        let model = AppModel(
            backupDestinationStore: destinationStore,
            libraryCatalogURL: fixture.support.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: fixture.support.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: fixture.local
        )
        model.libraryPersistenceEnabled = true

        let succeeded = await model.createLibraryBackupNow()
        XCTAssertTrue(succeeded)
        XCTAssertNotNil(LibraryBackupStore.latestValidSnapshot(in: fixture.external))
        XCTAssertNil(LibraryBackupStore.latestValidSnapshot(in: fixture.local))
        XCTAssertNotNil(destinationStore.lastSuccessAt)
    }

    func testDisconnectedConfiguredDestinationFailsWithoutLocalFallback() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let destinationStore = LibraryBackupDestinationStore(
            defaults: try makeDefaults(),
            inspectVolume: inspector(externalPath: fixture.external.path)
        )
        destinationStore.configure(fixture.external)
        try FileManager.default.removeItem(at: fixture.external)
        let model = AppModel(
            backupDestinationStore: destinationStore,
            libraryCatalogURL: fixture.support.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: fixture.support.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: fixture.local
        )
        model.libraryPersistenceEnabled = true

        let succeeded = await model.createLibraryBackupNow()
        XCTAssertFalse(succeeded)
        XCTAssertNil(LibraryBackupStore.latestValidSnapshot(in: fixture.local))
        XCTAssertNil(destinationStore.lastSuccessAt)
    }

    private func volume(id: String, available: Int64) -> LibraryBackupVolumeInfo {
        LibraryBackupVolumeInfo(
            identifier: id,
            name: id.capitalized,
            availableBytes: available,
            totalBytes: 2_000_000_000,
            isWritable: true
        )
    }

    private func inspector(externalPath: String) -> LibraryBackupDestinationStore.VolumeInspector {
        { [self] url in
            url.path.hasPrefix(externalPath)
                ? volume(id: "external", available: 1_000_000_000)
                : volume(id: "source", available: 1_000_000_000)
        }
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "LibraryBackupDestinationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeFixture() throws -> (
        support: URL,
        external: URL,
        local: URL,
        cleanup: () -> Void
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-backup-destination-\(UUID().uuidString)", isDirectory: true
        )
        let support = root.appendingPathComponent("support", isDirectory: true)
        let external = root.appendingPathComponent("external", isDirectory: true)
        let local = root.appendingPathComponent("local", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        return (support, external, local, { try? FileManager.default.removeItem(at: root) })
    }
}
