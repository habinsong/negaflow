import XCTest
import CoreImage
import Chromabase
@testable import negaflowApp

/// 결함 제거(브러시/가이드 결함 제거) 결과가 화면에서 되살아나거나 반영되지 않던 버그의 회귀 방지.
///
/// 원인: cleaned raw 의 메모리 적재본(cleanedRawImage)은 커밋 시 동기 갱신되지만, 디스크 백킹
/// (cleanedRawURL)은 커밋 후 비동기로 저장된다. 현상 입력 선택이 디스크 백킹을 메모리보다 먼저
/// 읽으면, 저장 지연 창(window)에서 방금 제거한 결함이 남은 이전 상태(또는 원본)로 렌더된다.
/// 실제 스캔은 fullMaxDimension(3600) 을 넘어 항상 이 프록시 경로를 타므로 증상이 상시 재현됐다.
///
/// 불변식: preloadedRaw(메모리 결함 제거 raw)가 있으면 현상 입력은 반드시 메모리에서 파생되어야 하고,
/// stale 할 수 있는 cleanedRawURL(디스크)로 내려가면 안 된다.
final class DefectRenderInputTests: XCTestCase {
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
    private let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!])

    func testPreloadedMemoryRawWinsOverStaleDiskBacking() throws {
        // 프록시 경로를 강제하려면 긴 변이 fullMaxDimension(3600) 을 넘어야 한다.
        let size = CGSize(width: 3800, height: 120)
        // 메모리 = 최신 결함 제거 결과(빨강), 디스크 = stale 백킹(초록). 색이 갈리므로 어느 쪽이 렌더됐는지 판별된다.
        let memoryCG = solidColorCG(red: 1, green: 0, blue: 0, size: size)
        let diskCG = solidColorCG(red: 0, green: 1, blue: 0, size: size)
        let diskURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-defects-stale-\(UUID().uuidString).tiff")
        XCTAssertTrue(ImageLoader.saveScannerTIFF(diskCG, to: diskURL))
        defer { try? FileManager.default.removeItem(at: diskURL) }

        let snapshot = makeSnapshot(preloadedRaw: memoryCG, cleanedRawURL: diskURL)
        let input = try XCTUnwrap(
            DevelopFrameRenderer.resolveRenderInput(snapshot, engine: ChromabaseEngine(), context: context)
        )
        let color = sampleCenter(input.image)
        // 메모리(빨강)가 선택돼야 한다 — 디스크(초록)로 내려가면 결함 제거가 되살아난다.
        XCTAssertGreaterThan(color.r, 0.5, "메모리 결함 제거 raw(빨강)가 아니라 stale 디스크(초록)가 렌더됨 → 결함 부활 회귀")
        XCTAssertLessThan(color.g, 0.5, "stale 디스크 백킹(초록)이 렌더됨 → 결함 부활 회귀")
    }

    func testFallsBackToDiskWhenMemoryAbsent() throws {
        // 메모리 적재본이 없으면(다른 프레임에서 돌아온 경우 등) 디스크 백킹이 최종본이므로 그걸 쓴다.
        let size = CGSize(width: 3800, height: 120)
        let diskCG = solidColorCG(red: 0, green: 1, blue: 0, size: size)
        let diskURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-defects-final-\(UUID().uuidString).tiff")
        XCTAssertTrue(ImageLoader.saveScannerTIFF(diskCG, to: diskURL))
        defer { try? FileManager.default.removeItem(at: diskURL) }

        let snapshot = makeSnapshot(preloadedRaw: nil, cleanedRawURL: diskURL)
        let input = try XCTUnwrap(
            DevelopFrameRenderer.resolveRenderInput(snapshot, engine: ChromabaseEngine(), context: context)
        )
        let color = sampleCenter(input.image)
        XCTAssertGreaterThan(color.g, 0.5, "메모리가 없으면 디스크 백킹(초록)을 써야 한다")
    }

    // MARK: helpers

    private func makeSnapshot(preloadedRaw: CGImage?, cleanedRawURL: URL?) -> DevelopFrameSnapshot {
        let params = DevelopParameters()
        return DevelopFrameSnapshot(
            rawScanURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("negaflow-defects-raw-\(UUID().uuidString).tiff"),
            preloadedRaw: preloadedRaw,
            cleanedRawURL: cleanedRawURL,
            filmType: .colorNegative,
            params: params,
            preset: nil,
            imageTransform: .identity,
            cachedBase: nil,
            baseKey: FilmBaseCacheKey(filmType: .colorNegative, mode: params.baseEstimationMode,
                                      manualBaseRGB: nil, filmStockDminID: nil),
            needsRawPreview: false,
            needsNeutralPreview: false,
            needsDebugPreviews: false
        )
    }

    private func solidColorCG(red: CGFloat, green: CGFloat, blue: CGFloat, size: CGSize) -> CGImage {
        let ci = CIImage(color: CIColor(red: red, green: green, blue: blue, colorSpace: linear)!)
            .cropped(to: CGRect(origin: .zero, size: size))
        return context.createCGImage(ci, from: ci.extent, format: .RGBA16, colorSpace: linear)!
    }

    private func sampleCenter(_ image: CIImage) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let extent = image.extent.integral
        let px = CGRect(x: extent.midX, y: extent.midY, width: 1, height: 1)
        var bytes = [Float](repeating: 0, count: 4)
        context.render(image, toBitmap: &bytes, rowBytes: 16, bounds: px,
                       format: .RGBAf, colorSpace: linear)
        return (CGFloat(bytes[0]), CGFloat(bytes[1]), CGFloat(bytes[2]))
    }
}
