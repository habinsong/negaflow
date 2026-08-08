import Chromabase
import CoreGraphics
import Foundation
import AppKit
import XCTest
@testable import negaflowApp

/// 인화 시트는 선택한 사진 전부를 순서대로 배치해야 한다. 이미지가 아직 메모리에 없는
/// 프레임 때문에 배치가 통째로 무너지면 다중 선택이 첫 장만 남은 것처럼 보인다.
@MainActor
final class PrintPackagePreviewTests: XCTestCase {
    func testPackagePreviewChoosesHighestResolutionPositiveImageInsteadOfThumbnailFirst() throws {
        let thumbnail = try makeImage(pixelWidth: 360)
        let developed = try makeImage(pixelWidth: 1_200)
        let packagePreview = try makeImage(pixelWidth: 1_600)
        let raw = try makeImage(pixelWidth: 2_400)

        XCTAssertIdentical(
            PrintPackagePreviewResolution.bestImage(
                developed: developed,
                packagePreview: packagePreview,
                thumbnail: thumbnail,
                raw: raw
            ),
            packagePreview
        )
        XCTAssertIdentical(
            PrintPackagePreviewResolution.bestImage(
                developed: developed,
                packagePreview: nil,
                thumbnail: thumbnail,
                raw: raw
            ),
            developed
        )
    }

    func testPackagePreviewUsesRawOnlyWhenNoPositivePreviewExists() throws {
        let raw = try makeImage(pixelWidth: 2_400)
        XCTAssertIdentical(
            PrintPackagePreviewResolution.bestImage(
                developed: nil,
                packagePreview: nil,
                thumbnail: nil,
                raw: raw
            ),
            raw
        )
    }

    func testPackagePreviewUpgradesOnlyWhenRasterIsSmallerThanDisplayedCell() throws {
        let thumbnail = try makeImage(pixelWidth: 360)
        let displayReady = try makeImage(pixelWidth: 1_024)
        let stretchedThumbnail = try makeImage(pixelWidth: 360, logicalWidth: 6_000)

        XCTAssertTrue(PrintPackagePreviewResolution.needsUpgrade(
            thumbnail,
            displayTargetPixels: 900
        ))
        XCTAssertTrue(PrintPackagePreviewResolution.needsUpgrade(
            stretchedThumbnail,
            displayTargetPixels: 900
        ))
        XCTAssertFalse(PrintPackagePreviewResolution.needsUpgrade(
            displayReady,
            displayTargetPixels: 900
        ))
        XCTAssertEqual(
            PrintPackagePreviewResolution.renderDimension(for: 900),
            1_024
        )
        XCTAssertEqual(
            PrintPackagePreviewResolution.renderDimension(for: 4_000),
            DevelopFrameRenderer.interactiveMaxDimension
        )
    }

    func testPackagePreviewCacheIsDiscardedWhenLeavingPrintWorkspace() throws {
        let model = AppModel()
        let frame = makeFrame(width: 6_000, height: 4_000)
        model.frames = [frame]
        model.activeWorkspaceModule = .print
        frame.printPackagePreviewImage = try makeImage(pixelWidth: 1_024)
        frame.printPackagePreviewDevelopRevision = frame.developRevision
        frame.printPackagePreviewCleanRawRevision = frame.cleanRawRevision
        frame.printPackagePreviewSourceLocationRevision = frame.sourceLocationRevision
        frame.printPackagePreviewTransform = frame.imageTransform
        frame.printPackagePreviewSoftProofRevision = model.softProofConfigurationRevision

        XCTAssertNotNil(model.printPackageDisplayImage(for: frame))
        model.activeWorkspaceModule = .develop

        XCTAssertNil(frame.printPackagePreviewImage)
        XCTAssertNil(frame.printPackagePreviewTask)
        XCTAssertEqual(frame.printPackagePreviewTargetDimension, 0)
    }

    func testCancellingPreviewTasksPreservesCompletedCacheForExportDisplay() throws {
        let model = AppModel()
        let frame = makeFrame(width: 6_000, height: 4_000)
        let preview = try makeImage(pixelWidth: 1_024)
        model.frames = [frame]
        frame.printPackagePreviewImage = preview
        frame.printPackagePreviewTask = Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
        }
        let generation = frame.printPackagePreviewGeneration

        model.cancelPrintPackagePreviewTasks()

        XCTAssertNil(frame.printPackagePreviewTask)
        XCTAssertIdentical(frame.printPackagePreviewImage, preview)
        XCTAssertEqual(frame.printPackagePreviewGeneration, generation + 1)
    }

    func testExportCountUsesPrintedPagesForAllFourLayoutsWithThirtyNineFrames() {
        let suiteName = "negaflow-print-output-count-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PrintWorkspaceSettingsStore(defaults: defaults)
        let model = AppModel(printWorkspaceSettingsStore: store)
        let frames = (0..<39).map { _ in
            let frame = makeFrame(width: 6_000, height: 4_000)
            frame.hasDevelopedOnce = true
            return frame
        }
        model.frames = frames
        model.updateInteractionScope(frames.map(\.id))
        model.selectedFrameIDs = Set(frames.map(\.id))

        store.layoutMode = .singleImage
        XCTAssertEqual(model.printExportOutputCount, 39)

        store.layoutMode = .contactSheet
        store.packageSettings = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 6,
            contactColumns: 7
        )
        XCTAssertEqual(model.printExportOutputCount, 1)

        store.layoutMode = .picturePackage
        store.packageSettings = PrintPackageSettings(
            mode: .picturePackage,
            pictureTemplate: .fourUp
        )
        XCTAssertEqual(model.printExportOutputCount, 10)

        store.layoutMode = .customPackage
        store.packageSettings = PrintPackageSettings(mode: .customPackage)
        store.prepareDefaultCustomPackage(sourceCount: frames.count)
        XCTAssertEqual(model.printExportOutputCount, 1)
    }

    func testLayoutSizeFallsBackToSourceMetadataWhenNoImageIsLoaded() {
        let model = AppModel()
        let frame = makeFrame(width: 6000, height: 4000)

        XCTAssertEqual(
            model.printPackageLayoutSize(for: frame),
            CGSize(width: 6000, height: 4000)
        )
    }

    func testLayoutSizeAppliesQuarterTurnFromImageTransform() {
        let model = AppModel()
        let frame = makeFrame(width: 6000, height: 4000, rotation: .deg90)

        XCTAssertEqual(
            model.printPackageLayoutSize(for: frame),
            CGSize(width: 4000, height: 6000)
        )
    }

    func testContactSheetKeepsEverySelectedSourceOnOnePage() throws {
        let model = AppModel()
        let frames = (0..<5).map { _ in makeFrame(width: 6000, height: 4000) }
        let sizes = frames.map { model.printPackageLayoutSize(for: $0) }
        XCTAssertFalse(sizes.contains(where: { $0 == nil }))

        let pages = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: sizes.compactMap { $0 },
            composition: PrintCompositionSettings(
                paperSize: .a4,
                orientation: .automatic,
                marginMM: 10,
                dpi: 72,
                perforationStyle: .none
            ),
            package: PrintPackageSettings(mode: .contactSheet)
        ))

        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].items.map(\.sourceIndex), [0, 1, 2, 3, 4])
    }

    /// 시트 방향 통일 — 프레임마다 회전이 달라도 배치 단계에서 스캔 기본 방향까지만 더 돌린다.
    /// 프레임 자체의 회전은 건드리지 않는다.
    func testOrientationNormalizationTurnsEverySourceToTheDefaultScanRotation() {
        let model = AppModel()
        model.defaultScanRotation = .deg180
        let upright = makeFrame(width: 6000, height: 4000)
        let quarter = makeFrame(width: 6000, height: 4000, rotation: .deg90)
        let flipped = makeFrame(width: 6000, height: 4000, rotation: .deg180)
        var package = PrintPackageSettings(mode: .contactSheet)
        package.normalizesSourceOrientation = true

        let turns = model.printPackageForcedQuarterTurns(
            for: [upright, quarter, flipped],
            package: package
        )

        XCTAssertEqual(turns, [2, 1, 0])
        XCTAssertEqual(upright.imageTransform.rotation, .deg0)
        XCTAssertEqual(quarter.imageTransform.rotation, .deg90)
    }

    func testOrientationNormalizationIsOffByDefault() {
        let model = AppModel()
        let frame = makeFrame(width: 6000, height: 4000, rotation: .deg90)

        XCTAssertFalse(PrintPackageSettings().normalizesSourceOrientation)
        XCTAssertNil(model.printPackageForcedQuarterTurns(
            for: [frame],
            package: PrintPackageSettings(mode: .contactSheet)
        ))
    }

    func testForcedQuarterTurnsRotateContactSheetCells() throws {
        var package = PrintPackageSettings(mode: .contactSheet, contactRows: 1, contactColumns: 2)
        package.normalizesSourceOrientation = true
        let composition = PrintCompositionSettings(
            paperSize: .a4,
            orientation: .landscape,
            marginMM: 10,
            dpi: 72,
            perforationStyle: .none
        )

        let pages = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: [CGSize(width: 6000, height: 4000), CGSize(width: 6000, height: 4000)],
            composition: composition,
            package: package,
            forcedQuarterTurns: [0, 1]
        ))

        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].items.map(\.quarterTurns), [0, 1])
        // 90° 돌린 셀은 세로가 길어진다.
        let rotated = pages[0].items[1].destinationRectPoints
        XCTAssertGreaterThan(rotated.height, rotated.width)
    }

    private func makeFrame(
        width: Int,
        height: Int,
        rotation: ImageRotation = .deg0
    ) -> ScanFrame {
        var transform = ImageTransform.identity
        transform.rotation = rotation
        return ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-print-\(UUID().uuidString).tiff"),
            filmType: .colorNegative,
            sourceKind: .importedFile,
            sourcePixelWidth: width,
            sourcePixelHeight: height,
            initialTransform: transform
        )
    }

    private func makeImage(pixelWidth: Int, logicalWidth: CGFloat? = nil) throws -> NSImage {
        let representation = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let image = NSImage(size: NSSize(width: logicalWidth ?? CGFloat(pixelWidth), height: 1))
        image.addRepresentation(representation)
        return image
    }
}
