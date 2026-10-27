import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO

/// 사진에 촬영 정보 띠를 더한 한 장을 만든다. 화면 미리보기와 내보내기가 이 한 함수를 쓴다.
///
/// 사진 화소는 정수 위치에 그대로 얹으므로 원래 값이 바뀌지 않는다. 글자·로고·히스토그램은 띠 크기의
/// 비트맵에만 그려 큰 사진에서도 메모리를 띠 넓이만큼만 쓴다.
public enum PrintWatermarkRenderer {
    /// - Parameters:
    ///   - photo: 공정 겉모습까지 적용한 사진.
    ///   - reference: 블러 바탕과 히스토그램에 쓸 작은 이미지(필름스트립 썸네일, 같은 겉모습 적용).
    ///     없으면 사진을 줄여 쓴다. 큰 사진을 블러·히스토그램용으로 다시 줄이는 일을 덜어 준다.
    ///   - context: 히스토그램을 셀 때 쓰는 공유 context.
    /// - Returns: 원점이 (0, 0) 인 띠 포함 이미지. 설정이 잘못됐으면 nil.
    public static func compose(
        photo: CIImage,
        settings: PrintWatermarkSettings,
        reference: CIImage? = nil,
        context: CIContext
    ) -> CIImage? {
        let source = normalized(photo)
        guard let layout = PrintWatermarkFrameLayout.make(
            imageSize: source.extent.size,
            settings: settings
        ) else { return nil }
        let frameRect = CGRect(origin: .zero, size: layout.frameSize)
        // 썸네일이 사진과 같은 비율(같은 회전·자르기)일 때만 대신 쓴다. 다르면 오래된 썸네일이다.
        let sample = reference.map(normalized).flatMap { reference in
            abs(reference.extent.width / reference.extent.height
                - source.extent.width / source.extent.height) < 0.02 ? reference : nil
        } ?? source
        var result = background(for: sample, settings: settings, frameSize: layout.frameSize)
        result = source
            .transformed(by: CGAffineTransform(translationX: 0, y: layout.imageRect.minY))
            .composited(over: result)

        let needsHistogram = settings.showsHistogram
        let histogram = needsHistogram
            ? PrintWatermarkHistogram.columns(of: sample, context: context)
            : nil
        let logo = settings.logoPNGData.flatMap(decodeLogo)
        let content = BandContent(settings: settings, histogram: histogram, logo: logo)

        if let bottom = bandImage(
            size: layout.bottomBand.size,
            draw: { context, band in drawBottomBand(content, in: context, size: band) }
        ) {
            result = bottom.composited(over: result)
        }
        if let topBand = layout.topBand,
           content.hasTopItems,
           let top = bandImage(
               size: topBand.size,
               draw: { context, band in drawTopBand(content, in: context, size: band) }
           ) {
            result = top
                .transformed(by: CGAffineTransform(translationX: 0, y: topBand.minY))
                .composited(over: result)
        }
        return result.cropped(to: frameRect)
    }

    /// 로고 파일(jpg·png·heic 등)을 띠에 그릴 PNG로 바꾸고 긴 변을 `maximumLogoPixels`로 줄인다.
    /// 이 데이터는 그릴 때만 쓰며 설정과 템플릿에는 경로만 저장한다. 열 수 없거나 너무 크면 nil.
    public static let maximumLogoPixels = 1_024

    public static func normalizedLogoPNG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumLogoPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, "public.png" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination),
              output.length <= PrintWatermarkSettings.maximumLogoBytes else { return nil }
        return output as Data
    }

    // MARK: - 바탕

    private static func background(
        for photo: CIImage,
        settings: PrintWatermarkSettings,
        frameSize: CGSize
    ) -> CIImage {
        let frameRect = CGRect(origin: .zero, size: frameSize)
        switch settings.background {
        case .white:
            return CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: frameRect)
        case .black:
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: frameRect)
        case .blur:
            // 해상도와 무관하게 같은 모양이 되도록 정해진 긴 변까지 줄여 흐린 뒤 띠 전체를 채운다.
            let extent = photo.extent
            let scale = min(1, PrintWatermarkMetrics.blurWorkingLongEdge / max(extent.width, extent.height))
            let small = scale < 1
                ? photo.applyingFilter(
                    "CILanczosScaleTransform",
                    parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1]
                )
                : photo
            let blurred = small.clampedToExtent()
                .applyingGaussianBlur(sigma: PrintWatermarkMetrics.blurSigma)
                .cropped(to: small.extent)
            let fill = max(
                frameSize.width / blurred.extent.width,
                frameSize.height / blurred.extent.height
            )
            let scaled = blurred.clampedToExtent()
                .transformed(by: CGAffineTransform(scaleX: fill, y: fill))
            let offset = CGAffineTransform(
                translationX: (frameSize.width - blurred.extent.width * fill) / 2
                    - blurred.extent.minX * fill,
                y: (frameSize.height - blurred.extent.height * fill) / 2
                    - blurred.extent.minY * fill
            )
            return scaled.transformed(by: offset).cropped(to: frameRect)
        }
    }

    // MARK: - 띠 내용

    private struct Palette {
        let primary: CGColor
        let secondary: CGColor

        init(_ ink: PrintWatermarkInk) {
            switch ink {
            case .black:
                // 흰 바탕: 굵은 줄은 검정, 둘째 줄은 회색.
                primary = CGColor(srgbRed: 0.07, green: 0.07, blue: 0.07, alpha: 1)
                secondary = CGColor(srgbRed: 0.53, green: 0.53, blue: 0.53, alpha: 1)
            case .white:
                // 검정 바탕: 모두 흰색.
                primary = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
                secondary = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            }
        }
    }

    private struct BandContent {
        let settings: PrintWatermarkSettings
        let histogram: [Double]?
        let logo: CGImage?
        let text: Palette
        let histogramColor: CGColor

        init(settings: PrintWatermarkSettings, histogram: [Double]?, logo: CGImage?) {
            self.settings = settings
            self.histogram = histogram
            self.logo = logo
            text = Palette(settings.textInk)
            histogramColor = Palette(settings.histogramInk).primary
        }

        var userName: String { settings.userName.trimmingCharacters(in: .whitespacesAndNewlines) }

        func showsHistogram(at placement: PrintWatermarkPlacement) -> Bool {
            settings.showsHistogram && histogram != nil
                && settings.effectivePlacement(settings.histogramPlacement) == placement
        }

        func showsUserName(at placement: PrintWatermarkPlacement) -> Bool {
            !userName.isEmpty && settings.effectivePlacement(settings.userNamePlacement) == placement
        }

        var hasTopItems: Bool {
            [PrintWatermarkPlacement.topLeading, .topCenter, .topTrailing].contains {
                showsHistogram(at: $0) || showsUserName(at: $0)
            }
        }
    }

    /// CoreText 한 줄과 그 치수.
    private struct TextLine {
        let line: CTLine
        let width: CGFloat
        let ascent: CGFloat
        let descent: CGFloat

        init?(_ text: String, fontName: String, size: CGFloat, color: CGColor) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, size > 0 else { return nil }
            let font = CTFontCreateWithName(fontName as CFString, size, nil)
            let attributes: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: color,
            ]
            guard let attributed = CFAttributedStringCreate(
                nil, trimmed as CFString, attributes as CFDictionary
            ) else { return nil }
            line = CTLineCreateWithAttributedString(attributed)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            self.ascent = ascent
            self.descent = descent
        }

        var height: CGFloat { ascent + descent }

        func draw(in context: CGContext, x: CGFloat, baseline: CGFloat) {
            context.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(line, context)
        }
    }

    private static let boldFontName = "HelveticaNeue-Bold"
    private static let regularFontName = "HelveticaNeue"

    /// 굵은 줄 + 보조 줄 두 줄 묶음. 한 줄만 있으면 그 줄을 가운데에 둔다.
    private struct TwoLineBlock {
        let first: TextLine?
        let second: TextLine?
        let gap: CGFloat

        init(first: String, second: String, band: CGFloat, scale: CGFloat, palette: Palette) {
            self.first = TextLine(
                first,
                fontName: PrintWatermarkRenderer.boldFontName,
                size: PrintWatermarkMetrics.primaryFontSize * band * scale,
                color: palette.primary
            )
            self.second = TextLine(
                second,
                fontName: PrintWatermarkRenderer.regularFontName,
                size: PrintWatermarkMetrics.secondaryFontSize * band * scale,
                color: palette.secondary
            )
            gap = PrintWatermarkMetrics.lineGap * band * scale
        }

        var width: CGFloat { max(first?.width ?? 0, second?.width ?? 0) }
        var isEmpty: Bool { first == nil && second == nil }

        func draw(in context: CGContext, x: CGFloat, bandHeight: CGFloat) {
            switch (first, second) {
            case let (first?, second?):
                let height = first.height + gap + second.height
                let top = (bandHeight + height) / 2
                first.draw(in: context, x: x, baseline: top - first.ascent)
                second.draw(in: context, x: x, baseline: top - first.height - gap - second.ascent)
            case let (line?, nil), let (nil, line?):
                line.draw(in: context, x: x, baseline: (bandHeight - line.height) / 2 + line.descent)
            case (nil, nil):
                break
            }
        }
    }

    /// 한 자리(아래 가운데·위 왼쪽·위 가운데·위 오른쪽)에 놓이는 히스토그램과 이름.
    ///
    /// 가운데 자리에 둘이 함께 있으면 가운데 축을 기준으로 데칼코마니처럼 놓는다: 히스토그램은 축
    /// 왼쪽, 이름은 축 오른쪽에 같은 간격으로 붙는다. 왼쪽·오른쪽 자리는 히스토그램 다음에 이름을 잇는다.
    private struct SlotItems {
        let histogram: [Double]?
        let histogramSize: CGSize
        let name: TextLine?
        let gap: CGFloat
        let histogramColor: CGColor
        let isCentered: Bool

        init(
            content: BandContent,
            placement: PrintWatermarkPlacement,
            band: CGFloat,
            scale: CGFloat
        ) {
            histogram = content.showsHistogram(at: placement) ? content.histogram : nil
            histogramSize = CGSize(
                width: PrintWatermarkMetrics.histogramWidth * band * scale,
                height: PrintWatermarkMetrics.histogramHeight * band * scale
            )
            name = content.showsUserName(at: placement)
                ? TextLine(
                    content.userName,
                    fontName: PrintWatermarkRenderer.regularFontName,
                    size: PrintWatermarkMetrics.secondaryFontSize * band * scale,
                    color: content.text.primary
                )
                : nil
            gap = PrintWatermarkMetrics.itemGap * band * scale
            histogramColor = content.histogramColor
            isCentered = placement.isCenter
        }

        var isEmpty: Bool { histogram == nil && name == nil }

        private var histogramWidth: CGFloat { histogram == nil ? 0 : histogramSize.width }
        private var nameWidth: CGFloat { name?.width ?? 0 }
        private var hasBoth: Bool { histogram != nil && name != nil }

        /// 차지하는 폭. 가운데 대칭 배치는 넓은 쪽이 축 양옆으로 같은 만큼 뻗는다고 보고 잰다.
        var width: CGFloat {
            if isCentered && hasBoth {
                return 2 * max(histogramWidth, nameWidth) + gap
            }
            return histogramWidth + nameWidth + (hasBoth ? gap : 0)
        }

        /// 왼쪽 끝 `x` 에서 시작해 늘어놓는다(위 왼쪽·위 오른쪽 자리).
        func draw(in context: CGContext, x: CGFloat, bandHeight: CGFloat) {
            drawHistogram(in: context, x: x, bandHeight: bandHeight)
            drawName(in: context, x: x + (histogram == nil ? 0 : histogramSize.width + gap), bandHeight: bandHeight)
        }

        /// 가운데 축 `centerX` 를 기준으로 놓는다. 둘이면 축 양옆에 같은 간격으로 붙인다.
        func drawCentered(in context: CGContext, centerX: CGFloat, bandHeight: CGFloat) {
            if hasBoth {
                drawHistogram(in: context, x: centerX - gap / 2 - histogramWidth, bandHeight: bandHeight)
                drawName(in: context, x: centerX + gap / 2, bandHeight: bandHeight)
            } else {
                drawHistogram(in: context, x: centerX - histogramWidth / 2, bandHeight: bandHeight)
                drawName(in: context, x: centerX - nameWidth / 2, bandHeight: bandHeight)
            }
        }

        private func drawHistogram(in context: CGContext, x: CGFloat, bandHeight: CGFloat) {
            guard let histogram else { return }
            PrintWatermarkRenderer.drawHistogram(
                histogram,
                in: context,
                rect: CGRect(
                    x: x,
                    y: (bandHeight - histogramSize.height) / 2,
                    width: histogramSize.width,
                    height: histogramSize.height
                ),
                color: histogramColor
            )
        }

        private func drawName(in context: CGContext, x: CGFloat, bandHeight: CGFloat) {
            guard let name else { return }
            name.draw(in: context, x: x, baseline: (bandHeight - name.height) / 2 + name.descent)
        }
    }

    /// 로고 + 세로선 + 노출·일시 두 줄. 로고나 글 한쪽만 있으면 세로선은 그리지 않는다.
    private struct TrailingBlock {
        let logo: CGImage?
        let logoSize: CGSize
        let text: TwoLineBlock
        let separatorGap: CGFloat
        let separatorSize: CGSize
        let separatorColor: CGColor

        init(content: BandContent, band: CGFloat, scale: CGFloat) {
            logo = content.logo
            if let logo, logo.width > 0, logo.height > 0 {
                let aspect = CGFloat(logo.width) / CGFloat(logo.height)
                let height = PrintWatermarkMetrics.logoHeight * band * scale
                let width = min(PrintWatermarkMetrics.logoMaximumWidth * band * scale, height * aspect)
                logoSize = CGSize(width: width, height: width / aspect)
            } else {
                logoSize = .zero
            }
            text = TwoLineBlock(
                first: content.settings.exposureLine,
                second: content.settings.captureDate,
                band: band,
                scale: scale,
                palette: content.text
            )
            separatorGap = PrintWatermarkMetrics.separatorGap * band * scale
            separatorSize = CGSize(
                width: max(1, (0.012 * band).rounded()),
                height: PrintWatermarkMetrics.separatorHeight * band * scale
            )
            separatorColor = content.text.secondary
        }

        private var hasLogo: Bool { logo != nil && logoSize.width > 0 }
        private var hasSeparator: Bool { hasLogo && !text.isEmpty }

        var width: CGFloat {
            (hasLogo ? logoSize.width : 0)
                + (hasSeparator ? 2 * separatorGap + separatorSize.width : 0)
                + text.width
        }

        var isEmpty: Bool { !hasLogo && text.isEmpty }

        func draw(in context: CGContext, trailingEdge: CGFloat, bandHeight: CGFloat) {
            var cursor = trailingEdge - width
            if let logo, hasLogo {
                context.interpolationQuality = .high
                context.draw(logo, in: CGRect(
                    x: cursor,
                    y: (bandHeight - logoSize.height) / 2,
                    width: logoSize.width,
                    height: logoSize.height
                ))
                cursor += logoSize.width
            }
            if hasSeparator {
                cursor += separatorGap
                context.setFillColor(separatorColor)
                context.fill(CGRect(
                    x: cursor.rounded(),
                    y: (bandHeight - separatorSize.height) / 2,
                    width: separatorSize.width,
                    height: separatorSize.height
                ))
                cursor += separatorSize.width + separatorGap
            }
            text.draw(in: context, x: cursor, bandHeight: bandHeight)
        }
    }

    /// 아래 띠: 왼쪽 카메라·렌즈, 오른쪽 로고·노출·일시, 가운데 히스토그램·이름.
    private static func drawBottomBand(_ content: BandContent, in context: CGContext, size: CGSize) {
        let band = size.height
        let inset = PrintWatermarkMetrics.horizontalInset * band
        let gap = PrintWatermarkMetrics.itemGap * band
        let available = size.width - 2 * inset
        guard available > 0 else { return }

        func parts(_ scale: CGFloat) -> (TwoLineBlock, TrailingBlock, SlotItems) {
            (
                TwoLineBlock(
                    first: content.settings.cameraName,
                    second: content.settings.lensName,
                    band: band,
                    scale: scale,
                    palette: content.text
                ),
                TrailingBlock(content: content, band: band, scale: scale),
                SlotItems(content: content, placement: .bottomCenter, band: band, scale: scale)
            )
        }
        let natural = parts(1)
        let needed = natural.2.isEmpty
            ? natural.0.width + natural.1.width + gap
            : 2 * max(natural.0.width, natural.1.width) + natural.2.width + 2 * gap
        let scale = fitScale(available: available, needed: needed)
        let (leading, trailing, center) = scale < 1 ? parts(scale) : natural

        leading.draw(in: context, x: inset, bandHeight: band)
        if !trailing.isEmpty {
            trailing.draw(in: context, trailingEdge: size.width - inset, bandHeight: band)
        }
        if !center.isEmpty {
            center.drawCentered(in: context, centerX: size.width / 2, bandHeight: band)
        }
    }

    /// 위 띠: 왼쪽·가운데·오른쪽 자리.
    private static func drawTopBand(_ content: BandContent, in context: CGContext, size: CGSize) {
        let band = size.height
        let inset = PrintWatermarkMetrics.horizontalInset * band
        let gap = PrintWatermarkMetrics.itemGap * band
        let available = size.width - 2 * inset
        guard available > 0 else { return }

        func parts(_ scale: CGFloat) -> (SlotItems, SlotItems, SlotItems) {
            (
                SlotItems(content: content, placement: .topLeading, band: band, scale: scale),
                SlotItems(content: content, placement: .topCenter, band: band, scale: scale),
                SlotItems(content: content, placement: .topTrailing, band: band, scale: scale)
            )
        }
        let natural = parts(1)
        let needed = natural.1.isEmpty
            ? natural.0.width + natural.2.width + gap
            : 2 * max(natural.0.width, natural.2.width) + natural.1.width + 2 * gap
        let scale = fitScale(available: available, needed: needed)
        let (leading, center, trailing) = scale < 1 ? parts(scale) : natural
        leading.draw(in: context, x: inset, bandHeight: band)
        center.drawCentered(in: context, centerX: size.width / 2, bandHeight: band)
        trailing.draw(in: context, x: size.width - inset - trailing.width, bandHeight: band)
    }

    private static func fitScale(available: CGFloat, needed: CGFloat) -> CGFloat {
        guard needed > available, needed > 0 else { return 1 }
        return max(PrintWatermarkMetrics.minimumFitScale, available / needed)
    }

    /// 점으로 된 세로 막대: 열마다 값에 비례한 개수의 점을 아래에서부터 쌓는다. 비어 있는 자리도 옅은
    /// 점으로 찍어 격자 전체가 보이게 한다 — 분포가 한쪽에 몰린 사진에서도 그래프의 폭과 위치가 읽힌다.
    private static func drawHistogram(
        _ values: [Double],
        in context: CGContext,
        rect: CGRect,
        color: CGColor
    ) {
        guard !values.isEmpty, rect.width > 0, rect.height > 0 else { return }
        let rows = PrintWatermarkMetrics.histogramRows
        let pitchX = rect.width / CGFloat(values.count)
        let pitchY = rect.height / CGFloat(rows)
        let diameter = min(pitchX, pitchY) * PrintWatermarkMetrics.histogramDotFill
        let faint = color.copy(alpha: PrintWatermarkMetrics.histogramEmptyDotAlpha) ?? color
        for (column, value) in values.enumerated() {
            let lit = value > 0 ? min(rows, max(1, Int((value * Double(rows)).rounded()))) : 0
            let centerX = rect.minX + (CGFloat(column) + 0.5) * pitchX
            for row in 0..<rows {
                let centerY = rect.minY + (CGFloat(row) + 0.5) * pitchY
                context.setFillColor(row < lit ? color : faint)
                context.fillEllipse(in: CGRect(
                    x: centerX - diameter / 2,
                    y: centerY - diameter / 2,
                    width: diameter,
                    height: diameter
                ))
            }
        }
    }

    // MARK: - 도우미

    private static func bandImage(
        size: CGSize,
        draw: (CGContext, CGSize) -> Void
    ) -> CIImage? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false)
        draw(context, CGSize(width: width, height: height))
        return context.makeImage().map { CIImage(cgImage: $0) }
    }

    private static func decodeLogo(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func normalized(_ image: CIImage) -> CIImage {
        guard image.extent.origin != .zero else { return image }
        return image.transformed(by: CGAffineTransform(
            translationX: -image.extent.minX,
            y: -image.extent.minY
        ))
    }
}
