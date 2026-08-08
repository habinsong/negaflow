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
    case sequenceNumber
    case rating
    case customText
}

public enum PrintPackageCaptionAlignment: String, CaseIterable, Codable, Sendable {
    case leading
    case center
    case trailing
}

/// 인화 시트(콘택트 시트·픽처 패키지·커스텀)의 용지 색. 이름은 저장 키 호환을 위해 유지한다.
public enum PrintContactSheetBackground: String, CaseIterable, Codable, Sendable {
    case black
    case gray
    case white

    /// 종이 위에 올릴 글자·크롭마크가 밝아야 하는가.
    public var prefersLightForeground: Bool {
        self != .white
    }
}

/// `normalizedRect`는 전체 용지 기준이며 Quartz 좌표계(좌하단 원점)다.
public struct PrintPackageCustomCaption: Codable, Equatable, Sendable {
    public var text: String
    public var normalizedRect: CGRect
    public var alignment: PrintPackageCaptionAlignment

    public init(
        text: String,
        normalizedRect: CGRect,
        alignment: PrintPackageCaptionAlignment = .leading
    ) {
        self.text = text
        self.normalizedRect = normalizedRect
        self.alignment = alignment
    }
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
    public static let maximumCustomCaptionCount = 32
    public static let maximumPageCount = 32

    public var mode: PrintPackageLayoutMode
    public var contactRows: Int
    public var contactColumns: Int
    public var horizontalSpacingMM: Double
    public var verticalSpacingMM: Double
    public var contentMode: PrintPackageContentMode
    public var rotateToFit: Bool
    public var repeatOnePhotoPerPage: Bool
    /// 켜면 시트에 올라간 모든 사진을 같은 방향(앱의 스캔 기본 방향)으로 돌려 배치한다.
    /// 프레임 자체의 방향은 건드리지 않는다 — 이 시트에서만 보이는 배치다.
    public var normalizesSourceOrientation: Bool
    public var pictureTemplate: PrintPicturePackageTemplate
    public var customItems: [PrintCustomPackageItem]
    public var contactSheetBackground: PrintContactSheetBackground
    public var captionMode: PrintPackageCaptionMode
    public var captionFontName: String
    public var captionAlignment: PrintPackageCaptionAlignment
    public var customCaptions: [PrintPackageCustomCaption]
    public var captionHeightMM: Double
    public var showsCropMarks: Bool
    public var cropMarkLengthMM: Double

    public init(
        mode: PrintPackageLayoutMode = .contactSheet,
        contactRows: Int = 7,
        contactColumns: Int = 6,
        horizontalSpacingMM: Double = 2,
        verticalSpacingMM: Double = 2,
        contentMode: PrintPackageContentMode = .fit,
        rotateToFit: Bool = false,
        repeatOnePhotoPerPage: Bool = false,
        normalizesSourceOrientation: Bool = false,
        pictureTemplate: PrintPicturePackageTemplate = .oneLargeTwoSmall,
        customItems: [PrintCustomPackageItem] = [
            PrintCustomPackageItem(
                sourceIndex: 0,
                normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1)
            ),
        ],
        contactSheetBackground: PrintContactSheetBackground = .black,
        captionMode: PrintPackageCaptionMode = .none,
        captionFontName: String = "Helvetica",
        captionAlignment: PrintPackageCaptionAlignment = .leading,
        customCaptions: [PrintPackageCustomCaption] = [
            PrintPackageCustomCaption(
                text: "",
                normalizedRect: CGRect(x: 0.05, y: 0.02, width: 0.9, height: 0.05),
                alignment: .center
            ),
        ],
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
        self.normalizesSourceOrientation = normalizesSourceOrientation
        self.pictureTemplate = pictureTemplate
        self.customItems = customItems
        self.contactSheetBackground = contactSheetBackground
        self.captionMode = captionMode
        self.captionFontName = captionFontName
        self.captionAlignment = captionAlignment
        self.customCaptions = customCaptions
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
            && !captionFontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && captionFontName.utf8.count <= 256
            && cropMarkLengthMM.isFinite
            && (1...10).contains(cropMarkLengthMM)
            && !customCaptions.isEmpty
            && customCaptions.count <= Self.maximumCustomCaptionCount
            && customCaptions.allSatisfy(Self.validCustomCaption)
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

    private static func validCustomCaption(_ caption: PrintPackageCustomCaption) -> Bool {
        let rect = caption.normalizedRect
        return caption.text.utf8.count <= 512
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

    private enum CodingKeys: String, CodingKey {
        case mode
        case contactRows
        case contactColumns
        case horizontalSpacingMM
        case verticalSpacingMM
        case contentMode
        case rotateToFit
        case repeatOnePhotoPerPage
        case normalizesSourceOrientation
        case pictureTemplate
        case customItems
        case contactSheetBackground
        case captionMode
        case captionFontName
        case captionAlignment
        case customCaptions
        case captionHeightMM
        case showsCropMarks
        case cropMarkLengthMM
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(PrintPackageLayoutMode.self, forKey: .mode)
        contactRows = try container.decode(Int.self, forKey: .contactRows)
        contactColumns = try container.decode(Int.self, forKey: .contactColumns)
        horizontalSpacingMM = try container.decode(Double.self, forKey: .horizontalSpacingMM)
        verticalSpacingMM = try container.decode(Double.self, forKey: .verticalSpacingMM)
        contentMode = try container.decode(PrintPackageContentMode.self, forKey: .contentMode)
        rotateToFit = try container.decode(Bool.self, forKey: .rotateToFit)
        repeatOnePhotoPerPage = try container.decode(Bool.self, forKey: .repeatOnePhotoPerPage)
        normalizesSourceOrientation = try container.decodeIfPresent(
            Bool.self,
            forKey: .normalizesSourceOrientation
        ) ?? false
        pictureTemplate = try container.decode(
            PrintPicturePackageTemplate.self,
            forKey: .pictureTemplate
        )
        customItems = try container.decode([PrintCustomPackageItem].self, forKey: .customItems)
        contactSheetBackground = try container.decodeIfPresent(
            PrintContactSheetBackground.self,
            forKey: .contactSheetBackground
        ) ?? .black
        captionMode = try container.decode(PrintPackageCaptionMode.self, forKey: .captionMode)
        captionFontName = try container.decodeIfPresent(
            String.self,
            forKey: .captionFontName
        ) ?? "Helvetica"
        captionAlignment = try container.decodeIfPresent(
            PrintPackageCaptionAlignment.self,
            forKey: .captionAlignment
        ) ?? .leading
        customCaptions = try container.decodeIfPresent(
            [PrintPackageCustomCaption].self,
            forKey: .customCaptions
        ) ?? [
            PrintPackageCustomCaption(
                text: "",
                normalizedRect: CGRect(x: 0.05, y: 0.02, width: 0.9, height: 0.05),
                alignment: .center
            ),
        ]
        captionHeightMM = try container.decode(Double.self, forKey: .captionHeightMM)
        showsCropMarks = try container.decode(Bool.self, forKey: .showsCropMarks)
        cropMarkLengthMM = try container.decode(Double.self, forKey: .cropMarkLengthMM)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(contactRows, forKey: .contactRows)
        try container.encode(contactColumns, forKey: .contactColumns)
        try container.encode(horizontalSpacingMM, forKey: .horizontalSpacingMM)
        try container.encode(verticalSpacingMM, forKey: .verticalSpacingMM)
        try container.encode(contentMode, forKey: .contentMode)
        try container.encode(rotateToFit, forKey: .rotateToFit)
        try container.encode(repeatOnePhotoPerPage, forKey: .repeatOnePhotoPerPage)
        try container.encode(normalizesSourceOrientation, forKey: .normalizesSourceOrientation)
        try container.encode(pictureTemplate, forKey: .pictureTemplate)
        try container.encode(customItems, forKey: .customItems)
        try container.encode(contactSheetBackground, forKey: .contactSheetBackground)
        try container.encode(captionMode, forKey: .captionMode)
        try container.encode(captionFontName, forKey: .captionFontName)
        try container.encode(captionAlignment, forKey: .captionAlignment)
        try container.encode(customCaptions, forKey: .customCaptions)
        try container.encode(captionHeightMM, forKey: .captionHeightMM)
        try container.encode(showsCropMarks, forKey: .showsCropMarks)
        try container.encode(cropMarkLengthMM, forKey: .cropMarkLengthMM)
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

public struct PrintPackageTextLayout: Equatable, Sendable {
    public let text: String
    public let rectPoints: CGRect
    public let alignment: PrintPackageCaptionAlignment

    public init(
        text: String,
        rectPoints: CGRect,
        alignment: PrintPackageCaptionAlignment
    ) {
        self.text = text
        self.rectPoints = rectPoints
        self.alignment = alignment
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
    public let textItems: [PrintPackageTextLayout]

    public init(
        pageIndex: Int,
        canvasSizePoints: CGSize,
        contentRectPoints: CGRect,
        items: [PrintPackageItemLayout],
        cropMarkSegments: [PrintPackageLineSegment],
        textItems: [PrintPackageTextLayout] = []
    ) {
        self.pageIndex = pageIndex
        self.canvasSizePoints = canvasSizePoints
        self.contentRectPoints = contentRectPoints
        self.items = items
        self.cropMarkSegments = cropMarkSegments
        self.textItems = textItems
    }
}
