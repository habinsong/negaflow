import Foundation
import XCTest
@testable import Chromabase

final class ScannerProfileRegistryIntegrityTests: XCTestCase {
    private let targetID = "noritsu__color-nega__kodak-ultramax-400"
    private let siblingID = "noritsu__color-nega__kodak-portra-400"

    func testLoadNamedFailsClosedWhenManifestSiblingBecomesCorrupt() throws {
        let directory = try makeTemporaryProfileBundle()
        XCTAssertNotNil(
            ScannerProfileRegistry.load(named: targetID, profilesDirectoryURL: directory)
        )

        let siblingURL = profileURL(named: siblingID, in: directory)
        var siblingData = try Data(contentsOf: siblingURL)
        siblingData.append(0x20)
        try siblingData.write(to: siblingURL, options: .atomic)

        XCTAssertNil(
            ScannerProfileRegistry.load(named: targetID, profilesDirectoryURL: directory),
            "요청하지 않은 manifest sibling 하나라도 손상되면 named load도 fail-closed여야 합니다."
        )
    }

    func testLoadNamedDoesNotUseCachedProfileAfterItsFileBytesChange() throws {
        let directory = try makeTemporaryProfileBundle()
        XCTAssertNotNil(
            ScannerProfileRegistry.load(named: targetID, profilesDirectoryURL: directory)
        )

        let targetURL = profileURL(named: targetID, in: directory)
        var targetData = try Data(contentsOf: targetURL)
        targetData.append(0x20)
        try targetData.write(to: targetURL, options: .atomic)

        XCTAssertNil(
            ScannerProfileRegistry.load(named: targetID, profilesDirectoryURL: directory),
            "캐시 hit가 현재 파일 바이트의 manifest SHA 검증을 우회하면 안 됩니다."
        )
    }

    func testLoadNamedDoesNotUseCachedProfileAfterManifestHashChanges() throws {
        let directory = try makeTemporaryProfileBundle()
        XCTAssertNotNil(
            ScannerProfileRegistry.load(named: targetID, profilesDirectoryURL: directory)
        )

        let manifestURL = directory.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        var manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        var entries = try XCTUnwrap(manifest["profiles"] as? [[String: Any]])
        let targetIndex = try XCTUnwrap(entries.firstIndex { $0["id"] as? String == targetID })
        entries[targetIndex]["fileSHA256"] = "sha256:" + String(repeating: "0", count: 64)
        manifest["profiles"] = entries
        let changedManifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try changedManifestData.write(to: manifestURL, options: .atomic)

        XCTAssertNil(
            ScannerProfileRegistry.load(named: targetID, profilesDirectoryURL: directory),
            "캐시 hit는 새 manifest의 선언 hash와 현재 파일 SHA 불일치를 숨기면 안 됩니다."
        )
    }

    private func makeTemporaryProfileBundle() throws -> URL {
        let source = try XCTUnwrap(ScannerProfileRegistry.bundledProfilesDirectoryURL)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "negaflow-scanner-profile-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        let destination = root.appendingPathComponent("ScannerProfiles", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return destination
    }

    private func profileURL(named id: String, in directory: URL) -> URL {
        directory.appendingPathComponent(id).appendingPathExtension("json")
    }
}
