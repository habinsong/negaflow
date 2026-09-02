import Chromabase
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import negaflowApp

/// 불러오기·스캔 → 현상 → 보정 → 내보내기 → 인화 합성 내보내기까지, 사용자가 실제로 지나는
/// 길을 앱 API 그대로 한 번 통과시킨다.
///
/// 라이브 프리뷰를 빠르게 만들려고 장면 측정과 프리뷰 입력을 프레임에 굳혀 두게 됐는데,
/// 그 캐시가 화면에만 유효하고 파일로 나가는 그림과 어긋나면 "화면에서 맞춘 색"과 "내보낸 색"이
/// 갈라진다. 이 테스트는 두 그림이 같은지까지 본다.
@MainActor
final class DevelopExportPrintWorkflowTests: XCTestCase {

    func testImportedNegativeDevelopsAdjustsExportsAndComposesPrint() async throws {
        let source = try Self.writeSyntheticNegativeTIFF(width: 2_400, height: 1_600)
        defer { try? FileManager.default.removeItem(at: source) }
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-workflow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        // 라이브러리는 임시 폴더로 격리한다 — 테스트가 사용자 카탈로그를 건드리지 않는다.
        let model = AppModel(
            libraryCatalogURL: outputDirectory.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: outputDirectory.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: outputDirectory.appendingPathComponent("Backups")
        )
        await model.restoreLibraryOnLaunch()
        model.activeWorkspaceModule = .develop
        model.canvasDisplayTargetPixels = 1_536
        let frame = ScanFrame(
            scanIndex: 1, rawScanURL: source, filmType: .colorNegative, sourceKind: .importedFile
        )
        model.frames = [frame]
        XCTAssertTrue(model.assignNewPersistentFrames([frame]))
        model.selectedFrameID = frame.id

        // 1) 현상.
        await model.developFrame(frame)
        XCTAssertTrue(frame.hasDevelopedOnce, "가져온 네거티브가 현상되지 않았다")
        let developedNeutral = try XCTUnwrap(frame.developedImage)
        XCTAssertGreaterThan(developedNeutral.size.width, 0)

        // 2) 보정 — 인스펙터를 실제로 만졌을 때처럼 값을 바꾸고 정착까지 기다린다.
        frame.updateParams {
            $0.exposure = 0.8
            $0.contrast = 0.25
            $0.warmth = -0.2
            $0.colorDepth = 0.15
        }
        let revisionBefore = frame.developRevision
        model.requestDevelop(frame)
        try await Self.waitUntilSettled(frame, afterRevision: revisionBefore)
        XCTAssertTrue(frame.developedIsSettled, "보정 뒤 정착 패스가 끝나지 않았다")
        let adjustedOnScreen = try XCTUnwrap(frame.cachedDevelopedBase)
        XCTAssertGreaterThan(
            Self.meanLuma(adjustedOnScreen), Self.meanLuma(developedNeutral.cgImageForTest()!),
            "노출을 +0.8 스탑 올렸는데 화면이 밝아지지 않았다"
        )

        // 3) 내보내기 — 화면에서 본 그림과 파일로 나간 그림이 같아야 한다.
        let exportURL = outputDirectory.appendingPathComponent("frame.tiff")
        let exported = await model.runExportFrameTransaction(
            frame, to: exportURL, format: .tiff16,
            writeSidecar: false, writeMainFlatMaster: false, writeOriginalRaw: false,
            options: .standard, recipeIdentity: nil, reportsGlobalStatus: false
        )
        guard case .completed(let outputURL, _) = exported else {
            return XCTFail("내보내기가 실패했다: \(exported)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let exportedImage = try XCTUnwrap(Self.loadCGImage(outputURL))
        let screenLuma = Self.meanLuma(adjustedOnScreen)
        let fileLuma = Self.meanLuma(exportedImage)
        XCTAssertEqual(
            screenLuma, fileLuma, accuracy: 0.02,
            "화면 평균 밝기 \(screenLuma) 와 내보낸 파일 \(fileLuma) 가 갈렸다"
        )

        // 4) 인화 합성 내보내기 — 같은 프레임을 종이 배치로 한 번 더 내보낸다.
        var composition = PrintCompositionSettings()
        composition.dpi = 150
        let printURL = outputDirectory.appendingPathComponent("print.tiff")
        let printed = await model.runExportFrameTransaction(
            frame, to: printURL, format: .tiff16,
            writeSidecar: false, writeMainFlatMaster: false, writeOriginalRaw: false,
            options: model.printExportOptions(.standard, dpi: composition.dpi),
            printComposition: composition,
            recipeIdentity: nil, reportsGlobalStatus: false
        )
        guard case .completed(let printOutputURL, _) = printed else {
            return XCTFail("인화 합성 내보내기가 실패했다: \(printed)")
        }
        let printedImage = try XCTUnwrap(Self.loadCGImage(printOutputURL))
        XCTAssertGreaterThan(printedImage.width, exportedImage.width / 4)
        XCTAssertGreaterThan(printedImage.height, 0)
    }

    /// 스캐너 산출 TIFF(무프로필 16bit linear)도 같은 길을 지난다.
    func testScannerSourceDevelopsAndExports() async throws {
        let source = try Self.writeSyntheticNegativeTIFF(width: 2_000, height: 1_333)
        defer { try? FileManager.default.removeItem(at: source) }
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-workflow-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let model = AppModel(
            libraryCatalogURL: outputDirectory.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: outputDirectory.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: outputDirectory.appendingPathComponent("Backups")
        )
        await model.restoreLibraryOnLaunch()
        model.activeWorkspaceModule = .develop
        model.canvasDisplayTargetPixels = 1_280
        let frame = ScanFrame(
            scanIndex: 1, rawScanURL: source, filmType: .colorNegative, sourceKind: .scannerTIFF
        )
        model.frames = [frame]
        XCTAssertTrue(model.assignNewPersistentFrames([frame]))
        model.selectedFrameID = frame.id

        await model.developFrame(frame)
        XCTAssertTrue(frame.hasDevelopedOnce)

        // 스캐너 타겟으로 바꾸고(측정 캐시가 타겟 전환을 넘어 살아남는 경로) 보정까지.
        frame.updateParams {
            $0.developTarget = .sp3000
            $0.exposure = -0.3
        }
        let revisionBefore = frame.developRevision
        model.requestDevelop(frame)
        try await Self.waitUntilSettled(frame, afterRevision: revisionBefore)
        let onScreen = try XCTUnwrap(frame.cachedDevelopedBase)

        let exportURL = outputDirectory.appendingPathComponent("scan.tiff")
        let exported = await model.runExportFrameTransaction(
            frame, to: exportURL, format: .tiff16,
            writeSidecar: false, writeMainFlatMaster: false, writeOriginalRaw: false,
            options: .standard, recipeIdentity: nil, reportsGlobalStatus: false
        )
        guard case .completed(let outputURL, _) = exported else {
            return XCTFail("스캔 원본 내보내기가 실패했다: \(exported)")
        }
        let exportedImage = try XCTUnwrap(Self.loadCGImage(outputURL))
        XCTAssertEqual(
            Self.meanLuma(onScreen), Self.meanLuma(exportedImage), accuracy: 0.02,
            "스캐너 타겟에서 화면과 파일이 갈렸다"
        )
    }

    // MARK: helpers

    /// 요청이 throttle 을 지나 실제로 새 리비전으로 돌기 시작한 뒤의 정착을 기다린다.
    /// 리비전을 안 보면 "아직 시작도 안 한" 직전 정착 상태를 끝난 것으로 오인한다.
    private static func waitUntilSettled(
        _ frame: ScanFrame, afterRevision revision: Int, timeout: TimeInterval = 20
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if frame.developRevision > revision, frame.developedIsSettled, !frame.isDeveloping { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("정착 패스가 \(timeout)초 안에 끝나지 않았다")
    }

    private static func loadCGImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// sRGB 코드값 평균 밝기(0...1). 크기가 달라도 비교되도록 정규화된 스칼라만 쓴다.
    private static func meanLuma(_ image: CGImage) -> Double {
        let width = 64
        let height = max(1, Int(Double(width) * Double(image.height) / Double(image.width)))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var sum = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            sum += (0.2126 * Double(pixels[index])
                + 0.7152 * Double(pixels[index + 1])
                + 0.0722 * Double(pixels[index + 2])) / 255
        }
        return sum / Double(width * height)
    }

    /// 오렌지 마스크 위에 장면 밀도가 실린 합성 네거티브(실사진 미사용).
    private static func writeSyntheticNegativeTIFF(width: Int, height: Int) throws -> URL {
        var pixels = [UInt16](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let fy = Double(y) / Double(height - 1)
            for x in 0..<width {
                let fx = Double(x) / Double(width - 1)
                let scene = 0.05 + 0.9 * (0.5 + 0.5 * sin(fx * 7.1) * cos(fy * 5.3))
                let density = 1.0 - scene
                let i = (y * width + x) * 4
                pixels[i] = UInt16(0.86 * (0.12 + 0.88 * density) * 65_535)
                pixels[i + 1] = UInt16(0.68 * (0.10 + 0.90 * density * 0.94) * 65_535)
                pixels[i + 2] = UInt16(0.50 * (0.08 + 0.92 * density * 0.88) * 65_535)
                pixels[i + 3] = UInt16.max
            }
        }
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let data = Data(bytes: pixels, count: pixels.count * MemoryLayout<UInt16>.size)
        let provider = CGDataProvider(data: data as CFData)!
        guard let cg = CGImage(
            width: width, height: height,
            bitsPerComponent: 16, bitsPerPixel: 64,
            bytesPerRow: width * 4 * MemoryLayout<UInt16>.size,
            space: linear,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else { throw CocoaError(.fileWriteUnknown) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-workflow-\(UUID().uuidString).tiff")
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.tiff.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }
}

private extension NSImage {
    func cgImageForTest() -> CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
