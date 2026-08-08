import XCTest
@testable import negaflowApp

final class SourceMetadataInspectorModelTests: XCTestCase {
    func testEmbeddedAndSidecarValuesKeepDistinctOrigins() {
        let model = SourceMetadataInspectorModel(snapshot(sidecarState: .loaded))

        XCTAssertEqual(model.camera.value, "Nikon, F3, NIKKOR 50mm")
        XCTAssertEqual(model.camera.origin, .embedded)
        XCTAssertEqual(model.date.value, "2024-02-29T10:20:30+09:00")
        XCTAssertEqual(model.date.origin, .sidecar)
        XCTAssertEqual(model.title.value, "Sidecar title")
        XCTAssertEqual(model.title.origin, .mixed)
        XCTAssertEqual(model.keywords.value, "film, negative, sidecar, catalog")
        XCTAssertEqual(model.keywords.origin, .mixed)
        XCTAssertEqual(model.sidecarState, .loaded)
        XCTAssertEqual(model.hasReadProblem, false)
    }

    func testMissingSnapshotIsUnknownRatherThanEmptyMetadata() {
        let model = SourceMetadataInspectorModel(nil)

        XCTAssertNil(model.sidecarState)
        XCTAssertNil(model.hasReadProblem)
        XCTAssertEqual(model.camera.origin, .unknown)
        XCTAssertEqual(model.date.origin, .unknown)
        XCTAssertEqual(model.title.origin, .unknown)
        XCTAssertEqual(model.keywords.origin, .unknown)
    }

    func testCorruptSidecarIsReportedWithoutUsingItsValues() {
        var snapshot = snapshot(sidecarState: .invalid)
        snapshot.discardedInvalidValues = true
        let model = SourceMetadataInspectorModel(snapshot)

        XCTAssertEqual(model.sidecarState, .invalid)
        XCTAssertEqual(model.hasReadProblem, true)
        XCTAssertEqual(model.date.value, "2024:02:29 10:20:30 +09:00")
        XCTAssertEqual(model.date.origin, .embedded)
        XCTAssertEqual(model.title.value, "Embedded title")
        XCTAssertEqual(model.title.origin, .embedded)
        XCTAssertEqual(model.keywords.value, "film, negative")
        XCTAssertEqual(model.keywords.origin, .embedded)
    }

    func testImportedHeaderFormatsTheRequestedExposureMetadataInOrder() {
        let exif = SourceEXIFMetadata(
            dateTimeOriginalRaw: nil,
            offsetTimeOriginalRaw: nil,
            subsecondTimeOriginalRaw: nil,
            cameraMake: nil,
            cameraModel: nil,
            lensModel: nil,
            software: nil,
            exposureTimeSeconds: 1.0 / 125.0,
            fNumber: 2.8,
            isoSpeedRatings: [400],
            focalLengthMM: 50
        )

        XCTAssertEqual(
            DevelopInspectorHeaderSummary.importedMetadata(exif),
            "ISO 400 · 1/125 s · f/2.8 · 50 mm"
        )
    }

    private func snapshot(sidecarState: SourceXMPReadState) -> SourceMetadataSnapshot {
        SourceMetadataSnapshot(
            exif: SourceEXIFMetadata(
                dateTimeOriginalRaw: "2024:02:29 10:20:30",
                offsetTimeOriginalRaw: "+09:00",
                subsecondTimeOriginalRaw: nil,
                cameraMake: "Nikon",
                cameraModel: "F3",
                lensModel: "NIKKOR 50mm",
                software: nil,
                exposureTimeSeconds: nil,
                fNumber: nil,
                isoSpeedRatings: [],
                focalLengthMM: nil
            ),
            iptc: SourceIPTCMetadata(
                title: "Embedded title",
                headline: nil,
                caption: nil,
                creators: [],
                credit: nil,
                copyrightNotice: nil,
                rightsUsageTerms: nil,
                source: nil,
                jobIdentifier: nil,
                keywords: ["film", "negative"],
                city: nil,
                stateProvince: nil,
                country: nil,
                countryCode: nil,
                sublocation: nil
            ),
            sidecarXMP: SourceXMPMetadata(
                createDateRaw: nil,
                dateCreatedRaw: "2024-02-29T10:20:30+09:00",
                title: SourceLocalizedText(valuesByLanguage: ["x-default": "Sidecar title"]),
                description: nil,
                creators: [],
                rights: nil,
                usageTerms: nil,
                headline: nil,
                credit: nil,
                jobIdentifier: nil,
                keywords: ["sidecar", "catalog"],
                city: nil,
                stateProvince: nil,
                country: nil,
                sublocation: nil,
                rating: nil,
                label: nil
            ),
            sidecarXMPState: sidecarState
        )
    }
}
