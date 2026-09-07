import CoreImage
import Foundation

final class CustomColorTargetCPU: CIImageProcessorKernel {
    override class func formatForInput(at inputIndex: Int32) -> CIFormat { .RGBAf }
    override class var outputFormat: CIFormat { .RGBAf }

    override class func process(with inputs: [CIImageProcessorInput]?, arguments: [String: Any]?,
                                output: CIImageProcessorOutput) throws {
        guard let input = inputs?.first,
              let rawValue = arguments?["target"] as? String,
              let target = DevelopTarget(rawValue: rawValue),
              let profile = CustomColorTarget.profile(for: target),
              input.region.contains(output.region) else {
            throw NSError(domain: "CustomColorTarget", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid custom color processor input"])
        }
        let width = Int(output.region.width), height = Int(output.region.height)
        let dx = Int(output.region.minX - input.region.minX)
        let dy = Int(output.region.minY - input.region.minY)
        guard width >= 0, height >= 0, dx >= 0, dy >= 0,
              input.bytesPerRow / MemoryLayout<Float>.stride >= (dx + width) * 4,
              output.bytesPerRow / MemoryLayout<Float>.stride >= width * 4 else {
            throw NSError(domain: "CustomColorTarget", code: 2)
        }
        for y in 0..<height {
            let source = input.baseAddress.advanced(by: (y + dy) * input.bytesPerRow)
                .assumingMemoryBound(to: Float.self)
            let destination = output.baseAddress.advanced(by: y * output.bytesPerRow)
                .assumingMemoryBound(to: Float.self)
            for x in 0..<width {
                let i = (x + dx) * 4, o = x * 4
                let alpha = source[i + 3]
                if alpha <= 0 {
                    for c in 0..<4 { destination[o + c] = 0 }
                    continue
                }
                let rgb = SIMD3(Double(source[i] / alpha), Double(source[i + 1] / alpha),
                                Double(source[i + 2] / alpha))
                guard rgb.x.isFinite, rgb.y.isFinite, rgb.z.isFinite, alpha.isFinite else {
                    throw NSError(domain: "CustomColorTarget", code: 3,
                                  userInfo: [NSLocalizedDescriptionKey: "Non-finite custom color input"])
                }
                let transformed = CustomColorTargetMath.rgb(rgb, profile: profile)
                destination[o] = Float(transformed.x) * alpha
                destination[o + 1] = Float(transformed.y) * alpha
                destination[o + 2] = Float(transformed.z) * alpha
                destination[o + 3] = alpha
            }
        }
    }
}
