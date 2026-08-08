import Foundation
import XCTest
@testable import negaflowApp

final class LibraryDuplicateCandidateScannerTests: XCTestCase {
    func testReportsOnlyFullByteMatchesAndSkipsUnavailableInputs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-duplicates-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = root.appendingPathComponent("first.bin")
        let second = root.appendingPathComponent("second.bin")
        let sameSizeDifferent = root.appendingPathComponent("different.bin")
        try Data("exact-content".utf8).write(to: first)
        try Data("exact-content".utf8).write(to: second)
        try Data("other-content".utf8).write(to: sameSizeDifferent)
        let firstID = UUID()
        let secondID = UUID()

        let report = try await LibraryDuplicateCandidateScanner.scan([
            .init(frameID: firstID, sourceURL: first),
            .init(frameID: secondID, sourceURL: second),
            .init(frameID: UUID(), sourceURL: sameSizeDifferent),
            .init(frameID: UUID(), sourceURL: root.appendingPathComponent("missing.bin")),
        ])

        XCTAssertEqual(report.groups.count, 1)
        XCTAssertEqual(Set(report.groups[0].members.map(\.frameID)), [firstID, secondID])
        XCTAssertEqual(report.groups[0].sha256.count, 64)
        XCTAssertEqual(report.inspectedFileCount, 3)
        XCTAssertEqual(report.skippedUnavailableCount, 1)
    }

    func testDuplicateFrameInputsAreInspectedOnce() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-duplicate-input-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("same".utf8).write(to: file)
        let id = UUID()

        let report = try await LibraryDuplicateCandidateScanner.scan([
            .init(frameID: id, sourceURL: file),
            .init(frameID: id, sourceURL: file),
        ])

        XCTAssertEqual(report.inspectedFileCount, 1)
        XCTAssertTrue(report.groups.isEmpty)
    }
}
