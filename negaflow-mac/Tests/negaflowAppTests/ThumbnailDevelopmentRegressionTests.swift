import XCTest
import AppKit
import CoreImage
import Chromabase
import ScannerKit
@testable import negaflowApp

@MainActor
final class ThumbnailDevelopmentRegressionTests: XCTestCase {
    func testPreservedThumbnailMatchesCurrentProcessAndTargetPixels() async throws {
        let (model, frame, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var outputs: [Data] = []
        for (filmType, digital, target) in [
            (FilmType.colorPositive, true, DevelopTarget.main),
            (.bwPositive, true, .hr), (.colorNegative, false, .main), (.colorNegative, false, .hr)
        ] {
            frame.filmType = filmType
            frame.updateParams { $0.filmType = filmType; $0.isDigitalSource = digital ? true : nil; $0.developTarget = target }
            await model.developFrame(frame, preserveThumbnail: true, skipInteractivePreview: true)
            XCTAssertTrue(frame.developedIsSettled)
            XCTAssertEqual(frame.thumbnailRecipeID, frame.currentThumbnailRecipeID())
            let snapshot = model.makeSnapshot(for: frame, baseKey: FilmBaseCacheKey(
                filmType: filmType, mode: frame.params.baseEstimationMode, manualBaseRGB: nil, filmStockDminID: nil),
                needsRawPreview: false, needsNeutralPreview: false, needsDebugPreviews: false,
                needsThumbnail: true, proxyMaxDimension: DevelopFrameRenderer.fullMaxDimension)
            let expected = try XCTUnwrap(DevelopFrameRenderer.render(snapshot).thumbnail)
            let actual = try XCTUnwrap(frame.thumbnailImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            XCTAssertEqual(pixels(actual), pixels(expected), "\(filmType), \(target)")
            outputs.append(pixels(actual))
        }
        XCTAssertNotEqual(outputs[0], outputs[1])
        XCTAssertNotEqual(outputs[2], outputs[3])
    }

    func testRestoredOldRecipeIsRebuiltAndLateRestoreCannotOverwriteAnEdit() async throws {
        let (model, frame, directory) = try fixture()
        model.libraryPersistenceEnabled = true
        defer { model.libraryPersistenceEnabled = false; try? FileManager.default.removeItem(at: directory) }
        await model.developFrame(frame, skipInteractivePreview: true)
        await model.thumbnailDiskCache.waitUntilIdle()
        XCTAssertNotNil(ThumbnailDiskCache.load(at: model.thumbnailFileURL(for: frame),
            matchingRecipe: frame.currentThumbnailRecipeID()))
        frame.thumbnailImage = nil
        let pending = model.loadThumbnailsFromDisk(for: [frame])
        frame.updateParams { $0.exposure = 1 }
        await pending.value
        XCTAssertNil(frame.thumbnailImage, "previous recipe must not publish after an edit")
        frame.developedImage = nil
        frame.developedIsSettled = false
        await model.loadThumbnailsFromDisk(for: [frame]).value
        await model.thumbnailDiskCache.waitUntilIdle()
        XCTAssertTrue(frame.developedIsSettled)
        XCTAssertEqual(frame.thumbnailRecipeID, frame.currentThumbnailRecipeID())
        XCTAssertNotNil(ThumbnailDiskCache.load(at: model.thumbnailFileURL(for: frame),
            matchingRecipe: frame.currentThumbnailRecipeID()))
    }

    private func fixture() throws -> (AppModel, ScanFrame, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("thumbnail-pixels-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 48, height: 32, to: url)
        let storage = DiskStorageStore(defaults: try XCTUnwrap(UserDefaults(suiteName: "thumbnail-pixels-\(UUID())")))
        storage.thumbnailsPath = directory.appendingPathComponent("thumbs").path
        let model = AppModel(diskStorageStore: storage, libraryCatalogURL: directory.appendingPathComponent("catalog.sqlite"),
            libraryDefectDirectoryURL: directory.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: directory.appendingPathComponent("backups"))
        let frame = ScanFrame(scanIndex: 1, rawScanURL: url, filmType: .colorPositive, sourceKind: .importedFile)
        model.frames = [frame]
        return (model, frame, directory)
    }

    private func pixels(_ image: CGImage) -> Data {
        var data = Data(count: image.width * image.height * 4)
        data.withUnsafeMutableBytes {
            ChromabaseEngine.sharedLinearRenderContext.render(CIImage(cgImage: image), toBitmap: $0.baseAddress!,
                rowBytes: image.width * 4, bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        return data
    }
}
