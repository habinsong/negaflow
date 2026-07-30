import Chromabase
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import negaflowApp

@MainActor
final class SoftProofRefreshTests: XCTestCase {
    func testPrintWorkspaceInspectorUsesDedicatedCPrintProofProfile() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(
            "Sources/negaflowApp/Features/Print/PrintWorkspaceInspector.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("model.cPrintProofICCProfileName"))
        XCTAssertTrue(source.contains("chooseCPrintProofProfile()"))
        XCTAssertTrue(source.contains("model.setCPrintProofICCProfile("))
        XCTAssertFalse(source.contains("$model.exportColorSpace"))
        XCTAssertFalse(source.contains("model.printerOutputICCProfileName"))
        XCTAssertFalse(source.contains("choosePrinterOutputProfile()"))
        XCTAssertFalse(source.contains("model.setPrinterOutputICCProfile("))
        XCTAssertFalse(source.contains("model.softProofICCProfileName"))
        XCTAssertFalse(source.contains("chooseSoftProofProfile()"))
        XCTAssertFalse(source.contains("model.setSoftProofICCProfile("))
    }

    func testSingleImageCanvasObservesOnlyActiveFramePreviewPromotion() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(
            "Sources/negaflowApp/Features/Print/PrintCanvasView.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private struct PrintSingleImagePageView"))
        XCTAssertTrue(source.contains("@ObservedObject var frame: ScanFrame"))
        XCTAssertTrue(source.contains("frame: activeFrame"))
        XCTAssertFalse(source.contains("ForEach(displayedFrames)"))
        XCTAssertTrue(
            source.contains(
                "frame.developedImage\n                ?? frame.rawPreviewImage"
            )
        )
    }

    func testPrintPackageShowsOnePageWhileEveryItemObservesItsOwnFrame() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(
            "Sources/negaflowApp/Features/Print/PrintPackageCanvasView.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("@State private var selectedPage"))
        XCTAssertTrue(source.contains("pageControls(count: preview.pages.count)"))
        XCTAssertTrue(source.contains("@ObservedObject var frame: ScanFrame"))
        // 시트 셀은 작다 — 썸네일을 먼저 쓰고, 없을 때만 더 큰 그림으로 내려간다.
        // 여기서 풀해상도 현상 결과를 먼저 요구하면 올린 장수만큼 무거운 렌더가 줄줄이 돈다.
        XCTAssertTrue(
            source.contains(
                "frame.thumbnailImage ?? frame.developedImage ?? frame.rawPreviewImage"
            )
        )
    }

    func testModuleSwitchInvalidatesOnlyWhenDisplayProofChanges() {
        let suiteName = "negaflow-module-proof.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            printWorkspaceSettingsStore: PrintWorkspaceSettingsStore(defaults: defaults)
        )
        let initialRevision = model.softProofConfigurationRevision

        model.activeWorkspaceModule = .library
        model.activeWorkspaceModule = .develop

        XCTAssertEqual(model.softProofConfigurationRevision, initialRevision)

        model.activeWorkspaceModule = .print
        XCTAssertEqual(model.softProofConfigurationRevision, initialRevision)

        model.activeWorkspaceModule = .develop
        model.softProofEnabled = true
        let proofRevision = model.softProofConfigurationRevision
        model.activeWorkspaceModule = .print
        XCTAssertEqual(model.softProofConfigurationRevision, proofRevision &+ 1)
    }

    func testCPrintProfileDoesNotEnterDevelopWorkspacePreview() throws {
        let suiteName = "negaflow-c-print-proof-scope.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            printWorkspaceSettingsStore: PrintWorkspaceSettingsStore(defaults: defaults)
        )
        let profile = try ICCOutputProfileTestFixture.snapshot()
        model.setPrintOutputProcess(.cPrint)
        let revisionBeforeSelection = model.softProofConfigurationRevision

        XCTAssertTrue(model.setCPrintProofICCProfile(
            data: profile.iccProfileData,
            name: profile.profileName
        ))
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow/c-print-scope.tiff"),
            filmType: .colorPositive
        )
        let printProof = model.displaySoftProofSettings(for: frame, in: .print)
        let developProof = model.displaySoftProofSettings(for: frame, in: .develop)

        XCTAssertTrue(printProof.isEnabled)
        XCTAssertEqual(printProof.iccProfileData, profile.iccProfileData)
        XCTAssertFalse(developProof.isEnabled)
        XCTAssertNotEqual(developProof.iccProfileData, profile.iccProfileData)
        XCTAssertEqual(model.softProofConfigurationRevision, revisionBeforeSelection)
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

    func testCPrintProfileRefreshesEverySelectedPrintFrame() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-proof-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let suiteName = "negaflow-proof-refresh.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            exportSettingsStore: ExportSettingsStore(defaults: defaults),
            printWorkspaceSettingsStore: PrintWorkspaceSettingsStore(defaults: defaults)
        )
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
        model.updateInteractionScope(frames.map(\.id))
        model.selectedFrameIDs = Set(frames.map(\.id))
        XCTAssertEqual(model.actionableSelectedFrames.map(\.id), frames.map(\.id))
        model.activeWorkspaceModule = .print
        model.setPrintOutputProcess(.cPrint)
        let profile = try ICCOutputProfileTestFixture.snapshot()

        XCTAssertTrue(model.setCPrintProofICCProfile(
            data: profile.iccProfileData,
            name: profile.profileName
        ))

        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline,
              frames.contains(where: {
                  $0.displayedSoftProofRevision != model.softProofConfigurationRevision
              }) {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let revisions = frames.map { $0.displayedSoftProofRevision.map(String.init) ?? "nil" }
        let imageStates = frames.map { $0.developedImage != nil }
        let developingStates = frames.map(\.isDeveloping)
        let settledStates = frames.map(\.developedIsSettled)
        XCTAssertTrue(frames.allSatisfy {
            $0.displayedSoftProofRevision == model.softProofConfigurationRevision
        }, "revisions=\(revisions) developing=\(developingStates) settled=\(settledStates) expected=\(model.softProofConfigurationRevision) status=\(model.statusMessage)")
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
