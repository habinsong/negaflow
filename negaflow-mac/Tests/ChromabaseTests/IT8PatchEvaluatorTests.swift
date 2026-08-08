import CoreGraphics
import CryptoKit
import ImageIO
import XCTest
@testable import Chromabase

final class IT8PatchEvaluatorTests: XCTestCase {
    func testSyntheticGridUsesTopLeftGeometryICCAndReferencePatchIDs() throws {
        let fixture = try makeFixture()
        let report = try IT8PatchEvaluator.evaluate(manifestURL: fixture.manifestURL)

        XCTAssertEqual(report.qualityDecision, .notEvaluated)
        XCTAssertEqual(report.sourceCodeEndpointClipping, .notMeasured)
        XCTAssertEqual(report.schemaVersion, 2)
        XCTAssertEqual(report.manifestSHA256, fixture.manifestSHA256)
        XCTAssertEqual(report.evidenceClass, .algorithmRegression)
        XCTAssertEqual(report.provenance.physicalTargetIdentity, .notVerified)
        XCTAssertEqual(
            report.provenance.referenceConditions,
            .evaluatorD50TwoDegreeConversionContractOnly
        )
        XCTAssertEqual(
            report.provenance.renderingIntent,
            .manifestDeclarationNotControlledByEvaluator
        )
        XCTAssertEqual(report.targetStandard, "IT8.7/1-synthetic")
        XCTAssertEqual(report.batchID, "synthetic-2x2-v1")
        XCTAssertEqual(report.image.sha256, fixture.imageSHA256)
        XCTAssertEqual(report.image.iccProfileName, fixture.iccProfileName)
        XCTAssertEqual(report.image.iccProfileSHA256, fixture.iccProfileSHA256)
        XCTAssertEqual(report.reference.sha256, fixture.referenceSHA256)
        XCTAssertEqual(report.reference.usedPatchCount, 4)
        XCTAssertEqual(report.reference.unusedReferencePatchCount, 1)
        XCTAssertEqual(report.patches.map(\.id), ["A1", "A2", "B1", "B2"])
        XCTAssertEqual(report.patches.map(\.referenceID), ["A01", "A2", "B01", "B2"])

        XCTAssertEqual(
            report.patches.map(\.roiTopLeftPixels),
            [
                .init(x: 5, y: 5, width: 10, height: 10),
                .init(x: 25, y: 5, width: 10, height: 10),
                .init(x: 5, y: 25, width: 10, height: 10),
                .init(x: 25, y: 25, width: 10, height: 10),
            ]
        )
        XCTAssertEqual(
            report.patches.map(\.roiCIImagePixels),
            [
                .init(x: 5, y: 25, width: 10, height: 10),
                .init(x: 25, y: 25, width: 10, height: 10),
                .init(x: 5, y: 5, width: 10, height: 10),
                .init(x: 25, y: 5, width: 10, height: 10),
            ]
        )

        for (patch, encodedRGB) in zip(report.patches, fixture.patchRGB) {
            XCTAssertEqual(patch.pixelCount, 100)
            XCTAssertEqual(patch.finitePixelCount, 100)
            XCTAssertTrue(patch.flags.isEmpty)
            let expected = encodedRGB.map(sRGBDecode)
            let mean = try XCTUnwrap(patch.linearRGBMean)
            XCTAssertEqual(mean.r, expected[0], accuracy: 0.002)
            XCTAssertEqual(mean.g, expected[1], accuracy: 0.002)
            XCTAssertEqual(mean.b, expected[2], accuracy: 0.002)
            let standardDeviation = try XCTUnwrap(patch.linearRGBStandardDeviation)
            XCTAssertLessThan(standardDeviation.r, 0.0001)
            XCTAssertLessThan(standardDeviation.g, 0.0001)
            XCTAssertLessThan(standardDeviation.b, 0.0001)
            XCTAssertLessThan(try XCTUnwrap(patch.delta?.e00), 0.2)
        }

        XCTAssertEqual(report.summary.validPatchCount, 4)
        XCTAssertEqual(report.summary.workingSpaceExcursionPatchCount, 0)
        XCTAssertLessThan(try XCTUnwrap(report.summary.maximumDeltaE00), 0.2)
    }

    func testImageHashMismatchIsRejectedBeforeMeasurement() throws {
        let fixture = try makeFixture(imageHashOverride: "sha256:" + String(repeating: "0", count: 64))

        XCTAssertThrowsError(try IT8PatchEvaluator.evaluate(manifestURL: fixture.manifestURL)) { error in
            guard case IT8BenchmarkError.fileHashMismatch(let kind, let expected, let actual) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(kind, "image")
            XCTAssertEqual(expected, "sha256:" + String(repeating: "0", count: 64))
            XCTAssertEqual(actual, fixture.imageSHA256)
        }
    }

    func testICCProfileNameMismatchIsRejected() throws {
        let fixture = try makeFixture(profileNameOverride: "not-the-embedded-profile")

        XCTAssertThrowsError(try IT8PatchEvaluator.evaluate(manifestURL: fixture.manifestURL)) { error in
            guard case IT8BenchmarkError.iccProfileNameMismatch(let expected, let actual) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(expected, "not-the-embedded-profile")
            XCTAssertEqual(actual, fixture.iccProfileName)
        }
    }

    func testImageAndReferenceOverridesDoNotRequireVendoredDefaultPaths() throws {
        let fixture = try makeFixture(
            imagePath: "not-vendored/official-target.tiff",
            referencePath: "not-vendored/official-reference.txt"
        )

        let report = try IT8PatchEvaluator.evaluate(
            manifestURL: fixture.manifestURL,
            imageURLOverride: fixture.imageURL,
            referenceURLOverride: fixture.referenceURL
        )

        XCTAssertEqual(report.image.sha256, fixture.imageSHA256)
        XCTAssertEqual(report.reference.sha256, fixture.referenceSHA256)
        XCTAssertEqual(report.summary.validPatchCount, 4)
    }

    func testManifestRelativePathEscapeIsRejectedEvenWithOverrides() throws {
        let fixture = try makeFixture(imagePath: "../outside.tiff")

        XCTAssertThrowsError(try IT8PatchEvaluator.evaluate(
            manifestURL: fixture.manifestURL,
            imageURLOverride: fixture.imageURL,
            referenceURLOverride: fixture.referenceURL
        )) { error in
            XCTAssertEqual(error as? IT8BenchmarkError, .manifestPathEscapes("../outside.tiff"))
        }
    }

    func testDeviceCharacterizationRequiresMeasurementPhysicalTargetIdentity() throws {
        let fixture = try makeFixture(evidenceClass: .deviceCharacterization)

        XCTAssertThrowsError(try IT8PatchEvaluator.evaluate(manifestURL: fixture.manifestURL)) {
            error in
            XCTAssertEqual(
                error as? IT8BenchmarkError,
                .invalidManifest(
                    "deviceCharacterization requires measurement.physicalTargetIdentity"
                )
            )
        }
    }

    func testLowerEvidenceClassCannotCarryPhysicalTargetIdentityClaim() throws {
        let fixture = try makeFixture(
            evidenceClass: .algorithmRegression,
            physicalTargetIdentity: physicalTargetIdentity()
        )

        XCTAssertThrowsError(try IT8PatchEvaluator.evaluate(manifestURL: fixture.manifestURL)) {
            error in
            XCTAssertEqual(
                error as? IT8BenchmarkError,
                .invalidManifest(
                    "measurement.physicalTargetIdentity is reserved for deviceCharacterization"
                )
            )
        }
    }

    func testDeviceCharacterizationRequiresExactReferenceHeaderIdentity() throws {
        let identity = physicalTargetIdentity()
        let fixture = try makeFixture(
            evidenceClass: .deviceCharacterization,
            physicalTargetIdentity: identity,
            referenceMetadata: physicalTargetMetadata(manufacturer: "Different Manufacturer")
        )

        XCTAssertThrowsError(try IT8PatchEvaluator.evaluate(manifestURL: fixture.manifestURL)) {
            error in
            XCTAssertEqual(
                error as? IT8BenchmarkError,
                .physicalTargetIdentityMismatch(
                    field: "MANUFACTURER",
                    expected: identity.manufacturer,
                    actual: "Different Manufacturer"
                )
            )
        }
    }

    func testDeviceCharacterizationReportsLimitedMatchedIdentityProvenance() throws {
        let identity = physicalTargetIdentity()
        let fixture = try makeFixture(
            evidenceClass: .deviceCharacterization,
            physicalTargetIdentity: identity,
            referenceMetadata: physicalTargetMetadata()
        )

        let report = try IT8PatchEvaluator.evaluate(manifestURL: fixture.manifestURL)

        XCTAssertEqual(report.evidenceClass, .deviceCharacterization)
        XCTAssertEqual(
            report.provenance.physicalTargetIdentity,
            .operatorRecordedMeasurementIdentityMatchedReferenceHeader
        )
        XCTAssertEqual(report.measurement.physicalTargetIdentity, identity)
        XCTAssertEqual(report.targetID, identity.serial)
        XCTAssertEqual(report.batchID, identity.batchValue)
    }

    func testReferenceConditionHeaderMatchIsDistinguishedFromConversionContractOnly() throws {
        let fixture = try makeFixture(referenceMetadata: [
            "ILLUMINATION_NAME": "D50",
            "OBSERVER_ANGLE": "2 degree",
        ])

        let report = try IT8PatchEvaluator.evaluate(manifestURL: fixture.manifestURL)

        XCTAssertEqual(
            report.provenance.referenceConditions,
            .referenceHeaderMatchAndEvaluatorConversionContract
        )
    }

    func testContradictoryReferenceConditionIsRejected() throws {
        let fixture = try makeFixture(referenceMetadata: ["ILLUMINATION_NAME": "D65"])

        XCTAssertThrowsError(try IT8PatchEvaluator.evaluate(manifestURL: fixture.manifestURL)) {
            error in
            XCTAssertEqual(
                error as? IT8BenchmarkError,
                .referenceConditionMismatch(
                    field: "ILLUMINATION_NAME",
                    expected: "D50",
                    actual: "D65"
                )
            )
        }
    }
}

private extension IT8PatchEvaluatorTests {
    struct Fixture {
        let manifestURL: URL
        let imageURL: URL
        let referenceURL: URL
        let manifestSHA256: String
        let imageSHA256: String
        let referenceSHA256: String
        let iccProfileName: String
        let iccProfileSHA256: String
        let patchRGB: [[Double]]
    }

    func makeFixture(
        imageHashOverride: String? = nil,
        profileNameOverride: String? = nil,
        imagePath: String = "target.tiff",
        referencePath: String = "reference.txt",
        evidenceClass: IT8BenchmarkManifest.EvidenceClass = .algorithmRegression,
        physicalTargetIdentity: IT8BenchmarkManifest.Measurement.PhysicalTargetIdentity? = nil,
        referenceMetadata: [String: String] = [:],
        targetID: String? = nil,
        batchID: String? = nil
    ) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-it8-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("target.tiff")
        let referenceURL = directory.appendingPathComponent("reference.txt")
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let encodedBytes: [[UInt8]] = [
            [64, 96, 128],
            [192, 96, 32],
            [32, 160, 96],
            [200, 200, 200],
        ]
        try writeTIFF(patches: encodedBytes, width: 40, height: 40, to: imageURL)
        let profile = try imageProfile(at: imageURL)

        let labs = encodedBytes.map { bytes -> ColorTargetLab in
            let rgb = SIMD3<Double>(
                sRGBDecode(Double(bytes[0]) / 255.0),
                sRGBDecode(Double(bytes[1]) / 255.0),
                sRGBDecode(Double(bytes[2]) / 255.0)
            )
            return ColorTargetColorimetry.linearSRGBToLabD50(rgb)
        }
        let rows: [(String, ColorTargetLab)] = [
            ("B2", labs[3]),
            ("B01", labs[2]),
            ("A2", labs[1]),
            ("A01", labs[0]),
            ("GS01", ColorTargetLab(l: 50, a: 0, b: 0)),
        ]
        var reference = referenceMetadata.keys.sorted().map { key in
            "\(key)\t\(referenceMetadata[key]!)\n"
        }.joined()
        reference += "SAMPLE_ID\tLAB_L\tLAB_A\tLAB_B\n"
        for (id, lab) in rows {
            reference += "\(id)\t\(lab.l)\t\(lab.a)\t\(lab.b)\n"
        }
        try Data(reference.utf8).write(to: referenceURL, options: .atomic)

        let imageSHA256 = try sha256(imageURL)
        let referenceSHA256 = try sha256(referenceURL)
        let manifest = IT8BenchmarkManifest(
            evidenceClass: evidenceClass,
            targetStandard: "IT8.7/1-synthetic",
            targetID: targetID ?? physicalTargetIdentity?.serial ?? "synthetic-2x2",
            batchID: batchID ?? physicalTargetIdentity?.batchValue ?? "synthetic-2x2-v1",
            referenceKind: "synthetic-fixture",
            image: .init(
                path: imagePath,
                sha256: imageHashOverride ?? imageSHA256,
                width: 40,
                height: 40,
                expectedICCProfileName: profileNameOverride ?? profile.name,
                expectedICCProfileSHA256: profile.sha256
            ),
            reference: .init(path: referencePath, sha256: referenceSHA256),
            layout: .init(
                rows: 2,
                columns: 2,
                gridRectTopLeftPixels: .init(x: 0, y: 0, width: 40, height: 40),
                roiInsetFraction: 0.25
            ),
            measurement: .init(physicalTargetIdentity: physicalTargetIdentity)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        let manifestSHA256 = try sha256(manifestURL)

        return Fixture(
            manifestURL: manifestURL,
            imageURL: imageURL,
            referenceURL: referenceURL,
            manifestSHA256: manifestSHA256,
            imageSHA256: imageSHA256,
            referenceSHA256: referenceSHA256,
            iccProfileName: profile.name,
            iccProfileSHA256: profile.sha256,
            patchRGB: encodedBytes.map { $0.map { Double($0) / 255.0 } }
        )
    }

    func physicalTargetIdentity()
    -> IT8BenchmarkManifest.Measurement.PhysicalTargetIdentity {
        .init(
            manufacturer: "Measured Target Co",
            material: "Positive transparency",
            serial: "TARGET-SERIAL-001",
            batchMetadataKey: "PROD_DATE",
            batchValue: "2026-07-18"
        )
    }

    func physicalTargetMetadata(
        manufacturer: String = "Measured Target Co"
    ) -> [String: String] {
        [
            "MANUFACTURER": manufacturer,
            "MATERIAL": "Positive transparency",
            "SERIAL": "TARGET-SERIAL-001",
            "PROD_DATE": "2026-07-18",
        ]
    }

    func writeTIFF(patches: [[UInt8]], width: Int, height: Int, to url: URL) throws {
        precondition(patches.count == 4)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let patchIndex = (y < height / 2 ? 0 : 2) + (x < width / 2 ? 0 : 1)
                let rgb = patches[patchIndex]
                let offset = (y * width + x) * 4
                bytes[offset] = rgb[0]
                bytes[offset + 1] = rgb[1]
                bytes[offset + 2] = rgb[2]
            }
        }
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .relativeColorimetric
              ),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                "public.tiff" as CFString,
                1,
                nil
              ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    func imageProfile(at url: URL) throws -> (name: String, sha256: String) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let name = try XCTUnwrap(properties[kCGImagePropertyProfileName] as? String)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let profileData = try XCTUnwrap(image.colorSpace?.copyICCData() as Data?)
        return (name, sha256(profileData))
    }

    func sha256(_ url: URL) throws -> String {
        sha256(try Data(contentsOf: url))
    }

    func sha256(_ data: Data) -> String {
        "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func sRGBDecode(_ encoded: Double) -> Double {
        encoded <= 0.04045
            ? encoded / 12.92
            : pow((encoded + 0.055) / 1.055, 2.4)
    }
}
