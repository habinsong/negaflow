import Chromabase
import XCTest
@testable import negaflowApp

final class PrintPackageArtifactLayoutTests: XCTestCase {
    func testLayoutUsesOneNumberedFamilyAndRejectsAnyMemberCollision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-print-layout-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let layout = try XCTUnwrap(PrintPackageArtifactLayout(
            folder: root,
            stem: "scan",
            pageCount: 3,
            format: .jpeg
        ))

        XCTAssertEqual(layout.outputURLs.map(\.lastPathComponent), [
            "scan-page-001.jpg",
            "scan-page-002.jpg",
            "scan-page-003.jpg",
        ])
        XCTAssertTrue(layout.isAvailable(protectedSources: [], reservedPaths: []))
        try Data("occupied".utf8).write(to: layout.outputURLs[1])
        XCTAssertFalse(layout.isAvailable(protectedSources: [], reservedPaths: []))
    }

    func testLayoutRejectsProtectedSourceAndReservedMember() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-print-layout-safety-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let layout = try XCTUnwrap(PrintPackageArtifactLayout(
            folder: root,
            stem: "source",
            pageCount: 1,
            format: .jpeg
        ))

        XCTAssertFalse(layout.isAvailable(
            protectedSources: [layout.outputURLs[0]],
            reservedPaths: []
        ))
        XCTAssertFalse(layout.isAvailable(
            protectedSources: [],
            reservedPaths: layout.standardizedPaths
        ))
    }
}
