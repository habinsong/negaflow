import XCTest
import CoreGraphics
@testable import negaflowApp

final class ThumbnailDiskCacheTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-thumbnail-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testRemoveCancelsPendingWriteWithoutRecreatingFile() async throws {
        let cache = ThumbnailDiskCache()
        let frameID = UUID()
        let fileURL = temporaryDirectory.appendingPathComponent("frame.jpg")
        let image = try XCTUnwrap(Self.makeImage())

        cache.store(image, for: frameID, at: fileURL)
        cache.remove(for: frameID, at: fileURL)
        await cache.waitUntilIdle()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testClearCancelsPendingWritesAndRemovesCacheRoot() async throws {
        let cache = ThumbnailDiskCache()
        let image = try XCTUnwrap(Self.makeImage())

        for index in 0..<8 {
            cache.store(
                image,
                for: UUID(),
                at: temporaryDirectory.appendingPathComponent("\(index).jpg")
            )
        }
        await cache.clear(at: temporaryDirectory)
        await cache.waitUntilIdle()

        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.path))
    }

    private static func makeImage() -> CGImage? {
        let width = 2_048
        let height = 2_048
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
