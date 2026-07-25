import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class AppMetadataOverlaySearchTests: XCTestCase {
    func testOverlayFieldsAreSearchableWithoutSourceMetadataSnapshot() throws {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/overlay-search.tif"),
            filmType: .colorNegative,
            appMetadataOverlay: AppMetadataOverlay(
                title: "Archive title",
                caption: "Contact sheet caption",
                keywords: ["film", "Seoul"],
                copyright: "Copyright 2026",
                sourceMetadataSHA256: nil,
                revision: 1
            )
        )
        let context = LibraryQueryContext.make(
            generation: 1,
            frames: [frame],
            folders: [],
            rolls: [],
            activeRollID: nil,
            scanSessions: [],
            scannerProfiles: [],
            availabilityByFrameID: [:]
        )
        let facts = try XCTUnwrap(context.factsByFrameID[frame.id])

        XCTAssertTrue(facts.textValues[.titleDescription, default: []].contains("archive title"))
        XCTAssertTrue(facts.textValues[.titleDescription, default: []].contains("contact sheet caption"))
        XCTAssertTrue(facts.textValues[.keywords, default: []].contains("seoul"))
        XCTAssertTrue(facts.textValues[.anySearchable, default: []].contains("copyright 2026"))
        XCTAssertEqual(facts.metadataPresenceByField[.title], .present)
        XCTAssertEqual(facts.metadataPresenceByField[.description], .present)
        XCTAssertEqual(facts.metadataPresenceByField[.keywords], .present)
    }
}
