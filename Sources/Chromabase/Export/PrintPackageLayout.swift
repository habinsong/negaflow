import CoreGraphics
import Foundation

public enum PrintPackageLayout {
    private static let pointsPerMM: CGFloat = 72 / 25.4
    private static let maximumSourceCount = 10_000

    public static func expectedPageCount(
        sourceCount: Int,
        package: PrintPackageSettings
    ) -> Int? {
        guard package.isValid,
              (0...maximumSourceCount).contains(sourceCount) else { return nil }
        guard sourceCount > 0 else { return 0 }
        let pageCount: Int
        switch package.mode {
        case .contactSheet:
            if package.repeatOnePhotoPerPage {
                pageCount = sourceCount
            } else {
                let capacity = package.contactRows * package.contactColumns
                pageCount = (sourceCount + capacity - 1) / capacity
            }
        case .picturePackage:
            pageCount = sourceCount
        case .customPackage:
            guard package.customItems.allSatisfy({ $0.sourceIndex < sourceCount }),
                  let highestPage = package.customItems.map(\.pageIndex).max() else { return nil }
            pageCount = highestPage + 1
        }
        return pageCount <= PrintPackageSettings.maximumPageCount ? pageCount : nil
    }

    public static func make(
        sourceSizes: [CGSize],
        composition: PrintCompositionSettings,
        package: PrintPackageSettings
    ) -> [PrintPackagePageLayout]? {
        guard composition.isValid,
              package.isValid,
              sourceSizes.count <= maximumSourceCount,
              sourceSizes.allSatisfy(validSize),
              expectedPageCount(sourceCount: sourceSizes.count, package: package) != nil else {
            return nil
        }
        guard !sourceSizes.isEmpty else { return [] }
        switch package.mode {
        case .contactSheet:
            guard let page = pageGeometry(
                sourceSize: sourceSizes[0],
                composition: composition
            ) else { return nil }
            return contactSheetPages(
                sourceSizes: sourceSizes,
                page: page,
                package: package
            )
        case .picturePackage:
            return picturePackagePages(
                sourceSizes: sourceSizes,
                composition: composition,
                package: package
            )
        case .customPackage:
            guard let firstSourceIndex = package.customItems
                .sorted(by: customItemOrder)
                .first?.sourceIndex,
                  sourceSizes.indices.contains(firstSourceIndex),
                  let page = pageGeometry(
                    sourceSize: sourceSizes[firstSourceIndex],
                    composition: composition
                  ) else { return nil }
            return customPackagePages(
                sourceSizes: sourceSizes,
                page: page,
                package: package
            )
        }
    }

    private struct PageGeometry {
        let canvasSize: CGSize
        let contentRect: CGRect
    }

    private static func pageGeometry(
        sourceSize: CGSize,
        composition: PrintCompositionSettings
    ) -> PageGeometry? {
        let base = composition.paperSize.dimensionsMM
        let pageMM: CGSize
        switch composition.orientation {
        case .automatic:
            pageMM = sourceSize.width >= sourceSize.height
                ? CGSize(width: max(base.width, base.height), height: min(base.width, base.height))
                : CGSize(width: min(base.width, base.height), height: max(base.width, base.height))
        case .portrait:
            pageMM = CGSize(width: min(base.width, base.height), height: max(base.width, base.height))
        case .landscape:
            pageMM = CGSize(width: max(base.width, base.height), height: min(base.width, base.height))
        }
        let canvas = CGSize(
            width: pageMM.width * pointsPerMM,
            height: pageMM.height * pointsPerMM
        )
        let margin = CGFloat(composition.marginMM) * pointsPerMM
        let content = CGRect(origin: .zero, size: canvas).insetBy(dx: margin, dy: margin)
        guard validSize(canvas), content.width > 1, content.height > 1 else { return nil }
        return PageGeometry(canvasSize: canvas, contentRect: content)
    }

    private static func contactSheetPages(
        sourceSizes: [CGSize],
        page: PageGeometry,
        package: PrintPackageSettings
    ) -> [PrintPackagePageLayout]? {
        let rows = package.contactRows
        let columns = package.contactColumns
        let horizontalGap = CGFloat(package.horizontalSpacingMM) * pointsPerMM
        let verticalGap = CGFloat(package.verticalSpacingMM) * pointsPerMM
        let availableWidth = page.contentRect.width - CGFloat(columns - 1) * horizontalGap
        let availableHeight = page.contentRect.height - CGFloat(rows - 1) * verticalGap
        guard availableWidth > 1, availableHeight > 1 else { return nil }
        let cellSize = CGSize(
            width: availableWidth / CGFloat(columns),
            height: availableHeight / CGFloat(rows)
        )
        guard validSize(cellSize) else { return nil }

        let capacity = rows * columns
        let assignments: [[Int]]
        if package.repeatOnePhotoPerPage {
            assignments = sourceSizes.indices.map { Array(repeating: $0, count: capacity) }
        } else {
            assignments = stride(from: 0, to: sourceSizes.count, by: capacity).map { start in
                Array(start..<min(start + capacity, sourceSizes.count))
            }
        }

        var pages: [PrintPackagePageLayout] = []
        pages.reserveCapacity(assignments.count)
        for (pageIndex, sourceIndices) in assignments.enumerated() {
            var items: [PrintPackageItemLayout] = []
            items.reserveCapacity(sourceIndices.count)
            for (slot, sourceIndex) in sourceIndices.enumerated() {
                let row = slot / columns
                let column = slot % columns
                let cell = CGRect(
                    x: page.contentRect.minX + CGFloat(column) * (cellSize.width + horizontalGap),
                    y: page.contentRect.maxY
                        - CGFloat(row + 1) * cellSize.height
                        - CGFloat(row) * verticalGap,
                    width: cellSize.width,
                    height: cellSize.height
                )
                guard let item = makeItem(
                    sourceIndex: sourceIndex,
                    sourceSize: sourceSizes[sourceIndex],
                    cellRect: cell,
                    contentMode: package.contentMode,
                    rotateToFit: package.rotateToFit,
                    captionMode: package.captionMode,
                    captionHeightMM: package.captionHeightMM,
                    zIndex: slot
                ) else { return nil }
                items.append(item)
            }
            pages.append(PrintPackagePageLayout(
                pageIndex: pageIndex,
                canvasSizePoints: page.canvasSize,
                contentRectPoints: page.contentRect,
                items: items,
                cropMarkSegments: cropMarks(
                    for: items.map(\.cellRectPoints),
                    in: CGRect(origin: .zero, size: page.canvasSize),
                    package: package
                )
            ))
        }
        return pages
    }

    private static func picturePackagePages(
        sourceSizes: [CGSize],
        composition: PrintCompositionSettings,
        package: PrintPackageSettings
    ) -> [PrintPackagePageLayout]? {
        var pages: [PrintPackagePageLayout] = []
        pages.reserveCapacity(sourceSizes.count)
        for sourceIndex in sourceSizes.indices {
            guard let page = pageGeometry(
                sourceSize: sourceSizes[sourceIndex],
                composition: composition
            ), let cells = pictureCells(
                template: package.pictureTemplate,
                contentRect: page.contentRect,
                horizontalGap: CGFloat(package.horizontalSpacingMM) * pointsPerMM,
                verticalGap: CGFloat(package.verticalSpacingMM) * pointsPerMM
            ) else { return nil }
            var items: [PrintPackageItemLayout] = []
            items.reserveCapacity(cells.count)
            for (slot, cell) in cells.enumerated() {
                guard let item = makeItem(
                    sourceIndex: sourceIndex,
                    sourceSize: sourceSizes[sourceIndex],
                    cellRect: cell,
                    contentMode: package.contentMode,
                    rotateToFit: package.rotateToFit,
                    captionMode: package.captionMode,
                    captionHeightMM: package.captionHeightMM,
                    zIndex: slot
                ) else { return nil }
                items.append(item)
            }
            pages.append(PrintPackagePageLayout(
                pageIndex: sourceIndex,
                canvasSizePoints: page.canvasSize,
                contentRectPoints: page.contentRect,
                items: items,
                cropMarkSegments: cropMarks(
                    for: cells,
                    in: CGRect(origin: .zero, size: page.canvasSize),
                    package: package
                )
            ))
        }
        return pages
    }

    private static func customPackagePages(
        sourceSizes: [CGSize],
        page: PageGeometry,
        package: PrintPackageSettings
    ) -> [PrintPackagePageLayout]? {
        guard package.customItems.allSatisfy({ $0.sourceIndex < sourceSizes.count }),
              let highestPage = package.customItems.map(\.pageIndex).max() else { return nil }
        let pageIndices = Set(package.customItems.map(\.pageIndex))
        guard pageIndices == Set(0...highestPage) else { return nil }

        let indexedItems = package.customItems.enumerated().map { ($0.offset, $0.element) }
        var pages: [PrintPackagePageLayout] = []
        pages.reserveCapacity(highestPage + 1)
        for pageIndex in 0...highestPage {
            let definitions = indexedItems
                .filter { $0.1.pageIndex == pageIndex }
                .sorted { lhs, rhs in
                    lhs.1.zIndex == rhs.1.zIndex ? lhs.0 < rhs.0 : lhs.1.zIndex < rhs.1.zIndex
                }
            var items: [PrintPackageItemLayout] = []
            items.reserveCapacity(definitions.count)
            for (_, definition) in definitions {
                let normalized = definition.normalizedRect
                let cell = CGRect(
                    x: page.contentRect.minX + normalized.minX * page.contentRect.width,
                    y: page.contentRect.minY + normalized.minY * page.contentRect.height,
                    width: normalized.width * page.contentRect.width,
                    height: normalized.height * page.contentRect.height
                )
                guard let item = makeItem(
                    sourceIndex: definition.sourceIndex,
                    sourceSize: sourceSizes[definition.sourceIndex],
                    cellRect: cell,
                    contentMode: definition.contentMode,
                    rotateToFit: definition.rotateToFit,
                    captionMode: package.captionMode,
                    captionHeightMM: package.captionHeightMM,
                    zIndex: definition.zIndex
                ) else { return nil }
                items.append(item)
            }
            pages.append(PrintPackagePageLayout(
                pageIndex: pageIndex,
                canvasSizePoints: page.canvasSize,
                contentRectPoints: page.contentRect,
                items: items,
                cropMarkSegments: cropMarks(
                    for: items.map(\.cellRectPoints),
                    in: CGRect(origin: .zero, size: page.canvasSize),
                    package: package
                )
            ))
        }
        return pages
    }

    private static func pictureCells(
        template: PrintPicturePackageTemplate,
        contentRect: CGRect,
        horizontalGap: CGFloat,
        verticalGap: CGFloat
    ) -> [CGRect]? {
        switch template {
        case .oneLargeTwoSmall:
            let availableWidth = contentRect.width - horizontalGap
            let availableHeight = contentRect.height - verticalGap
            guard availableWidth > 2, availableHeight > 2 else { return nil }
            let largeWidth = availableWidth * 2 / 3
            let smallWidth = availableWidth - largeWidth
            let smallHeight = availableHeight / 2
            return [
                CGRect(x: contentRect.minX, y: contentRect.minY, width: largeWidth, height: contentRect.height),
                CGRect(
                    x: contentRect.minX + largeWidth + horizontalGap,
                    y: contentRect.minY + smallHeight + verticalGap,
                    width: smallWidth,
                    height: smallHeight
                ),
                CGRect(
                    x: contentRect.minX + largeWidth + horizontalGap,
                    y: contentRect.minY,
                    width: smallWidth,
                    height: smallHeight
                ),
            ]
        case .twoUp:
            let width = (contentRect.width - horizontalGap) / 2
            guard width > 1 else { return nil }
            return [
                CGRect(x: contentRect.minX, y: contentRect.minY, width: width, height: contentRect.height),
                CGRect(
                    x: contentRect.minX + width + horizontalGap,
                    y: contentRect.minY,
                    width: width,
                    height: contentRect.height
                ),
            ]
        case .fourUp:
            let width = (contentRect.width - horizontalGap) / 2
            let height = (contentRect.height - verticalGap) / 2
            guard width > 1, height > 1 else { return nil }
            return (0..<4).map { slot in
                let row = slot / 2
                let column = slot % 2
                return CGRect(
                    x: contentRect.minX + CGFloat(column) * (width + horizontalGap),
                    y: contentRect.maxY - CGFloat(row + 1) * height - CGFloat(row) * verticalGap,
                    width: width,
                    height: height
                )
            }
        }
    }

    private static func makeItem(
        sourceIndex: Int,
        sourceSize: CGSize,
        cellRect: CGRect,
        contentMode: PrintPackageContentMode,
        rotateToFit: Bool,
        captionMode: PrintPackageCaptionMode,
        captionHeightMM: Double,
        zIndex: Int
    ) -> PrintPackageItemLayout? {
        let captionHeight = captionMode == .none ? 0 : CGFloat(captionHeightMM) * pointsPerMM
        guard captionHeight >= 0, captionHeight < cellRect.height - 1 else { return nil }
        let captionRect = captionMode == .none
            ? nil
            : CGRect(x: cellRect.minX, y: cellRect.minY, width: cellRect.width, height: captionHeight)
        let imageBounds = CGRect(
            x: cellRect.minX,
            y: cellRect.minY + captionHeight,
            width: cellRect.width,
            height: cellRect.height - captionHeight
        )
        guard imageBounds.width > 1, imageBounds.height > 1 else { return nil }

        let unrotatedScale = min(
            imageBounds.width / sourceSize.width,
            imageBounds.height / sourceSize.height
        )
        let rotatedScale = min(
            imageBounds.width / sourceSize.height,
            imageBounds.height / sourceSize.width
        )
        let quarterTurns = rotateToFit && rotatedScale > unrotatedScale ? 1 : 0
        let orientedSize = quarterTurns == 0
            ? sourceSize
            : CGSize(width: sourceSize.height, height: sourceSize.width)

        let destination: CGRect
        let crop: CGRect
        switch contentMode {
        case .fit:
            let scale = min(
                imageBounds.width / orientedSize.width,
                imageBounds.height / orientedSize.height
            )
            let size = CGSize(width: orientedSize.width * scale, height: orientedSize.height * scale)
            destination = CGRect(
                x: imageBounds.midX - size.width / 2,
                y: imageBounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
            crop = CGRect(x: 0, y: 0, width: 1, height: 1)
        case .fill:
            let scale = max(
                imageBounds.width / orientedSize.width,
                imageBounds.height / orientedSize.height
            )
            let visibleWidth = min(orientedSize.width, imageBounds.width / scale)
            let visibleHeight = min(orientedSize.height, imageBounds.height / scale)
            crop = CGRect(
                x: (orientedSize.width - visibleWidth) / (2 * orientedSize.width),
                y: (orientedSize.height - visibleHeight) / (2 * orientedSize.height),
                width: visibleWidth / orientedSize.width,
                height: visibleHeight / orientedSize.height
            )
            destination = imageBounds
        }

        return PrintPackageItemLayout(
            sourceIndex: sourceIndex,
            cellRectPoints: cellRect,
            destinationRectPoints: destination,
            sourceUnitCropRect: crop,
            quarterTurns: quarterTurns,
            captionRectPoints: captionRect,
            zIndex: zIndex
        )
    }

    private static func cropMarks(
        for cells: [CGRect],
        in contentRect: CGRect,
        package: PrintPackageSettings
    ) -> [PrintPackageLineSegment] {
        guard package.showsCropMarks else { return [] }
        let length = CGFloat(package.cropMarkLengthMM) * pointsPerMM
        var segments: [PrintPackageLineSegment] = []
        segments.reserveCapacity(cells.count * 8)

        func append(_ start: CGPoint, _ end: CGPoint) {
            guard start != end,
                  containsOrTouches(contentRect, point: start),
                  containsOrTouches(contentRect, point: end) else { return }
            segments.append(PrintPackageLineSegment(start: start, end: end))
        }

        for cell in cells {
            let leftStart = max(contentRect.minX, cell.minX - length)
            let rightEnd = min(contentRect.maxX, cell.maxX + length)
            let bottomStart = max(contentRect.minY, cell.minY - length)
            let topEnd = min(contentRect.maxY, cell.maxY + length)
            append(CGPoint(x: leftStart, y: cell.minY), CGPoint(x: cell.minX, y: cell.minY))
            append(CGPoint(x: leftStart, y: cell.maxY), CGPoint(x: cell.minX, y: cell.maxY))
            append(CGPoint(x: cell.maxX, y: cell.minY), CGPoint(x: rightEnd, y: cell.minY))
            append(CGPoint(x: cell.maxX, y: cell.maxY), CGPoint(x: rightEnd, y: cell.maxY))
            append(CGPoint(x: cell.minX, y: bottomStart), CGPoint(x: cell.minX, y: cell.minY))
            append(CGPoint(x: cell.maxX, y: bottomStart), CGPoint(x: cell.maxX, y: cell.minY))
            append(CGPoint(x: cell.minX, y: cell.maxY), CGPoint(x: cell.minX, y: topEnd))
            append(CGPoint(x: cell.maxX, y: cell.maxY), CGPoint(x: cell.maxX, y: topEnd))
        }
        return segments
    }

    private static func validSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private static func customItemOrder(
        _ lhs: PrintCustomPackageItem,
        _ rhs: PrintCustomPackageItem
    ) -> Bool {
        if lhs.pageIndex != rhs.pageIndex { return lhs.pageIndex < rhs.pageIndex }
        if lhs.zIndex != rhs.zIndex { return lhs.zIndex < rhs.zIndex }
        return lhs.sourceIndex < rhs.sourceIndex
    }

    private static func containsOrTouches(_ rect: CGRect, point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX
            && point.y >= rect.minY && point.y <= rect.maxY
    }
}
