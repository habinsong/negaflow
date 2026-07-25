import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

final class RegionDefectLargeROIRegressionTests: XCTestCase {
    private let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)!
    private let parameters = SoftwareDefectParameters(
        strength: 1,
        dustSensitivity: (3.0 - 0.7) / (6.0 - 0.7),
        scratchSensitivity: (3.0 - 0.7) / (6.0 - 0.7) + 0.1,
        protectDetail: 0.6
    )

    func testRepeatedTiledDetectionIsByteDeterministic() {
        let fixture = makeFixture(width: 960, height: 720)
        let roi = CGRect(x: 40, y: 40, width: 880, height: 640)
        var baselineMask: [UInt8]?
        var baselineGeometry: [ComponentGeometry]?

        for _ in 0..<3 {
            let field = SoftwareDefectRemoval.detectComponents(
                in: fixture.image,
                roi: roi,
                parameters: parameters,
                tileMax: 440,
                halo: 48
            )
            let mask = SoftwareDefectRemoval.componentMaskBytes(field: field, excluded: [])
            let geometry = normalizedGeometry(field)
            if let baselineMask, let baselineGeometry {
                XCTAssertEqual(mask, baselineMask)
                XCTAssertEqual(geometry, baselineGeometry)
            } else {
                baselineMask = mask
                baselineGeometry = geometry
            }
        }
    }

    func testTiledAndUntiledDetectionMatchAtTileSeams() {
        let fixture = makeFixture(width: 960, height: 720)
        let roi = CGRect(x: 40, y: 40, width: 880, height: 640)
        let untiled = SoftwareDefectRemoval.detectComponents(
            in: fixture.image,
            roi: roi,
            parameters: parameters,
            tileMax: 1_200,
            halo: 48
        )
        let tiled = SoftwareDefectRemoval.detectComponents(
            in: fixture.image,
            roi: roi,
            parameters: parameters,
            tileMax: 440,
            halo: 48
        )

        let untiledMask = SoftwareDefectRemoval.componentMaskBytes(field: untiled, excluded: [])
        let tiledMask = SoftwareDefectRemoval.componentMaskBytes(field: tiled, excluded: [])
        var defectMismatchCount = 0
        var tiledDefectCount = 0
        var untiledDefectCount = 0
        for point in fixture.defectPoints {
            let localX = point.x - Int(roi.minX)
            let localY = point.y - Int(roi.minY)
            guard localX >= 0, localY >= 0, localX < untiled.width, localY < untiled.height else { continue }
            let offset = (localY * untiled.width + localX) * 4
            if tiledMask[offset] > 0 { tiledDefectCount += 1 }
            if untiledMask[offset] > 0 { untiledDefectCount += 1 }
            if (tiledMask[offset] > 0) != (untiledMask[offset] > 0) { defectMismatchCount += 1 }
        }
        XCTAssertEqual(
            defectMismatchCount, 0,
            "타일 경계 실제 결함 중 \(defectMismatchCount)픽셀이 달라졌습니다"
                + "(tiled=\(tiledDefectCount), untiled=\(untiledDefectCount))."
        )

        let maskMismatchCount = zip(tiledMask, untiledMask).reduce(into: 0) { count, pair in
            if pair.0 != pair.1 { count += 1 }
        }
        XCTAssertEqual(maskMismatchCount, 0, "타일/단일 ROI 마스크가 \(maskMismatchCount)바이트 달라졌습니다.")
        let tiledGeometry = normalizedGeometry(tiled)
        let untiledGeometry = normalizedGeometry(untiled)
        XCTAssertTrue(
            tiledGeometry == untiledGeometry,
            "컴포넌트 geometry가 다릅니다: tiled=\(tiledGeometry.count), untiled=\(untiledGeometry.count)"
        )
    }

    func testFineGrainDensityDoesNotScaleIntoLargeROIFalsePositives() {
        let width = 960
        let height = 720
        let fixture = makeFixture(width: width, height: height, includeDefects: false)
        let smallROI = CGRect(x: 280, y: 200, width: 400, height: 320)
        let largeROI = CGRect(x: 40, y: 40, width: 880, height: 640)
        let small = SoftwareDefectRemoval.detectComponents(
            in: fixture.image,
            roi: smallROI,
            parameters: parameters,
            tileMax: 1_200
        )
        let large = SoftwareDefectRemoval.detectComponents(
            in: fixture.image,
            roi: largeROI,
            parameters: parameters,
            tileMax: 440,
            halo: 48
        )

        let smallDensity = Double(small.components.count) / (smallROI.width * smallROI.height / 1_000_000)
        let largeDensity = Double(large.components.count) / (largeROI.width * largeROI.height / 1_000_000)
        XCTAssertLessThanOrEqual(large.components.count, 8, "큰 ROI에서 필름 그레인이 결함 후보로 폭증했습니다.")
        XCTAssertLessThanOrEqual(
            largeDensity,
            max(8, smallDensity * 1.25),
            "ROI 면적을 키웠을 때 단위 면적당 그레인 오검출이 증가하면 안 됩니다."
        )
    }

    private struct Fixture {
        let image: CIImage
        let defectPoints: [(x: Int, y: Int)]
    }

    private struct ComponentGeometry: Equatable, Comparable {
        let kind: Int
        let minX: Int
        let minY: Int
        let maxX: Int
        let maxY: Int
        let count: Int

        static func < (lhs: ComponentGeometry, rhs: ComponentGeometry) -> Bool {
            (lhs.kind, lhs.minY, lhs.minX, lhs.maxY, lhs.maxX, lhs.count)
                < (rhs.kind, rhs.minY, rhs.minX, rhs.maxY, rhs.maxX, rhs.count)
        }
    }

    private func normalizedGeometry(_ field: DefectLabelField) -> [ComponentGeometry] {
        field.components.map { component in
            ComponentGeometry(
                kind: component.kind == .dust ? 0 : 1,
                minX: component.minX,
                minY: component.minY,
                maxX: component.maxX,
                maxY: component.maxY,
                count: Set(component.pixels).count
            )
        }.sorted()
    }

    private func makeFixture(width: Int, height: Int, includeDefects: Bool = true) -> Fixture {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var seed: UInt64 = 0x4E454741464C4F57
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let fine = Int(seed >> 61) - 3
                let correlated = ((x / 2) * 17 + (y / 2) * 29) % 7 - 3
                let base = 92 + 68 * x / width + 24 * y / height
                let value = UInt8(max(18, min(235, base + fine + correlated)))
                let offset = (y * width + x) * 4
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
            }
        }

        // 고대비 1~2px 입자가 촘촘히 존재하는 필름 그레인/스캔 노이즈 구간.
        for y in stride(from: 72, to: height - 72, by: 13) {
            for x in stride(from: 72, to: width - 72, by: 13) {
                let offset = (y * width + x) * 4
                let delta = ((x + y) & 1) == 0 ? 42 : -42
                for channel in 0..<3 {
                    pixels[offset + channel] = UInt8(max(0, min(255, Int(pixels[offset + channel]) + delta)))
                }
            }
        }

        var defectPoints: [(x: Int, y: Int)] = []
        if includeDefects {
            // tileMax=440일 때 ROI local seam인 x=440/y=320 주변을 가로지르는 실제 결함들.
            paintDisk(&pixels, width: width, height: height, centerX: 480, centerY: 360,
                      radius: 20, delta: 72, points: &defectPoints)
            paintDisk(&pixels, width: width, height: height, centerX: 477, centerY: 250,
                      radius: 3, delta: -62, points: &defectPoints)
            for x in 300..<660 {
                let y = 357 + Int((9 * sin(Double(x) / 23)).rounded())
                paint(&pixels, width: width, height: height, x: x, y: y, delta: 36)
                defectPoints.append((x, y))
            }
        }

        return Fixture(
            image: CIImage(
                bitmapData: Data(pixels),
                bytesPerRow: width * 4,
                size: CGSize(width: width, height: height),
                format: .RGBA8,
                colorSpace: colorSpace
            ),
            defectPoints: defectPoints
        )
    }

    private func paintDisk(_ pixels: inout [UInt8], width: Int, height: Int,
                           centerX: Int, centerY: Int, radius: Int, delta: Int,
                           points: inout [(x: Int, y: Int)]) {
        for y in (centerY - radius)...(centerY + radius) {
            for x in (centerX - radius)...(centerX + radius)
            where (x - centerX) * (x - centerX) + (y - centerY) * (y - centerY) <= radius * radius {
                paint(&pixels, width: width, height: height, x: x, y: y, delta: delta)
                points.append((x, y))
            }
        }
    }

    private func paint(_ pixels: inout [UInt8], width: Int, height: Int,
                       x: Int, y: Int, delta: Int) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let offset = (y * width + x) * 4
        for channel in 0..<3 {
            pixels[offset + channel] = UInt8(max(0, min(255, Int(pixels[offset + channel]) + delta)))
        }
    }
}
