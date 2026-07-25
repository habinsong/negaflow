import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

final class RegionDefectDenseStressTests: XCTestCase {
    func testManyDefectsAcrossFramesRepeatedlyWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["NEGAFLOW_DENSE_DEFECT_STRESS"] == "1" else {
            throw XCTSkip("Set NEGAFLOW_DENSE_DEFECT_STRESS=1 to run repeated dense-defect 영역 결함 제거 stress.")
        }

        let width = 1_280, height = 960
        let roi = CGRect(x: 24, y: 24, width: width - 48, height: height - 48)
        let params = SoftwareDefectParameters(
            strength: 1,
            dustSensitivity: 1,
            scratchSensitivity: 1,
            protectDetail: 0.6
        )
        let fixtures = (0..<8).map { makeFixture(index: $0, width: width, height: height) }
        var samples: [[String: Any]] = []
        var totalComponents = 0

        for round in 0..<3 {
            for (frameIndex, fixture) in fixtures.enumerated() {
                let result = try autoreleasepool { () throws -> (Int, Double, Double, Double, Double) in
                    let detectStarted = Date()
                    let field = SoftwareDefectRemoval.detectComponents(
                        in: fixture.image,
                        roi: roi,
                        parameters: params
                    )
                    let detectSeconds = Date().timeIntervalSince(detectStarted)
                    let mask = SoftwareDefectRemoval.componentMaskBytes(
                        field: field,
                        excluded: [],
                        scratchDilate: 3
                    )
                    let covered = fixture.defectPoints.reduce(into: 0) { count, point in
                        let localX = point.x - Int(roi.minX)
                        let localY = point.y - Int(roi.minY)
                        guard localX >= 0, localY >= 0,
                              localX < field.width, localY < field.height else { return }
                        if mask[(localY * field.width + localX) * 4] > 0 { count += 1 }
                    }
                    let coverage = Double(covered) / Double(max(1, fixture.defectPoints.count))

                    let maskData = Data(mask)
                    let repairStarted = Date()
                    let repaired = try XCTUnwrap(SoftwareDefectRemoval.repair(
                        image: fixture.image,
                        roi: roi,
                        maskRGBA8: maskData,
                        width: field.width,
                        height: field.height
                    ))
                    var rendered = [UInt8](repeating: 0, count: width * height * 4)
                    DefectContext.render.render(
                        repaired,
                        toBitmap: &rendered,
                        rowBytes: width * 4,
                        bounds: CGRect(x: 0, y: 0, width: width, height: height),
                        format: .RGBA8,
                        colorSpace: fixture.colorSpace
                    )
                    let repairSeconds = Date().timeIntervalSince(repairStarted)
                    var residual = 0
                    for point in fixture.defectPoints {
                        let offset = (point.y * width + point.x) * 4
                        residual += abs(Int(rendered[offset]) - Int(fixture.clean[offset]))
                    }
                    let averageResidual = Double(residual) / Double(max(1, fixture.defectPoints.count))
                    return (field.components.count, detectSeconds, repairSeconds, coverage, averageResidual)
                }
                totalComponents += result.0
                samples.append([
                    "round": round,
                    "frame": frameIndex,
                    "components": result.0,
                    "detectSeconds": result.1,
                    "repairSeconds": result.2,
                    "totalSeconds": result.1 + result.2,
                    "maskCoverage": result.3,
                    "averageDefectResidual": result.4,
                ])
                XCTAssertGreaterThan(result.0, 100)
                XCTAssertGreaterThan(result.3, 0.82)
                XCTAssertLessThan(result.4, 24)
            }
        }

        XCTAssertGreaterThan(totalComponents, 2_400)
        if let path = ProcessInfo.processInfo.environment["NEGAFLOW_DENSE_DEFECT_REPORT"], !path.isEmpty {
            let totals = samples.compactMap { $0["totalSeconds"] as? Double }.sorted()
            let report: [String: Any] = [
                "schemaVersion": 1,
                "frameCount": fixtures.count,
                "roundCount": 3,
                "operationCount": samples.count,
                "medianFrameSeconds": percentile(totals, 0.5),
                "p95FrameSeconds": percentile(totals, 0.95),
                "maxFrameSeconds": totals.max() ?? 0,
                "samples": samples,
            ]
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: url, options: .atomic)
        }
    }

    private struct Fixture {
        let image: CIImage
        let clean: [UInt8]
        let defectPoints: [(x: Int, y: Int)]
        let colorSpace: CGColorSpace
    }

    private func makeFixture(index: Int, width: Int, height: Int) -> Fixture {
        let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var clean = [UInt8](repeating: 255, count: width * height * 4)
        var seed = UInt64(0xD357 + index * 7919)
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let grain = Int(seed >> 61) - 3
                let value = UInt8(max(20, min(230, 72 + 116 * x / width + 18 * y / height + grain)))
                let offset = (y * width + x) * 4
                clean[offset] = value
                clean[offset + 1] = value
                clean[offset + 2] = value
            }
        }
        var damaged = clean
        var points = Set<Int>()
        for row in 0..<14 {
            for column in 0..<18 {
                let cx = 55 + column * 66 + (index * 11 + row * 7) % 17
                let cy = 55 + row * 61 + (index * 13 + column * 5) % 19
                let radius = 2 + (row + column + index) % 3
                for y in (cy - radius)...(cy + radius) {
                    for x in (cx - radius)...(cx + radius)
                    where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius {
                        paint(&damaged, width: width, x: x, y: y, delta: 76)
                        points.insert(y * width + x)
                    }
                }
            }
        }
        for line in 0..<10 {
            for y in 80..<(height - 80) {
                let x = 85 + line * 112 + Int((12 * sin(Double(y + index * 17 + line * 23) / 31)).rounded())
                for dx in -1...1 {
                    paint(&damaged, width: width, x: x + dx, y: y, delta: 62)
                    points.insert(y * width + x + dx)
                }
            }
        }
        let image = CIImage(
            bitmapData: Data(damaged),
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: colorSpace
        )
        return Fixture(
            image: image,
            clean: clean,
            defectPoints: points.map { ($0 % width, $0 / width) },
            colorSpace: colorSpace
        )
    }

    private func paint(_ bytes: inout [UInt8], width: Int, x: Int, y: Int, delta: Int) {
        let offset = (y * width + x) * 4
        let value = UInt8(min(255, Int(bytes[offset]) + delta))
        bytes[offset] = value
        bytes[offset + 1] = value
        bytes[offset + 2] = value
    }

    private func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let index = min(values.count - 1, max(0, Int(ceil(Double(values.count) * fraction)) - 1))
        return values[index]
    }
}
