import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import Chromabase

/// REQUEST-5 요청 C·D의 Apple Core Image 필터 기준값을 방출한다.
///
/// ```
/// NEGAFLOW_COREIMAGE_FILTER_GOLDEN_DIR=/path/to/docs/verification/macos-golden/task7-coreimage-filters \
/// swift test --filter CoreImageFilterMappingGoldenTests
/// ```
///
/// 출력은 모두 little-endian RGBAf, linear sRGB, 행 우선(y-down)이다. 입력 한 장에는
/// 수직·수평 계단, 임펄스 격자, 정현파 스윕, 0.18/0.50/0.90 균일면이 모두 들어 있다.
final class CoreImageFilterMappingGoldenTests: XCTestCase {
    private static let width = 256
    private static let height = 256

    private struct FilterCase {
        let name: String
        let radius: Double
        let intensity: Double?
        let provenance: String
    }

    func testEmitsCoreImageFilterMappings() throws {
        guard let directory = MacGoldenHarness.outputDirectory("NEGAFLOW_COREIMAGE_FILTER_GOLDEN_DIR") else {
            throw XCTSkip("NEGAFLOW_COREIMAGE_FILTER_GOLDEN_DIR 를 지정하면 필터 기준값을 생성합니다.")
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
        let inputURL = directory.appendingPathComponent("coreimage-filter-input-256x256.f32")
        try MacGoldenHarness.writeFloat32(input, to: inputURL)

        let unsharp = Self.unsharpCases()
        let gaussian = Self.gaussianCases()
        var unsharpRecords: [[String: Any]] = []
        var gaussianRecords: [[String: Any]] = []

        for item in unsharp {
            let filtered = image.applyingFilter("CIUnsharpMask", parameters: [
                "inputRadius": item.radius,
                "inputIntensity": item.intensity!,
            ]).cropped(to: image.extent)
            let output = MacGoldenHarness.renderLinearRGBAf(
                filtered,
                width: Self.width,
                height: Self.height,
                context: context,
                colorSpace: linear
            )
            XCTAssertTrue(output.allSatisfy(\.isFinite), "CIUnsharpMask가 유한하지 않은 값을 냈습니다: \(item.name)")
            let file = "ciunsharpmask-\(item.name)-256x256.f32"
            let url = directory.appendingPathComponent(file)
            try MacGoldenHarness.writeFloat32(output, to: url)
            unsharpRecords.append(try Self.record(item, file: file, url: url))
        }

        for item in gaussian {
            let filtered = image.applyingFilter("CIGaussianBlur", parameters: [
                "inputRadius": item.radius,
            ]).cropped(to: image.extent)
            let output = MacGoldenHarness.renderLinearRGBAf(
                filtered,
                width: Self.width,
                height: Self.height,
                context: context,
                colorSpace: linear
            )
            XCTAssertTrue(output.allSatisfy(\.isFinite), "CIGaussianBlur가 유한하지 않은 값을 냈습니다: \(item.name)")
            let file = "cigaussianblur-\(item.name)-256x256.f32"
            let url = directory.appendingPathComponent(file)
            try MacGoldenHarness.writeFloat32(output, to: url)
            gaussianRecords.append(try Self.record(item, file: file, url: url))
        }

        try MacGoldenHarness.writeJSON([
            "schemaVersion": 1,
            "task": "REQUEST-5 C and D · Core Image neighborhood-filter mapping",
            "workingColorSpace": "linear sRGB",
            "renderFormat": "little-endian Float32 RGBAf, row-major, y-down",
            "extentBehavior": "Each direct Core Image filter result is cropped to the 256x256 input extent.",
            "input": [
                "file": inputURL.lastPathComponent,
                "sha256": try MacGoldenHarness.sha256(of: inputURL),
                "bytes": try MacGoldenHarness.byteCount(of: inputURL),
                "width": Self.width,
                "height": Self.height,
                "layout": [
                    "rows 0-63: left vertical step, right horizontal step",
                    "rows 64-127: impulse grid on neutral 0.18",
                    "rows 128-191: vertical sine-frequency sweep",
                    "rows 192-255: 0.18, 0.50, 0.90 uniform neutral patches",
                ],
            ],
            "ciUnsharpMask": unsharpRecords,
            "ciGaussianBlur": gaussianRecords,
            "pipelineParameterContracts": [
                "clarityPositive": "radius = 6 + clarity*5; intensity = 0.10 + clarity*0.18; clarity in (0, 1]",
                "outputSharpening": "screen: radius 0.45*sqrt(clamp(dpi/144, 0.5, 2)), intensity 0.22*strength; matte: 1.00*sqrt(clamp(dpi/300, 0.5, 2)), 0.34*strength; glossy: 0.75*sqrt(clamp(dpi/300, 0.5, 2)), 0.28*strength; strength in (0, 1]",
                "clarityNegative": "radius = 4 - clarity*6 for clarity in [-1, 0); the blurred result is mixed at min(0.9, -clarity*0.8)",
                "fixedGaussianAnchors": "1.0 software-defect fallback and heal-brush feather; 1.3 film-scan denoise fine band; 2.4 low-saturation chroma neutralization",
            ],
        ], to: directory.appendingPathComponent("manifest.json"))
    }

    private static func unsharpCases() -> [FilterCase] {
        let exportCases: [(String, OutputSharpeningMedium, Int)] = [
            ("export-screen-dpi144-strength1", .screen, 144),
            ("export-matte-dpi300-strength1", .mattePaper, 300),
            ("export-glossy-dpi300-strength1", .glossyPaper, 300),
        ]
        let outputAnchors = exportCases.compactMap { name, medium, dpi -> FilterCase? in
            guard let parameters = OutputSharpening.parameters(strength: 1, medium: medium, dpi: dpi) else {
                return nil
            }
            return FilterCase(name: name, radius: parameters.radius, intensity: parameters.intensity,
                              provenance: "ExportEngine output sharpening")
        }
        return [
            FilterCase(name: "clarity-0.01", radius: 6.05, intensity: 0.1018,
                       provenance: "ColorModel positive clarity lower anchor"),
            FilterCase(name: "clarity-0.50", radius: 8.5, intensity: 0.19,
                       provenance: "ColorModel positive clarity midpoint"),
            FilterCase(name: "clarity-1.00", radius: 11, intensity: 0.28,
                       provenance: "ColorModel positive clarity upper anchor"),
        ] + outputAnchors
    }

    private static func gaussianCases() -> [FilterCase] {
        [
            FilterCase(name: "radius1.0", radius: 1.0, intensity: nil,
                       provenance: "SoftwareDefectRemoval fallback and DefectHealBrush feather"),
            FilterCase(name: "radius1.3", radius: 1.3, intensity: nil,
                       provenance: "FilmScanDenoise fine band"),
            FilterCase(name: "radius2.4", radius: 2.4, intensity: nil,
                       provenance: "ScannerNoiseReduction low-saturation chroma"),
            FilterCase(name: "clarity-0.00-radius4.0", radius: 4.0, intensity: nil,
                       provenance: "ColorModel negative clarity lower endpoint"),
            FilterCase(name: "clarity-0.50-radius7.0", radius: 7.0, intensity: nil,
                       provenance: "ColorModel negative clarity midpoint"),
            FilterCase(name: "clarity-1.00-radius10.0", radius: 10.0, intensity: nil,
                       provenance: "ColorModel negative clarity upper endpoint"),
        ]
    }

    private static func record(_ item: FilterCase, file: String, url: URL) throws -> [String: Any] {
        var value: [String: Any] = [
            "file": file,
            "radius": item.radius,
            "provenance": item.provenance,
        ]
        if let intensity = item.intensity {
            value["intensity"] = intensity
        }
        value["sha256"] = try MacGoldenHarness.sha256(of: url)
        value["bytes"] = try MacGoldenHarness.byteCount(of: url)
        return value
    }

    private static func fixturePixels() -> [Float] {
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value: Float
                switch y / 64 {
                case 0:
                    if x < 128 {
                        value = x < 64 ? 0.18 : 0.82
                    } else {
                        value = y < 32 ? 0.18 : 0.82
                    }
                case 1:
                    let isImpulse = x % 32 == 16 && y % 32 == 16
                    value = isImpulse ? 0.90 : 0.18
                case 2:
                    let frequency = 1.0 + Double(x) * 31.0 / 255.0
                    let phase = 2.0 * Double.pi * frequency * Double(y - 128) / 64.0
                    value = Float(0.5 + 0.32 * sin(phase))
                default:
                    value = x < 85 ? 0.18 : (x < 171 ? 0.50 : 0.90)
                }
                let index = (y * width + x) * 4
                pixels[index] = value
                pixels[index + 1] = value
                pixels[index + 2] = value
            }
        }
        return pixels
    }
}
