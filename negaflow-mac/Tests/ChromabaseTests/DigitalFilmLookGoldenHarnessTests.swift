import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import Chromabase

/// REQUEST-5 요청 F의 디지털 전용 필름 룩 기준값을 방출한다.
///
/// ```
/// NEGAFLOW_DIGITAL_FILM_LOOK_GOLDEN_DIR=/path/to/docs/verification/macos-golden/task8-digital-film-look \
/// swift test --filter DigitalFilmLookGoldenHarnessTests
/// ```
final class DigitalFilmLookGoldenHarnessTests: XCTestCase {
    private static let width = 256
    private static let height = 256

    private struct Case {
        let film: FilmEmulation
        let monochrome: Bool
    }

    func testEmitsDigitalFilmLookGolden() throws {
        guard let directory = MacGoldenHarness.outputDirectory("NEGAFLOW_DIGITAL_FILM_LOOK_GOLDEN_DIR") else {
            throw XCTSkip("NEGAFLOW_DIGITAL_FILM_LOOK_GOLDEN_DIR 를 지정하면 디지털 룩 기준값을 생성합니다.")
        }
        let linear = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))
        let context = SamplingContextPool.context(workingColorSpace: linear)
        let input = Self.fixturePixels()
        let image = MacGoldenHarness.makeLinearImage(
            pixels: input,
            width: Self.width,
            height: Self.height,
            colorSpace: linear
        )
        let inputURL = directory.appendingPathComponent("digital-film-look-input-256x256.f32")
        try MacGoldenHarness.writeFloat32(input, to: inputURL)

        var records: [[String: Any]] = []
        for item in Self.cases {
            for intensity in [0.5, 1.0] {
                let outputImage = DigitalFilmLook.apply(
                    to: image,
                    emulation: item.film,
                    intensity: intensity,
                    grainOverride: 0,
                    halationOverride: 0,
                    monochrome: item.monochrome
                )
                let output = MacGoldenHarness.renderLinearRGBAf(
                    outputImage,
                    width: Self.width,
                    height: Self.height,
                    context: context,
                    colorSpace: linear
                )
                XCTAssertTrue(output.allSatisfy(\.isFinite), "디지털 룩이 유한하지 않은 값을 냈습니다: \(item.film.rawValue)")
                let file = String(
                    format: "digital-film-look-%@-i%.3f-256x256.f32", item.film.rawValue, intensity
                )
                let url = directory.appendingPathComponent(file)
                try MacGoldenHarness.writeFloat32(output, to: url)
                records.append([
                    "filmEmulation": item.film.rawValue,
                    "monochrome": item.monochrome,
                    "intensity": intensity,
                    "file": file,
                    "sha256": try MacGoldenHarness.sha256(of: url),
                    "bytes": try MacGoldenHarness.byteCount(of: url),
                ])
            }
        }

        try MacGoldenHarness.writeJSON([
            "schemaVersion": 1,
            "task": "REQUEST-5 F · DigitalFilmLook pixel golden",
            "sourceContract": "synthetic positive digital scene; this is not a film-scan develop path",
            "workingColorSpace": "linear sRGB",
            "renderFormat": "little-endian Float32 RGBAf, row-major, y-down",
            "input": [
                "file": inputURL.lastPathComponent,
                "sha256": try MacGoldenHarness.sha256(of: inputURL),
                "bytes": try MacGoldenHarness.byteCount(of: inputURL),
                "width": Self.width,
                "height": Self.height,
                "layout": "sky gradient, warm subject, foliage, neutral wall, deep shadow, highlight patches",
            ],
            "cases": records,
        ], to: directory.appendingPathComponent("manifest.json"))
    }

    private static let cases = [
        Case(film: .portra400, monochrome: false),
        Case(film: .velvia50, monochrome: false),
        Case(film: .triX400, monochrome: true),
    ]

    private static func fixturePixels() -> [Float] {
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let r: Float
                let g: Float
                let b: Float
                switch (x / 64, y / 64) {
                case (_, 0):
                    let t = Float(x) / 255
                    r = 0.26 + 0.22 * t; g = 0.48 + 0.28 * t; b = 0.70 + 0.24 * t
                case (0, 1), (0, 2):
                    r = 0.07; g = 0.19 + Float(y % 64) / 512; b = 0.08
                case (1, 1), (1, 2):
                    r = 0.58 + Float(x % 64) / 512; g = 0.22; b = 0.10
                case (2, 1), (2, 2):
                    r = 0.17; g = 0.39 + Float(y % 64) / 640; b = 0.20
                case (3, 1), (3, 2):
                    r = 0.47; g = 0.45; b = 0.40
                case (_, 3):
                    if x < 64 {
                        r = 0.018; g = 0.022; b = 0.030
                    } else if x < 128 {
                        r = 0.18; g = 0.18; b = 0.18
                    } else if x < 192 {
                        r = 0.70; g = 0.64; b = 0.48
                    } else {
                        r = 0.95; g = 0.93; b = 0.88
                    }
                default:
                    r = 0; g = 0; b = 0
                }
                let index = (y * width + x) * 4
                pixels[index] = r
                pixels[index + 1] = g
                pixels[index + 2] = b
            }
        }
        return pixels
    }
}
