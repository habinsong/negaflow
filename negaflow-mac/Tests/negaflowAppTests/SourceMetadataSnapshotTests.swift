import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import negaflowApp

final class SourceMetadataSnapshotTests: XCTestCase {
    func testReaderSeparatesEmbeddedFactsFromExternalXMPWithoutPersistingGPSCoordinates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-source-metadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("negative.tiff")
        try writeTIFF(
            to: sourceURL,
            properties: [
                kCGImagePropertyDPIWidth: 300,
                kCGImagePropertyDPIHeight: 300,
                kCGImagePropertyOrientation: 6,
                kCGImagePropertyTIFFDictionary: [
                    kCGImagePropertyTIFFMake: "Nikon",
                    kCGImagePropertyTIFFModel: "F3",
                    kCGImagePropertyTIFFXResolution: 300,
                    kCGImagePropertyTIFFYResolution: 300,
                    kCGImagePropertyTIFFResolutionUnit: 2,
                ],
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifDateTimeOriginal: "2024:02:29 10:20:30",
                    kCGImagePropertyExifOffsetTimeOriginal: "+09:00",
                    kCGImagePropertyExifSubsecTimeOriginal: "25",
                    kCGImagePropertyExifLensModel: "NIKKOR 50mm f/1.4",
                    kCGImagePropertyExifExposureTime: 0.008,
                    kCGImagePropertyExifFNumber: 5.6,
                    kCGImagePropertyExifISOSpeedRatings: [100, 200],
                    kCGImagePropertyExifFocalLength: 50,
                ],
                kCGImagePropertyIPTCDictionary: [
                    kCGImagePropertyIPTCObjectName: "Title",
                    kCGImagePropertyIPTCHeadline: "Headline",
                    kCGImagePropertyIPTCCaptionAbstract: "Caption",
                    kCGImagePropertyIPTCByline: "Alice",
                    kCGImagePropertyIPTCKeywords: ["film", "archive"],
                    kCGImagePropertyIPTCCity: "Seoul",
                    kCGImagePropertyIPTCProvinceState: "Seoul",
                    kCGImagePropertyIPTCCountryPrimaryLocationName: "Korea",
                    kCGImagePropertyIPTCSubLocation: "Jongno",
                ],
                kCGImagePropertyGPSDictionary: [
                    kCGImagePropertyGPSLatitudeRef: "N",
                    kCGImagePropertyGPSLatitude: 37.5,
                    kCGImagePropertyGPSLongitudeRef: "E",
                    kCGImagePropertyGPSLongitude: 127.0,
                ],
            ]
        )
        try Data(sidecarXMP.utf8).write(
            to: sourceURL.deletingPathExtension().appendingPathExtension("xmp")
        )

        let snapshot = SourceMetadataReader.read(from: sourceURL)

        XCTAssertEqual(snapshot.version, SourceMetadataSnapshot.currentVersion)
        XCTAssertNotNil(snapshot.fileTypeIdentifier)
        XCTAssertGreaterThan(snapshot.fileSizeBytes ?? 0, 0)
        XCTAssertEqual(snapshot.pixelWidth, 2)
        XCTAssertEqual(snapshot.pixelHeight, 1)
        XCTAssertEqual(snapshot.resolutionDPI, 300)
        XCTAssertEqual(snapshot.orientation, 6)
        XCTAssertEqual(snapshot.exif?.cameraMake, "Nikon")
        XCTAssertEqual(snapshot.exif?.cameraModel, "F3")
        XCTAssertEqual(snapshot.exif?.lensModel, "NIKKOR 50mm f/1.4")
        XCTAssertEqual(snapshot.exif?.isoSpeedRatings, [100, 200])
        XCTAssertEqual(
            snapshot.exif?.capturedAt,
            SourceMetadataReader.parseXMPDate("2024-02-29T01:20:30.25Z")
        )
        XCTAssertEqual(snapshot.iptc?.title, "Title")
        XCTAssertEqual(snapshot.iptc?.keywords, ["film", "archive"])
        XCTAssertEqual(snapshot.iptc?.city, "Seoul")
        XCTAssertTrue(snapshot.containsStandardGPSMetadata)
        XCTAssertEqual(snapshot.sidecarXMPState, .loaded)
        XCTAssertEqual(snapshot.sidecarXMP?.title?.defaultValue, "Sidecar title")
        XCTAssertEqual(snapshot.sidecarXMP?.title?.valuesByLanguage["ko"], "사이드카 제목")
        XCTAssertEqual(snapshot.sidecarXMP?.description?.defaultValue, "Sidecar description")
        XCTAssertEqual(snapshot.sidecarXMP?.creators, ["Alice", "Bob"])
        XCTAssertEqual(snapshot.sidecarXMP?.keywords, ["film", "Seoul"])
        XCTAssertEqual(snapshot.sidecarXMP?.rating, 4)
        XCTAssertEqual(snapshot.sidecarXMP?.label, "Red")
        XCTAssertEqual(snapshot.sidecarXMP?.usageTerms?.defaultValue, "Editorial use")
        XCTAssertEqual(snapshot.sidecarXMP?.city, "Seoul")
        XCTAssertFalse(snapshot.discardedOversizedValues)

        let encoded = try JSONEncoder().encode(snapshot)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("gpslatitude"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("gpslongitude"))
    }

    func testEXIFDateRequiresAValidExplicitOffsetAndRejectsNormalizedInvalidDates() throws {
        XCTAssertNil(SourceMetadataReader.parseEXIFDate(
            dateTimeRaw: "2024:02:29 10:20:30",
            offsetRaw: nil,
            subsecondRaw: nil
        ))
        XCTAssertNil(SourceMetadataReader.parseEXIFDate(
            dateTimeRaw: "2023:02:29 10:20:30",
            offsetRaw: "+09:00",
            subsecondRaw: nil
        ))
        XCTAssertNil(SourceMetadataReader.parseEXIFDate(
            dateTimeRaw: "2024:02:29 10:20:30",
            offsetRaw: "+14:30",
            subsecondRaw: nil
        ))
        XCTAssertNil(SourceMetadataReader.parseEXIFDate(
            dateTimeRaw: "2024:02:29 10:20:30",
            offsetRaw: "-14:01",
            subsecondRaw: nil
        ))
        XCTAssertNil(SourceMetadataReader.parseEXIFDate(
            dateTimeRaw: "1900:02:29 10:20:30",
            offsetRaw: "+00:00",
            subsecondRaw: nil
        ))
        XCTAssertNotNil(SourceMetadataReader.parseEXIFDate(
            dateTimeRaw: "2000:02:29 10:20:30",
            offsetRaw: "+00:00",
            subsecondRaw: nil
        ))

        let positiveFourteen = SourceMetadataReader.parseEXIFDate(
            dateTimeRaw: "2024:02:29 10:20:30",
            offsetRaw: "+14:00",
            subsecondRaw: "125"
        )
        XCTAssertEqual(
            positiveFourteen,
            SourceMetadataReader.parseXMPDate("2024-02-28T20:20:30.125Z")
        )
        let negativeFourteen = SourceMetadataReader.parseEXIFDate(
            dateTimeRaw: "2024:02:29 10:20:30",
            offsetRaw: "-14:00",
            subsecondRaw: "000001"
        )
        XCTAssertEqual(
            try XCTUnwrap(negativeFourteen).timeIntervalSince1970,
            try XCTUnwrap(
                SourceMetadataReader.parseXMPDate("2024-03-01T00:20:30Z")
            ).timeIntervalSince1970 + 0.000001,
            accuracy: 0.000_000_1
        )

        let wholeSecond = SourceMetadataReader.parseEXIFDate(
            dateTimeRaw: "2024:02:29 10:20:30",
            offsetRaw: "+09:00",
            subsecondRaw: nil
        )
        XCTAssertEqual(
            SourceMetadataReader.parseEXIFDate(
                dateTimeRaw: "2024:02:29 10:20:30",
                offsetRaw: "+09:00",
                subsecondRaw: "not-a-number"
            ),
            wholeSecond
        )
    }

    func testXMPDateRequiresAnExplicitTimeZone() {
        XCTAssertNil(SourceMetadataReader.parseXMPDate("2024-02-29T10:20:30"))
        XCTAssertNotNil(SourceMetadataReader.parseXMPDate("2024-02-29T10:20:30+09:00"))
        XCTAssertNotNil(SourceMetadataReader.parseXMPDate("2024-02-29T01:20:30.125Z"))
    }

    func testContentDateParserPreservesWallClockWithoutGuessingTimezone() throws {
        guard case let .valid(exif, exifProblem) = SourceMetadataReader.parseEXIFContentDate(
            dateTimeRaw: "2024:02:29 10:20:30",
            offsetRaw: nil,
            subsecondRaw: "125"
        ) else {
            return XCTFail("timezone 없는 유효 EXIF wall-clock을 읽지 못했습니다")
        }
        XCTAssertFalse(exifProblem)
        XCTAssertEqual(exif.wallClock.year, 2024)
        XCTAssertEqual(exif.wallClock.month, 2)
        XCTAssertEqual(exif.wallClock.day, 29)
        XCTAssertEqual(exif.wallClock.nanosecond, 125_000_000)
        XCTAssertNil(exif.utcOffsetSeconds)
        XCTAssertNil(exif.instant)

        guard case let .valid(xmp, xmpProblem) = SourceMetadataReader.parseXMPContentDate(
            "2024-02-29T10:20:30.125"
        ) else {
            return XCTFail("timezone 없는 유효 XMP wall-clock을 읽지 못했습니다")
        }
        XCTAssertFalse(xmpProblem)
        XCTAssertEqual(xmp.wallClock, exif.wallClock)
        XCTAssertNil(xmp.instant)

        let decoded = try JSONDecoder().decode(
            SourceContentDateValue.self,
            from: JSONEncoder().encode(xmp)
        )
        XCTAssertEqual(decoded, xmp)
    }

    func testContentDateParserSeparatesWallClockFromInstantAndReportsBadSupplements() throws {
        func parsed(_ offset: String) throws -> SourceContentDateValue {
            guard case let .valid(value, false) = SourceMetadataReader.parseEXIFContentDate(
                dateTimeRaw: "2024:01:01 00:30:00",
                offsetRaw: offset,
                subsecondRaw: nil
            ) else {
                throw CocoaError(.coderInvalidValue)
            }
            return value
        }

        let positive = try parsed("+14:00")
        let negative = try parsed("-14:00")
        XCTAssertEqual(positive.wallClock, negative.wallClock)
        XCTAssertNotEqual(positive.instant, negative.instant)

        guard case let .valid(invalidOffset, hadProblem) =
                SourceMetadataReader.parseEXIFContentDate(
                    dateTimeRaw: "2024:01:01 00:30:00",
                    offsetRaw: "+14:30",
                    subsecondRaw: "invalid"
                ) else {
            return XCTFail("유효 wall-clock은 잘못된 보조값과 분리되어야 합니다")
        }
        XCTAssertTrue(hadProblem)
        XCTAssertNil(invalidOffset.instant)

        XCTAssertEqual(
            SourceMetadataReader.parseXMPContentDate("2023-02-29T10:20:30Z"),
            .invalid
        )
        guard case let .valid(dateOnly, false) =
                SourceMetadataReader.parseXMPContentDate("2024-02-29") else {
            return XCTFail("유효한 XMP 날짜-only 값을 읽지 못했습니다")
        }
        XCTAssertNil(dateOnly.wallClock.hour)
        XCTAssertNil(dateOnly.instant)
    }

    func testXMPReducedPrecisionDatesAreValidWithoutInventedComponents() {
        guard case let .valid(yearOnly, false) =
                SourceMetadataReader.parseXMPContentDate("2024") else {
            return XCTFail("XMP year precision을 읽지 못했습니다")
        }
        XCTAssertNil(yearOnly.wallClock.month)
        XCTAssertNil(yearOnly.wallClock.day)
        XCTAssertNil(yearOnly.instant)

        guard case let .valid(monthOnly, false) =
                SourceMetadataReader.parseXMPContentDate("2024-02") else {
            return XCTFail("XMP month precision을 읽지 못했습니다")
        }
        XCTAssertEqual(monthOnly.wallClock.month, 2)
        XCTAssertNil(monthOnly.wallClock.day)

        guard case let .valid(minutePrecision, false) =
                SourceMetadataReader.parseXMPContentDate("2024-02-29T10:20+09:00") else {
            return XCTFail("XMP minute precision을 읽지 못했습니다")
        }
        XCTAssertEqual(minutePrecision.wallClock.minute, 20)
        XCTAssertNil(minutePrecision.wallClock.second)
        XCTAssertNil(minutePrecision.instant)
    }

    func testEXIFUnknownPlaceholdersAreAbsentAndHostileOffsetDecodeFailsWithoutTrap() {
        XCTAssertEqual(
            SourceMetadataReader.parseEXIFContentDate(
                dateTimeRaw: "    :  :     :  :  ",
                offsetRaw: "   :  ",
                subsecondRaw: "   "
            ),
            .absent
        )

        guard case let .valid(placeholderOffset, false) =
                SourceMetadataReader.parseEXIFContentDate(
                    dateTimeRaw: "2024:02:29 10:20:30",
                    offsetRaw: "   :  ",
                    subsecondRaw: nil
                ) else {
            return XCTFail("정확한 EXIF unknown offset placeholder를 읽지 못했습니다")
        }
        XCTAssertNil(placeholderOffset.instant)

        let hostile = Data(#"""
        {
          "wallClock": {
            "year": 2024, "month": 1, "day": 1,
            "hour": 0, "minute": 0, "second": 0, "nanosecond": 0
          },
          "utcOffsetSeconds": -9223372036854775808
        }
        """#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SourceContentDateValue.self, from: hostile))
    }

    func testEXIFOffsetOnlyAcceptsExactSignedHourMinuteContract() {
        for offset in ["Z", "z", " +09:00", "+09:00 ", "\t  :  ", "\u{00A0}\u{00A0} :  ", "  :  ", "   : "] {
            guard case let .valid(value, hadProblem) =
                    SourceMetadataReader.parseEXIFContentDate(
                        dateTimeRaw: "2024:02:29 10:20:30",
                        offsetRaw: offset,
                        subsecondRaw: nil
                    ) else {
                return XCTFail("잘못된 보조 offset은 wall-clock 자체를 무효화하면 안 됩니다: \(offset.debugDescription)")
            }
            XCTAssertTrue(hadProblem, offset.debugDescription)
            XCTAssertNil(value.utcOffsetSeconds, offset.debugDescription)
            XCTAssertNil(value.instant, offset.debugDescription)
        }

        for offset in ["+00:00", "-00:00", "+09:30", "-14:00"] {
            guard case let .valid(value, false) =
                    SourceMetadataReader.parseEXIFContentDate(
                        dateTimeRaw: "2024:02:29 10:20:30",
                        offsetRaw: offset,
                        subsecondRaw: nil
                    ) else {
                return XCTFail("유효한 EXIF offset을 거부했습니다: \(offset)")
            }
            XCTAssertNotNil(value.instant, offset)
        }
    }

    func testEXIFDateUnknownPlaceholderMustMatchExactASCIIShape() {
        let malformedPlaceholders = [
            "\t   :  :     :  :  ",
            "\u{00A0}\u{00A0}\u{00A0}\u{00A0}:  :     :  :  ",
            "   :  :     :  :  ",
            "    -  -     :  :  ",
            " 2024:02:29 10:20:30",
            "2024:02:29 10:20:30 ",
        ]
        for raw in malformedPlaceholders {
            XCTAssertEqual(
                SourceMetadataReader.parseEXIFContentDate(
                    dateTimeRaw: raw,
                    offsetRaw: "+09:00",
                    subsecondRaw: nil
                ),
                .invalid,
                raw.debugDescription
            )
        }
    }

    func testSidecarKeepsCreateDateAndDateCreatedSeparateAndValidatesDecimalRatings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-source-metadata-xmp-values-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cases: [(raw: String, expected: Double?, discarded: Bool)] = [
            ("-1", -1, false),
            ("4.5", 4.5, false),
            ("99", nil, true),
            ("1e309", nil, true),
        ]
        for (index, ratingCase) in cases.enumerated() {
            let sourceURL = directory.appendingPathComponent("negative-\(index).tiff")
            try writeTIFF(to: sourceURL, properties: [:])
            try Data(compactSidecarXMP(
                createDate: "2024-02-29T10:20:30.125+09:00",
                dateCreated: "1999-12-31T23:59:59-14:00",
                rating: ratingCase.raw,
                includesGPS: true
            ).utf8).write(
                to: sourceURL.deletingPathExtension().appendingPathExtension("xmp")
            )

            let snapshot = SourceMetadataReader.read(from: sourceURL)

            XCTAssertEqual(snapshot.sidecarXMPState, .loaded, "rating=\(ratingCase.raw)")
            XCTAssertEqual(
                snapshot.sidecarXMP?.createDateRaw,
                "2024-02-29T10:20:30.125+09:00"
            )
            XCTAssertEqual(
                snapshot.sidecarXMP?.dateCreatedRaw,
                "1999-12-31T23:59:59-14:00"
            )
            XCTAssertNotEqual(
                snapshot.sidecarXMP?.createDate,
                snapshot.sidecarXMP?.dateCreated
            )
            XCTAssertEqual(snapshot.sidecarXMP?.rating, ratingCase.expected)
            XCTAssertEqual(snapshot.discardedInvalidValues, ratingCase.discarded)
            XCTAssertTrue(snapshot.containsStandardGPSMetadata)

            let encoded = try JSONEncoder().encode(snapshot)
            let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
            XCTAssertFalse(json.localizedCaseInsensitiveContains("gpslatitude"))
            XCTAssertFalse(json.localizedCaseInsensitiveContains("gpslongitude"))
            XCTAssertFalse(json.contains("37,30.000N"))
            XCTAssertFalse(json.contains("127,0.000E"))
        }
    }

    func testSidecarDiscoveryAcceptsMixedCaseAndDeduplicatesOnePhysicalFileWhenSupported() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-source-metadata-xmp-case-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Negative.TIFF")
        try writeTIFF(to: sourceURL, properties: [:])
        let sidecarURL = directory.appendingPathComponent("negative.xMp")
        try Data(compactSidecarXMP(rating: "4.5").utf8).write(to: sidecarURL)

        // 대소문자 구분 파일시스템이면 같은 inode의 두 번째 표기를 만든다. 기본 APFS처럼
        // 불가능한 환경에서는 기존 한 파일만으로 mixed-case 탐색 경로를 검증한다.
        let aliasURL = directory.appendingPathComponent("NEGATIVE.XMP")
        try? FileManager.default.linkItem(at: sidecarURL, to: aliasURL)

        let snapshot = SourceMetadataReader.read(from: sourceURL)

        XCTAssertEqual(snapshot.sidecarXMPState, .loaded)
        XCTAssertEqual(snapshot.sidecarXMP?.rating, 4.5)
    }

    func testTIFFResolutionUnitConvertsInchesAndCentimetersWithoutGuessingUnknownUnits() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-source-metadata-tiff-unit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let inchURL = directory.appendingPathComponent("inch.tiff")
        let centimeterURL = directory.appendingPathComponent("centimeter.tiff")
        let unknownURL = directory.appendingPathComponent("unknown.tiff")
        try writeResolutionTIFF(to: inchURL, resolution: 300, unit: 2)
        try writeResolutionTIFF(to: centimeterURL, resolution: 100, unit: 3)
        try writeResolutionTIFF(to: unknownURL, resolution: 123, unit: 1)

        let inch = SourceMetadataReader.read(from: inchURL)
        let centimeter = SourceMetadataReader.read(from: centimeterURL)
        let unknown = SourceMetadataReader.read(from: unknownURL)

        XCTAssertEqual(try XCTUnwrap(inch.dpiWidth), 300, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(inch.dpiHeight), 300, accuracy: 0.000_001)
        XCTAssertEqual(inch.resolutionDPI, 300)
        XCTAssertEqual(try XCTUnwrap(centimeter.dpiWidth), 254, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(centimeter.dpiHeight), 254, accuracy: 0.000_001)
        XCTAssertEqual(centimeter.resolutionDPI, 254)
        XCTAssertNil(unknown.dpiWidth)
        XCTAssertNil(unknown.dpiHeight)
        XCTAssertNil(unknown.resolutionDPI)
    }

    func testOversizedSidecarIsReportedAndNotParsed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-source-metadata-large-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("negative.tiff")
        let sidecarURL = sourceURL.deletingPathExtension().appendingPathExtension("xmp")
        let oversized = Data(
            repeating: 0x20,
            count: Int(SourceMetadataReader.maximumSidecarBytes + 1)
        )
        try oversized.write(to: sidecarURL)

        let snapshot = SourceMetadataReader.read(from: sourceURL)

        XCTAssertEqual(snapshot.sidecarXMPState, .tooLarge)
        XCTAssertNil(snapshot.sidecarXMP)
    }

    func testUnreadableImageOmitsZeroImageCountAndRecordsDiscardedInvalidValue() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-source-metadata-invalid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("invalid.tiff")
        try Data("not an image".utf8).write(to: sourceURL)

        let snapshot = SourceMetadataReader.read(from: sourceURL)

        XCTAssertEqual(snapshot.fileSizeBytes, 12)
        XCTAssertNil(snapshot.imageCount)
        XCTAssertTrue(snapshot.discardedInvalidValues)
    }

    func testSnapshotCodableRoundTripPreservesMetadataOrigins() throws {
        let snapshot = SourceMetadataSnapshot(
            fileTypeIdentifier: UTType.tiff.identifier,
            fileSizeBytes: 1_024,
            pixelWidth: 4_000,
            pixelHeight: 6_000,
            resolutionDPI: 2_400,
            bitsPerColorSample: 16,
            orientation: 1,
            colorModel: "RGB",
            colorProfileName: "Adobe RGB (1998)",
            exif: SourceEXIFMetadata(
                dateTimeOriginalRaw: "2024:02:29 10:20:30",
                offsetTimeOriginalRaw: "+09:00",
                subsecondTimeOriginalRaw: nil,
                cameraMake: "Nikon",
                cameraModel: "F3",
                lensModel: nil,
                exposureTimeSeconds: nil,
                fNumber: nil,
                isoSpeedRatings: [100],
                focalLengthMM: nil
            ),
            iptc: nil,
            imageMetadataXMPView: nil,
            sidecarXMP: SourceXMPMetadata(
                createDateRaw: nil,
                dateCreatedRaw: nil,
                title: SourceLocalizedText(valuesByLanguage: ["x-default": "Title"]),
                description: nil,
                creators: [],
                rights: nil,
                usageTerms: nil,
                headline: nil,
                credit: nil,
                jobIdentifier: nil,
                keywords: ["film"],
                city: nil,
                stateProvince: nil,
                country: nil,
                sublocation: nil,
                rating: 5,
                label: "Green"
            ),
            sidecarXMPState: .loaded,
            containsStandardGPSMetadata: true,
            discardedOversizedValues: false,
            discardedInvalidValues: false
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(
            SourceMetadataSnapshot.self,
            from: encoder.encode(snapshot)
        )

        XCTAssertEqual(decoded, snapshot)
    }

    private func writeTIFF(
        to url: URL,
        properties: [CFString: Any]
    ) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 2 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.tiff.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func writeResolutionTIFF(
        to url: URL,
        resolution: Double,
        unit: UInt16
    ) throws {
        try writeTIFF(
            to: url,
            properties: [
                kCGImagePropertyDPIWidth: resolution,
                kCGImagePropertyDPIHeight: resolution,
            ]
        )
        try patchTIFFResolutionUnit(at: url, unit: unit)
    }

    private func patchTIFFResolutionUnit(at url: URL, unit: UInt16) throws {
        var bytes = [UInt8](try Data(contentsOf: url))
        guard bytes.count >= 8 else {
            throw XCTSkip("ImageIO가 생성한 TIFF 헤더가 너무 짧습니다.")
        }
        let isLittleEndian: Bool
        if bytes[0] == 0x49, bytes[1] == 0x49 {
            isLittleEndian = true
        } else if bytes[0] == 0x4D, bytes[1] == 0x4D {
            isLittleEndian = false
        } else {
            throw XCTSkip("ImageIO가 생성한 파일의 TIFF byte order를 확인할 수 없습니다.")
        }
        func uint16(at offset: Int) -> UInt16 {
            if isLittleEndian {
                return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
            }
            return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
        }
        func uint32(at offset: Int) -> UInt32 {
            if isLittleEndian {
                return UInt32(bytes[offset])
                    | (UInt32(bytes[offset + 1]) << 8)
                    | (UInt32(bytes[offset + 2]) << 16)
                    | (UInt32(bytes[offset + 3]) << 24)
            }
            return (UInt32(bytes[offset]) << 24)
                | (UInt32(bytes[offset + 1]) << 16)
                | (UInt32(bytes[offset + 2]) << 8)
                | UInt32(bytes[offset + 3])
        }
        let ifdOffset = Int(uint32(at: 4))
        guard ifdOffset >= 0, ifdOffset + 2 <= bytes.count else {
            throw XCTSkip("ImageIO TIFF의 첫 IFD 범위를 확인할 수 없습니다.")
        }
        let entryCount = Int(uint16(at: ifdOffset))
        for index in 0..<entryCount {
            let entryOffset = ifdOffset + 2 + (index * 12)
            guard entryOffset + 12 <= bytes.count else { break }
            guard uint16(at: entryOffset) == 296 else { continue }
            if isLittleEndian {
                bytes[entryOffset + 8] = UInt8(unit & 0x00FF)
                bytes[entryOffset + 9] = UInt8(unit >> 8)
            } else {
                bytes[entryOffset + 8] = UInt8(unit >> 8)
                bytes[entryOffset + 9] = UInt8(unit & 0x00FF)
            }
            try Data(bytes).write(to: url, options: .atomic)
            return
        }
        throw XCTSkip("ImageIO TIFF에 ResolutionUnit 태그가 없습니다.")
    }

    private func compactSidecarXMP(
        createDate: String? = nil,
        dateCreated: String? = nil,
        rating: String? = nil,
        includesGPS: Bool = false
    ) -> String {
        let createDateAttribute = createDate.map { "xmp:CreateDate=\"\($0)\"" } ?? ""
        let dateCreatedAttribute = dateCreated.map { "photoshop:DateCreated=\"\($0)\"" } ?? ""
        let ratingAttribute = rating.map { "xmp:Rating=\"\($0)\"" } ?? ""
        let gpsAttributes = includesGPS
            ? "exif:GPSLatitude=\"37,30.000N\" exif:GPSLongitude=\"127,0.000E\""
            : ""
        return """
        <?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:xmp="http://ns.adobe.com/xap/1.0/"
              xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"
              xmlns:exif="http://ns.adobe.com/exif/1.0/"
              \(createDateAttribute)
              \(dateCreatedAttribute)
              \(ratingAttribute)
              \(gpsAttributes) />
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }

    private var sidecarXMP: String {
        """
        <?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:xmp="http://ns.adobe.com/xap/1.0/"
              xmlns:xmpRights="http://ns.adobe.com/xap/1.0/rights/"
              xmlns:dc="http://purl.org/dc/elements/1.1/"
              xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"
              xmlns:Iptc4xmpCore="http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/"
              xmp:CreateDate="2024-02-29T10:20:30+09:00"
              xmp:Rating="4"
              xmp:Label="Red"
              photoshop:Headline="Sidecar headline"
              photoshop:Credit="Agency"
              photoshop:TransmissionReference="JOB-42"
              photoshop:City="Seoul"
              photoshop:State="Seoul"
              photoshop:Country="Korea"
              Iptc4xmpCore:Location="Jongno">
              <dc:title><rdf:Alt><rdf:li xml:lang="x-default">Sidecar title</rdf:li><rdf:li xml:lang="ko">사이드카 제목</rdf:li></rdf:Alt></dc:title>
              <dc:description><rdf:Alt><rdf:li xml:lang="x-default">Sidecar description</rdf:li></rdf:Alt></dc:description>
              <dc:creator><rdf:Seq><rdf:li>Alice</rdf:li><rdf:li>Bob</rdf:li></rdf:Seq></dc:creator>
              <dc:subject><rdf:Bag><rdf:li>film</rdf:li><rdf:li>Seoul</rdf:li></rdf:Bag></dc:subject>
              <dc:rights><rdf:Alt><rdf:li xml:lang="x-default">Copyright Alice</rdf:li></rdf:Alt></dc:rights>
              <xmpRights:UsageTerms><rdf:Alt><rdf:li xml:lang="x-default">Editorial use</rdf:li></rdf:Alt></xmpRights:UsageTerms>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }
}
