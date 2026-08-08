import Foundation
import CoreImage
import CoreGraphics
import ImageIO

// MARK: - ExportEngine (plan §9.6, §8.3)
//
// JPEG 95% 기본 / 16bit TIFF 옵션 / Raw 보관. (plan §4.2)
// 출력은 sRGB로 변환 (plan §8.3 MVP).
// EXIF(scanner/dpi/film/software) 자동 주입.
public enum ExportEngine {
    // MARK: JPEG 크로마 서브샘플링
    //
    // Image I/O의 JPEG 인코더는 품질이 0.995 미만이면 4:2:0 크로마 서브샘플링을 쓴다(실측:
    // 0.99 → 4:2:0, 0.995 → 4:4:4). 색 해상도가 가로·세로 각각 절반이 되므로 채도 높은 미세
    // 디테일(간판·네온·컬러 그레인)의 경계가 뭉갠다. 휘도는 영향받지 않는다.
    //
    // 서브샘플링을 직접 끄는 공개 옵션이 없어 품질값으로만 제어할 수 있다. 고품질 구간을 고른
    // 사용자는 화질을 우선한 것이므로, 그 구간에서는 서브샘플링이 꺼지는 최소 품질로 올려
    // 인코드한다. 파일이 커지는 대신 색 해상도가 보존된다. 그 아래 구간은 사용자가 고른 값을
    // 그대로 쓴다 — 낮은 품질을 고른 의도는 용량 절감이기 때문이다.

    /// 4:4:4로 인코드되는 최소 품질(실측 임계값).
    public static let chromaSubsamplingFreeQuality = 0.995
    /// 이 값 이상을 고르면 서브샘플링 없이 인코드한다.
    public static let fullChromaQualityThreshold = 0.95

    /// 사용자가 고른 품질을 인코더에 넘길 값으로 변환한다.
    public static func encodedJPEGQuality(_ quality: Double) -> Double {
        guard quality.isFinite, quality >= fullChromaQualityThreshold else { return quality }
        return max(quality, chromaSubsamplingFreeQuality)
    }

    public static func write(_ image: CIImage, to url: URL, format: ExportFormat,
                             using context: CIContext, metadata: ExportMeta? = nil,
                             options: ExportOptions = .standard,
                             outputProfile: ICCOutputProfileSnapshot? = nil) throws {
        try options.validate(for: format)
        let outputColorSpace: CGColorSpace
        if format == .rawScanTIFF {
            guard outputProfile == nil else {
                throw ChromabaseError.writeFailed("invalid printer output ICC profile")
            }
            outputColorSpace = image.colorSpace
                ?? CGColorSpace(name: CGColorSpace.linearSRGB)
                ?? CGColorSpaceCreateDeviceRGB()
        } else if let outputProfile {
            guard let validated = outputProfile.validatedColorSpace() else {
                throw ChromabaseError.writeFailed("invalid printer output ICC profile")
            }
            outputColorSpace = validated
        } else {
            outputColorSpace = options.colorSpace.cgColorSpace
        }
        let sized = resized(image, longEdge: options.longEdge)
        let sharpened = OutputSharpening.apply(
            to: sized,
            strength: options.outputSharpening,
            medium: options.outputSharpeningMedium,
            dpi: options.dpi
        )
        switch format {
        case .jpeg:
            try writeJPEG(
                sharpened,
                to: url,
                using: context,
                metadata: metadata,
                options: options,
                colorSpace: outputColorSpace
            )
        case .png:
            try writePNG(
                sharpened,
                to: url,
                using: context,
                metadata: metadata,
                options: options,
                colorSpace: outputColorSpace
            )
        case .tiff16:
            try writeTIFF(
                sharpened,
                to: url,
                using: context,
                metadata: metadata,
                options: options,
                colorSpace: outputColorSpace
            )
        case .rawScanTIFF:
            try writeTIFF(
                sharpened,
                to: url,
                using: context,
                metadata: metadata,
                options: options,
                colorSpace: outputColorSpace
            )
        }
    }

    @discardableResult
    public static func writePaired(
        _ image: CIImage,
        mainFlatMaster: CIImage?,
        to url: URL,
        format: ExportFormat,
        using context: CIContext,
        metadata: ExportMeta? = nil,
        options: ExportOptions = .standard,
        primaryOutputProfile: ICCOutputProfileSnapshot? = nil,
        writeMainFlatMaster: Bool = false
    ) throws -> ExportWriteResult {
        try write(
            image,
            to: url,
            format: format,
            using: context,
            metadata: metadata,
            options: options,
            outputProfile: primaryOutputProfile
        )
        guard writeMainFlatMaster, format != .rawScanTIFF, let mainFlatMaster else {
            return ExportWriteResult(outputURL: url, mainFlatMasterURL: nil)
        }
        let mainFlatURL = ExportPairing.mainFlatMasterURL(for: url)
        try write(
            mainFlatMaster,
            to: mainFlatURL,
            format: format,
            using: context,
            metadata: metadata,
            options: options,
            outputProfile: nil
        )
        return ExportWriteResult(outputURL: url, mainFlatMasterURL: mainFlatURL)
    }

    /// 긴 변을 `longEdge`로 맞춰 비율 유지 축소(업스케일 안 함). nil이면 원본 그대로.
    static func resized(_ image: CIImage, longEdge: Int?) -> CIImage {
        guard let longEdge, longEdge > 0 else { return image }
        let extent = image.extent
        let currentLong = max(extent.width, extent.height)
        guard currentLong > CGFloat(longEdge) else { return image }
        let scale = CGFloat(longEdge) / currentLong
        let scaled = image
            .applyingFilter("CILanczosScaleTransform", parameters: [
                "inputScale": scale,
                "inputAspectRatio": 1.0,
            ])
        return scaled.cropped(to: CGRect(
            x: extent.minX * scale,
            y: extent.minY * scale,
            width: (extent.width * scale).rounded(),
            height: (extent.height * scale).rounded()
        ))
    }

    static func writeJPEG(_ image: CIImage, to url: URL, using context: CIContext,
                          metadata: ExportMeta? = nil, options: ExportOptions = .standard,
                          colorSpace: CGColorSpace) throws {
        var props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: encodedJPEGQuality(options.jpegQuality),
        ]
        props.merge(metadataProperties(metadata)) { _, new in new }
        // 8bit 양자화 직전 dithering으로 명부/하늘 banding 완화(OutputDither). 출력 계층에서만 적용.
        let cg = ExportRenderedImage.make(
            image,
            using: context,
            colorSpace: colorSpace,
            bitDepth: .eight,
            preserveAlpha: false,
            appliesDither: true
        )
        guard let cg else { throw ChromabaseError.writeFailed("createCGImage nil: \(url.path)") }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
        else { throw ChromabaseError.writeFailed("CGImageDestinationCreateWithURL nil: \(url.path)") }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ChromabaseError.writeFailed("CGImageDestinationFinalize failed: \(url.path)")
        }
    }

    static func writePNG(_ image: CIImage, to url: URL, using context: CIContext,
                         metadata: ExportMeta? = nil, options: ExportOptions = .standard,
                         colorSpace: CGColorSpace) throws {
        // PNG는 무손실이라 JPEG 같은 품질 손잡이가 없다. 화질을 정하는 값은 비트 심도뿐이다.
        // dither는 8bit 양자화 banding 완화용이므로 16bit에서는 걸지 않는다(TIFF와 같은 규칙).
        guard let cg = ExportRenderedImage.make(
            image,
            using: context,
            colorSpace: colorSpace,
            bitDepth: options.pngBitDepth,
            preserveAlpha: options.preserveAlpha,
            appliesDither: options.pngBitDepth == .eight
        )
        else { throw ChromabaseError.writeFailed("createCGImage nil: \(url.path)") }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { throw ChromabaseError.writeFailed("CGImageDestinationCreateWithURL nil: \(url.path)") }
        CGImageDestinationAddImage(dest, cg, metadataProperties(metadata) as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ChromabaseError.writeFailed("CGImageDestinationFinalize failed: \(url.path)")
        }
    }

    static func writeTIFF(_ image: CIImage, to url: URL, using context: CIContext,
                          metadata: ExportMeta? = nil, options: ExportOptions = .standard,
                          colorSpace: CGColorSpace) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil)
        else { throw ChromabaseError.writeFailed(url.path) }
        let cg = ExportRenderedImage.make(
            image,
            using: context,
            colorSpace: colorSpace,
            bitDepth: options.tiffBitDepth,
            preserveAlpha: options.preserveAlpha,
            appliesDither: options.tiffBitDepth == .eight
        )
        guard let cg else { throw ChromabaseError.writeFailed(url.path) }
        var props = metadataProperties(metadata)
        var tiff = props[kCGImagePropertyTIFFDictionary] as? [String: Any] ?? [:]
        tiff[kCGImagePropertyTIFFCompression as String] = options.tiffCompression.imageIOValue
        props[kCGImagePropertyTIFFDictionary] = tiff
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ChromabaseError.writeFailed(url.path)
        }
    }

    /// ExportMeta → CGImageDestination props(EXIF + TIFF dictionary).
    /// transform이 픽셀에 구워졌으므로 orientation=1.
    static func metadataProperties(_ meta: ExportMeta?) -> [CFString: Any] {
        guard let meta = meta else { return [:] }
        let filteredSource = meta.sourceMetadata?.filtered(for: meta.metadataPolicy)
        var props = filteredSource?.imageProperties ?? [:]
        if meta.metadataPolicy != .all {
            props[kCGImageMetadataShouldExcludeGPS] = true
        }
        var exif = props[kCGImagePropertyExifDictionary] as? [String: Any] ?? [:]
        var tiff = props[kCGImagePropertyTIFFDictionary] as? [String: Any] ?? [:]
        if meta.metadataPolicy == .copyrightOnly {
            props[kCGImagePropertyOrientation] = 1
            return props
        }
        if let scannerMake = meta.scannerMake {
            exif["Make"] = scannerMake
            tiff["Make"] = scannerMake
        }
        if let scannerModel = meta.scannerModel {
            exif["Model"] = scannerModel
            tiff["Model"] = scannerModel
        }
        if let dpi = meta.resolutionDPI, dpi > 0 {
            props[kCGImagePropertyDPIWidth] = dpi as NSNumber
            props[kCGImagePropertyDPIHeight] = dpi as NSNumber
            exif["XResolution"] = dpi as NSNumber
            exif["YResolution"] = dpi as NSNumber
            exif["ResolutionUnit"] = 2   // inches
            tiff["XResolution"] = dpi as NSNumber
            tiff["YResolution"] = dpi as NSNumber
            tiff["ResolutionUnit"] = 2
        }
        if let sourceDate = meta.sourceDate {
            let sourceTimestamp = exifTimestamp(sourceDate)
            exif[kCGImagePropertyExifDateTimeOriginal as String] = sourceTimestamp
            exif[kCGImagePropertyExifDateTimeDigitized as String] = sourceTimestamp
            exif[kCGImagePropertyExifOffsetTimeOriginal as String] = "+00:00"
            exif[kCGImagePropertyExifOffsetTimeDigitized as String] = "+00:00"
        }
        if let metadataDate = meta.metadataDate {
            tiff[kCGImagePropertyTIFFDateTime as String] = exifTimestamp(metadataDate)
            exif[kCGImagePropertyExifOffsetTime as String] = "+00:00"
        }
        if let software = meta.software { exif["Software"] = software; tiff["Software"] = software }
        // 필름 스톡은 사용자가 적은 촬영 기록이므로 metadata 를 비우기로 한 정책에서는 싣지 않는다.
        let filmStock = meta.metadataPolicy == .minimal ? nil : meta.filmStock
        let filmComment = [
            meta.filmType.map { "FilmType: \($0)" },
            filmStock.map { "FilmStock: \($0)" },
        ].compactMap { $0 }.joined(separator: "; ")
        if !filmComment.isEmpty { exif["UserComment"] = filmComment }
        exif["Orientation"] = 1   // transform 구움
        props[kCGImagePropertyExifDictionary] = exif
        props[kCGImagePropertyTIFFDictionary] = tiff
        props[kCGImagePropertyOrientation] = 1
        return props
    }

    private static func exifTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
