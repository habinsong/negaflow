import CoreGraphics
import CoreImage
import Foundation

public enum CustomColorTarget {
    public static let revision = "custom-3"
    private static let linearSRGB = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!

    static func profile(for target: DevelopTarget) -> CustomColorTargetProfile? {
        profiles.first { $0.target == target }
    }

    public static func apply(to image: CIImage, target: DevelopTarget) -> CIImage {
        guard let index = profiles.firstIndex(where: { $0.target == target }) else { return image }
        let linear = image.matchedFromWorkingSpace(to: linearSRGB) ?? image
        let result: CIImage
        if let kernel = CustomColorTargetKernel.kernel,
           let processed = kernel.apply(extent: image.extent, arguments: [linear, Double(index)]) {
            result = processed
        } else {
            result = applyCPU(to: linear, target: target)
        }
        return (result.matchedToWorkingSpace(from: linearSRGB) ?? result).cropped(to: image.extent)
    }

    // Metal을 사용할 수 없는 경우에도 같은 색 응답을 계산합니다. 원본으로 조용히 대체하지 않습니다.
    static func applyCPU(to image: CIImage, target: DevelopTarget) -> CIImage {
        do {
            return try CustomColorTargetCPU.apply(
                withExtent: image.extent, inputs: [image], arguments: ["target": target.rawValue]
            )
        } catch {
            preconditionFailure("Custom color processor setup failed: \(error)")
        }
    }
}
