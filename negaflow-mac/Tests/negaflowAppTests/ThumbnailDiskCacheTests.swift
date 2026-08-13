import XCTest
import CoreGraphics
import Chromabase
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

    func testRawAndDevelopedDestinationsForSameFrameAreBothPersisted() async throws {
        let cache = ThumbnailDiskCache()
        let frameID = UUID()
        let rawURL = temporaryDirectory.appendingPathComponent("raw.jpg")
        let developedURL = temporaryDirectory.appendingPathComponent("developed.jpg")

        cache.store(
            try XCTUnwrap(Self.makeImage(red: 0.8, green: 0.1, blue: 0.1)),
            for: frameID,
            at: rawURL
        )
        cache.store(
            try XCTUnwrap(Self.makeImage(red: 0.1, green: 0.8, blue: 0.1)),
            for: frameID,
            at: developedURL
        )
        await cache.waitUntilIdle()

        XCTAssertNotNil(ThumbnailDiskCache.load(at: rawURL))
        XCTAssertNotNil(ThumbnailDiskCache.load(at: developedURL))
    }

    @MainActor
    func testNeverDevelopedNegativeRestoresDiskCacheAsRawPreview() async throws {
        let suiteName = "negaflow-thumbnail-restore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let diskStorage = DiskStorageStore(defaults: defaults)
        diskStorage.thumbnailsPath = temporaryDirectory.path
        let model = AppModel(
            diskStorageStore: diskStorage,
            libraryCatalogURL: temporaryDirectory.appendingPathComponent("library.sqlite"),
            libraryDefectDirectoryURL: temporaryDirectory.appendingPathComponent(
                "defects",
                isDirectory: true
            ),
            libraryBackupDirectoryURL: temporaryDirectory.appendingPathComponent(
                "backups",
                isDirectory: true
            )
        )
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: temporaryDirectory.appendingPathComponent("missing-source.tiff"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        model.frames = [frame]

        model.thumbnailDiskCache.store(
            try XCTUnwrap(Self.makeImage()),
            for: frame.id,
            at: model.rawThumbnailFileURL(for: frame)
        )
        await model.thumbnailDiskCache.waitUntilIdle()
        model.loadThumbnailsFromDisk(for: [frame])

        let deadline = Date().addingTimeInterval(2)
        while frame.rawPreviewImage == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertNotNil(frame.rawPreviewImage)
        XCTAssertNil(frame.thumbnailImage)
        XCTAssertFalse(frame.hasDevelopedOnce)
    }

    @MainActor
    func testDevelopedNegativeKeepsLegacyThumbnailVisibleDuringCacheMigration() async throws {
        let suiteName = "negaflow-thumbnail-legacy-migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let diskStorage = DiskStorageStore(defaults: defaults)
        diskStorage.thumbnailsPath = temporaryDirectory.path
        let model = AppModel(
            diskStorageStore: diskStorage,
            libraryCatalogURL: temporaryDirectory.appendingPathComponent("library.sqlite"),
            libraryDefectDirectoryURL: temporaryDirectory.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: temporaryDirectory.appendingPathComponent("backups")
        )
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: temporaryDirectory.appendingPathComponent("offline-source.tiff"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        frame.hasDevelopedOnce = true
        model.frames = [frame]
        let legacyURL = model.legacyThumbnailFileURL(for: frame)
        model.thumbnailDiskCache.store(
            try XCTUnwrap(Self.makeImage()),
            for: frame.id,
            at: legacyURL
        )
        await model.thumbnailDiskCache.waitUntilIdle()

        model.loadThumbnailsFromDisk(for: [frame])

        let deadline = Date().addingTimeInterval(2)
        while frame.thumbnailImage == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertNotNil(frame.thumbnailImage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertNil(ThumbnailDiskCache.load(at: model.thumbnailFileURL(for: frame)))
        XCTAssertTrue(frame.hasDevelopedOnce)
    }

    @MainActor
    func testAllFilmProcessesRestoreRawAndDevelopedCachesSeparately() async throws {
        let suiteName = "negaflow-thumbnail-separated-restore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let diskStorage = DiskStorageStore(defaults: defaults)
        diskStorage.thumbnailsPath = temporaryDirectory.path
        let model = AppModel(
            diskStorageStore: diskStorage,
            libraryCatalogURL: temporaryDirectory.appendingPathComponent("library.sqlite"),
            libraryDefectDirectoryURL: temporaryDirectory.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: temporaryDirectory.appendingPathComponent("backups")
        )
        let filmTypes: [FilmType] = [.colorNegative, .colorPositive, .bwNegative, .bwPositive]
        let frames = filmTypes.enumerated().map { offset, filmType in
            let frame = ScanFrame(
                scanIndex: offset + 1,
                rawScanURL: temporaryDirectory.appendingPathComponent("missing-source-\(offset).tiff"),
                filmType: filmType,
                sourceKind: .importedFile
            )
            frame.hasDevelopedOnce = true
            return frame
        }
        model.frames = frames
        let rawImage = try XCTUnwrap(Self.makeImage(red: 0.8, green: 0.1, blue: 0.1))
        let developedImage = try XCTUnwrap(Self.makeImage(red: 0.1, green: 0.8, blue: 0.1))
        for frame in frames {
            model.thumbnailDiskCache.store(
                rawImage,
                for: frame.id,
                at: model.rawThumbnailFileURL(for: frame)
            )
            model.thumbnailDiskCache.store(
                developedImage,
                for: frame.id,
                at: model.thumbnailFileURL(for: frame)
            )
        }
        await model.thumbnailDiskCache.waitUntilIdle()
        model.loadThumbnailsFromDisk(for: frames)

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let hasLoadedAll = frames.allSatisfy { frame in
                frame.rawPreviewImage != nil && frame.thumbnailImage != nil
            }
            if hasLoadedAll { break }
            try await Task.sleep(for: .milliseconds(25))
        }

        for (frame, filmType) in zip(frames, filmTypes) {
            XCTAssertEqual(frame.filmType, filmType)
            let raw = try XCTUnwrap(frame.rawPreviewImage?.tiffRepresentation)
            let developed = try XCTUnwrap(frame.thumbnailImage?.tiffRepresentation)
            XCTAssertNotEqual(raw, developed)
        }
    }

    private static func makeImage(
        red: CGFloat = 0.3,
        green: CGFloat = 0.5,
        blue: CGFloat = 0.7
    ) -> CGImage? {
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
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
