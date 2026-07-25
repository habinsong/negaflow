import CoreGraphics
import Foundation

public enum PrintPackageLayoutMode: String, CaseIterable, Codable, Sendable {
    case contactSheet
    case picturePackage
    case customPackage
}

public enum PrintPackageContentMode: String, CaseIterable, Codable, Sendable {
    case fit
    case fill
}

public enum PrintPicturePackageTemplate: String, CaseIterable, Codable, Sendable {
    case oneLargeTwoSmall
    case twoUp
    case fourUp
}

public enum PrintPackageCaptionMode: String, CaseIterable, Codable, Sendable {
    case none
    case fileName
    case frameNumber
    case rating
}

/// `normalizedRect`는 용지 여백을 제외한 content rect 기준이며 Quartz 좌표계(좌하단 원점)다.
public struct PrintCustomPackageItem: Codable, Equatable, Sendable {
    public var sourceIndex: Int
    public var pageIndex: Int
    public var normalizedRect: CGRect
    public var contentMode: PrintPackageContentMode
    public var rotateToFit: Bool
    public var zIndex: Int

    public init(
        sourceIndex: Int,
        pageIndex: Int = 0,
        normalizedRect: CGRect,
        contentMode: PrintPackageContentMode = .fit,
        rotateToFit: Bool = false,
        zIndex: Int = 0
    ) {
        self.sourceIndex = sourceIndex
        self.pageIndex = pageIndex
        self.normalizedRect = normalizedRect
        self.contentMode = contentMode
        self.rotateToFit = rotateToFit
        self.zIndex = zIndex
    }
}

public struct PrintPackageSettings: Codable, Equatable, Sendable {
    public static let maximumCustomItemCount = 128
    public static let maximumPageCount = 32

    public var mode: PrintPackageLayoutMode
    public var contactRows: Int
    public var contactColumns: Int
    public var horizontalSpacingMM: Double
    public var verticalSpacingMM: Double
    public var contentMode: PrintPackageContentMode
    public var rotateToFit: Bool
    public var repeatOnePhotoPerPage: Bool
    public var pictureTemplate: PrintPicturePackageTemplate
    public var customItems: [PrintCustomPackageItem]
    public var captionMode: PrintPackageCaptionMode
    public var captionHeightMM: Double
    public var showsCropMarks: Bool
    public var cropMarkLengthMM: Double

    public init(
        mode: PrintPackageLayoutMode = .contactSheet,
        contactRows: Int = 3,
        contactColumns: Int = 3,
        horizontalSpacingMM: Double = 4,
        verticalSpacingMM: Double = 4,
        contentMode: PrintPackageContentMode = .fit,
        rotateToFit: Bool = false,
        repeatOnePhotoPerPage: Bool = false,
        pictureTemplate: PrintPicturePackageTemplate = .oneLargeTwoSmall,
        customItems: [PrintCustomPackageItem] = [
            PrintCustomPackageItem(
                sourceIndex: 0,
                normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1)
            ),
        ],
        captionMode: PrintPackageCaptionMode = .none,
        captionHeightMM: Double = 6,
        showsCropMarks: Bool = false,
        cropMarkLengthMM: Double = 3
    ) {
        self.mode = mode
        self.contactRows = contactRows
        self.contactColumns = contactColumns
        self.horizontalSpacingMM = horizontalSpacingMM
        self.verticalSpacingMM = verticalSpacingMM
        self.contentMode = contentMode
        self.rotateToFit = rotateToFit
        self.repeatOnePhotoPerPage = repeatOnePhotoPerPage
        self.pictureTemplate = pictureTemplate
        self.customItems = customItems
        self.captionMode = captionMode
        self.captionHeightMM = captionHeightMM
        self.showsCropMarks = showsCropMarks
        self.cropMarkLengthMM = cropMarkLengthMM
    }

    public var isValid: Bool {
        (1...12).contains(contactRows)
            && (1...12).contains(contactColumns)
            && horizontalSpacingMM.isFinite
            && (0...25).contains(horizontalSpacingMM)
            && verticalSpacingMM.isFinite
            && (0...25).contains(verticalSpacingMM)
            && captionHeightMM.isFinite
            && (0...20).contains(captionHeightMM)
            && cropMarkLengthMM.isFinite
            && (1...10).contains(cropMarkLengthMM)
            && !customItems.isEmpty
            && customItems.count <= Self.maximumCustomItemCount
            && customItems.allSatisfy(Self.validCustomItem)
            && (mode != .customPackage || Self.hasContiguousCustomPages(customItems))
    }

    private static func hasContiguousCustomPages(_ items: [PrintCustomPackageItem]) -> Bool {
        guard let highestPage = items.map(\.pageIndex).max() else { return false }
        return Set(items.map(\.pageIndex)) == Set(0...highestPage)
    }

    private static func validCustomItem(_ item: PrintCustomPackageItem) -> Bool {
        let rect = item.normalizedRect
        return item.sourceIndex >= 0
            && (0..<maximumPageCount).contains(item.pageIndex)
            && item.zIndex >= 0
            && rect.origin.x.isFinite
            && rect.origin.y.isFinite
            && rect.width.isFinite
            && rect.height.isFinite
            && rect.minX >= 0
            && rect.minY >= 0
            && rect.width > 0
            && rect.height > 0
            && rect.maxX <= 1
            && rect.maxY <= 1
    }
}

public struct PrintPackageLineSegment: Equatable, Sendable {
    public let start: CGPoint
    public let end: CGPoint

    public init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
    }
}

public struct PrintPackageItemLayout: Equatable, Sendable {
    public let sourceIndex: Int
    public let cellRectPoints: CGRect
    public let destinationRectPoints: CGRect
    /// 회전 적용 뒤의 source 기준 0...1 crop. fit은 항상 unit rect다.
    public let sourceUnitCropRect: CGRect
    public let quarterTurns: Int
    public let captionRectPoints: CGRect?
    public let zIndex: Int

    public init(
        sourceIndex: Int,
        cellRectPoints: CGRect,
        destinationRectPoints: CGRect,
        sourceUnitCropRect: CGRect,
        quarterTurns: Int,
        captionRectPoints: CGRect?,
        zIndex: Int
    ) {
        self.sourceIndex = sourceIndex
        self.cellRectPoints = cellRectPoints
        self.destinationRectPoints = destinationRectPoints
        self.sourceUnitCropRect = sourceUnitCropRect
        self.quarterTurns = quarterTurns
        self.captionRectPoints = captionRectPoints
        self.zIndex = zIndex
    }
}

public struct PrintPackagePageLayout: Equatable, Sendable {
    public let pageIndex: Int
    public let canvasSizePoints: CGSize
    public let contentRectPoints: CGRect
    public let items: [PrintPackageItemLayout]
    public let cropMarkSegments: [PrintPackageLineSegment]

    public init(
        pageIndex: Int,
        canvasSizePoints: CGSize,
        contentRectPoints: CGRect,
        items: [PrintPackageItemLayout],
        cropMarkSegments: [PrintPackageLineSegment]
    ) {
        self.pageIndex = pageIndex
        self.canvasSizePoints = canvasSizePoints
        self.contentRectPoints = contentRectPoints
        self.items = items
        self.cropMarkSegments = cropMarkSegments
    }
}
