import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import Metal

/// 감마와 독립적인 원본 코드 값을 보관합니다. 수명은 앱의 프레임 메모리 캐시가 소유합니다.
public final class InputGammaPreviewSource: @unchecked Sendable {
    private let url: URL
    private let observation: InputGammaFileObservation
    private let encoded: CIImage
    private let source: CGImage?
    private let profile: Data?
    private let automatic: CIImage
    private let linearSpace: CGColorSpace
    private let estimatedGamma: InputGammaInterpretation?
    private let orientation: Int32
    public let byteCost: Int
    private static let queue = MTLCreateSystemDefaultDevice()?.makeCommandQueue()
    private static let context: CIContext = {
        let options: [CIContextOption: Any] = [
            .workingColorSpace: NSNull(), .outputColorSpace: NSNull(),
            .workingFormat: CIFormat.RGBAf.rawValue, .cacheIntermediates: false
        ]
        if let queue { return CIContext(mtlCommandQueue: queue, options: options) }
        return CIContext(options: options)
    }()

    public init(url: URL) throws {
        self.url = url.standardizedFileURL
        observation = try InputGammaFileObservation.read(url)
        let (source, profile) = try ImageLoader.gammaSource(url)
        guard let cg = ImageLoader.createFullyDecodedImage(source) else { throw InputGammaDecodeError.decodeFailed }
        try InputGammaDecoder.validate(cg)
        self.profile = profile
        linearSpace = try profile.map(InputGammaProfile.linearized)
            ?? CGColorSpace(name: CGColorSpace.linearSRGB)!
        let info = try ImageLoader.inputGammaSourceInfo(url)
        estimatedGamma = info.estimatedGamma
        let automaticSpace: CGColorSpace
        if let profile, let space = CGColorSpace(iccData: profile as CFData) {
            automaticSpace = space
        } else {
            automaticSpace = CGColorSpace(
                name: info.curve == .assumedLinear ? CGColorSpace.linearSRGB : CGColorSpace.sRGB)!
        }
        if let cached = Self.cacheEncodedTexture(cg, linearSpace: linearSpace, automaticSpace: automaticSpace) {
            encoded = cached.encoded
            automatic = cached.automatic
            self.source = nil
            byteCost = cached.cost
        } else {
            encoded = CIImage(cgImage: cg, options: [.colorSpace: NSNull()])
            automatic = CIImage(cgImage: cg, options: [.colorSpace: automaticSpace])
            self.source = cg
            let cost = cg.bytesPerRow.multipliedReportingOverflow(by: cg.height)
            guard !cost.overflow else { throw InputGammaDecodeError.unsupportedPixels }
            byteCost = cost.partialValue
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        orientation = ImageLoader.exifOrientation(properties)
        guard try InputGammaFileObservation.read(url) == observation else { throw InputGammaDecodeError.decodeFailed }
    }

    public func matches(_ source: URL) -> Bool {
        source.standardizedFileURL == url && (try? InputGammaFileObservation.read(source)) == observation
    }

    /// power → 축소를 float GPU 텍스처에 평가합니다. 이후 기존 색공간 변환으로 연결합니다.
    public func image(gamma: InputGammaInterpretation, maxDimension: CGFloat, applyOrientation: Bool) throws -> CIImage {
        let resolved = gamma == .automatic ? estimatedGamma ?? gamma : gamma
        let image: CIImage
        if let power = resolved.value {
            let powered = encoded.applyingFilter("CIGammaAdjust", parameters: ["inputPower": power])
            let proxy = Self.proxy(powered, maxDimension: maxDimension)
            if let queue = Self.queue, let buffer = queue.makeCommandBuffer() {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float,
                    width: Int(proxy.extent.width), height: Int(proxy.extent.height), mipmapped: false)
                descriptor.storageMode = .private
                descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
                guard let texture = queue.device.makeTexture(descriptor: descriptor) else {
                    throw InputGammaDecodeError.decodeFailed
                }
                Self.context.render(proxy, to: texture, commandBuffer: buffer, bounds: proxy.extent, colorSpace: linearSpace)
                buffer.commit()
                buffer.waitUntilCompleted()
                guard buffer.status == .completed,
                      let result = CIImage(mtlTexture: texture, options: [.colorSpace: linearSpace]) else {
                    throw InputGammaDecodeError.decodeFailed
                }
                image = result
            } else {
                let fallback: CGImage
                if let source { fallback = source }
                else {
                    let (file, _) = try ImageLoader.gammaSource(url)
                    guard let cg = ImageLoader.createFullyDecodedImage(file) else { throw InputGammaDecodeError.decodeFailed }
                    fallback = cg
                }
                image = try InputGammaDecoder.decode(fallback, sourceICC: profile, gamma: resolved, maxDimension: maxDimension)
            }
        } else { image = Self.proxy(automatic, maxDimension: maxDimension) }
        return applyOrientation && orientation != 1 ? image.oriented(forExifOrientation: orientation) : image
    }

    /// 같은 원본을 매 틱 GPU로 다시 전송하지 않습니다. 성공하면 CPU 디코드 버퍼는 놓습니다.
    private static func cacheEncodedTexture(_ cg: CGImage, linearSpace: CGColorSpace, automaticSpace: CGColorSpace)
        -> (encoded: CIImage, automatic: CIImage, cost: Int)? {
        guard let queue, let buffer = queue.makeCommandBuffer() else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: cg.bitsPerComponent == 8 ? .rgba8Unorm : .rgba16Unorm,
            width: cg.width, height: cg.height, mipmapped: false)
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let texture = queue.device.makeTexture(descriptor: descriptor) else { return nil }
        let raw = CIImage(cgImage: cg, options: [.colorSpace: NSNull()])
        context.render(raw, to: texture, commandBuffer: buffer, bounds: raw.extent, colorSpace: linearSpace)
        buffer.commit()
        buffer.waitUntilCompleted()
        guard buffer.status == .completed,
              let encoded = CIImage(mtlTexture: texture, options: [.colorSpace: NSNull()]),
              let automatic = CIImage(mtlTexture: texture, options: [.colorSpace: automaticSpace]) else { return nil }
        return (encoded, automatic, texture.allocatedSize)
    }

    private static func proxy(_ source: CIImage, maxDimension: CGFloat) -> CIImage {
        guard maxDimension.isFinite, maxDimension > 0 else { return source }
        let ratio = min(1, maxDimension / max(source.extent.width, source.extent.height))
        guard ratio < 1 else { return source }
        let scaled = source.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: ratio, kCIInputAspectRatioKey: 1
        ])
        return scaled.cropped(to: CGRect(x: 0, y: 0,
            width: scaled.extent.width.rounded(.down), height: scaled.extent.height.rounded(.down)))
    }
}
