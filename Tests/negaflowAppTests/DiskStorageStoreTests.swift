import XCTest
@testable import negaflowApp

@MainActor
final class DiskStorageStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "negaflow.disk-storage.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    func testDefaultScanOriginalsUseSharedRootWithOtherStorageFolders() {
        let store = DiskStorageStore(defaults: defaults)
        let root = store.rootURL
        XCTAssertEqual(store.locationMode, .iCloud)
        XCTAssertEqual(root.lastPathComponent, "negaflow")
        XCTAssertEqual(store.thumbnailsURL, root.appendingPathComponent("Thumbnails", isDirectory: true))
        XCTAssertEqual(store.exportURL, root.appendingPathComponent("Export", isDirectory: true))
        XCTAssertEqual(store.quickExportURL, root.appendingPathComponent("Quick Export", isDirectory: true))
        XCTAssertEqual(
            store.importedSourcesURL,
            root.appendingPathComponent("Imported Originals", isDirectory: true)
        )
        XCTAssertEqual(store.scansURL, root.appendingPathComponent("Scans", isDirectory: true))
        XCTAssertEqual(store.cleanedRawURL, root.appendingPathComponent("Cleaned Raw", isDirectory: true))
        XCTAssertEqual(store.scanPreviewsURL, root.appendingPathComponent("Scan Previews", isDirectory: true))
    }

    func testCustomRootMovesDerivedFoldersAndPersists() {
        let store = DiskStorageStore(defaults: defaults)
        store.locationMode = .custom
        store.rootPath = "/tmp/negaflow-root"

        XCTAssertEqual(store.thumbnailsURL.path, "/tmp/negaflow-root/Thumbnails")

        let reloaded = DiskStorageStore(defaults: defaults)
        XCTAssertEqual(reloaded.locationMode, .custom)
        XCTAssertEqual(reloaded.rootURL.path, "/tmp/negaflow-root")
    }

    func testExplicitPathsOverrideRootDerivation() {
        let store = DiskStorageStore(defaults: defaults)
        store.locationMode = .custom
        store.rootPath = "/tmp/negaflow-root"
        store.thumbnailsPath = "/tmp/custom-thumbs"
        store.exportPath = "/tmp/custom-export"
        store.quickExportPath = "/tmp/custom-quick"
        store.scansPath = "/tmp/custom-scans"
        store.importedSourcesPath = "/tmp/custom-imports"
        store.cleanedRawPath = "/tmp/custom-cleaned"
        store.scanPreviewsPath = "/tmp/custom-previews"

        XCTAssertEqual(store.thumbnailsURL.path, "/tmp/custom-thumbs")
        XCTAssertEqual(store.exportURL.path, "/tmp/custom-export")
        XCTAssertEqual(store.quickExportURL.path, "/tmp/custom-quick")
        XCTAssertEqual(store.scansURL.path, "/tmp/custom-scans")
        XCTAssertEqual(store.importedSourcesURL.path, "/tmp/custom-imports")
        XCTAssertEqual(store.cleanedRawURL.path, "/tmp/custom-cleaned")
        XCTAssertEqual(store.scanPreviewsURL.path, "/tmp/custom-previews")

        let reloaded = DiskStorageStore(defaults: defaults)
        XCTAssertEqual(reloaded.scansURL.path, "/tmp/custom-scans")

        store.resetToDefaults()
        XCTAssertEqual(store.thumbnailsURL, store.rootURL.appendingPathComponent("Thumbnails", isDirectory: true))
        XCTAssertEqual(
            store.scansURL,
            store.rootURL.appendingPathComponent("Scans", isDirectory: true)
        )
        XCTAssertEqual(
            store.importedSourcesURL,
            store.rootURL.appendingPathComponent("Imported Originals", isDirectory: true)
        )
        XCTAssertEqual(store.scanPreviewsURL, DiskStorageStore.defaultScanPreviewsURL())
    }

    func testDesktopModePlacesEveryManagedFolderUnderDesktopNegaflow() {
        let store = DiskStorageStore(defaults: defaults)
        store.locationMode = .desktop

        let root = DiskStorageStore.desktopRootURL()
        XCTAssertEqual(store.rootURL, root)
        XCTAssertEqual(store.thumbnailsURL, root.appendingPathComponent("Thumbnails", isDirectory: true))
        XCTAssertEqual(store.exportURL, root.appendingPathComponent("Export", isDirectory: true))
        XCTAssertEqual(store.quickExportURL, root.appendingPathComponent("Quick Export", isDirectory: true))
        XCTAssertEqual(store.scansURL, root.appendingPathComponent("Scans", isDirectory: true))
        XCTAssertEqual(store.importedSourcesURL, root.appendingPathComponent("Imported Originals", isDirectory: true))
        XCTAssertEqual(store.cleanedRawURL, root.appendingPathComponent("Cleaned Raw", isDirectory: true))
        XCTAssertEqual(store.scanPreviewsURL, root.appendingPathComponent("Scan Previews", isDirectory: true))
    }

    func testSpecificFolderCreatesNegaflowAndManagedSubfolders() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-specific-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = DiskStorageStore(defaults: defaults)

        store.selectSpecificFolder(parent)

        let root = parent.appendingPathComponent("negaflow", isDirectory: true)
        XCTAssertEqual(store.locationMode, .specificFolder)
        XCTAssertEqual(store.rootURL, root)
        for url in [
            root, store.thumbnailsURL, store.exportURL, store.quickExportURL,
            store.scansURL, store.importedSourcesURL, store.cleanedRawURL, store.scanPreviewsURL,
        ] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.path)
        }
    }

    func testManagedModeIgnoresCustomPathsAndSwitchingBackRestoresThem() {
        let store = DiskStorageStore(defaults: defaults)
        store.locationMode = .custom
        store.rootPath = "/tmp/custom-root"
        store.thumbnailsPath = "/tmp/custom-thumbnails"
        store.scansPath = "/tmp/custom-scans"
        store.cleanedRawPath = "/tmp/custom-cleaned"

        store.locationMode = .iCloud
        XCTAssertEqual(store.thumbnailsURL, store.rootURL.appendingPathComponent("Thumbnails", isDirectory: true))
        XCTAssertEqual(store.scansURL, store.rootURL.appendingPathComponent("Scans", isDirectory: true))
        XCTAssertEqual(store.cleanedRawURL, store.rootURL.appendingPathComponent("Cleaned Raw", isDirectory: true))

        store.locationMode = .custom
        XCTAssertEqual(store.rootURL.path, "/tmp/custom-root")
        XCTAssertEqual(store.thumbnailsURL.path, "/tmp/custom-thumbnails")
        XCTAssertEqual(store.scansURL.path, "/tmp/custom-scans")
        XCTAssertEqual(store.cleanedRawURL.path, "/tmp/custom-cleaned")
    }

    func testLegacyExplicitPathStartsInCustomMode() {
        defaults.set("/tmp/legacy-scans", forKey: "disk.scansFolder")

        let store = DiskStorageStore(defaults: defaults)

        XCTAssertEqual(store.locationMode, .custom)
        XCTAssertEqual(store.scansURL.path, "/tmp/legacy-scans")
    }

    func testLocationModeAndSpecificFolderPersist() {
        let store = DiskStorageStore(defaults: defaults)
        store.specificFolderPath = "/tmp/negaflow-parent"
        store.locationMode = .specificFolder

        let reloaded = DiskStorageStore(defaults: defaults)
        XCTAssertEqual(reloaded.locationMode, .specificFolder)
        XCTAssertEqual(reloaded.specificFolderPath, "/tmp/negaflow-parent")
        XCTAssertEqual(reloaded.rootURL.path, "/tmp/negaflow-parent/negaflow")
    }

    func testAssigningExplicitPathSelectsCustomMode() {
        let store = DiskStorageStore(defaults: defaults)
        XCTAssertEqual(store.locationMode, .iCloud)

        store.exportPath = "/tmp/negaflow-explicit-export"

        XCTAssertEqual(store.locationMode, .custom)
        XCTAssertEqual(store.exportURL.path, "/tmp/negaflow-explicit-export")
    }

    func testLegacyQuickExportFolderKeyIsMigrated() {
        defaults.set("/tmp/legacy-quick", forKey: "export.quick.folder")
        let store = DiskStorageStore(defaults: defaults)
        XCTAssertEqual(store.quickExportURL.path, "/tmp/legacy-quick")
    }

    func testRecentCreatedScanFolderPersistsAndResets() {
        let store = DiskStorageStore(defaults: defaults)
        store.recentCreatedScanFolderPath = "/tmp/negaflow-recent-scan"

        XCTAssertEqual(
            DiskStorageStore(defaults: defaults).recentCreatedScanFolderURL?.path,
            "/tmp/negaflow-recent-scan"
        )

        store.resetToDefaults()
        XCTAssertNil(store.recentCreatedScanFolderURL)
    }

    func testCleanedRawPathHistoryRetainsPreviousCacheRootsForCleanup() {
        let store = DiskStorageStore(defaults: defaults)
        store.cleanedRawPath = "/tmp/negaflow-cleaned-a"
        store.cleanedRawPath = "/tmp/negaflow-cleaned-b"
        store.resetToDefaults()

        let knownPaths = Set(store.cleanedRawKnownDirectories.map(\.path))
        XCTAssertTrue(knownPaths.contains("/tmp/negaflow-cleaned-a"))
        XCTAssertTrue(knownPaths.contains("/tmp/negaflow-cleaned-b"))
        XCTAssertTrue(knownPaths.contains(store.cleanedRawURL.path))
    }

    func testDirectorySizeSumsFiles() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-disk-size-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("nested", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(count: 1024).write(to: folder.appendingPathComponent("a.bin"))
        try Data(count: 2048).write(to: folder.appendingPathComponent("nested/b.bin"))

        XCTAssertGreaterThanOrEqual(DiskStorageStore.directorySize(at: folder), 3072)
        XCTAssertEqual(DiskStorageStore.directorySize(at: folder.appendingPathComponent("missing")), 0)
    }

    func testScanStorageCloudClassificationUsesKnownMacOSProviderRoots() {
        XCTAssertTrue(ScanStorageLocationInspector.isCloudManagedPath(URL(
            fileURLWithPath: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/Scans"
        )))
        XCTAssertTrue(ScanStorageLocationInspector.isCloudManagedPath(URL(
            fileURLWithPath: "/Users/test/Library/CloudStorage/Dropbox/Scans"
        )))
        XCTAssertFalse(ScanStorageLocationInspector.isCloudManagedPath(URL(
            fileURLWithPath: "/Users/test/Pictures/negaflow/Scans"
        )))
    }

    func testScanStorageInspectorReportsLocalVolumeCapacityForNewChild() {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing/negaflow/Scans", isDirectory: true)
        let status = ScanStorageLocationInspector.inspect(target)

        XCTAssertEqual(status.kind, .local)
        XCTAssertGreaterThan(status.availableCapacityBytes ?? 0, 0)
    }
}
