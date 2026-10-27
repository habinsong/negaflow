import Chromabase
import CoreImage
import ImageIO
import XCTest
@testable import negaflowApp

/// 인화 워터마크 설정의 저장·템플릿·사진별 채우기.
@MainActor
final class PrintWatermarkSettingsTests: XCTestCase {
    func testWatermarkPersistsAndOnlyReachesSinglePhotoLayouts() {
        let suiteName = "PrintWatermarkSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PrintWorkspaceSettingsStore(defaults: defaults)
        XCTAssertFalse(store.watermark.isEnabled)
        XCTAssertNil(store.compositionSettings(dpi: 300).watermark, "꺼져 있으면 판에 싣지 않는다")

        store.watermark = PrintWatermarkSettings(isEnabled: true, background: .blur, cameraName: "Body")
        XCTAssertEqual(store.compositionSettings(dpi: 300).watermark?.cameraName, "Body")
        store.layoutMode = .contactSheet
        XCTAssertNil(store.compositionSettings(dpi: 300).watermark, "여러 장 한 판에는 띠를 넣지 않는다")
        store.layoutMode = .gelatin
        XCTAssertNotNil(store.compositionSettings(dpi: 300).watermark)

        let restored = PrintWorkspaceSettingsStore(defaults: defaults)
        XCTAssertEqual(restored.watermark, store.watermark)
    }

    func testTemplatesCarrySheetColorAndWatermarkButOldOnesKeepCurrentValues() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-watermark-templates-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "PrintWatermarkSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PrintWorkspaceSettingsStore(defaults: defaults)
        store.sheetColor = .black
        store.watermark = PrintWatermarkSettings(
            isEnabled: true,
            addsTopBand: true,
            cameraName: "Body",
            lensName: "Lens",
            focalLength: "50",
            aperture: "2",
            shutterSpeed: "1/60",
            iso: "400",
            captureDate: "2026/10/27",
            showsLogo: true,
            logoSourcePath: "/Users/me/Logos/brand.png",
            userName: "Me",
            userNamePlacement: .topTrailing
        )
        let templates = PrintLayoutTemplateStore(url: directory.appendingPathComponent("templates.json"))
        let saved = try XCTUnwrap(templates.add(name: "Frame", settings: store.templateSettings()))

        store.sheetColor = .white
        store.watermark = PrintWatermarkSettings()
        store.apply(PrintLayoutTemplateStore(url: templates.url).templates[0].settings)
        XCTAssertEqual(store.sheetColor, .black)
        XCTAssertEqual(store.watermark, saved.settings.watermark)
        // 글·로고 켜짐·로고 경로까지 그대로 다시 쓴다(로고 그림은 그 경로에서 그릴 때마다 읽는다).
        XCTAssertEqual(store.watermark.cameraName, "Body")
        XCTAssertEqual(store.watermark.captureDate, "2026/10/27")
        XCTAssertTrue(store.watermark.showsLogo)
        XCTAssertEqual(store.watermark.logoSourcePath, "/Users/me/Logos/brand.png")
        XCTAssertNil(store.watermark.logoPNGData, "로고 그림 바이트는 저장하지 않는다")

        // 종이 색·워터마크가 없던 예전 템플릿은 지금 값을 건드리지 않는다.
        var legacy = saved.settings
        legacy.sheetColor = nil
        legacy.watermark = nil
        let encoded = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(PrintLayoutTemplateSettings.self, from: encoded)
        XCTAssertNil(decoded.watermark)
        store.watermark = PrintWatermarkSettings(isEnabled: true, cameraName: "Keep")
        store.apply(decoded)
        XCTAssertEqual(store.watermark.cameraName, "Keep")
        XCTAssertEqual(store.sheetColor, .black)
    }

    /// 로고는 경로에서 읽는다: 켜고 경로가 비면 negaflow 로고, 파일이 지워졌으면 로고만 빠지고 오류 기록에
    /// 한 번 남는다(검사기에는 띄우지 않는다). 파일이 다시 생기면 다시 읽는다.
    func testLogoLoadsFromPathAndMissingFileOnlyDropsTheLogo() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-watermark-logo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var reported: [String] = []
        let previous = PrintWatermarkLogoLoader.reportMissing
        PrintWatermarkLogoLoader.reportMissing = { reported.append($0) }
        defer { PrintWatermarkLogoLoader.reportMissing = previous }

        var settings = PrintWatermarkSettings(isEnabled: true, cameraName: "Body", showsLogo: false)
        XCTAssertNil(settings.resolvingLogo().logoPNGData, "로고를 끄면 넣지 않는다")
        settings.showsLogo = true
        XCTAssertNotNil(settings.resolvingLogo().logoPNGData, "경로가 없으면 negaflow 로고")

        let logoURL = directory.appendingPathComponent("brand.png")
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmap = try XCTUnwrap(CGContext(
            data: nil, width: 40, height: 10, bitsPerComponent: 8, bytesPerRow: 160,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        bitmap.setFillColor(CGColor(srgbRed: 0.8, green: 0, blue: 0, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 40, height: 10))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(logoURL as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(bitmap.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        settings.logoSourcePath = logoURL.path
        XCTAssertNotNil(settings.resolvingLogo().logoPNGData)

        try FileManager.default.removeItem(at: logoURL)
        let resolved = settings.resolvingLogo()
        XCTAssertNil(resolved.logoPNGData, "지워진 파일은 로고만 빠진다")
        XCTAssertEqual(resolved.cameraName, "Body", "나머지는 그대로다")
        XCTAssertNotNil(PrintWatermarkRenderer.compose(
            photo: CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 300, height: 200)),
            settings: resolved,
            context: ChromabaseEngine.sharedLinearRenderContext
        ), "로고가 없어도 띠는 그린다")
        _ = settings.resolvingLogo()
        await Task.yield()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(reported, [logoURL.path], "같은 경로는 한 번만 오류 기록에 남긴다")
    }

    func testBlankFieldsAreFilledFromEachPhotosShotRecord() {
        let shot = FilmShotMetadata(
            cameraMake: "Nikon",
            cameraModel: "Nikon F3",
            lensModel: "Nikkor 50mm f/1.4",
            isoSpeed: 400,
            exposureTimeSeconds: 1.0 / 250,
            fNumber: 8,
            focalLengthMM: 50
        )
        var settings = PrintWatermarkSettings(isEnabled: true, aperture: "5.6")
        let filled = settings.filling(from: shot)
        XCTAssertEqual(filled.cameraName, "Nikon F3", "모델명에 제조사가 있으면 한 번만 적는다")
        XCTAssertEqual(filled.lensName, "Nikkor 50mm f/1.4")
        XCTAssertEqual(filled.exposureLine, "50mm f/5.6 1/250\" ISO400", "사용자가 적은 조리개가 먼저다")
        XCTAssertEqual(filled.captureDate, "", "촬영 일시는 기록에 없으므로 채우지 않는다")

        settings.cameraName = "Mine"
        XCTAssertEqual(settings.filling(from: shot).cameraName, "Mine")
        XCTAssertEqual(settings.filling(from: nil), settings)
        XCTAssertEqual(PrintWatermarkSettings.cameraName(make: "Leica", model: "M6"), "Leica M6")
    }
}
