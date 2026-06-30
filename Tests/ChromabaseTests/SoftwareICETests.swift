import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class SoftwareICETests: XCTestCase {
    func testDetectMaskFindsThinHorizontalScratchOnMidtone() {
        let width = 96
        let height = 48
        let image = makeLinearImage(width: width, height: height) { x, y in
            if (18..<78).contains(x), (24...25).contains(y) {
                return SIMD3<Float>(repeating: 0.95)
            }
            return SIMD3<Float>(0.34, 0.35, 0.36)
        }

        let mask = SoftwareICE.detectMask(
            in: image,
            parameters: SoftwareICEParameters(
                strength: 1,
                dustSensitivity: 0.7,
                scratchSensitivity: 0.95,
                protectDetail: 0.8
            )
        )
        let rendered = renderLinearRGBA(mask, width: width, height: height)

        XCTAssertGreaterThan(
            averageLuma(rendered, width: width, rect: CGRect(x: 24, y: 24, width: 48, height: 2)),
            0.55,
            "중간톤 위 1-2px 가로 스크래치는 마스크에 강하게 잡혀야 한다."
        )
        XCTAssertLessThan(
            averageLuma(rendered, width: width, rect: CGRect(x: 24, y: 8, width: 48, height: 8)),
            0.08,
            "스크래치가 없는 중간톤 평면은 오탐되면 안 된다."
        )
    }

    func testDetectMaskFindsThinVerticalScratch() {
        let width = 64
        let height = 96
        let image = makeLinearImage(width: width, height: height) { x, y in
            if (30...31).contains(x), (16..<80).contains(y) {
                return SIMD3<Float>(repeating: 0.92)
            }
            return SIMD3<Float>(0.34, 0.35, 0.36)
        }

        let mask = SoftwareICE.detectMask(
            in: image,
            parameters: SoftwareICEParameters(
                strength: 1,
                dustSensitivity: 0.7,
                scratchSensitivity: 0.95,
                protectDetail: 0.8
            )
        )
        let rendered = renderLinearRGBA(mask, width: width, height: height)

        XCTAssertGreaterThan(
            averageLuma(rendered, width: width, rect: CGRect(x: 30, y: 30, width: 2, height: 40)),
            0.5,
            "세로 얇은 스크래치도 다방향 검출로 잡혀야 한다."
        )
        XCTAssertLessThan(
            averageLuma(rendered, width: width, rect: CGRect(x: 8, y: 30, width: 8, height: 40)),
            0.08,
            "스크래치 없는 평면은 오탐되면 안 된다."
        )
    }

    func testDetectMaskSuppressesGrainTextureWithoutDefect() {
        let width = 128
        let height = 128
        // 결함 없는 결정적 그레인 평면(±0.024). 대량 오탐이 나면 안 된다.
        let image = makeLinearImage(width: width, height: height) { x, y in
            let n = Float((x * 7 + y * 13) % 5 - 2) * 0.012
            let v = 0.5 + n
            return SIMD3<Float>(v, v, v)
        }

        let mask = SoftwareICE.detectMask(
            in: image,
            parameters: SoftwareICEParameters(
                strength: 1,
                dustSensitivity: 0.7,
                scratchSensitivity: 0.85,
                protectDetail: 0.8
            )
        )
        let rendered = renderLinearRGBA(mask, width: width, height: height)

        XCTAssertLessThan(
            averageLuma(rendered, width: width, rect: CGRect(x: 0, y: 0, width: width, height: height)),
            0.02,
            "결함 없는 그레인 텍스처는 대량 오탐되면 안 된다(adaptive noise floor)."
        )
    }

    func testDetectMaskBrushConstrainsToPaintedRegion() {
        let width = 96
        let height = 96
        // 동일한 두 세로 선: 스크래치(x≈20)와 "구조물"(x≈70). 브러시는 스크래치만 덮는다.
        let image = makeLinearImage(width: width, height: height) { x, y in
            let onScratch = (19...20).contains(x) && (10..<86).contains(y)
            let onStructure = (70...71).contains(x) && (10..<86).contains(y)
            return (onScratch || onStructure) ? SIMD3<Float>(repeating: 0.9) : SIMD3<Float>(0.40, 0.41, 0.42)
        }
        let brush = makeLinearImage(width: width, height: height) { x, y in
            ((14...26).contains(x) && (6..<90).contains(y)) ? SIMD3<Float>(repeating: 1) : SIMD3<Float>(repeating: 0)
        }
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.7, scratchSensitivity: 0.9, protectDetail: 0.7)
        let mask = SoftwareICE.detectMask(in: image, parameters: params, brush: brush)
        let rendered = renderLinearRGBA(mask, width: width, height: height)

        XCTAssertGreaterThan(
            averageLuma(rendered, width: width, rect: CGRect(x: 18, y: 30, width: 4, height: 30)),
            0.3,
            "브러시로 칠한 스크래치는 검출되어야 한다."
        )
        XCTAssertLessThan(
            averageLuma(rendered, width: width, rect: CGRect(x: 68, y: 30, width: 6, height: 30)),
            0.05,
            "브러시 밖의 동일한 구조물은 검출되면 안 된다(ROI 한정)."
        )
    }

    func testApplyWithBrushRepairExtentLeavesOutsidePixelsUnchanged() {
        let width = 128
        let height = 80
        let image = makeLinearImage(width: width, height: height) { x, y in
            let leftScratch = x == 24 && (12..<68).contains(y)
            let rightScratch = x == 100 && (12..<68).contains(y)
            return (leftScratch || rightScratch) ? SIMD3<Float>(repeating: 0.95) : SIMD3<Float>(0.36, 0.37, 0.38)
        }
        let brush = makeLinearImage(width: width, height: height) { x, y in
            ((18...31).contains(x) && (8..<72).contains(y)) ? SIMD3<Float>(repeating: 1) : SIMD3<Float>(repeating: 0)
        }
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.75, scratchSensitivity: 0.95, protectDetail: 0.7)

        let repaired = SoftwareICE.apply(
            to: image,
            parameters: params,
            brush: brush,
            repairExtent: CGRect(x: 10, y: 4, width: 34, height: 72)
        )
        let before = renderLinearRGBA(image, width: width, height: height)
        let after = renderLinearRGBA(repaired, width: width, height: height)

        XCTAssertGreaterThan(
            averageLuma(before, width: width, rect: CGRect(x: 24, y: 24, width: 2, height: 30))
                - averageLuma(after, width: width, rect: CGRect(x: 24, y: 24, width: 2, height: 30)),
            0.2,
            "브러시 ROI 안의 스크래치는 복원으로 밝기가 줄어야 한다."
        )
        XCTAssertLessThan(
            maxChannelDelta(before, after, width: width, rect: CGRect(x: 98, y: 12, width: 5, height: 56)),
            0.001,
            "repairExtent 밖의 동일한 선 구조는 비트맵 결과가 바뀌면 안 된다."
        )
    }

    func testApplyWithBrushRepairsDetectedScratchNotWholeBrushStroke() {
        let width = 128
        let height = 80
        let image = makeLinearImage(width: width, height: height) { x, y in
            let scratch = (24...25).contains(x) && (12..<68).contains(y)
            if scratch {
                return SIMD3<Float>(repeating: 0.95)
            }
            let v = Float(0.22 + Double(x) * 0.006)
            return SIMD3<Float>(v, v * 0.92, v * 0.84)
        }
        let brush = makeLinearImage(width: width, height: height) { x, y in
            ((16...48).contains(x) && (8..<72).contains(y)) ? SIMD3<Float>(repeating: 1) : SIMD3<Float>(repeating: 0)
        }
        let params = SoftwareICEParameters(strength: 1, dustSensitivity: 0.75, scratchSensitivity: 0.95, protectDetail: 0.7)

        let repaired = SoftwareICE.apply(
            to: image,
            parameters: params,
            brush: brush,
            repairExtent: CGRect(x: 8, y: 4, width: 52, height: 72)
        )
        let before = renderLinearRGBA(image, width: width, height: height)
        let after = renderLinearRGBA(repaired, width: width, height: height)

        XCTAssertGreaterThan(
            averageLuma(before, width: width, rect: CGRect(x: 24, y: 24, width: 2, height: 30))
                - averageLuma(after, width: width, rect: CGRect(x: 24, y: 24, width: 2, height: 30)),
            0.2,
            "브러시 안의 실제 스크래치는 제거되어야 한다."
        )
        XCTAssertLessThan(
            maxChannelDelta(before, after, width: width, rect: CGRect(x: 38, y: 24, width: 6, height: 30)),
            0.01,
            "브러시로 칠했지만 결함이 아닌 내부 픽셀은 브러시 굵기만큼 우그러지면 안 된다."
        )
    }

    func testDetectMaskKeepsWideHighlightStructureProtected() {
        let width = 96
        let height = 48
        let image = makeLinearImage(width: width, height: height) { x, y in
            if (18..<78).contains(x), (20..<30).contains(y) {
                return SIMD3<Float>(repeating: 0.92)
            }
            return SIMD3<Float>(repeating: 0.36)
        }

        let mask = SoftwareICE.detectMask(
            in: image,
            parameters: SoftwareICEParameters(
                strength: 1,
                dustSensitivity: 0.7,
                scratchSensitivity: 0.95,
                protectDetail: 1
            )
        )
        let rendered = renderLinearRGBA(mask, width: width, height: height)

        XCTAssertLessThan(
            averageLuma(rendered, width: width, rect: CGRect(x: 24, y: 21, width: 48, height: 8)),
            0.08,
            "넓은 흰 구조물/하이라이트 면은 얇은 스크래치로 오탐되면 안 된다."
        )
    }

    func testDetectMaskKeepsDarkStructuralEdgesProtected() {
        let width = 96
        let height = 48
        let image = makeLinearImage(width: width, height: height) { x, y in
            if (18..<78).contains(x), (12..<36).contains(y) {
                return SIMD3<Float>(0.08, 0.09, 0.10)
            }
            return SIMD3<Float>(0.38, 0.39, 0.40)
        }

        let mask = SoftwareICE.detectMask(
            in: image,
            parameters: SoftwareICEParameters(
                strength: 1,
                dustSensitivity: 0.7,
                scratchSensitivity: 0.95,
                protectDetail: 1
            )
        )
        let rendered = renderLinearRGBA(mask, width: width, height: height)

        XCTAssertLessThan(
            averageLuma(rendered, width: width, rect: CGRect(x: 17, y: 12, width: 3, height: 24)),
            0.08,
            "암부 구조물의 강한 경계는 먼지/스크래치로 오탐되면 안 된다."
        )
    }

    func testOverlayMaskPaintsDetectedPixelsRed() {
        let width = 24
        let height = 16
        let image = makeLinearImage(width: width, height: height) { _, _ in
            SIMD3<Float>(repeating: 0.35)
        }
        let mask = makeLinearImage(width: width, height: height) { x, y in
            (x == 12 && y == 8) ? SIMD3<Float>(repeating: 1) : SIMD3<Float>(repeating: 0)
        }

        let overlay = SoftwareICE.overlayMask(on: image, mask: mask, opacity: 0.8)
        let rendered = renderRGBA8(overlay, width: width, height: height)
        let redPixel = rgba(rendered, width: width, x: 12, y: 8)
        let plainPixel = rgba(rendered, width: width, x: 4, y: 4)

        XCTAssertGreaterThan(redPixel.r, redPixel.g + 60, "마스크 픽셀은 빨간 overlay로 보여야 한다.")
        XCTAssertLessThan(abs(Int(plainPixel.r) - Int(plainPixel.g)), 10, "마스크 밖 픽셀은 원래 회색에 가까워야 한다.")
    }

    private func makeLinearImage(
        width: Int,
        height: Int,
        pixel: (Int, Int) -> SIMD3<Float>
    ) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let color = pixel(x, y)
                let offset = (y * width + x) * 4
                pixels[offset] = color.x
                pixels[offset + 1] = color.y
                pixels[offset + 2] = color.z
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

    private func renderLinearRGBA(_ image: CIImage, width: Int, height: Int) -> [Float] {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var rendered = [Float](repeating: 0, count: width * height * 4)
        CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear]).render(
            image,
            toBitmap: &rendered,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
        return rendered
    }

    private func renderRGBA8(_ image: CIImage, width: Int, height: Int) -> [UInt8] {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var rendered = [UInt8](repeating: 0, count: width * height * 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            image,
            toBitmap: &rendered,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: colorSpace
        )
        return rendered
    }

    private func averageLuma(_ buffer: [Float], width: Int, rect: CGRect) -> Double {
        let minX = Int(rect.minX)
        let maxX = Int(rect.maxX)
        let minY = Int(rect.minY)
        let maxY = Int(rect.maxY)
        var sum = 0.0
        var count = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                let offset = (y * width + x) * 4
                sum += Double(buffer[offset]) * 0.2126
                    + Double(buffer[offset + 1]) * 0.7152
                    + Double(buffer[offset + 2]) * 0.0722
                count += 1
            }
        }
        return count == 0 ? 0 : sum / Double(count)
    }

    private func rgba(_ buffer: [UInt8], width: Int, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let offset = (y * width + x) * 4
        return (Int(buffer[offset]), Int(buffer[offset + 1]), Int(buffer[offset + 2]))
    }

    private func luma(_ buffer: [Float], width: Int, x: Int, y: Int) -> Double {
        let offset = (y * width + x) * 4
        return Double(buffer[offset]) * 0.2126
            + Double(buffer[offset + 1]) * 0.7152
            + Double(buffer[offset + 2]) * 0.0722
    }

    private func maxChannelDelta(_ lhs: [Float], _ rhs: [Float], width: Int, rect: CGRect) -> Double {
        let minX = Int(rect.minX)
        let maxX = Int(rect.maxX)
        let minY = Int(rect.minY)
        let maxY = Int(rect.maxY)
        var maxDelta = 0.0
        for y in minY..<maxY {
            for x in minX..<maxX {
                let offset = (y * width + x) * 4
                for c in 0..<3 {
                    maxDelta = max(maxDelta, Double(abs(lhs[offset + c] - rhs[offset + c])))
                }
            }
        }
        return maxDelta
    }
}
