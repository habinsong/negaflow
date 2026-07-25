import Chromabase
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import negaflowApp

@MainActor
final class SoftProofRefreshTests: XCTestCase {
    func testPrintWorkspaceInspectorUsesPrinterOutputProfileAsOnlyProofTarget() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(
            "Sources/negaflowApp/Features/Print/PrintWorkspaceInspector.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("model.printerOutputICCProfileName"))
        XCTAssertTrue(source.contains("choosePrinterOutputProfile()"))
        XCTAssertTrue(source.contains("model.setPrinterOutputICCProfile("))
        XCTAssertFalse(source.contains("$model.exportColorSpace"))
        XCTAssertFalse(source.contains("model.softProofICCProfileName"))
        XCTAssertFalse(source.contains("chooseSoftProofProfile()"))
        XCTAssertFalse(source.contains("model.setSoftProofICCProfile("))
    }

    func testDisabledPrintProofDoesNotApplyPrinterOutputProfile() throws {
        let printerProfile = try ICCOutputProfileTestFixture.snapshot()
        let settings = SoftProofSettings(
            isEnabled: false,
            colorSpace: .displayP3,
            iccProfileData: SoftProof.profile(for: .displayP3)?.iccData,
            printerOutputICCProfileData: printerProfile.iccProfileData
        )
        let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))

        let rendered = try XCTUnwrap(DevelopFrameRenderer.renderDisplayCGImage(
            image,
            context: CIContext(),
            softProof: settings,
            developTarget: .print
        ))

        XCTAssertEqual(rendered.colorSpace?.name, CGColorSpace(name: CGColorSpace.sRGB)?.name)
        XCTAssertNotEqual(
            rendered.colorSpace?.copyICCData() as Data?,
            printerProfile.iccProfileData
        )
    }

    func testProofConfigurationRefreshesEverySelectedPrintFrame() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-proof-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let suiteName = "negaflow-proof-refresh.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(exportSettingsStore: ExportSettingsStore(defaults: defaults))
        let frames = try (0..<3).map { index -> ScanFrame in
            let url = directory.appendingPathComponent("frame-\(index).tiff")
            try writeTIFF(to: url, red: UInt8(80 + index * 50))
            let frame = ScanFrame(
                scanIndex: index + 1,
                rawScanURL: url,
                filmType: .colorPositive
            )
            frame.hasDevelopedOnce = true
            return frame
        }
        model.frames = frames
        model.selectedFrameID = frames[0].id
        model.selectedFrameIDs = Set(frames.map(\.id))

        model.softProofEnabled = true

        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline,
              frames.contains(where: {
                  $0.displayedSoftProofRevision != model.softProofConfigurationRevision
              }) {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let revisions = frames.map { $0.displayedSoftProofRevision.map(String.init) ?? "nil" }
        let imageStates = frames.map { $0.developedImage != nil }
        XCTAssertTrue(frames.allSatisfy {
            $0.displayedSoftProofRevision == model.softProofConfigurationRevision
        }, "revisions=\(revisions) expected=\(model.softProofConfigurationRevision) status=\(model.statusMessage)")
        XCTAssertTrue(
            frames.allSatisfy { $0.developedImage != nil },
            "developed=\(imageStates) status=\(model.statusMessage)"
        )
    }

    private func writeTIFF(to url: URL, red: UInt8) throws {
        let width = 8
        let height = 8
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = red
            pixels[offset + 1] = 96
            pixels[offset + 2] = 64
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.tiff.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
