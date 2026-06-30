import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class ChromaDenoiseFieldTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    private let width = 192
    private let height = 128

    func testReducesDenseShadowAndMidtoneNoiseFieldWithoutFlatteningColorOrEdges() {
        let clean = makeFieldFixture(noisy: false)
        let noisy = makeFieldFixture(noisy: true)
        let out = ChromaDenoise.apply(to: noisy, strength: 1.0)
        let cleanBuffer = render(clean)
        let noisyBuffer = render(noisy)
        let outBuffer = render(out)

        let shadow = CGRect(x: 8, y: 10, width: 56, height: 108)
        let midtone = CGRect(x: 72, y: 10, width: 64, height: 108)
        let colorPatch = CGRect(x: 154, y: 18, width: 26, height: 92)
        let edgeBand = CGRect(x: 144, y: 10, width: 2, height: 108)

        let shadowIn = meanLumaError(noisyBuffer, cleanBuffer, rect: shadow)
        let shadowOut = meanLumaError(outBuffer, cleanBuffer, rect: shadow)
        let midChromaIn = meanChromaError(noisyBuffer, cleanBuffer, rect: midtone)
        let midChromaOut = meanChromaError(outBuffer, cleanBuffer, rect: midtone)
        let colorIn = meanChroma(cleanBuffer, rect: colorPatch)
        let colorOut = meanChroma(outBuffer, rect: colorPatch)
        let edgeClean = meanEdge(cleanBuffer, rect: edgeBand)
        let edgeIn = meanEdge(noisyBuffer, rect: edgeBand)
        let edgeOut = meanEdge(outBuffer, rect: edgeBand)

        print(String(format: "[field-noise] shadow %.4f->%.4f | mid chroma %.4f->%.4f | color %.4f->%.4f | edge %.4f/%.4f->%.4f",
                     shadowIn, shadowOut, midChromaIn, midChromaOut, colorIn, colorOut, edgeClean, edgeIn, edgeOut))

        XCTAssertLessThan(shadowOut, shadowIn * 0.55)
        XCTAssertLessThan(midChromaOut, midChromaIn * 0.42)
        XCTAssertGreaterThan(colorOut, colorIn * 0.80)
        XCTAssertGreaterThan(edgeOut, edgeClean * 0.90)
    }

    private func makeFieldFixture(noisy: Bool) -> CIImage {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let fy = Float(y) / Float(height - 1)
                let fx = Float(x) / Float(width - 1)
                var rgb = baseRGB(x: x, fy: fy, fx: fx)
                if noisy {
                    if x < 70 {
                        let lumaGrain = field(x: x, y: y, periodX: 3, periodY: 5, scale: 0.036)
                            + field(x: x + 19, y: y, periodX: 9, periodY: 7, scale: 0.026)
                        let whiteSalt = hash(x, y, 31) > 0.82 ? Float(0.095) : 0
                        rgb += SIMD3<Float>(repeating: lumaGrain + whiteSalt)
                        rgb += chromaField(x: x, y: y, scale: 0.050)
                    } else if x < 144 {
                        rgb += chromaField(x: x, y: y, scale: 0.088)
                        rgb += SIMD3<Float>(repeating: field(x: x, y: y, periodX: 4, periodY: 6, scale: 0.012))
                    }
                }
                pixels[index] = min(max(rgb.x, 0), 1)
                pixels[index + 1] = min(max(rgb.y, 0), 1)
                pixels[index + 2] = min(max(rgb.z, 0), 1)
                pixels[index + 3] = 1
            }
        }
        let data = Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size)
        return CIImage(bitmapData: data,
                       bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                       size: CGSize(width: width, height: height),
                       format: .RGBAf,
                       colorSpace: linear)
    }

    private func baseRGB(x: Int, fy: Float, fx: Float) -> SIMD3<Float> {
        if x < 70 {
            let v = Float(0.095) + fy * 0.070 + fx * 0.018
            return SIMD3(v, v * 0.99, v * 1.01)
        }
        if x < 144 {
            let v = Float(0.36) + fy * 0.070
            return SIMD3(v, v, v)
        }
        if x < 154 {
            let v = Float(0.37) + fy * 0.050
            return SIMD3(v, v, v)
        }
        return SIMD3(0.70, 0.19 + fy * 0.05, 0.13)
    }

    private func chromaField(x: Int, y: Int, scale: Float) -> SIMD3<Float> {
        let block = ((x / 4) + (y / 5) * 2) % 5
        switch block {
        case 0: return SIMD3(1.00, -0.42, -0.58) * scale
        case 1: return SIMD3(-0.50, 0.96, -0.46) * scale
        case 2: return SIMD3(-0.34, -0.54, 0.88) * scale
        case 3: return SIMD3(0.55, -0.78, 0.23) * scale
        default: return SIMD3(-0.24, 0.18, 0.06) * scale
        }
    }

    private func field(x: Int, y: Int, periodX: Int, periodY: Int, scale: Float) -> Float {
        let signed = Float(((x / periodX + y / periodY) % 3) - 1)
        return signed * scale + (hash(x, y, periodX + periodY) - 0.5) * scale * 0.35
    }

    private func hash(_ x: Int, _ y: Int, _ salt: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: (x + salt) &* 374761393 &+ (y - salt) &* 668265263)
        h = (h ^ (h >> 13)) &* 1274126177
        h = h ^ (h >> 16)
        return Float(h) / Float(UInt32.max)
    }

    private func render(_ image: CIImage) -> [Float] {
        var buffer = [Float](repeating: 0, count: width * height * 4)
        let context = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        context.render(image,
                       toBitmap: &buffer,
                       rowBytes: width * 4 * MemoryLayout<Float>.size,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .RGBAf,
                       colorSpace: linear)
        return buffer
    }

    private func meanLumaError(_ a: [Float], _ b: [Float], rect: CGRect) -> Double {
        var sum = 0.0
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                sum += abs(luma(a, x: x, y: y) - luma(b, x: x, y: y))
                count += 1
            }
        }
        return sum / Double(max(1, count))
    }

    private func meanChromaError(_ a: [Float], _ b: [Float], rect: CGRect) -> Double {
        var sum = 0.0
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let ai = (y * width + x) * 4
                let bi = (y * width + x) * 4
                let ay = luma(a, x: x, y: y)
                let by = luma(b, x: x, y: y)
                let ar = Double(a[ai]) - ay
                let ag = Double(a[ai + 1]) - ay
                let ab = Double(a[ai + 2]) - ay
                let br = Double(b[bi]) - by
                let bg = Double(b[bi + 1]) - by
                let bb = Double(b[bi + 2]) - by
                sum += ((ar - br) * (ar - br) + (ag - bg) * (ag - bg) + (ab - bb) * (ab - bb)).squareRoot()
                count += 1
            }
        }
        return sum / Double(max(1, count))
    }

    private func meanChroma(_ buffer: [Float], rect: CGRect) -> Double {
        var sum = 0.0
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let i = (y * width + x) * 4
                let yy = luma(buffer, x: x, y: y)
                let r = Double(buffer[i]) - yy
                let g = Double(buffer[i + 1]) - yy
                let b = Double(buffer[i + 2]) - yy
                sum += (r * r + g * g + b * b).squareRoot()
                count += 1
            }
        }
        return sum / Double(max(1, count))
    }

    private func meanEdge(_ buffer: [Float], rect: CGRect) -> Double {
        var sum = 0.0
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                sum += abs(luma(buffer, x: x + 1, y: y) - luma(buffer, x: x - 1, y: y))
                count += 1
            }
        }
        return sum / Double(max(1, count))
    }

    private func luma(_ buffer: [Float], x: Int, y: Int) -> Double {
        let i = (y * width + x) * 4
        return 0.2126 * Double(buffer[i]) + 0.7152 * Double(buffer[i + 1]) + 0.0722 * Double(buffer[i + 2])
    }
}
