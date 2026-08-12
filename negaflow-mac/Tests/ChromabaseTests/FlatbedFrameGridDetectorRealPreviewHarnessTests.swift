import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Chromabase

/// 실제 프리뷰 위에 검출 사각형을 직접 그리는 opt-in 진단 하네스.
///
/// 앱의 회전·현상·SwiftUI 좌표 변환을 거치지 않으므로, 검출 결과 자체와 화면 표시 문제를
/// 분리할 수 있다. 실행 예:
///
/// ```
/// NEGAFLOW_FLATBED_PREVIEW_DIRS="/path/one:/path/two" \
/// NEGAFLOW_FLATBED_FRAME_FORMAT="fullFrame35mm" \
/// NEGAFLOW_FLATBED_ARTIFACT_DIR="/tmp/flatbed-overlays" \
/// swift test --filter FlatbedFrameGridDetectorRealPreviewHarnessTests
/// ```
final class FlatbedFrameGridDetectorRealPreviewHarnessTests: XCTestCase {
    func testWritesDetectionOverlaysAndMeasurementsWhenRequested() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rawDirectories = environment["NEGAFLOW_FLATBED_PREVIEW_DIRS"],
              !rawDirectories.isEmpty else {
            throw XCTSkip("NEGAFLOW_FLATBED_PREVIEW_DIRS가 지정되지 않았습니다.")
        }
        let rawFormat = try XCTUnwrap(
            environment["NEGAFLOW_FLATBED_FRAME_FORMAT"],
            "NEGAFLOW_FLATBED_FRAME_FORMAT이 지정되지 않았습니다."
        )
        let frameFormat = try XCTUnwrap(
            FilmFrameFormat(rawValue: rawFormat),
            "지원하지 않는 프레임 규격: \(rawFormat)"
        )

        let directories = rawDirectories
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }
        let files = try directories.flatMap(previewFiles).sorted { $0.path < $1.path }
        XCTAssertFalse(files.isEmpty, "실제 프리뷰 파일이 없습니다.")

        let outputDirectory = environment["NEGAFLOW_FLATBED_ARTIFACT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                "negaflow-flatbed-overlays-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        var measurements = [
            "fixture\tcount\tdetector_ms\trow\tcolumn\tx_mm\ty_mm\twidth_mm\theight_mm\tconfidence"
        ]
        for file in files {
            let physicalSize = try XCTUnwrap(
                FlatbedFrameGridDetector.physicalSizeMM(url: file),
                file.path
            )
            let startedAt = CFAbsoluteTimeGetCurrent()
            let detections = FlatbedFrameGridDetector.detect(
                url: file,
                physicalSize: physicalSize,
                frameFormat: frameFormat
            )
            let detectorMilliseconds = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
            XCTAssertLessThanOrEqual(
                detectorMilliseconds,
                2_000,
                "자동 검출이 2초를 넘었습니다: \(file.path)"
            )
            let fixtureName = "\(file.deletingLastPathComponent().lastPathComponent)-\(file.deletingPathExtension().lastPathComponent)"
            let overlayURL = outputDirectory
                .appendingPathComponent(fixtureName)
                .appendingPathExtension("png")
            try writeOverlay(
                sourceURL: file,
                detections: detections,
                destinationURL: overlayURL
            )
            if let preview = FlatbedFrameGridDetector.Preview(
                url: file,
                physicalSize: physicalSize
            ) {
                try writeProfiles(
                    fixtureName: fixtureName,
                    preview: preview,
                    frameFormat: frameFormat,
                    destinationURL: outputDirectory
                        .appendingPathComponent(fixtureName)
                        .appendingPathExtension("profiles.tsv")
                )
            }
            if detections.isEmpty {
                measurements.append(
                    "\(fixtureName)\t0\t\(formatted(detectorMilliseconds))\t\t\t\t\t\t\t"
                )
            }
            for detection in detections.sorted(by: detectionOrder) {
                let rect = detection.normalizedRect
                measurements.append([
                    fixtureName,
                    String(detections.count),
                    formatted(detectorMilliseconds),
                    String(detection.row),
                    String(detection.column),
                    formatted(Double(rect.minX) * physicalSize.width),
                    formatted(Double(rect.minY) * physicalSize.height),
                    formatted(Double(rect.width) * physicalSize.width),
                    formatted(Double(rect.height) * physicalSize.height),
                    formatted(detection.confidence),
                ].joined(separator: "\t"))
            }
        }

        let measurementsURL = outputDirectory.appendingPathComponent("detections.tsv")
        try (measurements.joined(separator: "\n") + "\n").write(
            to: measurementsURL,
            atomically: true,
            encoding: .utf8
        )
        FileHandle.standardError.write(
            Data("flatbed artifacts: \(outputDirectory.path)\n".utf8)
        )
    }

    private func previewFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter {
            ["tif", "tiff"].contains($0.pathExtension.lowercased())
        }
    }

    private func writeOverlay(
        sourceURL: URL,
        detections: [FlatbedFrameDetection],
        destinationURL: URL
    ) throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(sourceURL as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try XCTUnwrap(pixels.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        })
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setLineWidth(max(2, CGFloat(width) / 600))

        for detection in detections {
            let unit = detection.normalizedRect
            let rect = CGRect(
                x: unit.minX * CGFloat(width),
                y: (1 - unit.maxY) * CGFloat(height),
                width: unit.width * CGFloat(width),
                height: unit.height * CGFloat(height)
            )
            let hue = CGFloat(detection.row % 3) / 3
            let color = CGColor(
                colorSpace: colorSpace,
                components: hsvToRGBA(hue: hue)
            )!
            context.setStrokeColor(color)
            context.stroke(rect)
        }

        let overlay = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, overlay, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), destinationURL.path)
    }

    private func writeProfiles(
        fixtureName: String,
        preview: FlatbedFrameGridDetector.Preview,
        frameFormat: FilmFrameFormat,
        destinationURL: URL
    ) throws {
        let geometry = FlatbedFrameGridDetector.FrameGeometry(
            format: frameFormat,
            preview: preview
        )
        let columns = FlatbedFrameGridDetector.ColumnProfiles(preview: preview)
        let slots = FlatbedFrameGridDetector.slots(
            preview: preview,
            profiles: columns,
            geometry: geometry
        )
        var lines = [
            "fixture\tslot\tband\ty_mm\tmean\thorizontal_detail\tvertical_grain\tplateau\tedge\tcontent\tgrid_pitch_mm\tgrid_boundaries_mm"
        ]
        for (slotIndex, slot) in slots.enumerated() {
            let rows = FlatbedFrameGridDetector.RowProfiles(
                preview: preview,
                slot: slot.measured
            )
            let bands = FlatbedFrameGridDetector.filmBands(
                preview: preview,
                slot: slot,
                rows: rows,
                geometry: geometry
            )
            for (bandIndex, band) in bands.enumerated() {
                let evidence = FlatbedFrameGridDetector.gapEvidence(
                    rows: rows,
                    band: band,
                    geometry: geometry
                )
                let grid = FlatbedFrameGridDetector.fitGrid(
                    evidence: evidence,
                    geometry: geometry
                )
                let pitch = grid.map {
                    formatted($0.pitch / geometry.pixelsPerMillimeterY)
                } ?? ""
                let boundaries = grid.map {
                    $0.boundaries.map { boundary in
                        formatted(
                            (Double(band.lowerBound) + boundary)
                                / geometry.pixelsPerMillimeterY
                        )
                    }.joined(separator: ",")
                } ?? ""
                for localY in 0..<evidence.count {
                    let absoluteY = band.lowerBound + localY
                    lines.append([
                        fixtureName,
                        String(slotIndex),
                        String(bandIndex),
                        formatted(Double(absoluteY) / geometry.pixelsPerMillimeterY),
                        formatted(rows.mean[absoluteY]),
                        formatted(rows.detail[absoluteY]),
                        formatted(rows.grain[absoluteY]),
                        formatted(evidence.plateau[localY]),
                        formatted(evidence.edge[localY]),
                        formatted(evidence.content[localY]),
                        pitch,
                        boundaries,
                    ].joined(separator: "\t"))
                }
            }
        }
        try (lines.joined(separator: "\n") + "\n").write(
            to: destinationURL,
            atomically: true,
            encoding: .utf8
        )
    }

    private func detectionOrder(
        _ lhs: FlatbedFrameDetection,
        _ rhs: FlatbedFrameDetection
    ) -> Bool {
        (lhs.row, lhs.column) < (rhs.row, rhs.column)
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private func hsvToRGBA(hue: CGFloat) -> [CGFloat] {
        let sector = hue * 6
        let index = Int(sector.rounded(.down)) % 6
        let fraction = sector - CGFloat(index)
        let values: [(CGFloat, CGFloat, CGFloat)] = [
            (1, fraction, 0),
            (1 - fraction, 1, 0),
            (0, 1, fraction),
            (0, 1 - fraction, 1),
            (fraction, 0, 1),
            (1, 0, 1 - fraction),
        ]
        let value = values[index]
        return [value.0, value.1, value.2, 1]
    }
}
