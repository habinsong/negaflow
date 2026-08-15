import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import XCTest
@testable import Chromabase

/// [작업 6] 메타데이터 정책 — 정책 네 가지로 TIFF 를 쓰고 실제로 들어간 태그를 남긴다.
///
/// 실행 예:
/// ```
/// NEGAFLOW_GOLDEN_DIR=/path/to/docs/verification/macos-golden/task6-metadata \
/// swift test --filter MacGoldenMetadataPolicyHarnessTests
/// ```
///
/// 픽셀은 정책과 무관하므로 64×64 합성 이미지를 쓴다 — 파일이 작아 네 개를 그대로 남긴다.
/// 원본 메타데이터는 고정 상수다. 실제 스캔 TIFF 에는 IPTC/GPS 가 없어 네 정책이 같은 결과를
/// 내므로, 정책 필터가 실제로 무엇을 지우는지 보이지 않기 때문이다.
final class MacGoldenMetadataPolicyHarnessTests: XCTestCase {

    func testEmitsMetadataPolicyGolden() throws {
        guard let outputDirectory = MacGoldenHarness.outputDirectory() else {
            throw XCTSkip("NEGAFLOW_GOLDEN_DIR 를 지정하면 golden 을 생성합니다.")
        }

        let image = CIImage(color: CIColor(red: 0.25, green: 0.5, blue: 0.75))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let context = ChromabaseEngine.sharedLinearRenderContext

        var records: [[String: Any]] = []
        for policy in [
            ExportMetadataPolicy.minimal,
            .copyrightOnly,
            .removeLocation,
            .all,
        ] {
            let meta = Self.makeMeta(policy: policy)
            let output = outputDirectory.appendingPathComponent("policy-\(policy.rawValue).tif")
            try ExportEngine.write(
                image,
                to: output,
                format: .tiff16,
                using: context,
                metadata: meta,
                options: ExportOptions(
                    colorSpace: .sRGB,
                    tiffCompression: .none,
                    tiffBitDepth: .sixteen,
                    metadataPolicy: policy
                )
            )
            records.append([
                "policy": policy.rawValue,
                "file": output.lastPathComponent,
                "sha256": try MacGoldenHarness.sha256(of: output),
                "bytes": try MacGoldenHarness.byteCount(of: output),
                "requestedProperties": Self.describe(ExportEngine.metadataProperties(meta)),
                "writtenProperties": Self.describe(Self.readProperties(output)),
            ])
        }

        let manifest: [String: Any] = [
            "task": "6 · export metadata policy",
            "fixture": [
                "pixels": "64x64 solid CIColor(0.25, 0.5, 0.75), sRGB, TIFF 16-bit uncompressed",
                "sourceMetadata": Self.describeSourceMetadata(Self.sourceMetadata),
                "exportMeta": [
                    "scannerMake": "Seiko Epson",
                    "scannerModel": "GT-X900",
                    "resolutionDPI": 2_400,
                    "filmType": "colorNegative",
                    "filmStock": "Kodak Portra 400",
                    "software": "negaflow golden harness",
                    "sourceDate": "2026-01-02T03:04:05Z",
                    "metadataDate": "2026-01-02T03:04:05Z",
                ],
            ],
            "policies": records,
        ]
        try MacGoldenHarness.writeJSON(
            manifest,
            to: outputDirectory.appendingPathComponent("metadata-policy.json")
        )
    }

    // MARK: 고정 픽스처

    private static let fixedDate = Date(timeIntervalSince1970: 1_767_323_045)   // 2026-01-02T03:04:05Z

    private static let sourceMetadata = ExportSourceMetadata(
        tiff: [
            "Artist": .string("Song Habin"),
            "Copyright": .string("(c) 2026 Song Habin"),
            "ImageDescription": .string("golden fixture"),
            "Make": .string("Seiko Epson"),
            "Model": .string("GT-X900"),
        ],
        exif: [
            "LensModel": .string("Nikkor 50mm f/1.4"),
            "ISOSpeedRatings": .integers([400]),
            "FNumber": .number(1.4),
        ],
        iptc: [
            "Byline": .string("Song Habin"),
            "CopyrightNotice": .string("(c) 2026 Song Habin"),
            "City": .string("Seoul"),
            // ImageIO 상수는 "SubLocation" 이다("Sub-location" 은 무시된다).
            "SubLocation": .string("Jongno-gu"),
            "Province/State": .string("Seoul"),
            "Country/PrimaryLocationName": .string("Republic of Korea"),
            "Country/PrimaryLocationCode": .string("KOR"),
            "Headline": .string("golden fixture"),
        ],
        gps: [
            "Latitude": .number(37.5729),
            "LatitudeRef": .string("N"),
            "Longitude": .number(126.9794),
            "LongitudeRef": .string("E"),
        ]
    )

    private static func makeMeta(policy: ExportMetadataPolicy) -> ExportMeta {
        ExportMeta(
            scannerMake: "Seiko Epson",
            scannerModel: "GT-X900",
            resolutionDPI: 2_400,
            filmType: "colorNegative",
            filmStock: "Kodak Portra 400",
            software: "negaflow golden harness",
            sourceDate: fixedDate,
            metadataDate: fixedDate,
            sourceMetadata: sourceMetadata,
            metadataPolicy: policy
        )
    }

    // MARK: 덤프

    private static func readProperties(_ url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else { return [:] }
        return properties
    }

    private static func describeSourceMetadata(_ metadata: ExportSourceMetadata) -> [String: Any] {
        [
            "tiff": metadata.tiff.mapValues(\.stringValue),
            "exif": metadata.exif.mapValues(\.stringValue),
            "iptc": metadata.iptc.mapValues(\.stringValue),
            "gps": metadata.gps.mapValues(\.stringValue),
        ]
    }

    /// CFString 키 딕셔너리를 JSON 으로 쓸 수 있는 문자열 트리로 바꾼다.
    private static func describe(_ properties: [CFString: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in properties {
            result[key as String] = normalize(value)
        }
        return result
    }

    private static func normalize(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.mapValues(normalize)
        }
        if let dictionary = value as? [CFString: Any] {
            return describe(dictionary)
        }
        if let array = value as? [Any] {
            return array.map(normalize)
        }
        if let number = value as? NSNumber { return number }
        if let string = value as? String { return string }
        return String(describing: value)
    }
}
