import XCTest
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
@testable import Chromabase

// MARK: - 프로필 없는 16bit 스캔의 가져오기/스캔 경로 동등성
//
// 같은 파일을 스캔으로 얻었는지 가져왔는지에 따라 결과가 달라지면 안 된다. 프로필 없는 16bit TIFF는
// 스캐너 소프트웨어의 linear raw 출력이며, 이를 sRGB로 읽으면 Dmin 실측이 실패하고 반전이 흰색으로
// 붕뜬다. 실제 스캔 파일 없이 합성 네거티브로 수치 검증한다.
final class UntaggedLinearScanDevelopTests: XCTestCase {
    func testImportedAndScannerPathsDevelopTheSameFileIdentically() throws {
        let url = try writeSyntheticLinearNegativeTIFF()
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = ChromabaseEngine()

        let imported = try XCTUnwrap(engine.loadImportedImage(url))
        let scanner = try XCTUnwrap(engine.loadScannerImage(url))
        var params = DevelopParameters()
        params.filmType = .colorNegative

        let importedResult = engine.develop(
            image: imported,
            base: engine.estimateFilmBase(in: imported, mode: .auto),
            params: params
        )
        let scannerResult = engine.developScanner(
            image: scanner,
            base: engine.estimateFilmBase(in: scanner, mode: .auto),
            params: params
        )
        let a = varianceOfLuma(importedResult, width: 96, height: 72)
        let b = varianceOfLuma(scannerResult, width: 96, height: 72)

        XCTAssertEqual(a.mean, b.mean, accuracy: 0.01,
                       "같은 파일이면 가져오기와 스캔 경로의 현상 결과가 같아야 한다.")
        XCTAssertEqual(a.range, b.range, accuracy: 0.01)
    }

    func testUntaggedLinearNegativeKeepsMeasuredBaseAndFullRangeOnImport() throws {
        let url = try writeSyntheticLinearNegativeTIFF()
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = ChromabaseEngine()
        let imported = try XCTUnwrap(engine.loadImportedImage(url))

        let base = try XCTUnwrap(
            engine.estimateFilmBase(in: imported, mode: .auto),
            "가져온 무프로필 16bit 네거티브에서도 베이스가 실측돼야 한다."
        )
        // 픽스처의 미노광 베이스는 (0.250, 0.140, 0.075)이다.
        XCTAssertEqual(base.rgb.x, 0.250, accuracy: 0.03)
        XCTAssertEqual(base.rgb.y, 0.140, accuracy: 0.03)
        XCTAssertEqual(base.rgb.z, 0.075, accuracy: 0.03)

        var params = DevelopParameters()
        params.filmType = .colorNegative
        let developed = engine.develop(image: imported, base: base, params: params)
        let stats = varianceOfLuma(developed, width: 96, height: 72)

        XCTAssertGreaterThan(stats.range, 0.25, "반전 결과가 계조를 유지해야 한다.")
        XCTAssertLessThan(stats.mean, 0.85, "반전 결과가 밝은 쪽으로 뭉치면 안 된다.")
    }

    func testReadingTheSameScanAsSRGBCollapsesTheInversion() throws {
        // 원인 고정: 값 도메인을 sRGB로 잘못 읽으면 같은 파일이 밝은 쪽으로 눌린다.
        let url = try writeSyntheticLinearNegativeTIFF()
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = ChromabaseEngine()
        var params = DevelopParameters()
        params.filmType = .colorNegative

        let linear = try XCTUnwrap(ImageLoader.loadImported(url))
        let misread = try XCTUnwrap(ImageLoader.loadImported(url, untaggedTIFFRole: .standardImage))
        let linearStats = varianceOfLuma(
            engine.develop(image: linear, base: engine.estimateFilmBase(in: linear, mode: .auto), params: params),
            width: 96, height: 72
        )
        let misreadStats = varianceOfLuma(
            engine.develop(image: misread, base: engine.estimateFilmBase(in: misread, mode: .auto), params: params),
            width: 96, height: 72
        )

        XCTAssertGreaterThan(linearStats.range, misreadStats.range,
                             "linear 해석이 sRGB 오해석보다 넓은 계조를 만들어야 한다.")
        XCTAssertGreaterThan(misreadStats.mean, linearStats.mean,
                             "sRGB 오해석은 결과를 밝은 쪽으로 민다(붕뜸).")
    }

    func testImportedPreviewUsesTheSameProfileRuleAsFullResolution() throws {
        let url = try writeUniform16BitTIFF(value: 0.5, colorSpace: CGColorSpaceCreateDeviceRGB())
        defer { try? FileManager.default.removeItem(at: url) }

        let full = try XCTUnwrap(ImageLoader.loadImported(url))
        let preview = try XCTUnwrap(ImageLoader.loadImportedPreview(
            url, maxDimension: 4, highResolutionThreshold: 4
        ))

        XCTAssertEqual(renderMidPixelLuma(preview.image), renderMidPixelLuma(full), accuracy: 0.05,
                       "프록시와 전체 해상도가 다른 색 도메인으로 읽히면 프리뷰와 결과가 어긋난다.")
    }
}
