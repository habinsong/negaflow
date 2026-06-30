import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

/// Regression: the chroma denoise recombination (`reduceColorNoise`) used
/// `CIAdditionCompositing`, which adds the *alpha* channels of its two inputs
/// (1 + 1 = 2, compounding to ~3.6 across the layered passes). The next
/// alpha-normalizing filter (AutoLevels' `CIColorMatrix`) then divided the
/// premultiplied RGB by that inflated alpha, darkening every scan by ~1 stop and
/// pulling all highlights below white. Switching to `CILinearDodgeBlendMode`
/// adds color but keeps alpha = 1. These tests lock that in.
final class ChromaRecombineAlphaTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    /// Render a CIImage to mean RGB, mean/max alpha, and max luminance.
    private func measure(_ image: CIImage) -> (rgb: SIMD3<Double>, alphaMean: Double, alphaMax: Double, lumMax: Double) {
        let w = max(1, Int(image.extent.width)), h = max(1, Int(image.extent.height))
        var bm = [Float](repeating: 0, count: w * h * 4)
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        ctx.render(image, toBitmap: &bm, rowBytes: w * 4 * MemoryLayout<Float>.size,
                   bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBAf, colorSpace: linear)
        var r = 0.0, g = 0.0, b = 0.0, aSum = 0.0, aMax = 0.0, lumMax = 0.0
        for p in 0..<(w*h) {
            let pr = Double(bm[p*4]), pg = Double(bm[p*4+1]), pb = Double(bm[p*4+2]), pa = Double(bm[p*4+3])
            r += pr; g += pg; b += pb; aSum += pa; aMax = max(aMax, pa)
            lumMax = max(lumMax, 0.2126*pr + 0.7152*pg + 0.0722*pb)
        }
        let n = Double(w*h)
        return (SIMD3(r/n, g/n, b/n), aSum/n, aMax, lumMax)
    }

    private func uniform(_ rgb: SIMD3<Double>, _ size: Int = 96) -> CIImage {
        var px = [Float](repeating: 0, count: size*size*4)
        for p in 0..<(size*size) {
            px[p*4] = Float(rgb.x); px[p*4+1] = Float(rgb.y); px[p*4+2] = Float(rgb.z); px[p*4+3] = 1
        }
        let data = Data(bytes: px, count: px.count*MemoryLayout<Float>.size)
        return CIImage(bitmapData: data, bytesPerRow: size*4*MemoryLayout<Float>.size,
                       size: CGSize(width: size, height: size), format: .RGBAf, colorSpace: linear)
    }

    func testChromaDenoiseDoesNotInflateAlpha() {
        let input = uniform(SIMD3(0.85, 0.83, 0.80))
        let out = ScannerNoiseReduction.reduceMainTargetChroma(in: input)
        let m = measure(out)
        XCTAssertEqual(m.alphaMean, 1.0, accuracy: 0.05,
                       "chroma denoise must not inflate alpha (regression: was ~3.6)")
        XCTAssertLessThan(m.alphaMax, 1.2,
                          "no pixel alpha should exceed ~1 (regression: was up to 4.0)")
    }

    /// Render a developed CIImage to RGBA8 bytes.
    private func renderRGBA8(_ image: CIImage, width: Int, height: Int) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: width * height * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: cs])
        ctx.render(image, toBitmap: &px, rowBytes: width * 4,
                   bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: cs)
        return px
    }

    /// Full-range color-negative density ramp → develop → assert tonal gradation (DR) is
    /// preserved: monotonic, with distinct output levels in BOTH the shadow and highlight
    /// quarters (no clipping/crush plateaus). Guards the recombination fix against the user's
    /// concern that restoring full scale might clip highlights or crush shadows.
    func testFullRangeRampPreservesShadowAndHighlightGradation() {
        let width = 256, height = 8
        let base = SIMD3<Double>(0.86, 0.54, 0.34)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            // density 0(brightest scene → densest negative? ) across full range 0..2.2.
            let density = Double(x) / Double(width - 1) * 2.2
            let atten = pow(10.0, -density)
            let i = (y*width + x)*4
            bytes[i]   = UInt8(max(0, min(255, Int(base.x * atten * 255))))
            bytes[i+1] = UInt8(max(0, min(255, Int(base.y * atten * 255))))
            bytes[i+2] = UInt8(max(0, min(255, Int(base.z * atten * 255))))
            bytes[i+3] = 255
        }}
        let data = Data(bytes: bytes, count: bytes.count)
        let input = CIImage(bitmapData: data, bytesPerRow: width*4,
                            size: CGSize(width: width, height: height), format: .RGBA8,
                            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
        var params = DevelopParameters()
        params.filmType = .colorNegative
        params.developTarget = .main
        let out = renderRGBA8(
            ChromabaseEngine().develop(image: input, base: FilmBase(rgb: base, source: .border), params: params),
            width: width, height: height
        )
        // Mid-row luma per ramp step.
        let midY = height / 2
        var luma = [Double]()
        for x in 0..<width {
            let i = (midY*width + x)*4
            luma.append(0.2126*Double(out[i]) + 0.7152*Double(out[i+1]) + 0.0722*Double(out[i+2]))
        }
        // Sort by brightness so we measure gradation regardless of ramp direction.
        let sorted = luma.sorted()
        func distinct(_ slice: ArraySlice<Double>) -> Int { Set(slice.map { Int($0.rounded()) }).count }
        let q = width / 4
        let shadowLevels = distinct(sorted[0..<q])
        let midLevels = distinct(sorted[q..<(3*q)])
        let highlightLevels = distinct(sorted[(3*q)..<width])
        let clipped255 = sorted.filter { $0 >= 254.5 }.count
        let crushed0 = sorted.filter { $0 <= 0.5 }.count
        print("[gradation] shadowDistinct=\(shadowLevels)/\(q) midDistinct=\(midLevels)/\(2*q) highlightDistinct=\(highlightLevels)/\(q) clipped@255=\(clipped255) crushed@0=\(crushed0) range=[\(Int(sorted.first!))..\(Int(sorted.last!))]")
        // Monotonic non-decreasing along the ramp (no tonal inversions from the recombination).
        let rampLuma = luma
        let ascending = rampLuma.last! >= rampLuma.first!
        var maxDrop = 0.0
        for i in 1..<rampLuma.count {
            let d = ascending ? rampLuma[i-1] - rampLuma[i] : rampLuma[i] - rampLuma[i-1]
            maxDrop = max(maxDrop, d)
        }
        XCTAssertLessThan(maxDrop, 6.0, "ramp must stay monotonic (no tonal inversions). maxDrop=\(maxDrop)")
        // Gradation preserved in every region. Shadows must stay fully open (no crush plateau).
        XCTAssertGreaterThan(shadowLevels, 30, "shadow gradation must be preserved (no crush plateau)")
        // The brightest quarter is compressed by the intentional filmic highlight shoulder
        // (roll-off), but must keep real gradation — a hard-clip plateau collapses to ≤3 levels.
        XCTAssertGreaterThan(highlightLevels, 6, "highlight gradation must survive the shoulder (no clip plateau)")
        // No hard-clip plateau at pure white (filmic roll-off, not clipping).
        XCTAssertLessThan(clipped255, width / 8, "highlights must roll off, not hard-clip a large plateau")
    }

    func testBrightHighlightSurvivesDenoisePlusAutoLevels() {
        // A neutral gradient 0.05..0.90 (so AutoLevels has a real range and runs its
        // CIColorMatrix stretch — the step that divided by the inflated alpha). After chroma
        // denoise + AutoLevels(outputWhite 0.95) the bright end must reach near white, not ~half.
        let size = 192
        var px = [Float](repeating: 0, count: size*size*4)
        for y in 0..<size { for x in 0..<size {
            let v = Float(0.05 + Double(x)/Double(size-1) * 0.85)
            let i = (y*size+x)*4; px[i]=v; px[i+1]=v; px[i+2]=v; px[i+3]=1
        }}
        let data = Data(bytes: px, count: px.count*MemoryLayout<Float>.size)
        let input = CIImage(bitmapData: data, bytesPerRow: size*4*MemoryLayout<Float>.size,
                            size: CGSize(width: size, height: size), format: .RGBAf, colorSpace: linear)
        var img = ScannerNoiseReduction.reduceMainTargetChroma(in: input)
        img = AutoLevels.apply(to: img, sampleColorSpace: linear, outputWhite: 0.95)
        let m = measure(img)
        XCTAssertGreaterThan(m.lumMax, 0.85,
                             "bright end must stretch toward white ~0.95 (regression: collapsed to ~0.45)")
    }
}
