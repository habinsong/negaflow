import Chromabase
import CoreGraphics
import CoreImage
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

    func testOrientationNormalizationUsesDevelopedAspectIncludingCrop() {
        let model = AppModel()
        let square = makeFrame(width: 4000, height: 4000, rotation: .deg180)
        let landscape = makeFrame(width: 6000, height: 4000, rotation: .deg180)
        let portrait = makeFrame(width: 6000, height: 4000, rotation: .deg90)
        let rotatedLandscape = makeFrame(width: 4000, height: 6000, rotation: .deg270)
        let croppedPortrait = makeFrame(width: 6000, height: 4000)
        croppedPortrait.imageTransform.cropRect = SIMD4(0.1, 0, 0.4, 1)
        let frames = [square, landscape, portrait, rotatedLandscape, croppedPortrait]
        let transforms = frames.map(\.imageTransform)
        var package = PrintPackageSettings(mode: .contactSheet)
        package.normalizesSourceOrientation = true

        XCTAssertEqual(model.printPackageForcedQuarterTurns(
            for: frames,
            package: package
        ), [0, 0, 1, 0, 1])
        XCTAssertEqual(model.printPackageForcedQuarterTurns(
            for: [portrait, square, landscape, croppedPortrait, rotatedLandscape],
            package: package
        ), [0, 0, 1, 0, 1])
        XCTAssertEqual(frames.map(\.imageTransform), transforms)
    }

    func testOrientationNormalizationDoesNotRotateSquareOrUnknownSources() {
        let model = AppModel()
        let package = PrintPackageSettings(normalizesSourceOrientation: true)
        XCTAssertEqual(model.printPackageForcedQuarterTurns(
            for: [
                makeFrame(width: 4000, height: 4000, rotation: .deg90),
                makeFrame(width: 0, height: 0),
            ],
            package: package
        ), [0, 0])
    }

    func testPackagePagesPreserveDevelopedPixelsRegardlessOfDefaultScanRotation() throws {
        let suiteName = "negaflow-print-orientation-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            presentationPreferencesStore: PresentationPreferencesStore(defaults: defaults)
        )
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let source = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 40, height: 20))
            .composited(over: CIImage(color: .green)
                .cropped(to: CGRect(x: 40, y: 0, width: 40, height: 20)))
            .composited(over: CIImage(color: .blue)
                .cropped(to: CGRect(x: 0, y: 20, width: 40, height: 20)))
            .composited(over: CIImage(color: CIColor(red: 1, green: 1, blue: 0))
                .cropped(to: CGRect(x: 40, y: 20, width: 40, height: 20)))
        let composition = PrintCompositionSettings(
            paperSize: .fourBySix,
            orientation: .landscape,
            marginMM: 5,
            dpi: 72,
            perforationStyle: .none
        )

        for sourceKind in [FrameSource.scannerTIFF, .importedFile] {
            for rotation in ImageRotation.allCases {
                let frame = makeFrame(width: 80, height: 40, rotation: rotation, sourceKind: sourceKind)
                frame.imageTransform.flipHorizontal = true
                let transform = frame.imageTransform
                let developed = ImageTransformStage.apply(to: source, transform: transform)
                let size = try XCTUnwrap(model.printPackageLayoutSize(for: frame))
                XCTAssertEqual(size, developed.extent.size)

                for scanRotation in ImageRotation.allCases {
                    model.defaultScanRotation = scanRotation
                    for mode in PrintPackageLayoutMode.allCases {
                        for normalizes in [false, true] {
                            let package = PrintPackageSettings(
                                mode: mode,
                                contactRows: 1,
                                contactColumns: 1,
                                normalizesSourceOrientation: normalizes
                            )
                            let page = try XCTUnwrap(PrintPackageLayout.make(
                                sourceSizes: [size],
                                composition: composition,
                                package: package,
                                forcedQuarterTurns: model.printPackageForcedQuarterTurns(
                                    for: [frame],
                                    package: package
                                )
                            )?.first)
                            let message = "\(sourceKind), \(mode), rotation=\(rotation), scan=\(scanRotation), normalize=\(normalizes)"
                            XCTAssertTrue(page.items.allSatisfy { $0.quarterTurns == 0 }, message)
                            let rendered = try XCTUnwrap(PrintPackageRenderer.renderPage(
                                sources: [PrintPackageRenderSource(image: developed)],
                                layout: page,
                                dpi: composition.dpi
                            ))
                            let destination = try XCTUnwrap(page.items.first?.destinationRectPoints)
                            for x in [0.25, 0.75] {
                                for y in [0.25, 0.75] {
                                    let expected = pixel(
                                        in: developed, rect: developed.extent, x: x, y: y,
                                        context: context, colorSpace: colorSpace
                                    )
                                    let actual = pixel(
                                        in: rendered, rect: destination, x: x, y: y,
                                        context: context, colorSpace: colorSpace
                                    )
                                    XCTAssertEqual(actual, expected, message)
                                }
                            }
                            XCTAssertEqual(frame.imageTransform, transform)
                        }
                    }
                }
            }
        }
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
        rotation: ImageRotation = .deg0,
        sourceKind: FrameSource = .importedFile
    ) -> ScanFrame {
        var transform = ImageTransform.identity
        transform.rotation = rotation
        return ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-print-\(UUID().uuidString).tiff"),
            filmType: .colorNegative,
            sourceKind: sourceKind,
            sourcePixelWidth: width,
            sourcePixelHeight: height,
            initialTransform: transform
        )
    }

    private func pixel(
        in image: CIImage,
        rect: CGRect,
        x: CGFloat,
        y: CGFloat,
        context: CIContext,
        colorSpace: CGColorSpace
    ) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image,
            toBitmap: &bytes,
            rowBytes: 4,
            bounds: CGRect(
                x: floor(rect.minX + rect.width * x),
                y: floor(rect.minY + rect.height * y),
                width: 1,
                height: 1
            ),
            format: .RGBA8,
            colorSpace: colorSpace
        )
        return bytes
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
