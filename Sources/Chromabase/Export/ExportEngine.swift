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
            kCGImageDestinationLossyCompressionQuality: options.jpegQuality,
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
        guard let cg = ExportRenderedImage.make(
            image,
            using: context,
            colorSpace: colorSpace,
            bitDepth: .eight,
            preserveAlpha: options.preserveAlpha,
            appliesDither: true
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
