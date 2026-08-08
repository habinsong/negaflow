import XCTest
import CoreImage
import ImageIO
@testable import Chromabase

final class ExportMetadataPolicyTests: XCTestCase {
    func testPoliciesFilterActualTIFFMetadataByCategory() throws {
        let metadata = sourceMetadata()
        let expectations: [(ExportMetadataPolicy, Bool, Bool, Bool)] = [
            (.all, true, true, true),
            (.removeLocation, false, true, true),
            (.copyrightOnly, false, true, false),
            (.minimal, false, false, false),
        ]

        for (policy, hasLocation, hasCopyright, hasCamera) in expectations {
            let url = temporaryURL("metadata-\(policy.rawValue).tif")
            defer { try? FileManager.default.removeItem(at: url) }
            try ExportEngine.write(
                CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8)),
                to: url,
                format: .tiff16,
                using: CIContext(),
                metadata: ExportMeta(
                    sourceMetadata: metadata,
                    metadataPolicy: policy
                ),
                options: ExportOptions(metadataPolicy: policy)
            )

            let properties = try imageProperties(url)
            let tiff = dictionary(properties[kCGImagePropertyTIFFDictionary])
            let exif = dictionary(properties[kCGImagePropertyExifDictionary])
            let iptc = dictionary(properties[kCGImagePropertyIPTCDictionary])
            let gps = dictionary(properties[kCGImagePropertyGPSDictionary])
            XCTAssertEqual(!gps.isEmpty, hasLocation, policy.rawValue)
            XCTAssertEqual(iptc[kCGImagePropertyIPTCCity as String] != nil, hasLocation, policy.rawValue)
            XCTAssertEqual(
                iptc[kCGImagePropertyIPTCCopyrightNotice as String] as? String == "Copyright 2026",
                hasCopyright,
                policy.rawValue
            )
            XCTAssertEqual(
                tiff[kCGImagePropertyTIFFMake as String] as? String == "Source Camera"
                    || exif["Make"] as? String == "Source Camera",
                hasCamera,
                policy.rawValue
            )
        }
    }

    func testSidecarXMPUsesSameFilteredMetadataPolicy() {
        let source = sourceMetadata()
        for policy in ExportMetadataPolicy.allCases {
            var sidecar = Sidecar(
                filmType: .colorNegative,
                parameters: DevelopParameters()
            )
            sidecar.exportMetadataPolicy = policy
            sidecar.exportSourceMetadata = source.filtered(for: policy)
            let packet = sidecar.xmpPacket()

            XCTAssertTrue(packet.contains("negaflow:ExportMetadataPolicy=\"\(policy.rawValue)\""))
            XCTAssertEqual(packet.contains("photoshop:City=\"Seoul\""), policy == .all)
            XCTAssertEqual(
                packet.contains("dc:rights=\"Copyright 2026\""),
                policy == .all || policy == .removeLocation || policy == .copyrightOnly
            )
            XCTAssertEqual(packet.contains("tiff:Make=\"Source Camera\""), policy == .all || policy == .removeLocation)
            XCTAssertEqual(packet.contains("exif:GPSLatitude=\"37.5\""), policy == .all)
        }
    }

    func testJPEGLocationRemovalAffectsActualEncodedMetadata() throws {
        for policy in [ExportMetadataPolicy.all, .removeLocation] {
            let url = temporaryURL("metadata-\(policy.rawValue).jpg")
            defer { try? FileManager.default.removeItem(at: url) }
            try ExportEngine.write(
                CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16)),
                to: url,
                format: .jpeg,
                using: CIContext(),
                metadata: ExportMeta(
                    sourceMetadata: sourceMetadata(),
                    metadataPolicy: policy
                ),
                options: ExportOptions(metadataPolicy: policy)
            )

            let properties = try imageProperties(url)
            let iptc = dictionary(properties[kCGImagePropertyIPTCDictionary])
            let gps = dictionary(properties[kCGImagePropertyGPSDictionary])
            XCTAssertEqual(!gps.isEmpty, policy == .all)
            XCTAssertEqual(
                iptc[kCGImagePropertyIPTCCity as String] as? String == "Seoul",
                policy == .all
            )
            XCTAssertEqual(
                iptc[kCGImagePropertyIPTCCopyrightNotice as String] as? String,
                "Copyright 2026"
            )
        }
    }

    func testLegacyOptionsAndSidecarEncodingDefaultToMinimalPolicy() throws {
        let legacyOptions = Data(#"{"colorSpace":"sRGB","dpi":0}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(ExportOptions.self, from: legacyOptions).metadataPolicy,
            .minimal
        )

        let legacyEncoding = Data(#"{"colorSpace":"sRGB","dpi":0,"jpegQuality":0.95,"preserveAlpha":false,"tiffBitDepth":16,"tiffCompression":"none"}"#.utf8)
        XCTAssertNil(
            try JSONDecoder().decode(Sidecar.ExportEncodingInfo.self, from: legacyEncoding)
                .metadataPolicy
        )
    }

    private func sourceMetadata() -> ExportSourceMetadata {
        ExportSourceMetadata(
            tiff: [
                kCGImagePropertyTIFFMake as String: .string("Source Camera"),
                kCGImagePropertyTIFFArtist as String: .string("Photographer"),
                kCGImagePropertyTIFFCopyright as String: .string("Copyright 2026"),
            ],
            exif: [
                kCGImagePropertyExifLensModel as String: .string("Source Lens"),
            ],
            iptc: [
                kCGImagePropertyIPTCObjectName as String: .string("Frame Title"),
                kCGImagePropertyIPTCCity as String: .string("Seoul"),
                kCGImagePropertyIPTCCopyrightNotice as String: .string("Copyright 2026"),
            ],
            gps: [
                kCGImagePropertyGPSLatitude as String: .number(37.5),
                kCGImagePropertyGPSLatitudeRef as String: .string("N"),
                kCGImagePropertyGPSLongitude as String: .number(127.0),
                kCGImagePropertyGPSLongitudeRef as String: .string("E"),
            ]
        )
    }

    private func imageProperties(_ url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
    }

    private func dictionary(_ value: Any?) -> [String: Any] {
        value as? [String: Any] ?? [:]
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-\(UUID().uuidString)-\(name)")
    }
}
