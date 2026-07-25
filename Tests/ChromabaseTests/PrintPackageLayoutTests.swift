import CoreGraphics
import XCTest
@testable import Chromabase

final class PrintPackageLayoutTests: XCTestCase {
    private let landscape = CGSize(width: 3_000, height: 2_000)
    private let portrait = CGSize(width: 2_000, height: 3_000)

    func testContactSheetPaginatesInTopToBottomRowMajorOrder() throws {
        let sources = Array(repeating: landscape, count: 7)
        let package = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 2,
            contactColumns: 3,
            horizontalSpacingMM: 4,
            verticalSpacingMM: 5
        )

        let pages = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: sources,
            composition: composition(),
            package: package
        ))

        XCTAssertEqual(pages.map { $0.items.count }, [6, 1])
        XCTAssertEqual(pages[0].items.map(\.sourceIndex), Array(0..<6))
        XCTAssertEqual(pages[1].items.map(\.sourceIndex), [6])
        XCTAssertLessThan(pages[0].items[0].cellRectPoints.minX, pages[0].items[1].cellRectPoints.minX)
        XCTAssertGreaterThan(pages[0].items[0].cellRectPoints.minY, pages[0].items[3].cellRectPoints.minY)
        XCTAssertEqual(pages[0].items[0].cellRectPoints.minY, pages[0].items[2].cellRectPoints.minY)
    }

    func testContactSheetRepeatCreatesOneFullPagePerSource() throws {
        let package = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 2,
            contactColumns: 3,
            repeatOnePhotoPerPage: true
        )

        let pages = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: [landscape, portrait],
            composition: PrintCompositionSettings(
                paperSize: .a4,
                orientation: .automatic,
                marginMM: 10,
                dpi: 300
            ),
            package: package
        ))

        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].items.map(\.sourceIndex), Array(repeating: 0, count: 6))
        XCTAssertEqual(pages[1].items.map(\.sourceIndex), Array(repeating: 1, count: 6))
    }

    func testPicturePackageRepeatsEachPhotoAcrossDeterministicDifferentSizedCells() throws {
        let package = PrintPackageSettings(
            mode: .picturePackage,
            pictureTemplate: .oneLargeTwoSmall
        )

        let pages = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: [landscape, portrait],
            composition: composition(),
            package: package
        ))

        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].items.map(\.sourceIndex), [0, 0, 0])
        XCTAssertEqual(pages[1].items.map(\.sourceIndex), [1, 1, 1])
        XCTAssertGreaterThan(pages[0].items[0].cellRectPoints.area, pages[0].items[1].cellRectPoints.area)
        XCTAssertEqual(
            pages[0].items[1].cellRectPoints.size,
            pages[0].items[2].cellRectPoints.size
        )
    }

    func testCustomPackagePreservesPageSourceGeometryAndStableZOrder() throws {
        let definitions = [
            PrintCustomPackageItem(
                sourceIndex: 2,
                normalizedRect: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                zIndex: 5
            ),
            PrintCustomPackageItem(
                sourceIndex: 0,
                normalizedRect: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                zIndex: 1
            ),
            PrintCustomPackageItem(
                sourceIndex: 1,
                pageIndex: 1,
                normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                zIndex: 0
            ),
        ]
        let package = PrintPackageSettings(mode: .customPackage, customItems: definitions)

        let pages = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: [landscape, portrait, landscape],
            composition: composition(),
            package: package
        ))

        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].items.map(\.sourceIndex), [0, 2])
        XCTAssertEqual(pages[0].items.map(\.zIndex), [1, 5])
        XCTAssertEqual(pages[1].items.map(\.sourceIndex), [1])
        let content = pages[1].contentRectPoints
        let cell = try XCTUnwrap(pages[1].items.first?.cellRectPoints)
        XCTAssertEqual(cell.minX, content.minX + content.width * 0.25, accuracy: 1e-9)
        XCTAssertEqual(cell.minY, content.minY + content.height * 0.25, accuracy: 1e-9)
        XCTAssertEqual(cell.width, content.width * 0.5, accuracy: 1e-9)
        XCTAssertEqual(cell.height, content.height * 0.5, accuracy: 1e-9)
    }

    func testFitFillAndRotateToFitExposeExactRenderContract() throws {
        let cell = PrintCustomPackageItem(
            sourceIndex: 0,
            normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        let fitPackage = PrintPackageSettings(
            mode: .customPackage,
            customItems: [cell]
        )
        let fit = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: [CGSize(width: 3, height: 1)],
            composition: composition(),
            package: fitPackage
        )).first!.items[0]
        XCTAssertEqual(fit.sourceUnitCropRect, CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(fit.destinationRectPoints.width / fit.destinationRectPoints.height, 3, accuracy: 1e-9)
        XCTAssertEqual(fit.quarterTurns, 0)

        var fillCell = cell
        fillCell.contentMode = .fill
        let fill = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: [CGSize(width: 3, height: 1)],
            composition: composition(),
            package: PrintPackageSettings(mode: .customPackage, customItems: [fillCell])
        )).first!.items[0]
        XCTAssertEqual(fill.destinationRectPoints, fill.cellRectPoints)
        XCTAssertLessThan(fill.sourceUnitCropRect.width, 1)
        XCTAssertEqual(fill.sourceUnitCropRect.height, 1, accuracy: 1e-9)
        XCTAssertEqual(fill.sourceUnitCropRect.midX, 0.5, accuracy: 1e-9)

        var rotatedCell = cell
        rotatedCell.rotateToFit = true
        let rotated = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: [CGSize(width: 3, height: 1)],
            composition: composition(),
            package: PrintPackageSettings(mode: .customPackage, customItems: [rotatedCell])
        )).first!.items[0]
        XCTAssertEqual(rotated.quarterTurns, 1)
        XCTAssertEqual(rotated.destinationRectPoints.height / rotated.destinationRectPoints.width, 3, accuracy: 1e-9)
    }

    func testPhysicalMarginsSpacingCaptionsAndCropMarksUsePoints() throws {
        let package = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 1,
            contactColumns: 2,
            horizontalSpacingMM: 4,
            verticalSpacingMM: 0,
            captionMode: .fileName,
            captionHeightMM: 6,
            showsCropMarks: true,
            cropMarkLengthMM: 3
        )
        let page = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: [landscape, portrait],
            composition: composition(marginMM: 10),
            package: package
        )).first!
        let pointsPerMM = 72.0 / 25.4

        XCTAssertEqual(page.canvasSizePoints.width, 210 * pointsPerMM, accuracy: 1e-9)
        XCTAssertEqual(page.contentRectPoints.minX, 10 * pointsPerMM, accuracy: 1e-9)
        XCTAssertEqual(page.contentRectPoints.minY, 10 * pointsPerMM, accuracy: 1e-9)
        XCTAssertEqual(
            page.items[1].cellRectPoints.minX - page.items[0].cellRectPoints.maxX,
            4 * pointsPerMM,
            accuracy: 1e-9
        )
        for item in page.items {
            let caption = try XCTUnwrap(item.captionRectPoints)
            XCTAssertEqual(caption.height, 6 * pointsPerMM, accuracy: 1e-9)
            XCTAssertGreaterThanOrEqual(item.destinationRectPoints.minY, caption.maxY)
            XCTAssertTrue(page.contentRectPoints.contains(item.destinationRectPoints))
        }
        XCTAssertFalse(page.cropMarkSegments.isEmpty)
        let canvas = CGRect(origin: .zero, size: page.canvasSizePoints)
        XCTAssertTrue(page.cropMarkSegments.allSatisfy { segment in
            containsOrTouches(canvas, segment.start)
                && containsOrTouches(canvas, segment.end)
        })
        XCTAssertTrue(page.cropMarkSegments.contains { segment in
            !containsOrTouches(page.contentRectPoints, segment.start)
                || !containsOrTouches(page.contentRectPoints, segment.end)
        })
    }

    func testInvalidInputsFailClosedAndValidEmptySelectionReturnsNoPages() throws {
        let validPackage = PrintPackageSettings(mode: .contactSheet)
        XCTAssertEqual(PrintPackageLayout.make(
            sourceSizes: [],
            composition: composition(),
            package: validPackage
        ), [])
        XCTAssertNil(PrintPackageLayout.make(
            sourceSizes: [CGSize(width: CGFloat.nan, height: 10)],
            composition: composition(),
            package: validPackage
        ))

        var invalidRows = validPackage
        invalidRows.contactRows = 0
        XCTAssertNil(PrintPackageLayout.make(
            sourceSizes: [landscape],
            composition: composition(),
            package: invalidRows
        ))

        var invalidSpacing = validPackage
        invalidSpacing.horizontalSpacingMM = .nan
        XCTAssertNil(PrintPackageLayout.make(
            sourceSizes: [landscape],
            composition: composition(),
            package: invalidSpacing
        ))

        var invalidHiddenCustomItems = validPackage
        invalidHiddenCustomItems.customItems = []
        XCTAssertFalse(invalidHiddenCustomItems.isValid)
        XCTAssertNil(PrintPackageLayout.make(
            sourceSizes: [landscape],
            composition: composition(),
            package: invalidHiddenCustomItems
        ))

        let outOfBounds = PrintCustomPackageItem(
            sourceIndex: 0,
            normalizedRect: CGRect(x: 0.8, y: 0, width: 0.3, height: 1)
        )
        XCTAssertNil(PrintPackageLayout.make(
            sourceSizes: [landscape],
            composition: composition(),
            package: PrintPackageSettings(mode: .customPackage, customItems: [outOfBounds])
        ))

        let missingSource = PrintCustomPackageItem(
            sourceIndex: 1,
            normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        XCTAssertNil(PrintPackageLayout.make(
            sourceSizes: [landscape],
            composition: composition(),
            package: PrintPackageSettings(mode: .customPackage, customItems: [missingSource])
        ))

        let skippedPage = PrintCustomPackageItem(
            sourceIndex: 0,
            pageIndex: 1,
            normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        XCTAssertNil(PrintPackageLayout.make(
            sourceSizes: [landscape],
            composition: composition(),
            package: PrintPackageSettings(mode: .customPackage, customItems: [skippedPage])
        ))
    }

    func testLayoutIsDeterministic() throws {
        let package = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 3,
            contactColumns: 2,
            contentMode: .fill,
            rotateToFit: true,
            captionMode: .frameNumber,
            showsCropMarks: true
        )
        let sources = [landscape, portrait, landscape, portrait, landscape, portrait, landscape]

        let first = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: sources,
            composition: composition(),
            package: package
        ))
        let second = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: sources,
            composition: composition(),
            package: package
        ))

        XCTAssertEqual(first, second)
    }

    func testExpectedPageCountMatchesEveryLayoutMode() throws {
        let contact = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 2,
            contactColumns: 3
        )
        XCTAssertEqual(PrintPackageLayout.expectedPageCount(sourceCount: 7, package: contact), 2)
        XCTAssertEqual(
            PrintPackageLayout.make(
                sourceSizes: Array(repeating: landscape, count: 7),
                composition: composition(),
                package: contact
            )?.count,
            2
        )

        let picture = PrintPackageSettings(mode: .picturePackage)
        XCTAssertEqual(PrintPackageLayout.expectedPageCount(sourceCount: 3, package: picture), 3)

        let custom = PrintPackageSettings(
            mode: .customPackage,
            customItems: [
                PrintCustomPackageItem(
                    sourceIndex: 0,
                    normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1)
                ),
                PrintCustomPackageItem(
                    sourceIndex: 1,
                    pageIndex: 1,
                    normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1)
                ),
            ]
        )
        XCTAssertEqual(PrintPackageLayout.expectedPageCount(sourceCount: 2, package: custom), 2)
        XCTAssertNil(PrintPackageLayout.expectedPageCount(sourceCount: 1, package: custom))
    }

    func testPageCountLimitIsConsistentForContactAndPicturePackages() {
        let thirtyTwoSources = Array(
            repeating: landscape,
            count: PrintPackageSettings.maximumPageCount
        )
        let thirtyThreeSources = thirtyTwoSources + [landscape]
        let contact = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 1,
            contactColumns: 1
        )
        let picture = PrintPackageSettings(mode: .picturePackage)

        XCTAssertEqual(
            PrintPackageLayout.expectedPageCount(
                sourceCount: thirtyTwoSources.count,
                package: contact
            ),
            PrintPackageSettings.maximumPageCount
        )
        XCTAssertNotNil(PrintPackageLayout.make(
            sourceSizes: thirtyTwoSources,
            composition: composition(),
            package: contact
        ))
        XCTAssertNil(PrintPackageLayout.expectedPageCount(
            sourceCount: thirtyThreeSources.count,
            package: contact
        ))
        XCTAssertNil(PrintPackageLayout.make(
            sourceSizes: thirtyThreeSources,
            composition: composition(),
            package: contact
        ))

        XCTAssertEqual(
            PrintPackageLayout.expectedPageCount(
                sourceCount: thirtyTwoSources.count,
                package: picture
            ),
            PrintPackageSettings.maximumPageCount
        )
        XCTAssertNotNil(PrintPackageLayout.make(
            sourceSizes: thirtyTwoSources,
            composition: composition(),
            package: picture
        ))
        XCTAssertNil(PrintPackageLayout.expectedPageCount(
            sourceCount: thirtyThreeSources.count,
            package: picture
        ))
        XCTAssertNil(PrintPackageLayout.make(
            sourceSizes: thirtyThreeSources,
            composition: composition(),
            package: picture
        ))
    }

    func testAutomaticPicturePackageOrientationFollowsEachSourcePage() throws {
        let pages = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: [landscape, portrait],
            composition: PrintCompositionSettings(
                paperSize: .a4,
                orientation: .automatic,
                marginMM: 10,
                dpi: 300
            ),
            package: PrintPackageSettings(mode: .picturePackage)
        ))

        XCTAssertGreaterThan(pages[0].canvasSizePoints.width, pages[0].canvasSizePoints.height)
        XCTAssertLessThan(pages[1].canvasSizePoints.width, pages[1].canvasSizePoints.height)
    }

    private func composition(marginMM: Double = 10) -> PrintCompositionSettings {
        PrintCompositionSettings(
            paperSize: .a4,
            orientation: .portrait,
            marginMM: marginMM,
            dpi: 300
        )
    }

    private func containsOrTouches(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX
            && point.y >= rect.minY && point.y <= rect.maxY
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
