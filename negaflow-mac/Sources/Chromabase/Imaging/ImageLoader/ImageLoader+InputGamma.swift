import Foundation
import CoreImage
import CoreGraphics
import ImageIO

extension ImageLoader {
    /// 기존 optional API는 자동 해석을 유지합니다. 명시적 해석은 오류를 구분해 전달합니다.
    public static func loadImportedDecoded(
        _ url: URL,
        inputGamma: InputGammaInterpretation,
        untaggedTIFFRole: UntaggedTIFFRole = .linearScannerRaw,
        rawRendering: RAWRendering = .sceneLinear
    ) throws -> DecodedImage {
        if inputGamma == .automatic {
            if let estimated = try inputGammaSourceInfo(url).estimatedGamma {
                return try decodeGammaTIFF(url, gamma: estimated, applyOrientation: true)
            }
            guard let decoded = loadImportedDecoded(url, untaggedTIFFRole: untaggedTIFFRole,
                                                    rawRendering: rawRendering) else {
                throw InputGammaDecodeError.decodeFailed
            }
            return decoded
        }
        return try decodeGammaTIFF(url, gamma: inputGamma, applyOrientation: true)
    }

    public static func loadScannerTIFFDecoded(
        _ url: URL,
        inputGamma: InputGammaInterpretation
    ) throws -> DecodedImage {
        if inputGamma == .automatic {
            if let estimated = try inputGammaSourceInfo(url).estimatedGamma {
                return try decodeGammaTIFF(url, gamma: estimated, applyOrientation: false)
            }
            guard let decoded = loadScannerTIFFDecoded(url) else { throw InputGammaDecodeError.decodeFailed }
            return decoded
        }
        return try decodeGammaTIFF(url, gamma: inputGamma, applyOrientation: false)
    }

    public static func loadImportedPreview(
        _ url: URL, maxDimension: CGFloat, highResolutionThreshold: CGFloat,
        inputGamma: InputGammaInterpretation,
        rawRendering: RAWRendering = .sceneLinear
    ) throws -> PreviewImage? {
        if inputGamma == .automatic {
            if let estimated = try inputGammaSourceInfo(url).estimatedGamma {
                return try gammaPreview(url, maxDimension: maxDimension, highResolutionThreshold: highResolutionThreshold,
                    gamma: estimated, applyOrientation: true)
            }
            return loadImportedPreview(url, maxDimension: maxDimension,
                                       highResolutionThreshold: highResolutionThreshold,
                                       rawRendering: rawRendering)
        }
        return try gammaPreview(url, maxDimension: maxDimension,
                                highResolutionThreshold: highResolutionThreshold,
                                gamma: inputGamma, applyOrientation: true)
    }

    public static func loadScannerPreview(
        _ url: URL, maxDimension: CGFloat, highResolutionThreshold: CGFloat,
        inputGamma: InputGammaInterpretation
    ) throws -> PreviewImage? {
        if inputGamma == .automatic {
            if let estimated = try inputGammaSourceInfo(url).estimatedGamma {
                return try gammaPreview(url, maxDimension: maxDimension, highResolutionThreshold: highResolutionThreshold,
                    gamma: estimated, applyOrientation: false)
            }
            return loadScannerPreview(url, maxDimension: maxDimension,
                                      highResolutionThreshold: highResolutionThreshold)
        }
        return try gammaPreview(url, maxDimension: maxDimension,
                                highResolutionThreshold: highResolutionThreshold,
                                gamma: inputGamma, applyOrientation: false)
    }

    public static func validateInputGammaSource(_ url: URL) throws {
        let (source, profile) = try gammaSource(url)
        guard let cg = CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw InputGammaDecodeError.decodeFailed
        }
        try InputGammaDecoder.validate(cg)
        if let profile { _ = try InputGammaProfile.linearized(profile) }
    }

    private static func gammaSource(_ url: URL) throws -> (CGImageSource, Data?) {
        guard kind(of: url) != .rawDng,
              let source = imageSource(url),
              CGImageSourceGetType(source) as String? == "public.tiff" else {
            throw InputGammaDecodeError.unsupportedSource
        }
        let metadata = try TIFFInputProfileReader.read(url)
        guard metadata.supportsPower else { throw InputGammaDecodeError.unsupportedPixels }
        return (source, metadata.profile)
    }

    private static func decodeGammaTIFF(
        _ url: URL, gamma: InputGammaInterpretation, applyOrientation: Bool
    ) throws -> DecodedImage {
        let (source, profile) = try gammaSource(url)
        guard let cg = createFullyDecodedImage(source) else { throw InputGammaDecodeError.decodeFailed }
        let raw = try InputGammaDecoder.decode(cg, sourceICC: profile, gamma: gamma)
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = applyOrientation ? exifOrientation(props) : 1
        return DecodedImage(
            image: orientation == 1 ? raw : raw.oriented(forExifOrientation: orientation),
            provenance: DecodeProvenance(decoder: .imageIO, inputGamma: gamma)
        )
    }

    private static func gammaPreview(
        _ url: URL, maxDimension: CGFloat, highResolutionThreshold: CGFloat,
        gamma: InputGammaInterpretation, applyOrientation: Bool
    ) throws -> PreviewImage? {
        guard maxDimension.isFinite, maxDimension > 0 else { throw InputGammaDecodeError.unsupportedPixels }
        let (source, profile) = try gammaSource(url)
        guard let size = sourcePixelSize(source),
              max(size.width, size.height) > max(highResolutionThreshold, maxDimension) else { return nil }
        guard let cg = createFullyDecodedImage(source) else { throw InputGammaDecodeError.decodeFailed }
        let raw = try InputGammaDecoder.decode(cg, sourceICC: profile, gamma: gamma, maxDimension: maxDimension)
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = applyOrientation ? exifOrientation(props) : 1
        return PreviewImage(image: orientation == 1 ? raw : raw.oriented(forExifOrientation: orientation),
                            sourcePixelSize: size, usesLinearSRGB: true)
    }
}
