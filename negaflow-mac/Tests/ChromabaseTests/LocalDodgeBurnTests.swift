import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class LocalDodgeBurnTests: XCTestCase {
    func testRadialDodgeBrightensCenterThroughDevelopEngineWithoutMovingCorners() {
        let input = makeLinearImage(width: 96, height: 72)
        var baselineParams = DevelopParameters()
        baselineParams.filmType = .colorPositive
        baselineParams.developTarget = .main

        var adjustedParams = baselineParams
        adjustedParams.localDodgeBurn = [
            LocalDodgeBurnAdjustment(
                mode: .dodge,
                amount: 0.7,
                mask: .radial(center: LocalDodgeBurnPoint(x: 0.50, y: 0.50), radius: 0.24, feather: 0.45)
            ),
        ]

        let engine = ChromabaseEngine()
        let baseline = render(engine.develop(image: input, base: nil, params: baselineParams), width: 96, height: 72)
        let adjusted = render(engine.develop(image: input, base: nil, params: adjustedParams), width: 96, height: 72)

        XCTAssertGreaterThan(
            meanLuma(adjusted, width: 96, rect: CGRect(x: 40, y: 28, width: 16, height: 16)),
            meanLuma(baseline, width: 96, rect: CGRect(x: 40, y: 28, width: 16, height: 16)) + 0.08
        )
        XCTAssertLessThan(
            abs(meanLuma(adjusted, width: 96, rect: CGRect(x: 2, y: 2, width: 14, height: 14)) -
                meanLuma(baseline, width: 96, rect: CGRect(x: 2, y: 2, width: 14, height: 14))),
            0.018
        )
    }

    func testBrushLinearAndPolygonMasksStayLocal() {
        let input = makeLinearImage(width: 128, height: 96, value: 0.42)

        let brush = LocalDodgeBurnAdjustment(
            mode: .dodge,
            amount: 0.65,
            mask: .brush(strokes: [
                LocalDodgeBurnStroke(
                    points: [LocalDodgeBurnPoint(x: 0.18, y: 0.52), LocalDodgeBurnPoint(x: 0.36, y: 0.52)],
                    thickness: 0.080,
                    feather: 0.025
                ),
            ])
        )
        assertLocalLift(
            LocalDodgeBurnStage.apply(to: input, adjustments: [brush]),
            control: input,
            changed: CGRect(x: 24, y: 40, width: 20, height: 16),
            guarded: CGRect(x: 98, y: 40, width: 20, height: 16),
            width: 128,
            height: 96,
            sign: 1
        )

        let linear = LocalDodgeBurnAdjustment(
            mode: .burn,
            amount: 0.55,
            mask: .linear(
                start: LocalDodgeBurnPoint(x: 0.50, y: 0.05),
                end: LocalDodgeBurnPoint(x: 0.50, y: 0.48),
                feather: 1.0
            )
        )
        assertLocalLift(
            LocalDodgeBurnStage.apply(to: input, adjustments: [linear]),
            control: input,
            changed: CGRect(x: 54, y: 6, width: 20, height: 16),
            guarded: CGRect(x: 54, y: 74, width: 20, height: 16),
            width: 128,
            height: 96,
            sign: -1
        )

        let polygon = LocalDodgeBurnAdjustment(
            mode: .burn,
            amount: 0.70,
            mask: .polygon(
                points: [
                    LocalDodgeBurnPoint(x: 0.66, y: 0.30),
                    LocalDodgeBurnPoint(x: 0.92, y: 0.32),
                    LocalDodgeBurnPoint(x: 0.82, y: 0.72),
                    LocalDodgeBurnPoint(x: 0.60, y: 0.68),
                ],
                feather: 0.030
            )
        )
        assertLocalLift(
            LocalDodgeBurnStage.apply(to: input, adjustments: [polygon]),
            control: input,
            changed: CGRect(x: 88, y: 48, width: 16, height: 16),
            guarded: CGRect(x: 12, y: 48, width: 16, height: 16),
            width: 128,
            height: 96,
            sign: -1
        )
    }

    func testDefaultDecodeAndZeroAmountAreNoops() throws {
        let decoded = try JSONDecoder().decode(DevelopParameters.self, from: Data("{}".utf8))
        XCTAssertTrue(decoded.localDodgeBurn.isEmpty)

        let input = makeLinearImage(width: 64, height: 48, value: 0.38)
        let zero = LocalDodgeBurnAdjustment(
            mode: .dodge,
            amount: 0,
            mask: .polygon(
                points: [
                    LocalDodgeBurnPoint(x: -0.3, y: -0.2),
                    LocalDodgeBurnPoint(x: 1.2, y: 0.2),
                    LocalDodgeBurnPoint(x: 0.6, y: 1.4),
                ],
                feather: 0.02
            )
        )

        let baseline = render(input, width: 64, height: 48)
        let adjusted = render(LocalDodgeBurnStage.apply(to: input, adjustments: [zero]), width: 64, height: 48)
        XCTAssertLessThan(maxAbsoluteDifference(baseline, adjusted), 0.0001)
    }

    private func assertLocalLift(
        _ output: CIImage,
        control: CIImage,
        changed: CGRect,
        guarded: CGRect,
        width: Int,
        height: Int,
        sign: Double
    ) {
        let baseline = render(control, width: width, height: height)
        let adjusted = render(output, width: width, height: height)
        let changedDelta = meanLuma(adjusted, width: width, rect: changed) - meanLuma(baseline, width: width, rect: changed)
        let guardDelta = meanLuma(adjusted, width: width, rect: guarded) - meanLuma(baseline, width: width, rect: guarded)

        XCTAssertGreaterThan(changedDelta * sign, 0.07)
        XCTAssertLessThan(abs(guardDelta), 0.015)
    }

    private func makeLinearImage(width: Int, height: Int, value: Float? = nil) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let t = value ?? (0.24 + Float(x) / Float(max(1, width - 1)) * 0.46)
                let i = (y * width + x) * 4
                pixels[i] = t * 1.02
                pixels[i + 1] = t
                pixels[i + 2] = t * 0.97
            }
        }
        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
    }

    private func render(_ image: CIImage, width: Int, height: Int) -> [Float] {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var out = [Float](repeating: 0, count: width * height * 4)
        CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear]).render(
            image,
            toBitmap: &out,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        return out
    }

    private func meanLuma(_ rgba: [Float], width: Int, rect: CGRect) -> Double {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(width, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(rgba.count / (width * 4), Int(rect.maxY.rounded(.up)))
        var sum = 0.0
        var count = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                let i = (y * width + x) * 4
                sum += Double(rgba[i]) * 0.2126 + Double(rgba[i + 1]) * 0.7152 + Double(rgba[i + 2]) * 0.0722
                count += 1
            }
        }
        return count == 0 ? 0 : sum / Double(count)
    }

    private func maxAbsoluteDifference(_ a: [Float], _ b: [Float]) -> Double {
        zip(a, b).map { abs(Double($0 - $1)) }.max() ?? 0
    }
}
