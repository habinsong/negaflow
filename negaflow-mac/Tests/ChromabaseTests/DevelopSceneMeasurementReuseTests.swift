import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

/// 장면 측정 재사용이 그림을 바꾸지 않는다는 계약을 고정한다.
///
/// 측정(반전 밀도역·채도 게이트·스캐너 톤 앵커)은 인스펙터 값이 걸리기 **전** 단계에서
/// 나오므로, 슬라이더만 움직이는 동안 다시 재도 같은 값이 나와야 한다. 이 테스트가 깨지면
/// 측정 지점이 슬라이더 뒤로 옮겨진 것이고, 그때는 캐시를 재사용해서는 안 된다.
final class DevelopSceneMeasurementReuseTests: XCTestCase {
    func testReusedMeasurementsProduceIdenticalPixels() throws {
        // 자동 보정 토글까지 조합한다 — 켜면 반전 뒤에 측정이 두 개 더 붙는다.
        let cases: [(FilmType, DevelopParameters.BaseMode, DevelopTarget, Bool, Bool)] = [
            (.colorNegative, .auto, .main, false, false),
            (.colorNegative, .auto, .sp3000, false, false),
            (.colorNegative, .auto, .noritsu, false, false),
            (.colorNegative, .auto, .f135, false, false),
            (.colorNegative, .auto, .rescue, false, false),
            (.colorNegative, .preset, .main, false, false),
            (.colorNegative, .preset, .sp3000, false, false),
            (.bwNegative, .auto, .main, false, false),
            (.colorNegative, .auto, .main, true, false),
            (.colorNegative, .auto, .main, false, true),
            (.colorNegative, .auto, .main, true, true),
            (.colorNegative, .auto, .rescue, true, true),
            (.colorNegative, .auto, .sp3000, true, true),
        ]

        for (filmType, mode, target, autoLevels, autoNeutral) in cases {
            let input = try makeNegative(filmType: filmType)
            let engine = ChromabaseEngine()
            var params = DevelopParameters()
            params.filmType = filmType
            params.baseEstimationMode = mode
            params.developTarget = target
            params.autoLevels = autoLevels
            params.autoNeutralBalance = autoNeutral
            if mode == .preset {
                params.filmStockDminID = try XCTUnwrap(
                    FilmStockDminRegistry.all.first?.id,
                    "번들 필름 프리셋이 하나는 있어야 한다"
                )
            }
            let base = try XCTUnwrap(engine.estimateFilmBase(
                in: input,
                mode: mode,
                filmStockDminID: params.filmStockDminID,
                filmType: filmType
            ))

            // 한 번 재서 묶음을 채운다(슬라이더를 잡은 첫 틱에 해당).
            var reused = DevelopSceneMeasurements()
            _ = engine.developScannerPreview(
                image: input, base: base, params: params,
                maxDimension: 512, measurements: &reused
            )

            // 이후 틱들: 인스펙터 값만 바꾸고 측정은 재사용한다.
            for step in 1...4 {
                var edited = params
                edited.exposure = Double(step) * 0.3 - 0.6
                edited.contrast = Double(step) * 0.2 - 0.4
                edited.warmth = Double(step) * 0.15 - 0.3
                edited.colorDepth = Double(step) * 0.1
                edited.curveHighlights = Double(step) * 0.1 - 0.2

                var carried = reused
                let cached = engine.developScannerPreview(
                    image: input, base: base, params: edited,
                    maxDimension: 512, measurements: &carried
                )
                let fresh = engine.developScannerPreview(
                    image: input, base: base, params: edited, maxDimension: 512
                )

                let label = "\(filmType) \(mode) \(target.displayName)"
                    + " autoLevels=\(autoLevels) autoNeutral=\(autoNeutral) step \(step)"
                XCTAssertEqual(
                    render(cached), render(fresh),
                    "측정을 재사용한 결과가 매번 새로 잰 결과와 달라졌다 — \(label)"
                )
                XCTAssertEqual(
                    carried, reused,
                    "인스펙터 값만 바꿨는데 측정 묶음이 갱신됐다 — \(label)"
                )
            }
        }
    }

    /// 입력이 바뀌면(결함 제거 등) 캐시를 버려야 한다는 근거: 같은 베이스라도 측정값이 달라진다.
    func testMeasurementsDependOnInputPixels() throws {
        let engine = ChromabaseEngine()
        var params = DevelopParameters()
        params.filmType = .colorNegative
        let bright = try makeNegative(filmType: .colorNegative)
        let dark = try makeNegative(filmType: .colorNegative, densityScale: 0.6)
        let base = try XCTUnwrap(engine.estimateFilmBase(in: bright, mode: .auto))

        var first = DevelopSceneMeasurements()
        _ = engine.developScannerPreview(
            image: bright, base: base, params: params, maxDimension: 512, measurements: &first
        )
        var second = DevelopSceneMeasurements()
        _ = engine.developScannerPreview(
            image: dark, base: base, params: params, maxDimension: 512, measurements: &second
        )
        XCTAssertNotEqual(first, second, "다른 입력에서 같은 측정이 나오면 캐시 키가 무의미해진다")
    }

    // MARK: helpers

    private func render(_ image: CIImage) -> [UInt8] {
        let extent = image.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
        ]).render(
            image,
            toBitmap: &pixels,
            rowBytes: width * 4,
            bounds: extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        return pixels
    }

    /// 오렌지 마스크 위에 장면 밀도가 실린 합성 네거티브(실사진 미사용).
    private func makeNegative(
        filmType: FilmType,
        densityScale: Double = 1.0
    ) throws -> CIImage {
        let width = 480
        let height = 320
        let monochrome = filmType == .bwNegative
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            let fy = Double(y) / Double(height - 1)
            for x in 0..<width {
                let fx = Double(x) / Double(width - 1)
                let scene = 0.05 + 0.9 * (0.5 + 0.5 * sin(fx * 6.7) * cos(fy * 4.9))
                let density = (1.0 - scene) * densityScale
                let i = (y * width + x) * 4
                if monochrome {
                    let v = 0.80 * (0.10 + 0.90 * density)
                    pixels[i] = Float(v)
                    pixels[i + 1] = Float(v)
                    pixels[i + 2] = Float(v)
                } else {
                    pixels[i] = Float(0.86 * (0.12 + 0.88 * density))
                    pixels[i + 1] = Float(0.68 * (0.10 + 0.90 * density * 0.94))
                    pixels[i + 2] = Float(0.50 * (0.08 + 0.92 * density * 0.88))
                }
                pixels[i + 3] = 1
            }
        }
        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
        )
    }
}
