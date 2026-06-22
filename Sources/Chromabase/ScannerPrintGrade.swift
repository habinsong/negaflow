import CoreImage
import CoreGraphics
import Foundation

enum ScannerPrintGrade {
    private static let fractions = [0.01, 0.05, 0.20, 0.50, 0.80, 0.95, 0.99]

    private static let targetSRGB: [[Double]] = [
        [0.039, 0.094, 0.518, 0.843, 0.953, 0.969, 0.976],
        [0.071, 0.110, 0.447, 0.753, 0.937, 0.953, 0.961],
        [0.047, 0.090, 0.369, 0.706, 0.933, 0.949, 0.957],
    ]

    static func apply(to image: CIImage) -> CIImage {
        guard let stats = samplePercentiles(from: image),
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else {
            return image
        }
        let dimension = 64
        let strength = 0.72
        let curves = (0..<3).map { channel in
            makeCurve(
                source: stats[channel],
                target: targetSRGB[channel].map(srgbToLinear),
                dimension: dimension,
                strength: strength
            )
        }
        var cube = [Float](repeating: 0, count: dimension * dimension * dimension * 4)
        for b in 0..<dimension {
            for g in 0..<dimension {
                for r in 0..<dimension {
                    let offset = ((b * dimension + g) * dimension + r) * 4
                    cube[offset] = Float(curves[0][r])
                    cube[offset + 1] = Float(curves[1][g])
                    cube[offset + 2] = Float(curves[2][b])
                    cube[offset + 3] = 1
                }
            }
        }
        let graded = image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": dimension,
            "inputCubeData": Data(bytes: cube, count: cube.count * MemoryLayout<Float>.size),
            "inputColorSpace": linear,
        ]).cropped(to: image.extent)
        let shaped = applyDynamicRangeRecovery(to: applyShadowBalance(to: applyLumaCurve(to: graded)))
        return applyOutputPrintCurve(to: shaped)
    }

    private static func samplePercentiles(from image: CIImage) -> [[Double]]? {
        let extent = image.extent.integral
        guard extent.width > 8, extent.height > 8,
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        let targetW = max(64, min(320, Int(extent.width)))
        let scale = Double(targetW) / Double(extent.width)
        let targetH = max(1, Int(Double(extent.height) * scale))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        var bitmap = [Float](repeating: 0, count: targetW * targetH * 4)
        CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear]).render(
            scaled,
            toBitmap: &bitmap,
            rowBytes: targetW * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: targetW, height: targetH),
            format: .RGBAf,
            colorSpace: linear
        )
        let insetX = max(1, Int(Double(targetW) * 0.035))
        let insetY = max(1, Int(Double(targetH) * 0.035))
        var channels = [[Double](), [Double](), [Double]()]
        channels[0].reserveCapacity(targetW * targetH)
        for y in insetY..<max(insetY + 1, targetH - insetY) {
            for x in insetX..<max(insetX + 1, targetW - insetX) {
                let offset = (y * targetW + x) * 4
                channels[0].append(Double(bitmap[offset]))
                channels[1].append(Double(bitmap[offset + 1]))
                channels[2].append(Double(bitmap[offset + 2]))
            }
        }
        guard channels[0].count >= 64 else { return nil }
        return channels.map { channel in
            let sorted = channel.sorted()
            return fractions.map { percentile(sorted, $0) }
        }
    }

    private static func makeCurve(source: [Double], target: [Double], dimension: Int, strength: Double) -> [Double] {
        var xs = [0.0]
        var ys = [0.0]
        for (sourceValue, targetValue) in zip(source, target) {
            let nextX = max(sourceValue, (xs.last ?? 0) + 1e-4)
            xs.append(min(nextX, 1.0))
            let blended = sourceValue + (targetValue - sourceValue) * strength
            ys.append(min(max(blended, 0.0), 1.0))
        }
        xs.append(1.0)
        ys.append(1.0)
        return (0..<dimension).map { index in
            interpolate(Double(index) / Double(dimension - 1), xs: xs, ys: ys)
        }
    }

    private static func interpolate(_ value: Double, xs: [Double], ys: [Double]) -> Double {
        guard value > xs[0] else { return ys[0] }
        for index in 1..<xs.count {
            if value <= xs[index] {
                let width = max(xs[index] - xs[index - 1], 1e-4)
                let t = (value - xs[index - 1]) / width
                return ys[index - 1] + (ys[index] - ys[index - 1]) * t
            }
        }
        return ys.last ?? value
    }

    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        let index = max(0, min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction)))
        return sorted[index]
    }

    private static func srgbToLinear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func applyLumaCurve(to image: CIImage) -> CIImage {
        let p0 = CIVector(x: 0.00, y: 0.00)
        let p1 = CIVector(x: 0.25, y: 0.18)
        let p2 = CIVector(x: 0.50, y: 0.46)
        let p3 = CIVector(x: 0.75, y: 0.78)
        let p4 = CIVector(x: 1.00, y: 1.00)
        return image.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": p0,
            "inputPoint1": p1,
            "inputPoint2": p2,
            "inputPoint3": p3,
            "inputPoint4": p4,
        ]).cropped(to: image.extent)
    }

    private static func applyShadowBalance(to image: CIImage) -> CIImage {
        let extent = image.extent
        let balanced = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1.06, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0.96, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1.03, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: extent)
        let luma = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: extent)
        let mask = luma.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: -1.0 / 0.30, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: -1.0 / 0.30, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: -1.0 / 0.30, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputMaxComponents": CIVector(x: 0.36, y: 0.36, z: 0.36, w: 1),
        ]).cropped(to: extent)
        return CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: balanced,
            kCIInputBackgroundImageKey: image,
            "inputMaskImage": mask,
        ])?.outputImage?.cropped(to: extent) ?? image
    }

    private static func applyDynamicRangeRecovery(to image: CIImage) -> CIImage {
        let extent = image.extent
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "scannerDynamicRange") else { return image }
        return kernel.apply(extent: extent, arguments: [image])?.cropped(to: extent) ?? image
    }

    private static func applyOutputPrintCurve(to image: CIImage) -> CIImage {
        let curved = image.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0.00, y: 0.020),
            "inputPoint1": CIVector(x: 0.25, y: 0.158),
            "inputPoint2": CIVector(x: 0.50, y: 0.430),
            "inputPoint3": CIVector(x: 0.80, y: 0.520),
            "inputPoint4": CIVector(x: 1.00, y: 0.735),
        ]).cropped(to: image.extent)
        return curved
    }

}

enum ScannerOutputGrade {
    static func apply(to image: CIImage) -> CIImage {
        let extent = image.extent
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "scannerOutputGrade") else { return image }
        return kernel.apply(extent: extent, arguments: [image])?.cropped(to: extent) ?? image
    }
}
