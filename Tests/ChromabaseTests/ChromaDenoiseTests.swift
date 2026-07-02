import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

/// Selective despeckle (NOT blur). Must: (1) remove impulse noise pixels (chroma speckle +
/// luma grain outliers), (2) leave a CLEAN smooth region essentially UNCHANGED (no mushing),
/// (3) preserve a strong edge, (4) not desaturate real color.
final class ChromaDenoiseTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    private let size = 128

    /// Left third = midtone gray + impulse speckle. Middle third = CLEAN flat gray (control).
    /// Right third = clean saturated red. Boundary at x=2/3 is a strong edge.
    private func makeFixture() -> CIImage {
        func hash(_ x: Int, _ y: Int) -> Float {
            var h = UInt32(truncatingIfNeeded: x &* 374761393 &+ y &* 668265263)
            h = (h ^ (h >> 13)) &* 1274126177; h = h ^ (h >> 16)
            return Float(h) / Float(UInt32.max) * 2 - 1
        }
        let a = size/3, b = 2*size/3
        var px = [Float](repeating: 0, count: size*size*4)
        for y in 0..<size { for x in 0..<size {
            let i = (y*size+x)*4
            if x < a {
                // sparse strong impulses (every ~5th pixel) + fine grain over gray.
                let impulse: Float = (hash(x,y) > 0.6) ? 0.22 : ((hash(x+7,y+3) < -0.6) ? -0.22 : 0)
                let cspeckle: Float = (hash(x+1,y+9) > 0.55) ? 0.18 : 0
                px[i]   = 0.40 + impulse + cspeckle
                px[i+1] = 0.40 + impulse
                px[i+2] = 0.40 + impulse - cspeckle
            } else if x < b {
                px[i] = 0.40; px[i+1] = 0.40; px[i+2] = 0.40   // CLEAN flat gray (control)
            } else {
                px[i] = 0.72; px[i+1] = 0.12; px[i+2] = 0.12   // saturated red
            }
            px[i+3] = 1
        }}
        let data = Data(bytes: px, count: px.count*MemoryLayout<Float>.size)
        return CIImage(bitmapData: data, bytesPerRow: size*4*MemoryLayout<Float>.size,
                       size: CGSize(width: size, height: size), format: .RGBAf, colorSpace: linear)
    }

    private func render(_ image: CIImage) -> [Float] {
        var bm = [Float](repeating: 0, count: size*size*4)
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        ctx.render(image, toBitmap: &bm, rowBytes: size*4*MemoryLayout<Float>.size,
                   bounds: CGRect(x: 0, y: 0, width: size, height: size), format: .RGBAf, colorSpace: linear)
        return bm
    }

    private func lum(_ bm: [Float], _ x: Int, _ y: Int) -> Double {
        let i = (y*size+x)*4
        return 0.2126*Double(bm[i]) + 0.7152*Double(bm[i+1]) + 0.0722*Double(bm[i+2])
    }
    /// noise magnitude = mean |pixel − local 4-neighbour mean| over a column range (per channel).
    private func noise(_ bm: [Float], _ xr: Range<Int>) -> Double {
        func v(_ x: Int, _ y: Int, _ ch: Int) -> Double { Double(bm[(y*size+x)*4 + ch]) }
        var s = 0.0; var n = 0
        for y in 1..<(size-1) {
            for x in xr where x >= 1 && x < size-1 {
                for ch in 0..<3 {
                    let nb = (v(x-1,y,ch) + v(x+1,y,ch) + v(x,y-1,ch) + v(x,y+1,ch)) * 0.25
                    s += abs(v(x,y,ch) - nb); n += 1
                }
            }
        }
        return s/Double(max(1,n))
    }
    private func chroma(_ bm: [Float], _ xr: Range<Int>) -> Double {
        var s = 0.0; var n = 0
        for y in 0..<size { for x in xr {
            let i = (y*size+x)*4
            let r = Double(bm[i]), g = Double(bm[i+1]), b = Double(bm[i+2])
            let yv = 0.2126*r+0.7152*g+0.0722*b
            s += ((r-yv)*(r-yv)+(g-yv)*(g-yv)+(b-yv)*(b-yv)).squareRoot(); n += 1
        }}
        return s/Double(n)
    }
    private func edge(_ bm: [Float]) -> Double {
        var s = 0.0; let bx = 2*size/3
        for y in 0..<size { s += abs(lum(bm,bx,y) - lum(bm,bx-1,y)) }
        return s/Double(size)
    }

    func testRemovesImpulseNoiseLeavesCleanRegionUntouchedPreservesEdgeAndColor() {
        let input = makeFixture()
        let out = ChromaDenoise.apply(to: input, strength: 1.0)
        let bi = render(input), bo = render(out)
        let noisy = 4..<(size/3 - 4), clean = (size/3 + 6)..<(2*size/3 - 6), red = (2*size/3 + 6)..<(size - 4)

        let nIn = noise(bi, noisy), nOut = noise(bo, noisy)
        let cleanDelta = noise(bo, clean)                 // any change introduced into clean flat region
        let eIn = edge(bi), eOut = edge(bo)
        let sIn = chroma(bi, red), sOut = chroma(bo, red)
        print(String(format: "[despeckle] noise %.4f->%.4f | clean-region-change %.5f | edge %.4f->%.4f | sat %.4f->%.4f",
                     nIn, nOut, cleanDelta, eIn, eOut, sIn, sOut))

        XCTAssertLessThan(nOut, nIn * 0.65, "impulse noise pixels must be removed ≥35%")
        XCTAssertLessThan(cleanDelta, 0.002, "CLEAN flat region must stay essentially untouched (no blur/mushing)")
        XCTAssertGreaterThan(eOut, eIn * 0.80, "strong edge must be preserved")
        XCTAssertGreaterThan(sOut, sIn * 0.85, "saturated real color must be preserved")
    }

    func testStrengthZeroReturnsInputUnchanged() {
        let input = makeFixture()
        let out = ChromaDenoise.apply(to: input, strength: 0)
        let bi = render(input)
        let bo = render(out)
        for i in stride(from: 0, to: bi.count, by: 17) {
            XCTAssertEqual(bo[i], bi[i], accuracy: 0.000001)
        }
    }

    func testRemovesShadowWhiteSpecklesAndMidtoneColorBlotchesWithoutFlatteningImage() {
        let width = 160
        let height = 112
        let clean = makeShadowMidtoneFixture(width: width, height: height, noisy: false)
        let noisy = makeShadowMidtoneFixture(width: width, height: height, noisy: true)
        let out = ChromaDenoise.apply(to: noisy, strength: 0.7)
        let bc = render(clean, width: width, height: height)
        let bi = render(noisy, width: width, height: height)
        let bo = render(out, width: width, height: height)

        let shadows = CGRect(x: 8, y: 8, width: 44, height: 96)
        let midtones = CGRect(x: 58, y: 8, width: 52, height: 96)
        let colorPatch = CGRect(x: 124, y: 12, width: 24, height: 88)
        let edgeBand = CGRect(x: 128, y: 8, width: 2, height: 96)

        let shadowIn = meanAbsLumaError(bi, bc, width: width, rect: shadows)
        let shadowOut = meanAbsLumaError(bo, bc, width: width, rect: shadows)
        let midChromaIn = meanChromaError(bi, bc, width: width, rect: midtones)
        let midChromaOut = meanChromaError(bo, bc, width: width, rect: midtones)
        let colorIn = meanChroma(bc, width: width, rect: colorPatch)
        let colorOut = meanChroma(bo, width: width, rect: colorPatch)
        let noisyEdge = meanEdge(bi, width: width, rect: edgeBand)
        let outEdge = meanEdge(bo, width: width, rect: edgeBand)

        print(String(format: "[real-noise] shadow %.4f->%.4f | mid chroma %.4f->%.4f | color %.4f->%.4f | edge %.4f->%.4f",
                     shadowIn, shadowOut, midChromaIn, midChromaOut, colorIn, colorOut, noisyEdge, outEdge))

        XCTAssertLessThan(shadowOut, shadowIn * 0.50, "암부 흰 speckle은 기본 NR 강도에서도 luma 구조를 밀지 않고 줄어야 한다")
        XCTAssertLessThan(midChromaOut, midChromaIn * 0.32, "중간톤 컬러 얼룩은 기본 NR 강도에서도 실제 휘도 구조와 분리해 줄어야 한다")
        XCTAssertGreaterThan(colorOut, colorIn * 0.82, "실제 고채도 색은 노이즈로 오인해 탈색하면 안 된다")
        XCTAssertGreaterThan(outEdge, noisyEdge * 0.92, "엣지 대비를 플랫하게 더 밀면 안 된다")
    }

    private func makeShadowMidtoneFixture(width: Int, height: Int, noisy: Bool) -> CIImage {
        func hash(_ x: Int, _ y: Int, _ salt: Int = 0) -> Float {
            var h = UInt32(truncatingIfNeeded: (x + salt) &* 374761393 &+ (y - salt) &* 668265263)
            h = (h ^ (h >> 13)) &* 1274126177
            h = h ^ (h >> 16)
            return Float(h) / Float(UInt32.max)
        }

        var px = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let i = (y * width + x) * 4
            let fy = Float(y) / Float(height - 1)
            let fx = Float(x) / Float(width - 1)
            var rgb: SIMD3<Float>
            if x < width * 7 / 20 {
                let v = Float(0.105) + fy * 0.050 + fx * 0.010
                rgb = SIMD3(v, v * 0.98, v * 1.02)
            } else if x < width * 7 / 10 {
                let v = Float(0.38) + fy * 0.055
                rgb = SIMD3(v, v, v)
            } else {
                let v = Float(0.34) + fy * 0.050
                rgb = x < width * 4 / 5
                    ? SIMD3(v, v, v)
                    : SIMD3(0.70, 0.18 + fy * 0.04, 0.13)
            }

            if noisy {
                if x < width * 7 / 20 {
                    if hash(x, y) > 0.76 {
                        rgb += SIMD3<Float>(repeating: 0.155)
                    } else {
                        let grain = (hash(x, y, 11) - 0.5) * 0.026
                        rgb += SIMD3<Float>(repeating: grain)
                    }
                } else if x < width * 7 / 10 {
                    let block = (x / 5 + (y / 7) * 2) % 4
                    let blotch: SIMD3<Float>
                    switch block {
                    case 0: blotch = SIMD3(0.080, -0.030, -0.050)
                    case 1: blotch = SIMD3(-0.045, 0.070, -0.025)
                    case 2: blotch = SIMD3(-0.020, -0.040, 0.082)
                    default: blotch = SIMD3(0.040, -0.060, 0.030)
                    }
                    rgb += blotch + SIMD3<Float>(repeating: (hash(x, y, 23) - 0.5) * 0.010)
                }
            }

            px[i] = min(max(rgb.x, 0), 1)
            px[i + 1] = min(max(rgb.y, 0), 1)
            px[i + 2] = min(max(rgb.z, 0), 1)
            px[i + 3] = 1
        }}
        let data = Data(bytes: px, count: px.count * MemoryLayout<Float>.size)
        return CIImage(bitmapData: data, bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                       size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: linear)
    }

    private func render(_ image: CIImage, width: Int, height: Int) -> [Float] {
        var bm = [Float](repeating: 0, count: width * height * 4)
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        ctx.render(image, toBitmap: &bm, rowBytes: width * 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBAf, colorSpace: linear)
        return bm
    }

    private func meanAbsLumaError(_ a: [Float], _ b: [Float], width: Int, rect: CGRect) -> Double {
        var sum = 0.0
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                sum += abs(luma(a, width: width, x: x, y: y) - luma(b, width: width, x: x, y: y))
                count += 1
            }
        }
        return sum / Double(max(1, count))
    }

    private func meanChromaError(_ a: [Float], _ b: [Float], width: Int, rect: CGRect) -> Double {
        var sum = 0.0
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let ai = (y * width + x) * 4
                let bi = (y * width + x) * 4
                let ay = luma(a, width: width, x: x, y: y)
                let by = luma(b, width: width, x: x, y: y)
                let ar = Double(a[ai]) - ay, ag = Double(a[ai + 1]) - ay, ab = Double(a[ai + 2]) - ay
                let br = Double(b[bi]) - by, bg = Double(b[bi + 1]) - by, bb = Double(b[bi + 2]) - by
                sum += ((ar - br) * (ar - br) + (ag - bg) * (ag - bg) + (ab - bb) * (ab - bb)).squareRoot()
                count += 1
            }
        }
        return sum / Double(max(1, count))
    }

    private func meanChroma(_ a: [Float], width: Int, rect: CGRect) -> Double {
        var sum = 0.0
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let i = (y * width + x) * 4
                let yy = luma(a, width: width, x: x, y: y)
                let r = Double(a[i]) - yy, g = Double(a[i + 1]) - yy, b = Double(a[i + 2]) - yy
                sum += (r * r + g * g + b * b).squareRoot()
                count += 1
            }
        }
        return sum / Double(max(1, count))
    }

    private func meanEdge(_ a: [Float], width: Int, rect: CGRect) -> Double {
        var sum = 0.0
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                sum += abs(luma(a, width: width, x: x + 1, y: y) - luma(a, width: width, x: x - 1, y: y))
                count += 1
            }
        }
        return sum / Double(max(1, count))
    }

    private func luma(_ a: [Float], width: Int, x: Int, y: Int) -> Double {
        let i = (y * width + x) * 4
        return 0.2126 * Double(a[i]) + 0.7152 * Double(a[i + 1]) + 0.0722 * Double(a[i + 2])
    }
}
