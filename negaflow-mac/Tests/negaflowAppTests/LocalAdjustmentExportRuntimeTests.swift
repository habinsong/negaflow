import XCTest
import CoreImage
import CoreGraphics
import ImageIO
import Chromabase
import ScannerKit
@testable import negaflowApp

@MainActor
final class LocalAdjustmentExportRuntimeTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-local-export-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try await super.tearDown()
    }

    func testExportUsesVisibilityAndPersistsAdjustmentInSidecar() throws {
        let source = directory.appendingPathComponent("source.tif")
        try MockScannerBackend.writeSyntheticNegative(width: 96, height: 72, to: source)
        let frame = ScanFrame(scanIndex: 1, rawScanURL: source, filmType: .colorPositive)
        let adjustment = LocalDodgeBurnAdjustment(
            mode: .dodge,
            amount: 0.8,
            mask: .radial(
                center: LocalDodgeBurnPoint(x: 0.5, y: 0.5),
                radius: 0.25,
                feather: 0.4
            )
        )
        frame.updateParams { $0.localDodgeBurn = [adjustment] }

        let activeURL = directory.appendingPathComponent("active.tif")
        _ = try ExportFrameWriter.write(try snapshot(frame: frame, output: activeURL, sidecar: true))

        frame.updateParams { $0.localDodgeBurn[0].isEnabled = false }
        let hiddenURL = directory.appendingPathComponent("hidden.tif")
        _ = try ExportFrameWriter.write(try snapshot(frame: frame, output: hiddenURL, sidecar: false))

        XCTAssertGreaterThan(centerLuma(activeURL), centerLuma(hiddenURL) + 0.03)
        let sidecarURL = activeURL.deletingPathExtension().appendingPathExtension("negaflow.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sidecar = try decoder.decode(Sidecar.self, from: Data(contentsOf: sidecarURL))
        XCTAssertEqual(sidecar.parameters.localDodgeBurn, [adjustment])
    }

    private func snapshot(frame: ScanFrame, output: URL, sidecar: Bool) throws -> ExportFrameSnapshot {
        ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL),
            outputURL: output,
            format: .tiff16,
            writeSidecar: sidecar,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: ExportOptions(metadataPolicy: .minimal),
            scannerModel: nil,
            backendUsed: nil,
            metadataDate: Date(timeIntervalSince1970: 1_800_000_000)
        ).snapshot
    }

    private func centerLuma(_ url: URL) -> Double {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return 0 }
        let ciImage = CIImage(cgImage: image)
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        CIContext(options: [.workingColorSpace: colorSpace]).render(
            ciImage,
            toBitmap: &pixels,
            rowBytes: width * 4,
            bounds: ciImage.extent,
            format: .RGBA8,
            colorSpace: colorSpace
        )
        let xRange = (width * 2 / 5)..<(width * 3 / 5)
        let yRange = (height * 2 / 5)..<(height * 3 / 5)
        var total = 0.0
        var count = 0
        for y in yRange {
            for x in xRange {
                let offset = (y * width + x) * 4
                total += (0.2126 * Double(pixels[offset])
                    + 0.7152 * Double(pixels[offset + 1])
                    + 0.0722 * Double(pixels[offset + 2])) / 255
                count += 1
            }
        }
        return count == 0 ? 0 : total / Double(count)
    }
}
