import CoreGraphics
import CoreImage
import CryptoKit
import Foundation
import XCTest
@testable import Chromabase

// Emits the macOS ColorSync reference for the Windows ICM parity probe, and only when an
// explicit destination is given. Normal unit-test runs skip it and never write files.
//
// The measured path is the product import path, not a bespoke transform:
//   * a CGImage tagged with the synthetic scanner profile, wrapped by CIImage(cgImage:)
//     exactly as ImageLoader.profileAwareImage does for any ICC-tagged source,
//   * rendered through ChromabaseEngine.sharedLinearRenderContext, whose working colour
//     space is linear sRGB.
// Neither rendering intent nor black point compensation is selectable on that path, so
// the emitted document records the configuration rather than claiming an observed effect.
final class ColorSyncIcmParityGoldenTests: XCTestCase {
    private static let fixtureID = "colorsync-icm-parity-v1"

    func testEmitParityGoldenWhenRequested() throws {
        guard let destination = ProcessInfo.processInfo.environment[
            "NEGAFLOW_COLORSYNC_PARITY_OUTPUT"
        ], !destination.isEmpty else {
            throw XCTSkip("Set NEGAFLOW_COLORSYNC_PARITY_OUTPUT to emit the ColorSync parity reference.")
        }

        let profileData = SyntheticScannerICCProfile.data()
        let profileSpace = try XCTUnwrap(
            CGColorSpace(iccData: profileData as CFData),
            "ColorSync rejected the synthesised scanner profile"
        )
        let linearSRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))

        let patches = ColorSyncParityPatchSet.patches
        let quantized = patches.map { patch in
            [patch.rgb.0, patch.rgb.1, patch.rgb.2].map(Self.quantizeTo16Bit)
        }
        let image = try makeTaggedImage(quantized: quantized, colorSpace: profileSpace)
        let context = ChromabaseEngine.sharedLinearRenderContext
        let rendered = render(image, width: patches.count, context: context, colorSpace: linearSRGB)

        var records: [PatchRecord] = []
        var maxAnalyticDeviation = 0.0
        for (index, patch) in patches.enumerated() {
            let base = index * 4
            let output = [rendered[base], rendered[base + 1], rendered[base + 2]].map(Double.init)
            let input = quantized[index]
            for channel in 0..<3 {
                let expected = pow(input[channel], SyntheticScannerICCProfile.gamma)
                maxAnalyticDeviation = max(maxAnalyticDeviation, abs(output[channel] - expected))
            }
            XCTAssertTrue(output.allSatisfy { $0.isFinite }, "non-finite output for \(patch.name)")
            records.append(PatchRecord(name: patch.name, in: input, out: output))
        }

        let document = ParityDocument(
            schemaVersion: 1,
            fixtureId: Self.fixtureID,
            operatingSystem: Self.operatingSystem(),
            sourceCommit: Self.sourceCommit(),
            renderingIntent: "unspecified-core-image-default",
            blackPointCompensation: false,
            profile: ProfileRecord(
                synthesisRule: "Negaflow.Windows/docs/research/colorsync-icm-parity-profile.md",
                sha256: Self.hexDigest(profileData),
                byteCount: profileData.count
            ),
            macos: MacOSRecord(
                measuredPath: "CIImage(cgImage:) + ChromabaseEngine.sharedLinearRenderContext",
                workingColorSpace: "linear-sRGB",
                workingFormat: Self.formatName(context.workingFormat),
                outputDomain: "linear-sRGB float",
                inputQuantization: "round(value * 65535) / 65535",
                analyticReference: "pow(input, \(SyntheticScannerICCProfile.gamma))",
                analyticMaxAbsDeviation: maxAnalyticDeviation
            ),
            patches: records
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        let outputURL = URL(fileURLWithPath: destination)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
        print("COLORSYNC_PARITY path=\(outputURL.path) bytes=\(data.count) max_analytic_deviation=\(maxAnalyticDeviation)")
    }

    /// Guards the fixture contract itself, so a patch-set or profile edit fails here
    /// rather than silently producing a reference Windows cannot line up against.
    func testFixtureContractHoldsWithoutEmitting() throws {
        let patches = ColorSyncParityPatchSet.patches
        XCTAssertGreaterThanOrEqual(patches.count, 32)
        XCTAssertEqual(Set(patches.map(\.name)).count, patches.count, "patch names must be unique")
        for patch in patches {
            for channel in [patch.rgb.0, patch.rgb.1, patch.rgb.2] {
                XCTAssertTrue((0.0...1.0).contains(channel), "\(patch.name) is outside 0...1")
            }
        }
        for required in [0.000, 0.005, 0.010, 0.020, 0.050] {
            XCTAssertTrue(
                patches.contains { $0.rgb.0 == required && $0.rgb.1 == required && $0.rgb.2 == required },
                "near-black probe \(required) is missing"
            )
        }

        let profileData = SyntheticScannerICCProfile.data()
        XCTAssertEqual(profileData.count % 4, 0, "ICC profile must be 4-byte aligned")
        XCTAssertEqual(
            profileData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self).bigEndian },
            UInt32(profileData.count),
            "header size field must match the byte count"
        )
        XCTAssertNotNil(
            CGColorSpace(iccData: profileData as CFData),
            "ColorSync must accept the synthesised profile"
        )
        // The bytes are a contract with the Windows rebuild; a change here needs the
        // documented synthesis rule updated in the same commit.
        XCTAssertEqual(Self.hexDigest(profileData), Self.expectedProfileDigest)
    }

    static let expectedProfileDigest =
        "8c2dce29801bda9b1f532b3236f61f91171267ad8bbc997d46fb662cf9125d02"

    // MARK: - Helpers

    private func makeTaggedImage(
        quantized: [[Double]],
        colorSpace: CGColorSpace
    ) throws -> CIImage {
        var samples = [UInt16]()
        samples.reserveCapacity(quantized.count * 3)
        for patch in quantized {
            for channel in patch {
                samples.append(UInt16((channel * 65535.0).rounded()))
            }
        }
        let bytes = samples.withUnsafeBufferPointer { buffer in
            Data(bytes: buffer.baseAddress!, count: buffer.count * MemoryLayout<UInt16>.size)
        }
        let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
        let cgImage = try XCTUnwrap(
            CGImage(
                width: quantized.count,
                height: 1,
                bitsPerComponent: 16,
                bitsPerPixel: 48,
                bytesPerRow: quantized.count * 3 * MemoryLayout<UInt16>.size,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
                    .union(.byteOrder16Little),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .relativeColorimetric
            ),
            "could not build a 16-bit CGImage tagged with the synthetic profile"
        )
        // Same call the product import path makes for any ICC-tagged source.
        return CIImage(cgImage: cgImage)
    }

    private func render(
        _ image: CIImage,
        width: Int,
        context: CIContext,
        colorSpace: CGColorSpace
    ) -> [Float] {
        var output = [Float](repeating: 0, count: width * 4)
        output.withUnsafeMutableBufferPointer { buffer in
            context.render(
                image,
                toBitmap: buffer.baseAddress!,
                rowBytes: width * 4 * MemoryLayout<Float>.size,
                bounds: CGRect(x: 0, y: 0, width: width, height: 1),
                format: .RGBAf,
                colorSpace: colorSpace
            )
        }
        return output
    }

    private static func quantizeTo16Bit(_ value: Double) -> Double {
        (value * 65535.0).rounded() / 65535.0
    }

    private static func hexDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// `operatingSystemVersionString` is localised, so the emitted document would change
    /// with the runner's language. Compose the numeric version instead.
    private static func operatingSystem() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static func sourceCommit() -> String {
        let environment = ProcessInfo.processInfo.environment
        for key in ["NEGAFLOW_SOURCE_COMMIT", "GITHUB_SHA"] {
            if let value = environment[key], !value.isEmpty { return value }
        }
        return "local-unrecorded"
    }

    private static func formatName(_ format: CIFormat) -> String {
        switch format {
        case .RGBAf: return "RGBAf"
        case .RGBAh: return "RGBAh"
        case .RGBA16: return "RGBA16"
        case .RGBA8: return "RGBA8"
        default: return "unknown(\(format.rawValue))"
        }
    }
}

private struct ParityDocument: Encodable {
    let schemaVersion: Int
    let fixtureId: String
    let operatingSystem: String
    let sourceCommit: String
    let renderingIntent: String
    let blackPointCompensation: Bool
    let profile: ProfileRecord
    let macos: MacOSRecord
    let patches: [PatchRecord]
}

private struct ProfileRecord: Encodable {
    let synthesisRule: String
    let sha256: String
    let byteCount: Int
}

private struct MacOSRecord: Encodable {
    let measuredPath: String
    let workingColorSpace: String
    let workingFormat: String
    let outputDomain: String
    let inputQuantization: String
    let analyticReference: String
    let analyticMaxAbsDeviation: Double
}

private struct PatchRecord: Encodable {
    let name: String
    let `in`: [Double]
    let out: [Double]
}
