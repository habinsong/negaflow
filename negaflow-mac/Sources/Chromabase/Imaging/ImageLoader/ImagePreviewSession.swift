import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// One selection's interactive and settled passes share a decoder. This object is
/// transient; only materialized, budgeted preview buffers survive the selection task.
public final class ImagePreviewSession: @unchecked Sendable {
    public let url: URL
    private let gamma: InputGammaInterpretation
    private let rendering: ImageLoader.RAWRendering
    private let applyOrientation: Bool
    private let interpretInputGamma: Bool
    private let lock = NSLock()
    private var observation: InputGammaFileObservation?
    private var filter: CIRAWFilter?
    private var gammaSource: InputGammaPreviewSource?
    private var standard: CIImage?
    private var size: CGSize = .zero
    private var usesLinear = true

    public init(url: URL, inputGamma: InputGammaInterpretation,
                rawRendering: ImageLoader.RAWRendering, applyOrientation: Bool,
                interpretInputGamma: Bool = true) {
        self.url = url
        gamma = inputGamma
        rendering = rawRendering
        self.applyOrientation = applyOrientation
        self.interpretInputGamma = interpretInputGamma
    }

    public func preview(maxDimension: CGFloat) throws -> ImageLoader.PreviewImage? {
        guard maxDimension.isFinite, maxDimension > 0 else { throw InputGammaDecodeError.unsupportedPixels }
        return try lock.withLock {
            try Task.checkCancellation()
            if let observation, try InputGammaFileObservation.read(url) != observation {
                throw InputGammaDecodeError.decodeFailed
            }
            if observation == nil {
                let before = try InputGammaFileObservation.read(url)
                if ImageLoader.kind(of: url) == .rawDng {
                    guard gamma == .automatic else { throw InputGammaDecodeError.unsupportedSource }
                    guard rendering != .cameraNativeNegative,
                          let raw = CIRAWFilter(imageURL: url) else { return nil }
                    ImageLoader.configureRAW(raw, rendering: rendering)
                    // CIRAWFilter already owns the ImageIO source and its metadata.
                    // Opening another source just to read the dimensions repeats that work.
                    let properties = raw.properties
                    if let width = properties[kCGImagePropertyPixelWidth as String] as? NSNumber,
                       let height = properties[kCGImagePropertyPixelHeight as String] as? NSNumber {
                        size = CGSize(width: width.doubleValue, height: height.doubleValue)
                    } else { size = raw.nativeSize }
                    guard size.width.isFinite, size.height.isFinite,
                          size.width > 0, size.height > 0 else { return nil }
                    filter = raw
                } else {
                    guard let file = ImageLoader.imageSource(url),
                          CGImageSourceGetType(file) as String? == "public.tiff",
                          let dimensions = ImageLoader.sourcePixelSize(file),
                          let cg = ImageLoader.createFullyDecodedImage(file) else { return nil }
                    size = dimensions
                    let info = interpretInputGamma
                        ? try ImageLoader.inputGammaSourceInfo(url, source: file, image: cg) : nil
                    if let info, info.manualError == nil {
                        let metadata = try TIFFInputProfileReader.read(url)
                        gammaSource = try InputGammaPreviewSource(url: url, source: file,
                            profile: metadata.profile, image: cg)
                    } else {
                        if gamma != .automatic, let failure = info?.manualError { throw failure }
                        let props = CGImageSourceCopyPropertiesAtIndex(file, 0, nil) as? [CFString: Any]
                        let image = ImageLoader.profileAwareImage(cg, properties: props,
                            untaggedTIFFRole: .linearScannerRaw)
                        let orientation = applyOrientation ? ImageLoader.exifOrientation(props) : 1
                        standard = orientation == 1 ? image : image.oriented(forExifOrientation: orientation)
                        usesLinear = ImageLoader.sourceBitDepth(cg, properties: props) >= 16
                    }
                }
                guard try InputGammaFileObservation.read(url) == before else { throw InputGammaDecodeError.decodeFailed }
                observation = before
            }
            try Task.checkCancellation()
            let image: CIImage
            if let filter {
                filter.scaleFactor = Float(max(0.01, min(1, maxDimension / max(size.width, size.height))))
                guard let output = filter.outputImage else { return nil }
                image = output
            } else if let gammaSource {
                image = try gammaSource.image(gamma: gamma, maxDimension: maxDimension,
                    applyOrientation: applyOrientation)
            } else if let standard {
                let scale = min(1, maxDimension / max(standard.extent.width, standard.extent.height))
                let scaled = scale < 1 ? standard.applyingFilter("CILanczosScaleTransform",
                    parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1]) : standard
                image = scaled.cropped(to: CGRect(x: scaled.extent.minX, y: scaled.extent.minY,
                    width: scaled.extent.width.rounded(.down), height: scaled.extent.height.rounded(.down)))
            } else { return nil }
            return ImageLoader.PreviewImage(image: image, sourcePixelSize: size, usesLinearSRGB: usesLinear)
        }
    }
}
