import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import Chromabase

// Emits a reviewed macOS Core Image reference only when an explicit destination
// is provided. Normal unit-test runs skip this harness and never write files.
final class WindowsFilmEmulationGoldenTests: XCTestCase {
    func testEmitGoldenWhenRequested() throws {
        guard let destination = ProcessInfo.processInfo.environment[
            "NEGAFLOW_WINDOWS_FILM_GOLDEN_OUTPUT"
        ], !destination.isEmpty else {
            throw XCTSkip("Set NEGAFLOW_WINDOWS_FILM_GOLDEN_OUTPUT to emit the Windows parity golden.")
        }

        let linearSRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))
        let contexts = makeContexts(linearSRGB: linearSRGB)
        let colorInput = colorFixturePixels()
        let colorImage = makeImage(
            pixels: colorInput,
            width: 4,
            height: 3,
            colorSpace: linearSRGB
        )
        let cube = FilmEmulationLUT.cube(for: .velvia50, intensity: 0.73)
        let colorOnly = colorImage.applyingFilter(
            "CIColorCubeWithColorSpace",
            parameters: [
                "inputCubeDimension": cube.dimension,
                "inputCubeData": cube.data,
                "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB) as Any,
            ]
        )
        let fullStage = FilmEmulationStage.apply(
            to: colorImage,
            emulation: .velvia50,
            intensity: 0.73
        )
        let patterns = probePatterns()
        let configurations = unsharpConfigurations()

        var rendererGoldens: [RendererGolden] = []
        for context in contexts {
            let colorOutput = render(
                colorOnly,
                width: 4,
                height: 3,
                context: context.context,
                colorSpace: linearSRGB
            )
            let fullStageOutput = render(
                fullStage,
                width: 4,
                height: 3,
                context: context.context,
                colorSpace: linearSRGB
            )
            var probes: [UnsharpProbeGolden] = []
            for pattern in patterns {
                let image = makeImage(
                    pixels: pattern.pixels,
                    width: pattern.width,
                    height: pattern.height,
                    colorSpace: linearSRGB
                )
                let inputRow = centerRow(
                    pattern.pixels,
                    width: pattern.width,
                    height: pattern.height
                )
                for configuration in configurations {
                    let filtered = image.applyingFilter(
                        "CIUnsharpMask",
                        parameters: [
                            "inputRadius": configuration.radius,
                            "inputIntensity": configuration.intensity,
                        ]
                    ).cropped(to: image.extent)
                    let output = render(
                        filtered,
                        width: pattern.width,
                        height: pattern.height,
                        context: context.context,
                        colorSpace: linearSRGB
                    )
                    probes.append(
                        UnsharpProbeGolden(
                            pattern: pattern.name,
                            radius: configuration.radius,
                            intensity: configuration.intensity,
                            width: pattern.width,
                            height: pattern.height,
                            row: pattern.height / 2,
                            inputCenterRow: inputRow,
                            outputCenterRow: centerRow(
                                output,
                                width: pattern.width,
                                height: pattern.height
                            )
                        )
                    )
                }
            }
            rendererGoldens.append(
                RendererGolden(
                    contextMode: context.name,
                    colorCubeOutput: colorOutput,
                    fullStageOutput: fullStageOutput,
                    unsharpProbes: probes
                )
            )
        }

        XCTAssertTrue(
            rendererGoldens.allSatisfy { renderer in
                renderer.colorCubeOutput.allSatisfy { $0.isFinite } &&
                    renderer.fullStageOutput.allSatisfy { $0.isFinite } &&
                    renderer.unsharpProbes.allSatisfy {
                        $0.outputCenterRow.allSatisfy { $0.isFinite }
                    }
            }
        )

        let document = FilmEmulationGoldenDocument(
            schemaVersion: 1,
            fixtureID: "film-emulation-core-image-v1",
            macOSBaselineCommit: try baselineCommit(),
            runnerCommit: ProcessInfo.processInfo.environment["GITHUB_SHA"] ?? "local-unrecorded",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            workingColorSpace: "extended-linear-sRGB",
            renderFormat: "RGBAf",
            alphaContract: "opaque",
            cubeDimension: cube.dimension,
            profile: FilmEmulation.velvia50.rawValue,
            requestedIntensity: 0.73,
            quantizedIntensity: 0.75,
            colorCubeInput: colorInput,
            renderers: rendererGoldens
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        let outputURL = URL(fileURLWithPath: destination)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
        XCTAssertGreaterThan(data.count, 1_000)
        print("WINDOWS_FILM_GOLDEN path=\(outputURL.path) bytes=\(data.count)")
    }

    private func makeContexts(linearSRGB: CGColorSpace) -> [NamedContext] {
        let common: [CIContextOption: Any] = [
            .workingColorSpace: linearSRGB,
            .outputColorSpace: linearSRGB,
            .cacheIntermediates: false,
        ]
        var softwareRequested = common
        softwareRequested[.useSoftwareRenderer] = true
        return [
            NamedContext(name: "default", context: CIContext(options: common)),
            NamedContext(
                name: "software_requested",
                context: CIContext(options: softwareRequested)
            ),
        ]
    }

    private func makeImage(
        pixels: [Float],
        width: Int,
        height: Int,
        colorSpace: CGColorSpace
    ) -> CIImage {
        precondition(pixels.count == width * height * 4)
        let data = pixels.withUnsafeBufferPointer { buffer in
            Data(
                bytes: buffer.baseAddress!,
                count: buffer.count * MemoryLayout<Float>.size
            )
        }
        return CIImage(
            bitmapData: data,
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: colorSpace
        )
    }

    private func render(
        _ image: CIImage,
        width: Int,
        height: Int,
        context: CIContext,
        colorSpace: CGColorSpace
    ) -> [Float] {
        var output = [Float](repeating: 0, count: width * height * 4)
        output.withUnsafeMutableBufferPointer { buffer in
            context.render(
                image,
                toBitmap: buffer.baseAddress!,
                rowBytes: width * 4 * MemoryLayout<Float>.size,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBAf,
                colorSpace: colorSpace
            )
        }
        return output
    }

    private func centerRow(_ pixels: [Float], width: Int, height: Int) -> [Float] {
        let start = (height / 2) * width * 4
        return Array(pixels[start..<(start + width * 4)])
    }

    private func colorFixturePixels() -> [Float] {
        [
            -0.2, 0.3, 1.2, 1.0,
            0.62, 0.30, 0.30, 1.0,
            0.72, 0.50, 0.12, 1.0,
            0.20, 0.65, 0.30, 1.0,
            0.10, 0.68, 0.72, 1.0,
            0.18, 0.22, 0.82, 1.0,
            0.62, 0.18, 0.70, 1.0,
            0.50, 0.50, 0.50, 1.0,
            0.02, 0.02, 0.02, 1.0,
            0.95, 0.90, 0.85, 1.0,
            1.2, -0.1, 0.2, 1.0,
            0.35, 0.30, 0.25, 1.0,
        ]
    }

    private func probePatterns() -> [ProbePattern] {
        let width = 33
        let height = 9
        var impulse = solidPixels(width: width, height: height, rgb: (0.25, 0.25, 0.25))
        setPixel(
            &impulse,
            width: width,
            x: width / 2,
            y: height / 2,
            rgb: (0.75, 0.75, 0.75)
        )

        var neutralStep = solidPixels(width: width, height: height, rgb: (0.25, 0.25, 0.25))
        var saturatedStep = solidPixels(width: width, height: height, rgb: (0.65, 0.10, 0.08))
        for y in 0..<height {
            for x in (width / 2)..<width {
                setPixel(
                    &neutralStep,
                    width: width,
                    x: x,
                    y: y,
                    rgb: (0.75, 0.75, 0.75)
                )
                setPixel(
                    &saturatedStep,
                    width: width,
                    x: x,
                    y: y,
                    rgb: (0.10, 0.65, 0.16)
                )
            }
        }
        return [
            ProbePattern(name: "neutral_impulse", width: width, height: height, pixels: impulse),
            ProbePattern(name: "neutral_step", width: width, height: height, pixels: neutralStep),
            ProbePattern(name: "saturated_step", width: width, height: height, pixels: saturatedStep),
        ]
    }

    private func solidPixels(
        width: Int,
        height: Int,
        rgb: (Float, Float, Float)
    ) -> [Float] {
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for index in 0..<(width * height) {
            pixels[index * 4] = rgb.0
            pixels[index * 4 + 1] = rgb.1
            pixels[index * 4 + 2] = rgb.2
        }
        return pixels
    }

    private func setPixel(
        _ pixels: inout [Float],
        width: Int,
        x: Int,
        y: Int,
        rgb: (Float, Float, Float)
    ) {
        let offset = (y * width + x) * 4
        pixels[offset] = rgb.0
        pixels[offset + 1] = rgb.1
        pixels[offset + 2] = rgb.2
        pixels[offset + 3] = 1
    }

    private func unsharpConfigurations() -> [UnsharpConfiguration] {
        [
            UnsharpConfiguration(radius: 1.0, intensity: 0.05),
            UnsharpConfiguration(radius: 1.0, intensity: 0.16),
            UnsharpConfiguration(radius: 1.0, intensity: 1.0),
            UnsharpConfiguration(radius: 1.1, intensity: 0.20),
            UnsharpConfiguration(radius: 1.1, intensity: 1.0),
            UnsharpConfiguration(radius: 1.2, intensity: 0.11),
            UnsharpConfiguration(radius: 1.2, intensity: 0.22),
            UnsharpConfiguration(radius: 1.2, intensity: 1.0),
        ]
    }

    private func baselineCommit() throws -> String {
        // 작업 디렉터리는 호출 방식(`--package-path` 등)에 따라 달라진다. Windows 트리는
        // 패키지 밖 저장소 루트에 있으므로 이 파일 위치를 기준으로 찾는다.
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ChromabaseTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // negaflow-mac
            .deletingLastPathComponent()   // 저장소 루트
            .appendingPathComponent("negaflow-windows/baseline/bootstrap-manifest.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
        guard let root = object as? [String: Any],
              let source = root["source"] as? [String: Any],
              let commit = source["mac_commit"] as? String,
              !commit.isEmpty else {
            throw GoldenEmitterError.invalidBaselineManifest
        }
        return commit
    }
}

private struct NamedContext {
    let name: String
    let context: CIContext
}

private struct ProbePattern {
    let name: String
    let width: Int
    let height: Int
    let pixels: [Float]
}

private struct UnsharpConfiguration {
    let radius: Double
    let intensity: Double
}

private struct FilmEmulationGoldenDocument: Encodable {
    let schemaVersion: Int
    let fixtureID: String
    let macOSBaselineCommit: String
    let runnerCommit: String
    let operatingSystem: String
    let workingColorSpace: String
    let renderFormat: String
    let alphaContract: String
    let cubeDimension: Int
    let profile: String
    let requestedIntensity: Double
    let quantizedIntensity: Double
    let colorCubeInput: [Float]
    let renderers: [RendererGolden]
}

private struct RendererGolden: Encodable {
    let contextMode: String
    let colorCubeOutput: [Float]
    let fullStageOutput: [Float]
    let unsharpProbes: [UnsharpProbeGolden]
}

private struct UnsharpProbeGolden: Encodable {
    let pattern: String
    let radius: Double
    let intensity: Double
    let width: Int
    let height: Int
    let row: Int
    let inputCenterRow: [Float]
    let outputCenterRow: [Float]
}

private enum GoldenEmitterError: Error {
    case invalidBaselineManifest
}
