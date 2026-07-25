import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class RegionDefectDustScaleDensityTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    private let defaultParameters = SoftwareDefectParameters(
        strength: 1,
        dustSensitivity: 0.45,
        scratchSensitivity: 0.55,
        protectDetail: 0.6
    )

    private func image(_ pixels: [UInt8], width: Int, height: Int) -> CIImage {
        CIImage(
            bitmapData: Data(pixels),
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: linear
        )
    }

    private func background(width: Int, height: Int, value: UInt8 = 120) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for pixel in 0..<(width * height) {
            let offset = pixel * 4
            pixels[offset] = value
            pixels[offset + 1] = value
            pixels[offset + 2] = value
        }
        return pixels
    }

    private func paintSquare(_ pixels: inout [UInt8], width: Int,
                             centerX: Int, centerY: Int, radius: Int, value: UInt8) {
        for y in (centerY - radius)...(centerY + radius) {
            for x in (centerX - radius)...(centerX + radius) {
                let offset = (y * width + x) * 4
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
            }
        }
    }

    private func render(_ image: CIImage, width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        CIContext(options: [.workingColorSpace: linear]).render(
            image,
            toBitmap: &pixels,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: linear
        )
        return pixels
    }

    private func value(_ pixels: [UInt8], width: Int, x: Int, y: Int) -> Int {
        Int(pixels[(y * width + x) * 4])
    }

    func testDetectedLargeDebrisMaskCoversItsInteriorBeforeRepair() throws {
        let width = 320
        let height = 320
        let center = 120
        var pixels = background(width: width, height: height)
        paintSquare(&pixels, width: width, centerX: center, centerY: center,
                    radius: 22, value: 210)
        paintSquare(&pixels, width: width, centerX: center, centerY: center,
                    radius: 19, value: 176)
        let input = image(pixels, width: width, height: height)
        let roi = CGRect(x: 0, y: height - 240, width: 240, height: 240)
        let field = SoftwareDefectRemoval.detectComponents(in: input, roi: roi, parameters: defaultParameters)
        XCTAssertFalse(field.isEmpty)

        let mask = SoftwareDefectRemoval.componentMaskBytes(field: field, excluded: [])
        XCTAssertGreaterThan(mask[(center * field.width + center) * 4], 0)

        let repaired = try XCTUnwrap(
            SoftwareDefectRemoval.repairComponents(image: input, roi: roi, field: field, excluded: [])
        )
        let output = render(repaired, width: width, height: height)
        XCTAssertLessThan(abs(value(output, width: width, x: center, y: center) - 120), 16)
    }

    func testTinyFaintResidueIsDetectedAndRemoved() throws {
        let width = 240
        let height = 240
        let center = 80
        var pixels = background(width: width, height: height)
        paintSquare(&pixels, width: width, centerX: center, centerY: center,
                    radius: 1, value: 138)
        let input = image(pixels, width: width, height: height)
        let roi = CGRect(x: 0, y: height - 180, width: 180, height: 180)

        let field = SoftwareDefectRemoval.detectComponents(
            in: input,
            roi: roi,
            parameters: defaultParameters
        )
        XCTAssertNotNil(field.nearestComponentID(atX: center, y: center, radius: 3))

        let repaired = try XCTUnwrap(
            SoftwareDefectRemoval.repairComponents(image: input, roi: roi, field: field, excluded: [])
        )
        let output = render(repaired, width: width, height: height)
        XCTAssertLessThan(abs(value(output, width: width, x: center, y: center) - 120), 8)
    }

    func testLargeCompactDebrisIsDetectedAcrossItsCenterAndRemoved() throws {
        let width = 400
        let height = 400
        let center = 160
        var pixels = background(width: width, height: height)
        paintSquare(&pixels, width: width, centerX: center, centerY: center,
                    radius: 27, value: 210)
        let input = image(pixels, width: width, height: height)
        let roi = CGRect(x: 0, y: height - 320, width: 320, height: 320)

        let field = SoftwareDefectRemoval.detectComponents(
            in: input,
            roi: roi,
            parameters: defaultParameters
        )
        XCTAssertNotNil(field.nearestComponentID(atX: center, y: center, radius: 3))

        let mask = SoftwareDefectRemoval.componentMaskBytes(field: field, excluded: [])
        XCTAssertGreaterThan(mask[(center * field.width + center) * 4], 0)

        let repaired = try XCTUnwrap(
            SoftwareDefectRemoval.repairComponents(image: input, roi: roi, field: field, excluded: [])
        )
        let output = render(repaired, width: width, height: height)
        XCTAssertLessThan(abs(value(output, width: width, x: center, y: center) - 120), 16)
    }

    func testDenseDustDoesNotDisappearWhenParticlesAreDetectedTogether() throws {
        let width = 300
        let height = 300
        var pixels = background(width: width, height: height)
        var centers: [(Int, Int)] = []
        for row in 0..<4 {
            for column in 0..<4 {
                let x = 82 + column * 18
                let y = 82 + row * 18
                centers.append((x, y))
                paintSquare(&pixels, width: width, centerX: x, centerY: y,
                            radius: 1, value: 205)
            }
        }
        let input = image(pixels, width: width, height: height)
        let roi = CGRect(x: 0, y: height - 220, width: 220, height: 220)

        let field = SoftwareDefectRemoval.detectComponents(
            in: input,
            roi: roi,
            parameters: defaultParameters
        )
        for (x, y) in centers {
            XCTAssertNotNil(
                field.nearestComponentID(atX: x, y: y, radius: 3),
                "밀집 먼지 (\(x), \(y))가 함께 검출될 때 누락됐습니다."
            )
        }

        let repaired = try XCTUnwrap(
            SoftwareDefectRemoval.repairComponents(image: input, roi: roi, field: field, excluded: [])
        )
        let output = render(repaired, width: width, height: height)
        for (x, y) in centers {
            XCTAssertLessThan(abs(value(output, width: width, x: x, y: y) - 120), 12)
        }
    }

    func testDenseLowContrastFineGrainIsNotReportedAsDust() {
        let width = 360
        let height = 360
        var pixels = background(width: width, height: height)
        for y in stride(from: 58, through: 298, by: 12) {
            for x in stride(from: 58, through: 298, by: 12) {
                for py in y..<(y + 2) {
                    for px in x..<(x + 2) {
                        let offset = (py * width + px) * 4
                        pixels[offset] = 138
                        pixels[offset + 1] = 138
                        pixels[offset + 2] = 138
                    }
                }
            }
        }
        let input = image(pixels, width: width, height: height)
        let roi = CGRect(x: 20, y: 20, width: 320, height: 320)

        let field = SoftwareDefectRemoval.detectComponents(
            in: input,
            roi: roi,
            parameters: defaultParameters
        )
        XCTAssertLessThan(
            field.components.count,
            5,
            "반복되는 저대비 2×2 필름 입자를 미세 먼지로 대량 오검출하면 안 됩니다."
        )
    }

    func testPartialROIDetectionStopsBeforeStartingCancelledWork() {
        let width = 320
        let height = 320
        let input = image(background(width: width, height: height), width: width, height: height)
        let field = SoftwareDefectRemoval.detectComponents(
            in: input,
            roi: CGRect(x: 20, y: 20, width: 280, height: 280),
            parameters: defaultParameters,
            shouldCancel: { true }
        )
        XCTAssertTrue(field.isEmpty)
    }

    func testPartialROILargeDetectionPerformance() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DEFECT_PERF"] != nil,
            "성능 측정은 DEFECT_PERF=1 + Release(-c release)에서만 실행합니다."
        )
        let width = 1_700
        let height = 1_700
        var pixels = background(width: width, height: height)
        for y in stride(from: 180, through: 1_500, by: 260) {
            for x in stride(from: 180, through: 1_500, by: 260) {
                paintSquare(&pixels, width: width, centerX: x, centerY: y, radius: 2, value: 205)
            }
        }
        let input = image(pixels, width: width, height: height)
        let start = CFAbsoluteTimeGetCurrent()
        _ = SoftwareDefectRemoval.detectComponents(
            in: input,
            roi: CGRect(x: 50, y: 50, width: 1_600, height: 1_600),
            parameters: defaultParameters
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        print("[perf] partial 1600x1600 영역 결함 제거 = \(String(format: "%.2f", elapsed))s")
        XCTAssertLessThan(elapsed, 2.0)
    }
}
