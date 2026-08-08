import Foundation
import ScannerKit
import XCTest
@testable import negaflowApp

@MainActor
final class SupportBundleTests: XCTestCase {
    func testModelBundleOmitsPathsNamesMetadataAndArchivesRedactedJSON() async throws {
        let secret = "Alice Family Roll 2026"
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(secret, isDirectory: true)
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let defaultsName = "negaflow-support-bundle-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let diskStorage = DiskStorageStore(defaults: defaults)
        diskStorage.scansPath = root.appendingPathComponent("Private Scans").path
        let model = AppModel(
            diskStorageStore: diskStorage,
            scannerPluginTrustStore: nil,
            libraryCatalogURL: support.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: support.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: support.appendingPathComponent("Backups")
        )
        let pluginID = "alice-private-plugin"
        model.installedScannerPlugins = [InstalledScannerPlugin(
            manifest: ScannerPluginManifest(
                schemaVersion: 1,
                protocolVersion: 2,
                id: pluginID,
                name: secret,
                executable: "bin/private-scanner",
                pluginVersion: "1.2.3"
            ),
            manifestURL: root.appendingPathComponent("manifest.json"),
            executableURL: root.appendingPathComponent("private-scanner"),
            trustIdentity: ScannerPluginTrustIdentity(
                pluginID: pluginID,
                pluginVersion: "1.2.3",
                manifestSHA256: String(repeating: "a", count: 64),
                executableSHA256: String(repeating: "b", count: 64)
            )
        )]
        AppDiagnostics.clearForTesting()
        let trace = AppDiagnostics.start(.catalogSave, category: .catalog)
        trace.fail(NSError(
            domain: root.path,
            code: 13,
            userInfo: [NSLocalizedDescriptionKey: secret]
        ))

        let document = await model.makeSupportBundleDocument()
        let encoded = try SupportBundleArchiveWriter.encodedDocument(document)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.plugins.count, 1)
        XCTAssertEqual(document.plugins[0].approvalState, "storeUnavailable")
        XCTAssertFalse(document.plugins[0].pluginIDHash.isEmpty)
        // 앞선 테스트의 비동기 잔여 작업(현상 등)이 실패 이벤트를 뒤늦게 기록할 수 있어 전역
        // 개수는 단정하지 않는다 — 이 테스트가 기록한 catalog 실패의 존재와, 문서 전문의
        // redaction(아래 assertPrivateValuesAbsent — 잔여 이벤트 포함)만 계약이다.
        XCTAssertTrue(document.recentErrors.contains {
            $0.category == .catalog && $0.operation == .catalogSave
        })
        assertPrivateValuesAbsent(in: text, values: [root.path, secret, pluginID, "Private Scans"])

        let archive = root.appendingPathComponent("support.zip")
        try SupportBundleArchiveWriter.write(document, to: archive)
        XCTAssertGreaterThan(
            (try archive.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0,
            0
        )
        let extracted = root.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        try extract(archive, to: extracted)
        let archivedData = try Data(contentsOf: extracted
            .appendingPathComponent("negaflow-support", isDirectory: true)
            .appendingPathComponent("support.json"))
        let archivedText = try XCTUnwrap(String(data: archivedData, encoding: .utf8))
        assertPrivateValuesAbsent(
            in: archivedText,
            values: [root.path, secret, pluginID, "Private Scans"]
        )
    }

    func testCatalogSummaryAggregatesIssueCodesWithoutFrameIdentityOrPath() throws {
        let secretPath = "/Users/alice/Pictures/Private Wedding Roll.tiff"
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: secretPath),
            filmType: .colorNegative
        )
        let catalog = LibraryCatalog(frames: [LibraryFrameRecord(frame: frame)])
        let summary = SupportBundleSummaries.catalog(
            lifecycle: "ready",
            blockReason: nil,
            catalog: catalog,
            fallbackFrameCount: 0,
            fallbackRollCount: 0,
            defectDirectory: FileManager.default.temporaryDirectory
        )
        let data = try JSONEncoder().encode(summary)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(summary.issues.contains { $0.code == "offlineSource" })
        XCTAssertFalse(text.contains(secretPath))
        XCTAssertFalse(text.contains(frame.id.uuidString))
    }

    func testPrivacyHashUsesPerBundleSalt() {
        let first = SupportBundlePrivacyHasher(salt: Data("first".utf8))
        let second = SupportBundlePrivacyHasher(salt: Data("second".utf8))

        XCTAssertEqual(first.hash("same"), first.hash("same"))
        XCTAssertNotEqual(first.hash("same"), second.hash("same"))
        XCTAssertEqual(first.hash("same").count, 24)
    }

    private func assertPrivateValuesAbsent(in text: String, values: [String]) {
        for value in values {
            XCTAssertFalse(text.contains(value), "private value leaked: \(value)")
        }
    }

    private func extract(_ archive: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
