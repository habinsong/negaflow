import XCTest
@testable import negaflowApp

final class LibraryProcessLockTests: XCTestCase {
    func testSecondWriterIsRejectedUntilFirstLockReleases() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalogURL = root.appendingPathComponent("library.json")
        var first: LibraryProcessLock? = try LibraryProcessLock.acquire(for: catalogURL)
        XCTAssertEqual(first?.lockURL, catalogURL.appendingPathExtension("lock"))

        XCTAssertThrowsError(try LibraryProcessLock.acquire(for: catalogURL)) { error in
            XCTAssertEqual(error as? LibraryProcessLockError, .alreadyLocked)
        }

        first = nil
        let reacquired = try LibraryProcessLock.acquire(for: catalogURL)
        XCTAssertEqual(
            reacquired.lockURL,
            catalogURL.appendingPathExtension("lock")
        )
        withExtendedLifetime(reacquired) {}
    }

    func testLockPathSymlinkIsRejected() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalogURL = root.appendingPathComponent("library.json")
        let lockURL = catalogURL.appendingPathExtension("lock")
        let target = root.appendingPathComponent("target")
        try Data().write(to: target)
        try FileManager.default.createSymbolicLink(
            at: lockURL,
            withDestinationURL: target
        )

        XCTAssertThrowsError(try LibraryProcessLock.acquire(for: catalogURL)) { error in
            guard case .unavailable = error as? LibraryProcessLockError else {
                return XCTFail("symlink lock path must be unavailable")
            }
        }
    }

    @MainActor
    func testSecondAppModelFailsClosedBeforeCatalogRestore() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalogURL = root.appendingPathComponent("library.json")
        let defectURL = root.appendingPathComponent("defects")
        let backupURL = root.appendingPathComponent("backups")
        let first = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: defectURL,
            libraryBackupDirectoryURL: backupURL
        )
        await first.restoreLibraryOnLaunch()
        XCTAssertEqual(first.libraryLifecycleState, .ready)

        let second = AppModel(
            libraryCatalogURL: catalogURL,
            libraryDefectDirectoryURL: defectURL,
            libraryBackupDirectoryURL: backupURL
        )
        await second.restoreLibraryOnLaunch()

        XCTAssertEqual(second.libraryLifecycleState, .blocked)
        XCTAssertEqual(second.libraryCatalogBlockReason, .lockedByAnotherProcess)
        XCTAssertFalse(second.libraryPersistenceEnabled)
        XCTAssertNil(second.libraryProcessLock)
        XCTAssertEqual(
            second.statusMessage,
            second.text(AppLocalizedPhrase.libraryCatalogLockedStatus)
        )
        withExtendedLifetime(first) {}
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-library-lock-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
