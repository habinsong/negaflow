import CoreGraphics
import CoreImage
import Foundation

public enum PrintPaperSize: String, CaseIterable, Codable, Sendable {
    case fourBySix
    case fiveBySeven
    case eightByTen
    case a4
    /// 사진과 같은 비율의 용지. 실제 치수는 사진의 가로세로비에서 만든다(긴 변 10 in 고정).
    case photoRatio

    /// 사진 비율 용지의 긴 변.
    public static let photoRatioLongEdgeMM: Double = 254

    public var dimensionsMM: CGSize {
        switch self {
        case .fourBySix: CGSize(width: 101.6, height: 152.4)
        case .fiveBySeven: CGSize(width: 127, height: 177.8)
        case .eightByTen: CGSize(width: 203.2, height: 254)
        case .a4: CGSize(width: 210, height: 297)
        case .photoRatio: CGSize(width: Self.photoRatioLongEdgeMM * 2 / 3, height: Self.photoRatioLongEdgeMM)
        }
    }

    /// 사진 비율(가로/세로)에서 용지 치수를 만든다. 비율을 모르면 3:2 로 둔다.
    public func dimensionsMM(photoAspectRatio: Double?) -> CGSize {
        guard self == .photoRatio,
              let photoAspectRatio,
              photoAspectRatio.isFinite,
              photoAspectRatio > 0 else { return dimensionsMM }
        let longEdge = Self.photoRatioLongEdgeMM
        return photoAspectRatio >= 1
            ? CGSize(width: longEdge, height: longEdge / photoAspectRatio)
            : CGSize(width: longEdge * photoAspectRatio, height: longEdge)
    }

    public var uiLabel: String {
        switch self {
        case .fourBySix: "4 × 6 in"
        case .fiveBySeven: "5 × 7 in"
        case .eightByTen: "8 × 10 in"
        case .a4: "A4"
        case .photoRatio: "Photo"
        }
    }
}

public enum PrintPaperOrientation: String, CaseIterable, Codable, Sendable {
    case automatic
    case portrait
    case landscape
}

public enum PrintPerforationStyle: String, CaseIterable, Codable, Sendable {
    case none
    case thirtyFiveMillimeter
}

/// 인화 레이아웃이 사진에 적용하는 고정 표현 방식.
///
/// 측정 프로파일을 대신하는 장치 정확도 시뮬레이션이 아니라, 공정의 핵심 시각 특성만
/// 화면과 파일에 동일하게 적용한다.
public enum PrintPresentationStyle: String, CaseIterable, Codable, Sendable {
    case standard
    case cyanotype
    case glassPlate
    case gelatinSilver
}

public struct PrintPresentationAppearance: Equatable, Sendable {
    public let shadowRGBA: SIMD4<Double>
    public let highlightRGBA: SIMD4<Double>

    public init(style: PrintPresentationStyle) {
        switch style {
        case .standard:
            shadowRGBA = SIMD4(0, 0, 0, 1)
            highlightRGBA = SIMD4(1, 1, 1, 1)
        case .cyanotype:
            // 시아노타입의 철염 이미지가 갖는 청색 단색 관계만 표현한다.
            shadowRGBA = SIMD4(0.02, 0.10, 0.36, 1)
            highlightRGBA = SIMD4(0.96, 0.98, 1, 1)
        case .glassPlate:
            shadowRGBA = SIMD4(0, 0, 0, 1)
            highlightRGBA = SIMD4(1, 1, 1, 1)
        case .gelatinSilver:
            shadowRGBA = SIMD4(0, 0, 0, 1)
            highlightRGBA = SIMD4(1, 1, 1, 1)
        }
    }
}

public struct PrintFilmStripAppearance: Equatable, Sendable {
    public let baseRGBA: SIMD4<Double>

    public init(filmType: FilmType) {
        switch filmType {
        case .colorNegative:
            // 현상된 컬러 네거티브의 마스크가 남은 비노광 가장자리.
            baseRGBA = SIMD4(0.44, 0.17, 0.055, 0.92)
        case .bwNegative:
            // 흑백 네거티브의 중성 회색 투명 베이스.
            baseRGBA = SIMD4(0.12, 0.12, 0.12, 0.84)
        case .colorPositive:
            // 컬러 리버설의 비노광 가장자리는 거의 불투명한 흑색이다.
            baseRGBA = SIMD4(0.025, 0.032, 0.042, 0.97)
        case .bwPositive:
            // 흑백 리버설의 비노광 가장자리는 중성 흑색이다.
            baseRGBA = SIMD4(0.022, 0.022, 0.022, 0.97)
        }
    }
}

public struct PrintCompositionSettings: Codable, Equatable, Sendable {
    public var paperSize: PrintPaperSize
    public var orientation: PrintPaperOrientation
    public var marginMM: Double
    public var dpi: Int
    public var perforationStyle: PrintPerforationStyle
    /// `photoRatio` 용지가 따라갈 사진의 가로/세로비. 다른 용지에서는 무시된다.
    public var photoAspectRatio: Double?
    public var presentationStyle: PrintPresentationStyle

    public init(
        paperSize: PrintPaperSize = .a4,
        orientation: PrintPaperOrientation = .automatic,
        marginMM: Double = 10,
        dpi: Int = 300,
        perforationStyle: PrintPerforationStyle = .none,
        photoAspectRatio: Double? = nil,
        presentationStyle: PrintPresentationStyle = .standard
    ) {
        self.paperSize = paperSize
        self.orientation = orientation
        self.marginMM = marginMM
        self.dpi = dpi
        self.perforationStyle = perforationStyle
        self.photoAspectRatio = photoAspectRatio
        self.presentationStyle = presentationStyle
    }

    /// 이 설정이 쓰는 실제 용지 치수.
    public var paperDimensionsMM: CGSize {
        paperSize.dimensionsMM(photoAspectRatio: photoAspectRatio)
    }

    public var isValid: Bool {
        marginMM.isFinite && (0...50).contains(marginMM) && (72...600).contains(dpi)
    }

    private enum CodingKeys: String, CodingKey {
        case paperSize
        case orientation
        case marginMM
        case dpi
        case perforationStyle
        case photoAspectRatio
        case presentationStyle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paperSize = try container.decode(PrintPaperSize.self, forKey: .paperSize)
        orientation = try container.decode(PrintPaperOrientation.self, forKey: .orientation)
        marginMM = try container.decode(Double.self, forKey: .marginMM)
        dpi = try container.decode(Int.self, forKey: .dpi)
        perforationStyle = try container.decode(
            PrintPerforationStyle.self,
            forKey: .perforationStyle
        )
        photoAspectRatio = try container.decodeIfPresent(Double.self, forKey: .photoAspectRatio)
        presentationStyle = try container.decodeIfPresent(
            PrintPresentationStyle.self,
            forKey: .presentationStyle
        ) ?? .standard
    }
}

public struct PrintCompositionLayout: Equatable, Sendable {
    public let canvasSize: CGSize
    public let contentRect: CGRect
    public let imageRect: CGRect
    public let filmRect: CGRect?
    public let perforationRects: [CGRect]
    public let perforationCornerRadius: CGFloat

    public static func make(
        sourceSize: CGSize,
        settings: PrintCompositionSettings
    ) -> PrintCompositionLayout? {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              sourceSize.width.isFinite,
              sourceSize.height.isFinite,
              settings.isValid else { return nil }

        let sourceIsLandscape = sourceSize.width >= sourceSize.height
        let base = settings.paperDimensionsMM
        let pageMM: CGSize
        switch settings.orientation {
        case .automatic:
            pageMM = sourceIsLandscape
                ? CGSize(width: max(base.width, base.height), height: min(base.width, base.height))
                : CGSize(width: min(base.width, base.height), height: max(base.width, base.height))
        case .portrait:
            pageMM = CGSize(width: min(base.width, base.height), height: max(base.width, base.height))
        case .landscape:
            pageMM = CGSize(width: max(base.width, base.height), height: min(base.width, base.height))
        }

        let pixelsPerMM = CGFloat(settings.dpi) / 25.4
        let canvasSize = CGSize(
            width: max(1, (pageMM.width * pixelsPerMM).rounded()),
            height: max(1, (pageMM.height * pixelsPerMM).rounded())
        )
        let margin = CGFloat(settings.marginMM) * pixelsPerMM
        let contentRect = CGRect(origin: .zero, size: canvasSize).insetBy(dx: margin, dy: margin)
        guard contentRect.width > 1, contentRect.height > 1 else { return nil }

        if settings.perforationStyle == .none {
            return PrintCompositionLayout(
                canvasSize: canvasSize,
                contentRect: contentRect,
                imageRect: aspectFit(sourceSize, in: contentRect),
                filmRect: nil,
                perforationRects: [],
                perforationCornerRadius: 0
            )
        }

        let isLandscape = sourceSize.width >= sourceSize.height
        // ISO 1007의 135 풀프레임 기준: 35 mm 폭, 24 × 36 mm 이미지 게이트,
        // 프레임 피치 38 mm(4.75 mm KS-1870 천공 8개).
        let physicalFilmSizeMM = isLandscape
            ? CGSize(width: 38, height: 35)
            : CGSize(width: 35, height: 38)
        let filmRect = aspectFit(physicalFilmSizeMM, in: contentRect)
        let unit = isLandscape ? filmRect.height / 35 : filmRect.width / 35
        let gateSizeMM = isLandscape
            ? CGSize(width: 36, height: 24)
            : CGSize(width: 24, height: 36)
        let gateRect = CGRect(
            x: filmRect.midX - gateSizeMM.width * unit / 2,
            y: filmRect.midY - gateSizeMM.height * unit / 2,
            width: gateSizeMM.width * unit,
            height: gateSizeMM.height * unit
        )
        let imageRect = aspectFit(sourceSize, in: gateRect)

        let pitch = 4.75 * unit
        let railCenterOffset = 2.75 * unit
        var perforationRects: [CGRect] = []
        perforationRects.reserveCapacity(16)
        if isLandscape {
            let holeSize = CGSize(width: 2.79 * unit, height: 1.98 * unit)
            let occupiedWidth = 7 * pitch + holeSize.width
            let firstX = filmRect.midX - occupiedWidth / 2
            let bottomY = filmRect.minY + railCenterOffset - holeSize.height / 2
            let topY = filmRect.maxY - railCenterOffset - holeSize.height / 2
            for index in 0..<8 {
                let x = firstX + CGFloat(index) * pitch
                perforationRects.append(CGRect(origin: CGPoint(x: x, y: bottomY), size: holeSize))
                perforationRects.append(CGRect(origin: CGPoint(x: x, y: topY), size: holeSize))
            }
        } else {
            let holeSize = CGSize(width: 1.98 * unit, height: 2.79 * unit)
            let occupiedHeight = 7 * pitch + holeSize.height
            let firstY = filmRect.midY - occupiedHeight / 2
            let leftX = filmRect.minX + railCenterOffset - holeSize.width / 2
            let rightX = filmRect.maxX - railCenterOffset - holeSize.width / 2
            for index in 0..<8 {
                let y = firstY + CGFloat(index) * pitch
                perforationRects.append(CGRect(origin: CGPoint(x: leftX, y: y), size: holeSize))
                perforationRects.append(CGRect(origin: CGPoint(x: rightX, y: y), size: holeSize))
            }
        }

        return PrintCompositionLayout(
            canvasSize: canvasSize,
            contentRect: contentRect,
            imageRect: imageRect,
            filmRect: filmRect,
            perforationRects: perforationRects,
            perforationCornerRadius: 0.51 * unit
        )
    }

    private static func aspectFit(_ size: CGSize, in bounds: CGRect) -> CGRect {
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: bounds.midX - fitted.width / 2,
            y: bounds.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}

public enum PrintCompositionRenderer {
    public static func apply(
        to image: CIImage,
        settings: PrintCompositionSettings,
        filmType: FilmType = .colorPositive
    ) -> CIImage? {
        guard let layout = PrintCompositionLayout.make(
            sourceSize: image.extent.size,
            settings: settings
        ) else { return nil }

        let canvasRect = CGRect(origin: .zero, size: layout.canvasSize)
        let paper = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: canvasRect)
        var result = paper

        if let filmRect = layout.filmRect {
            let rgba = PrintFilmStripAppearance(filmType: filmType).baseRGBA
            let film = CIImage(color: CIColor(
                red: CGFloat(rgba.x),
                green: CGFloat(rgba.y),
                blue: CGFloat(rgba.z),
                alpha: CGFloat(rgba.w)
            ))
                .cropped(to: filmRect)
            result = film.composited(over: result)
        }

        let presented = PrintPresentationRenderer.apply(
            to: image,
            style: settings.presentationStyle
        )
        let placed = place(presented, in: layout.imageRect)
        result = placed.composited(over: result)

        for rect in layout.perforationRects {
            guard let hole = roundedRectangle(
                rect: rect,
                radius: layout.perforationCornerRadius,
                color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)
            ) else { return nil }
            result = hole.composited(over: result)
        }
        return result.cropped(to: canvasRect)
    }

    private static func roundedRectangle(
        rect: CGRect,
        radius: CGFloat,
        color: CIColor
    ) -> CIImage? {
        CIFilter(
            name: "CIRoundedRectangleGenerator",
            parameters: [
                "inputExtent": CIVector(cgRect: rect),
                "inputRadius": radius,
                kCIInputColorKey: color
            ]
        )?.outputImage?.cropped(to: rect)
    }

    private static func place(_ image: CIImage, in rect: CGRect) -> CIImage {
        let normalized = normalize(image)
        let scale = min(rect.width / normalized.extent.width, rect.height / normalized.extent.height)
        let scaled = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return scaled.transformed(by: CGAffineTransform(
            translationX: rect.midX - scaled.extent.midX,
            y: rect.midY - scaled.extent.midY
        ))
    }

    private static func normalize(_ image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.origin != .zero else { return image }
        return image.transformed(by: CGAffineTransform(
            translationX: -extent.minX,
            y: -extent.minY
        ))
    }
}

public enum PrintPresentationRenderer {
    /// 필터 그래프만 연결하고 여기서는 픽셀을 렌더하지 않는다. 최종 export의 공유 `CIContext`가
    /// 한 번에 평가하므로 중간 비트맵과 추가 디코드를 만들지 않는다.
    public static func apply(
        to image: CIImage,
        style: PrintPresentationStyle
    ) -> CIImage {
        switch style {
        case .standard:
            return image
        case .cyanotype:
            let palette = PrintPresentationAppearance(style: style)
            return monochrome(image).applyingFilter(
                "CIFalseColor",
                parameters: [
                    "inputColor0": ciColor(palette.shadowRGBA),
                    "inputColor1": ciColor(palette.highlightRGBA),
                ]
            )
        case .glassPlate:
            return monochrome(image).applyingFilter("CIColorInvert")
        case .gelatinSilver:
            return monochrome(image)
        }
    }

    private static func monochrome(_ image: CIImage) -> CIImage {
        image.applyingFilter(
            "CIColorControls",
            parameters: [kCIInputSaturationKey: 0]
        )
    }

    private static func ciColor(_ rgba: SIMD4<Double>) -> CIColor {
        CIColor(
            red: CGFloat(rgba.x),
            green: CGFloat(rgba.y),
            blue: CGFloat(rgba.z),
            alpha: CGFloat(rgba.w)
        )
    }
}
