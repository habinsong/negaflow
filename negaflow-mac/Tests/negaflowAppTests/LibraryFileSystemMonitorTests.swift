import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import negaflowApp

final class LibraryFileSystemMonitorTests: XCTestCase {
    func testReportsChangedFolderWithoutPolling() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-folder-monitor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let changed = expectation(description: "folder change")
        let monitor = LibraryFileSystemMonitor()
        monitor.update(folderURLs: [directory]) { changedURL in
            if changedURL.standardizedFileURL == directory.standardizedFileURL {
                changed.fulfill()
            }
        }
        try await Task.sleep(for: .milliseconds(100))

        try Data("new file".utf8).write(
            to: directory.appendingPathComponent("new-file.txt")
        )

        await fulfillment(of: [changed], timeout: 2)
        monitor.cancel()
    }

    /// 감시 폴더에 파일이 새로 생겨도 자동으로 가져오지 않는다 — 한 장만 가져온 폴더의
    /// 나머지 사진이 통째로 라이브러리에 밀려 들어오던 경로다.
    @MainActor
    func testAppModelDoesNotAutomaticallyImportNewImageFromChangedFolder() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-model-folder-monitor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel()
        model.libraryFolders = [LibraryFolder(url: directory)]
        try await Task.sleep(for: .milliseconds(100))
        let imageURL = directory.appendingPathComponent("new.png")
        try Self.writePNG(to: imageURL)

        try await Task.sleep(for: .milliseconds(600))

        XCTAssertTrue(
            model.frames.isEmpty,
            "pending=\(model.pendingLibraryFileSystemRefreshPaths) status=\(model.statusMessage)"
        )
        model.libraryFileSystemMonitor.cancel()
    }

    private static func writePNG(to url: URL) throws {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
