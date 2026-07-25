import XCTest
import Chromabase
import ScannerKit
@testable import negaflowApp

@MainActor
final class LibraryQueryTests: XCTestCase {
    func testTextRulesUseDeterministicUnicodeNormalization() {
        let frame = fact(
            textValues: [
                .fileName: ["Ｃａｆé  ROLL\t01.TIF"],
                .keywords: ["flower"],
            ]
        )
        let context = LibraryQueryContext(generation: 1, facts: [frame])

        XCTAssertTrue(matches(
            .text(.init(field: .fileName, rule: .containsAll, value: "cafe roll")),
            frameID: frame.id,
            context: context
        ))
        XCTAssertTrue(matches(
            .text(.init(field: .fileName, rule: .startsWith, value: "cafe")),
            frameID: frame.id,
            context: context
        ))
        XCTAssertTrue(matches(
            .text(.init(field: .fileName, rule: .endsWith, value: "01.tif")),
            frameID: frame.id,
            context: context
        ))
        XCTAssertFalse(matches(
            .text(.init(field: .keywords, rule: .containsAllWords, value: "flow")),
            frameID: frame.id,
            context: context
        ))
        XCTAssertTrue(matches(
            .text(.init(field: .keywords, rule: .containsAllWords, value: "flower")),
            frameID: frame.id,
            context: context
        ))
    }

    func testContainsAllTermsCanMatchAcrossDifferentFields() {
        let frame = fact(textValues: [
            .displayName: ["John"],
            .keywords: ["Susan"],
            .anySearchable: ["John", "Susan"],
        ])
        let context = LibraryQueryContext(generation: 1, facts: [frame])

        XCTAssertTrue(matches(
            .text(.init(field: .anySearchable, rule: .containsAll, value: "john susan")),
            frameID: frame.id,
            context: context
        ))
        XCTAssertFalse(matches(
            .text(.init(field: .displayName, rule: .containsAll, value: "john susan")),
            frameID: frame.id,
            context: context
        ))
    }

    func testContainsSearchIgnoresWhitespaceInsidePhotoNames() {
        let spaced = fact(textValues: [.displayName: ["사진 2"]])
        let compact = fact(textValues: [.displayName: ["사진2"]])
        let context = LibraryQueryContext(generation: 1, facts: [spaced, compact])

        XCTAssertTrue(matches(
            .text(.init(field: .anySearchable, rule: .containsAll, value: "사진2")),
            frameID: spaced.id,
            context: context
        ))
        XCTAssertTrue(matches(
            .text(.init(field: .displayName, rule: .containsAll, value: "사진2")),
            frameID: spaced.id,
            context: context
        ))
        XCTAssertTrue(matches(
            .text(.init(field: .anySearchable, rule: .containsAll, value: "사진 2")),
            frameID: compact.id,
            context: context
        ))
    }

    func testAnySearchableSubstringIndexDoesNotMatchAcrossValueBoundaries() {
        let facts = fact(textValues: [
            .displayName: ["ab"],
            .keywords: ["cd"],
        ])
        let context = LibraryQueryContext(generation: 1, facts: [facts])

        XCTAssertFalse(
            LibraryQuery(conditions: [
                .text(.init(field: .anySearchable, rule: .containsAll, value: "bc")),
            ]).matches(frameID: facts.id, in: context)
        )
        XCTAssertTrue(
            LibraryQuery(conditions: [
                .text(.init(field: .anySearchable, rule: .containsAll, value: "ab cd")),
            ]).matches(frameID: facts.id, in: context)
        )
    }

    func testNegativeTextDoesNotTreatMissingFieldAsContainingQuery() {
        let frame = fact()
        let context = LibraryQueryContext(generation: 1, facts: [frame])

        XCTAssertTrue(matches(
            .text(.init(field: .keywords, rule: .doesNotContainAny, value: "dust")),
            frameID: frame.id,
            context: context
        ))
        XCTAssertTrue(matches(
            .text(.init(field: .keywords, rule: .isEmpty, value: "")),
            frameID: frame.id,
            context: context
        ))
        XCTAssertFalse(matches(
            .text(.init(field: .keywords, rule: .isNotEmpty, value: "")),
            frameID: frame.id,
            context: context
        ))
    }

    func testWordRuleWithOnlyPunctuationFailsClosed() {
        let frame = fact(textValues: [.keywords: ["flower"]])
        let context = LibraryQueryContext(generation: 1, facts: [frame])
        let query = LibraryQuery(matchMode: .any, conditions: [
            .text(.init(field: .keywords, rule: .containsAllWords, value: "!!!"))
        ])

        XCTAssertFalse(query.isValid)
        XCTAssertFalse(query.matches(frameID: frame.id, in: context))
    }

    func testContainsAllTreatsPunctuationAsTermBoundaries() {
        let frame = fact(textValues: [.anySearchable: ["John", "Susan"]])
        let context = LibraryQueryContext(generation: 1, facts: [frame])

        XCTAssertTrue(matches(
            .text(.init(field: .anySearchable, rule: .containsAll, value: "john,susan")),
            frameID: frame.id,
            context: context
        ))
    }

    func testTextIsAnyOfKeepsSameFieldORInsideAllQuery() {
        let nikon = fact(textValues: [
            .camera: ["Nikon F3"],
            .lens: ["Nikkor 50mm"],
        ])
        let canon = fact(textValues: [
            .camera: ["Canon F-1"],
            .lens: ["FD 50mm"],
        ])
        let wrongLens = fact(textValues: [
            .camera: ["Nikon F3"],
            .lens: ["Nikkor 105mm"],
        ])
        let context = LibraryQueryContext(generation: 1, facts: [nikon, canon, wrongLens])
        let query = LibraryQuery(conditions: [
            .textIsAnyOf(field: .camera, values: ["NIKON F3", "Canon F-1"]),
            .text(.init(field: .lens, rule: .containsAll, value: "50mm")),
        ])
        let projection = LibraryBrowserProjection.make(
            sourceFrameIDs: [nikon.id, canon.id, wrongLens.id],
            query: query,
            context: context,
            sort: .init(key: .inputOrder, ascending: true)
        )

        XCTAssertEqual(projection.orderedFrameIDs, [nikon.id, canon.id])
    }

    func testNegativeTextFailsClosedWhenFieldKnowledgeIsIncomplete() {
        let frame = fact(unknownTextFields: [.scannerDevice])
        let context = LibraryQueryContext(generation: 1, facts: [frame])

        XCTAssertFalse(matches(
            .text(.init(field: .scannerDevice, rule: .isEmpty, value: "")),
            frameID: frame.id,
            context: context
        ))
        XCTAssertFalse(matches(
            .text(.init(field: .scannerDevice, rule: .doesNotContainAny, value: "Epson")),
            frameID: frame.id,
            context: context
        ))
    }

    func testAllAndAnyConditionCombinationIsExplicit() {
        let picked = fact(rating: 4, pickState: .picked)
        let rejected = fact(rating: 1, pickState: .rejected)
        let context = LibraryQueryContext(generation: 1, facts: [picked, rejected])
        let conditions: [LibraryQueryCondition] = [
            .rating(comparison: .greaterThanOrEqual, value: 3),
            .pickState(isAnyOf: [.rejected]),
        ]

        let all = LibraryBrowserProjection.make(
            sourceFrameIDs: [picked.id, rejected.id],
            query: LibraryQuery(matchMode: .all, conditions: conditions),
            context: context,
            sort: .init(key: .inputOrder, ascending: true)
        )
        let any = LibraryBrowserProjection.make(
            sourceFrameIDs: [picked.id, rejected.id],
            query: LibraryQuery(matchMode: .any, conditions: conditions),
            context: context,
            sort: .init(key: .inputOrder, ascending: true)
        )

        XCTAssertTrue(all.orderedFrameIDs.isEmpty)
        XCTAssertEqual(any.orderedFrameIDs, [picked.id, rejected.id])
    }

    func testStateConditionsKeepUnknownSeparateFromNegativeFacts() {
        let unknown = fact(
            availability: .unknown,
            exportState: .unknown,
            userEditState: .unknown,
            defectReviewState: .unknown,
            deviceCalibrationState: .unknown
        )
        let known = fact(
            availability: .offline,
            exportState: .never,
            userEditState: .edited,
            defectReviewState: .needsReview,
            deviceCalibrationState: .uncalibrated
        )
        let context = LibraryQueryContext(generation: 1, facts: [unknown, known])
        let query = LibraryQuery(conditions: [
            .sourceAvailability(isAnyOf: [.offline]),
            .exportState(isAnyOf: [.never]),
            .userEditState(isAnyOf: [.edited]),
            .defectReviewState(isAnyOf: [.needsReview]),
            .deviceCalibrationState(isAnyOf: [.uncalibrated]),
        ])

        let projection = LibraryBrowserProjection.make(
            sourceFrameIDs: [unknown.id, known.id],
            query: query,
            context: context,
            sort: .init(key: .inputOrder, ascending: true)
        )

        XCTAssertEqual(projection.orderedFrameIDs, [known.id])
    }

    func testAmbiguousVirtualCopyStateMatchesNeitherBoolean() {
        let frame = fact(isVirtualCopy: nil)
        let context = LibraryQueryContext(generation: 1, facts: [frame])

        XCTAssertFalse(matches(.virtualCopy(true), frameID: frame.id, context: context))
        XCTAssertFalse(matches(.virtualCopy(false), frameID: frame.id, context: context))
    }

    func testRatingPickRollAndBooleanConditionsUseTypedFacts() {
        let rollID = UUID()
        let frame = fact(
            rollID: rollID,
            rating: 4,
            pickState: .picked,
            isVirtualCopy: true,
            hasInfraredCapture: true,
            hasDefectRecipe: true,
            hasCreativeCalibrationAdjustments: true
        )
        let context = LibraryQueryContext(
            generation: 1,
            facts: [frame],
            activeRollID: rollID
        )
        let query = LibraryQuery(conditions: [
            .rating(comparison: .greaterThanOrEqual, value: 4),
            .pickState(isAnyOf: [.picked, .rejected]),
            .roll(isAnyOf: [rollID]),
            .currentRoll,
            .virtualCopy(true),
            .infraredCapture(true),
            .defectRecipe(true),
            .creativeCalibrationAdjusted(true),
        ])

        XCTAssertTrue(query.matches(frameID: frame.id, in: context))
    }

    func testDateRangeIsStartInclusiveAndEndExclusive() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let atStart = fact(contentDate: start)
        let atEnd = fact(contentDate: end)
        let context = LibraryQueryContext(generation: 1, facts: [atStart, atEnd])
        let query = LibraryQuery(conditions: [
            .date(.init(field: .contentInstant, predicate: .range(startInclusive: start, endExclusive: end)))
        ])

        XCTAssertTrue(query.matches(frameID: atStart.id, in: context))
        XCTAssertFalse(query.matches(frameID: atEnd.id, in: context))
    }

    func testCalendarDatePreservesOriginalWallClockWithoutTimezoneGuessing() {
        var exifSnapshot = SourceMetadataSnapshot()
        exifSnapshot.exif = exif(date: "2024:01:02 23:59:58", offset: nil)
        var xmpSnapshot = SourceMetadataSnapshot()
        xmpSnapshot.imageMetadataXMPView = xmp(
            dateCreated: "2024-01-01T00:30:00+14:00"
        )
        let exifFrame = makeFrame(index: 1, metadata: exifSnapshot)
        let xmpFrame = makeFrame(index: 2, metadata: xmpSnapshot)
        let context = makeContext(frames: [exifFrame, xmpFrame])
        let januaryFirst = LibraryCalendarDate(year: 2024, month: 1, day: 1)!
        let januarySecond = LibraryCalendarDate(year: 2024, month: 1, day: 2)!
        let januaryThird = LibraryCalendarDate(year: 2024, month: 1, day: 3)!

        XCTAssertNil(context.factsByFrameID[exifFrame.id]?.contentDate)
        XCTAssertEqual(context.factsByFrameID[exifFrame.id]?.contentCalendarDate, januarySecond)
        XCTAssertEqual(context.factsByFrameID[xmpFrame.id]?.contentCalendarDate, januaryFirst)
        XCTAssertTrue(LibraryQuery(conditions: [
            .calendarDate(.init(
                field: .contentDate,
                predicate: .range(startInclusive: januarySecond, endExclusive: januaryThird)
            ))
        ]).matches(frameID: exifFrame.id, in: context))
    }

    func testReducedPrecisionXMPDateMatchesOnlyRangesContainingItsWholeInterval() {
        var yearSnapshot = SourceMetadataSnapshot()
        yearSnapshot.sidecarXMPState = .loaded
        yearSnapshot.sidecarXMP = xmp(dateCreated: "2024")
        yearSnapshot.exif = exif(date: "1999:06:15 12:00:00", offset: "+00:00")

        var monthSnapshot = SourceMetadataSnapshot()
        monthSnapshot.sidecarXMPState = .loaded
        monthSnapshot.sidecarXMP = xmp(dateCreated: "2024-02")
        monthSnapshot.exif = exif(date: "1999:06:15 12:00:00", offset: "+00:00")

        let yearFrame = makeFrame(index: 1, metadata: yearSnapshot)
        let monthFrame = makeFrame(index: 2, metadata: monthSnapshot)
        let context = makeContext(frames: [yearFrame, monthFrame])
        let date = { (year: Int, month: Int, day: Int) in
            LibraryCalendarDate(year: year, month: month, day: day)!
        }
        let matchesRange = { (frameID: UUID, start: LibraryCalendarDate, end: LibraryCalendarDate) in
            LibraryQuery(conditions: [
                .calendarDate(.init(
                    field: .contentDate,
                    predicate: .range(startInclusive: start, endExclusive: end)
                ))
            ]).matches(frameID: frameID, in: context)
        }

        XCTAssertNil(context.factsByFrameID[yearFrame.id]?.contentCalendarDate)
        XCTAssertNil(context.factsByFrameID[monthFrame.id]?.contentCalendarDate)
        XCTAssertTrue(matchesRange(yearFrame.id, date(2024, 1, 1), date(2025, 1, 1)))
        XCTAssertFalse(matchesRange(yearFrame.id, date(2024, 1, 2), date(2025, 1, 1)))
        XCTAssertFalse(matchesRange(yearFrame.id, date(2024, 1, 1), date(2024, 12, 31)))
        XCTAssertFalse(matchesRange(yearFrame.id, date(1999, 1, 1), date(2000, 1, 1)))

        XCTAssertTrue(matchesRange(monthFrame.id, date(2024, 2, 1), date(2024, 3, 1)))
        XCTAssertTrue(matchesRange(monthFrame.id, date(2024, 1, 1), date(2025, 1, 1)))
        XCTAssertFalse(matchesRange(monthFrame.id, date(2024, 2, 2), date(2024, 3, 1)))
        XCTAssertFalse(matchesRange(monthFrame.id, date(2024, 2, 1), date(2024, 2, 29)))
        XCTAssertFalse(matchesRange(monthFrame.id, date(2024, 2, 14), date(2024, 2, 15)))
        XCTAssertFalse(matchesRange(monthFrame.id, date(1999, 6, 1), date(1999, 7, 1)))
    }

    func testMetadataPresenceAndReadProblemAreSeparate() {
        let frame = fact(
            metadataPresentFields: [.snapshot, .camera],
            metadataReadProblem: true
        )
        let context = LibraryQueryContext(generation: 1, facts: [frame])

        XCTAssertTrue(matches(
            .metadata(field: .camera, presence: .present),
            frameID: frame.id,
            context: context
        ))
        XCTAssertTrue(matches(
            .metadata(field: .lens, presence: .missing),
            frameID: frame.id,
            context: context
        ))
        XCTAssertTrue(matches(
            .metadataReadProblem(true),
            frameID: frame.id,
            context: context
        ))
    }

    func testMissingMetadataSnapshotDoesNotBecomeKnownMissingOrClean() {
        let frame = makeFrame(index: 1, metadata: nil)
        let context = makeContext(frames: [frame])

        XCTAssertFalse(matches(
            .metadata(field: .camera, presence: .missing),
            frameID: frame.id,
            context: context
        ))
        XCTAssertFalse(matches(
            .metadataReadProblem(false),
            frameID: frame.id,
            context: context
        ))
        XCTAssertTrue(matches(
            .metadata(field: .camera, presence: .unknown),
            frameID: frame.id,
            context: context
        ))
    }

    func testMetadataReadProblemKeepsAbsentFieldsUnknown() {
        var snapshot = SourceMetadataSnapshot()
        snapshot.discardedInvalidValues = true
        let frame = makeFrame(index: 1, metadata: snapshot)
        let context = makeContext(frames: [frame])

        XCTAssertTrue(matches(
            .metadata(field: .camera, presence: .unknown),
            frameID: frame.id,
            context: context
        ))
        XCTAssertFalse(matches(
            .metadata(field: .camera, presence: .missing),
            frameID: frame.id,
            context: context
        ))
    }

    func testEXIFSoftwareIsSearchableButNotCameraMetadata() {
        var snapshot = SourceMetadataSnapshot()
        snapshot.exif = SourceEXIFMetadata(
            dateTimeOriginalRaw: nil,
            offsetTimeOriginalRaw: nil,
            subsecondTimeOriginalRaw: nil,
            cameraMake: nil,
            cameraModel: nil,
            lensModel: nil,
            software: "SilverFast",
            exposureTimeSeconds: nil,
            fNumber: nil,
            isoSpeedRatings: [],
            focalLengthMM: nil
        )
        let frame = makeFrame(index: 1, metadata: snapshot)
        let context = makeContext(frames: [frame])
        let facts = try! XCTUnwrap(context.factsByFrameID[frame.id])

        XCTAssertFalse(facts.textValues[.camera]?.contains("silverfast") == true)
        XCTAssertTrue(facts.textValues[.anySearchable]?.contains("silverfast") == true)
        XCTAssertFalse(matches(
            .metadata(field: .camera, presence: .present),
            frameID: frame.id,
            context: context
        ))
    }

    func testProfileStatesDoNotClassifyNoProfileAsUnvalidated() {
        let noProfile = fact(scannerProfileState: .none)
        let missing = fact(scannerProfileState: .missing)
        let draft = fact(scannerProfileState: .draft)
        let validated = fact(scannerProfileState: .pairedValidated)
        let context = LibraryQueryContext(
            generation: 1,
            facts: [noProfile, missing, draft, validated]
        )
        let query = LibraryQuery(conditions: [
            .scannerProfileState(isAnyOf: [.missing, .draft, .realOnly, .pairedSmoke])
        ])

        let projection = LibraryBrowserProjection.make(
            sourceFrameIDs: [noProfile.id, missing.id, draft.id, validated.id],
            query: query,
            context: context,
            sort: .init(key: .inputOrder, ascending: true)
        )

        XCTAssertEqual(projection.orderedFrameIDs, [missing.id, draft.id])
    }

    func testProjectionDeduplicatesScopeAndUsesStableTieOrder() {
        let first = fact(sortName: "same", rating: 3)
        let second = fact(sortName: "same", rating: 3)
        let outside = fact(sortName: "outside", rating: 5)
        let context = LibraryQueryContext(generation: 7, facts: [first, second, outside])

        let projection = LibraryBrowserProjection.make(
            sourceFrameIDs: [second.id, first.id, second.id],
            query: LibraryQuery(),
            context: context,
            sort: .init(key: .rating, ascending: false)
        )

        XCTAssertEqual(projection.contextGeneration, 7)
        XCTAssertEqual(projection.sourceCount, 2)
        XCTAssertEqual(projection.matchedCount, 2)
        XCTAssertEqual(projection.orderedFrameIDs, [second.id, first.id])
        XCTAssertFalse(projection.orderedFrameIDs.contains(outside.id))
    }

    func testMissingFileSizeSortsLastInBothDirections() {
        let small = fact(fileSizeBytes: 10)
        let large = fact(fileSizeBytes: 20)
        let missing = fact(fileSizeBytes: nil)
        let context = LibraryQueryContext(generation: 1, facts: [small, large, missing])

        let ascending = LibraryBrowserProjection.make(
            sourceFrameIDs: [missing.id, large.id, small.id],
            query: LibraryQuery(),
            context: context,
            sort: .init(key: .fileSize, ascending: true)
        )
        let descending = LibraryBrowserProjection.make(
            sourceFrameIDs: [missing.id, large.id, small.id],
            query: LibraryQuery(),
            context: context,
            sort: .init(key: .fileSize, ascending: false)
        )

        XCTAssertEqual(ascending.orderedFrameIDs, [small.id, large.id, missing.id])
        XCTAssertEqual(descending.orderedFrameIDs, [large.id, small.id, missing.id])
    }

    func testProjectionKeepsKnownFoldersWhenFilteringLeavesThemEmpty() {
        let first = fact(folderPath: "/roll/a", rating: 5)
        let second = fact(folderPath: "/roll/b", rating: 1)
        let context = LibraryQueryContext(
            generation: 1,
            facts: [first, second],
            folderFacts: [
                .init(id: "/roll/a", folderID: UUID(), title: "A"),
                .init(id: "/roll/b", folderID: UUID(), title: "B"),
            ]
        )

        let projection = LibraryBrowserProjection.make(
            sourceFrameIDs: [first.id, second.id],
            query: LibraryQuery(conditions: [
                .rating(comparison: .greaterThanOrEqual, value: 3)
            ]),
            context: context,
            sort: .init(key: .inputOrder, ascending: true)
        )

        XCTAssertEqual(projection.folderSections.map(\.id), ["/roll/a", "/roll/b"])
        XCTAssertEqual(projection.folderSections.first?.orderedFrameIDs, [first.id])
        XCTAssertEqual(projection.folderSections.last?.orderedFrameIDs, [])
    }

    func testInvalidAndFutureQueriesFailClosed() {
        let frame = fact()
        let context = LibraryQueryContext(generation: 1, facts: [frame])
        let invalidRating = LibraryQuery(conditions: [
            .rating(comparison: .equal, value: 6)
        ])
        let future = LibraryQuery(version: 2)

        for query in [invalidRating, future] {
            let projection = LibraryBrowserProjection.make(
                sourceFrameIDs: [frame.id],
                query: query,
                context: context,
                sort: .init(key: .inputOrder, ascending: true)
            )
            XCTAssertFalse(projection.queryWasValid)
            XCTAssertTrue(projection.orderedFrameIDs.isEmpty)
        }
    }

    func testRollAnyOfRejectsMoreThanMaximumRawValues() {
        let rollIDs = (0...LibraryQuery.maximumAnyOfValueCount).map { _ in UUID() }
        let frame = fact(rollID: rollIDs[0])
        let context = LibraryQueryContext(generation: 1, facts: [frame])
        let query = LibraryQuery(conditions: [.roll(isAnyOf: rollIDs)])

        XCTAssertFalse(query.isValid)

        let projection = LibraryBrowserProjection.make(
            sourceFrameIDs: [frame.id],
            query: query,
            context: context,
            sort: .init(key: .inputOrder, ascending: true)
        )
        XCTAssertFalse(projection.queryWasValid)
        XCTAssertTrue(projection.orderedFrameIDs.isEmpty)
    }

    func testEnumAnyOfRejectsMoreThanMaximumRawValuesEvenWhenRepeated() {
        let values = Array(
            repeating: FramePickState.picked,
            count: LibraryQuery.maximumAnyOfValueCount + 1
        )
        let frame = fact(pickState: .picked)
        let context = LibraryQueryContext(generation: 1, facts: [frame])
        let query = LibraryQuery(conditions: [.pickState(isAnyOf: values)])

        XCTAssertFalse(query.isValid)

        let projection = LibraryBrowserProjection.make(
            sourceFrameIDs: [frame.id],
            query: query,
            context: context,
            sort: .init(key: .inputOrder, ascending: true)
        )
        XCTAssertFalse(projection.queryWasValid)
        XCTAssertTrue(projection.orderedFrameIDs.isEmpty)
    }

    func testQueryCodableRoundTripPreservesOperatorsAndValues() throws {
        let query = LibraryQuery(matchMode: .any, conditions: [
            .text(.init(field: .titleDescription, rule: .containsAllWords, value: "night train")),
            .textIsAnyOf(field: .camera, values: ["Nikon F3", "Canon F-1"]),
            .rating(comparison: .greaterThanOrEqual, value: 4),
            .pickState(isAnyOf: [.picked, .rejected]),
            .sourceAvailability(isAnyOf: [.offline, .unknown]),
            .calendarDate(.init(
                field: .contentDate,
                predicate: .range(
                    startInclusive: LibraryCalendarDate(year: 2024, month: 1, day: 1)!,
                    endExclusive: LibraryCalendarDate(year: 2025, month: 1, day: 1)!
                )
            )),
        ])

        let data = try JSONEncoder().encode(query)
        let decoded = try JSONDecoder().decode(LibraryQuery.self, from: data)

        XCTAssertEqual(decoded, query)
    }

    func testQueryVersionOneUsesExplicitTaggedConditionContract() throws {
        let query = LibraryQuery(conditions: [
            .text(.init(field: .fileName, rule: .containsAll, value: "archive 01")),
            .date(.init(
                field: .contentInstant,
                predicate: .range(
                    startInclusive: Date(timeIntervalSince1970: 1_700_000_000),
                    endExclusive: Date(timeIntervalSince1970: 1_700_086_400)
                )
            )),
            .currentRoll,
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(query)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let conditions = try XCTUnwrap(object["conditions"] as? [[String: Any]])

        XCTAssertEqual(conditions.compactMap { $0["kind"] as? String }, [
            "text", "date", "currentRoll",
        ])
        let dateCondition = try XCTUnwrap(conditions[1]["dateCondition"] as? [String: Any])
        XCTAssertEqual(dateCondition["field"] as? String, "contentInstant")
        let predicate = try XCTUnwrap(dateCondition["predicate"] as? [String: Any])
        XCTAssertEqual(predicate["kind"] as? String, "range")

        var invalid = object
        var invalidConditions = conditions
        invalidConditions[0]["kind"] = "futureCondition"
        invalid["conditions"] = invalidConditions
        let invalidData = try JSONSerialization.data(
            withJSONObject: invalid,
            options: [.sortedKeys]
        )
        XCTAssertThrowsError(try JSONDecoder().decode(LibraryQuery.self, from: invalidData))
    }

    func testContextBuilderUsesAuthoritativeContentDatePriority() {
        let sidecarDate = "2024-03-04T05:06:07+09:00"
        let exifDate = "2023:02:03 04:05:06"
        let imageDate = "2022-01-02T03:04:05Z"
        var sidecarSnapshot = SourceMetadataSnapshot()
        sidecarSnapshot.exif = exif(date: exifDate, offset: "+09:00")
        sidecarSnapshot.imageMetadataXMPView = xmp(dateCreated: imageDate)
        sidecarSnapshot.sidecarXMPState = .loaded
        sidecarSnapshot.sidecarXMP = xmp(dateCreated: sidecarDate)

        var exifSnapshot = sidecarSnapshot
        exifSnapshot.sidecarXMPState = .notFound
        exifSnapshot.sidecarXMP = nil

        var imageSnapshot = SourceMetadataSnapshot()
        imageSnapshot.imageMetadataXMPView = xmp(
            createDate: "2020-01-01T00:00:00Z",
            dateCreated: imageDate
        )

        var createDateOnly = SourceMetadataSnapshot()
        createDateOnly.imageMetadataXMPView = xmp(createDate: "2020-01-01T00:00:00Z")

        let sidecarFrame = makeFrame(index: 1, metadata: sidecarSnapshot)
        let exifFrame = makeFrame(index: 2, metadata: exifSnapshot)
        let imageFrame = makeFrame(index: 3, metadata: imageSnapshot)
        let createOnlyFrame = makeFrame(index: 4, metadata: createDateOnly)
        let context = LibraryQueryContext.make(
            generation: 3,
            frames: [sidecarFrame, exifFrame, imageFrame, createOnlyFrame],
            folders: [],
            rolls: [],
            activeRollID: nil,
            scanSessions: [],
            scannerProfiles: [],
            availabilityByFrameID: [:]
        )

        XCTAssertEqual(
            context.factsByFrameID[sidecarFrame.id]?.contentDate,
            SourceMetadataReader.parseXMPDate(sidecarDate)
        )
        XCTAssertEqual(
            context.factsByFrameID[exifFrame.id]?.contentDate,
            SourceMetadataReader.parseEXIFDate(
                dateTimeRaw: exifDate,
                offsetRaw: "+09:00",
                subsecondRaw: nil
            )
        )
        XCTAssertEqual(
            context.factsByFrameID[imageFrame.id]?.contentDate,
            SourceMetadataReader.parseXMPDate(imageDate)
        )
        XCTAssertNil(context.factsByFrameID[createOnlyFrame.id]?.contentDate)
    }

    func testInvalidHigherPriorityContentDateFallsBackAndRecordsReadProblem() {
        var snapshot = SourceMetadataSnapshot()
        snapshot.sidecarXMPState = .loaded
        snapshot.sidecarXMP = xmp(dateCreated: "2023-02-29T10:20:30Z")
        snapshot.exif = exif(date: "2024:02:29 10:20:30", offset: nil)
        snapshot.imageMetadataXMPView = xmp(dateCreated: "2025-03-01T00:00:00Z")
        let frame = makeFrame(index: 1, metadata: snapshot)
        let context = makeContext(frames: [frame])
        let facts = try! XCTUnwrap(context.factsByFrameID[frame.id])

        XCTAssertEqual(
            facts.contentCalendarDate,
            LibraryCalendarDate(year: 2024, month: 2, day: 29)
        )
        XCTAssertNil(facts.contentDate)
        XCTAssertEqual(facts.metadataReadProblem, true)
        XCTAssertEqual(facts.metadataPresenceByField[.contentDate], .present)
    }

    func testValidHigherPriorityContentDateStillReportsInvalidLowerMetadata() {
        var snapshot = SourceMetadataSnapshot()
        snapshot.sidecarXMPState = .loaded
        snapshot.sidecarXMP = xmp(dateCreated: "2024-01-02T03:04:05Z")
        snapshot.exif = exif(date: "2023:02:29 10:20:30", offset: "+09:00")
        let frame = makeFrame(index: 1, metadata: snapshot)
        let facts = try! XCTUnwrap(makeContext(frames: [frame]).factsByFrameID[frame.id])

        XCTAssertEqual(
            facts.contentCalendarDate,
            LibraryCalendarDate(year: 2024, month: 1, day: 2)
        )
        XCTAssertEqual(facts.metadataReadProblem, true)
    }

    func testReducedPrecisionContentDateIsPresentButNotInventedAsCalendarDay() {
        var snapshot = SourceMetadataSnapshot()
        snapshot.imageMetadataXMPView = xmp(dateCreated: "2024-02")
        let frame = makeFrame(index: 1, metadata: snapshot)
        let facts = try! XCTUnwrap(makeContext(frames: [frame]).factsByFrameID[frame.id])

        XCTAssertNil(facts.contentCalendarDate)
        XCTAssertNil(facts.contentDate)
        XCTAssertEqual(facts.metadataPresenceByField[.contentDate], .present)
        XCTAssertEqual(facts.metadataReadProblem, false)
    }

    func testContextBuilderIndexesMetadataUnionsAndReadProblems() {
        var snapshot = SourceMetadataSnapshot()
        snapshot.exif = exif(
            date: nil,
            offset: nil,
            cameraMake: "Nikon",
            cameraModel: "F3",
            lens: "Nikkor 50mm"
        )
        snapshot.iptc = iptc(
            title: "Night Train",
            caption: "Platform",
            keywords: ["grain"]
        )
        snapshot.imageMetadataXMPView = xmp(
            keywords: ["film"],
            title: ["x-default": "Railway"]
        )
        snapshot.sidecarXMPState = .loaded
        snapshot.sidecarXMP = xmp(
            keywords: ["archive", "grain"],
            description: ["ko": "야간 열차"]
        )
        snapshot.discardedOversizedValues = true
        let frame = makeFrame(index: 1, metadata: snapshot)

        let context = LibraryQueryContext.make(
            generation: 1,
            frames: [frame],
            folders: [],
            rolls: [],
            activeRollID: nil,
            scanSessions: [],
            scannerProfiles: [],
            availabilityByFrameID: [frame.id: .offline]
        )
        let facts = try! XCTUnwrap(context.factsByFrameID[frame.id])

        XCTAssertEqual(facts.availability, .offline)
        XCTAssertTrue(facts.textValues[.keywords]?.contains("grain") == true)
        XCTAssertTrue(facts.textValues[.keywords]?.contains("film") == true)
        XCTAssertTrue(facts.textValues[.keywords]?.contains("archive") == true)
        XCTAssertTrue(facts.textValues[.titleDescription]?.contains("야간 열차") == true)
        XCTAssertTrue(facts.textValues[.camera]?.contains("nikon") == true)
        XCTAssertTrue(facts.textValues[.camera]?.contains("nikon f3") == true)
        XCTAssertTrue(facts.textValues[.lens]?.contains("nikkor 50mm") == true)
        XCTAssertTrue(facts.metadataPresentFields.isSuperset(of: [
            .snapshot, .camera, .lens, .title, .description, .keywords, .descriptive,
        ]))
        XCTAssertEqual(facts.metadataReadProblem, true)
    }

    func testContextBuilderDoesNotIndexInvalidSidecarMetadata() {
        var snapshot = SourceMetadataSnapshot()
        snapshot.sidecarXMPState = .invalid
        snapshot.sidecarXMP = xmp(
            dateCreated: "2024-01-01T00:00:00Z",
            keywords: ["must-not-index"]
        )
        let frame = makeFrame(index: 1, metadata: snapshot)
        let context = makeContext(frames: [frame])
        let facts = try! XCTUnwrap(context.factsByFrameID[frame.id])

        XCTAssertNil(facts.contentDate)
        XCTAssertFalse(facts.textValues[.keywords]?.contains("must-not-index") == true)
        XCTAssertEqual(facts.metadataReadProblem, true)
    }

    func testContextBuilderUsesExactRollProfileAndRejectsUnfinishedCaptureSession() throws {
        let sessionID = UUID()
        let jobID = UUID()
        let device = ScannerDescriptor(
            id: "mock:archive-scanner",
            displayName: "Archive Scanner",
            vendor: "ArchiveCo",
            model: "AS-1",
            backendType: .mock,
            serialNumber: "SERIAL-1"
        )
        let session = try makeSession(id: sessionID, jobID: jobID, device: device)
        var profile = try scannerProfile(id: "profile-a", status: .pairedValidated)
        profile.displayName = "Archive Profile"
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/archive.tiff"),
            filmType: .colorNegative,
            scanSessionID: sessionID,
            scanJobID: jobID
        )
        frame.updateParams { $0.scannerProfileID = profile.id }
        let rollID = UUID()
        let roll = try XCTUnwrap(LibraryRoll.physical(
            id: rollID,
            name: "Tokyo 01",
            filmType: .colorNegative,
            frameIDs: [frame.id]
        ))

        let context = LibraryQueryContext.make(
            generation: 1,
            frames: [frame],
            folders: [],
            rolls: [roll],
            activeRollID: rollID,
            scanSessions: [session],
            scannerProfiles: [profile],
            availabilityByFrameID: [frame.id: .online]
        )
        let facts = try XCTUnwrap(context.factsByFrameID[frame.id])

        XCTAssertEqual(facts.rollID, rollID)
        XCTAssertEqual(facts.scannerProfileState, .pairedValidated)
        XCTAssertTrue(facts.textValues[.roll]?.contains("tokyo 01") == true)
        XCTAssertTrue(facts.textValues[.scannerProfile]?.contains("archive profile") == true)
        XCTAssertTrue(facts.textValues[.scannerDevice]?.isEmpty == true)

        let ambiguous = LibraryQueryContext.make(
            generation: 2,
            frames: [frame],
            folders: [],
            rolls: [roll, roll],
            activeRollID: rollID,
            scanSessions: [session, session],
            scannerProfiles: [profile, profile],
            availabilityByFrameID: [:]
        )
        let ambiguousFacts = try XCTUnwrap(ambiguous.factsByFrameID[frame.id])
        XCTAssertNil(ambiguousFacts.rollID)
        XCTAssertEqual(ambiguousFacts.scannerProfileState, .unknown)
        XCTAssertTrue(ambiguousFacts.textValues[.scannerDevice]?.isEmpty == true)
        XCTAssertEqual(ambiguousFacts.availability, .unknown)
    }

    func testContextBuilderAttributesDeviceOnlyToPublishedSuccessfulFrameFamily() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-query-provenance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sessionID = UUID()
        let jobID = UUID()
        let rootID = UUID()
        let rawURL = directory.appendingPathComponent("capture.tiff")
        try Data([1]).write(to: rawURL)
        let device = ScannerDescriptor(
            id: "mock:published-scanner",
            displayName: "Published Scanner",
            vendor: "ArchiveCo",
            model: "PS-1",
            backendType: .mock,
            serialNumber: "SERIAL-PUBLISHED"
        )
        let session = try makeSucceededSession(
            id: sessionID,
            jobID: jobID,
            publicationFrameID: rootID,
            rawURL: rawURL,
            device: device
        )
        let manifest = try XCTUnwrap(session.jobs.first?.captureManifest)
        let root = ScanFrame(
            scanIndex: 1,
            rawScanURL: rawURL,
            filmType: .colorNegative,
            sourcePixelWidth: manifest.result.width,
            sourcePixelHeight: manifest.result.height,
            sourceResolutionDPI: manifest.result.reportedResolution?.dpi,
            sourceBitDepth: manifest.result.reportedBitDepth?.rawValue,
            scanSessionID: sessionID,
            scanJobID: jobID,
            scannedAt: manifest.captureCompletedAt,
            id: rootID,
            storageGroupName: "query-provenance"
        )
        let copy = root.makeVirtualCopy(copyNumber: 1)
        let unrelated = ScanFrame(
            scanIndex: 1,
            rawScanURL: rawURL,
            filmType: .colorNegative,
            scanSessionID: sessionID,
            scanJobID: jobID
        )
        let context = LibraryQueryContext.make(
            generation: 1,
            frames: [root, copy, unrelated],
            folders: [],
            rolls: [],
            activeRollID: nil,
            scanSessions: [session],
            scannerProfiles: [],
            availabilityByFrameID: [:]
        )

        for frame in [root, copy] {
            XCTAssertTrue(context.factsByFrameID[frame.id]?
                .textValues[.scannerDevice]?.contains("published scanner") == true)
            XCTAssertFalse(context.factsByFrameID[frame.id]?
                .unknownTextFields.contains(.scannerDevice) == true)
        }
        XCTAssertTrue(context.factsByFrameID[unrelated.id]?
            .textValues[.scannerDevice]?.isEmpty == true)
        XCTAssertTrue(context.factsByFrameID[unrelated.id]?
            .unknownTextFields.contains(.scannerDevice) == true)
    }

    func testCaptureDeviceDistinguishesImportedNotApplicableFromLegacyScannerUnknown() {
        let imported = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/imported.tiff"),
            filmType: .colorNegative,
            sourceKind: .importedFile
        )
        let legacyScanner = makeFrame(index: 2)
        let context = makeContext(frames: [imported, legacyScanner])

        XCTAssertFalse(context.factsByFrameID[imported.id]?
            .unknownTextFields.contains(.scannerDevice) == true)
        XCTAssertTrue(matches(
            .text(.init(field: .scannerDevice, rule: .isEmpty, value: "")),
            frameID: imported.id,
            context: context
        ))
        XCTAssertTrue(context.factsByFrameID[legacyScanner.id]?
            .unknownTextFields.contains(.scannerDevice) == true)
        XCTAssertFalse(matches(
            .text(.init(field: .scannerDevice, rule: .isEmpty, value: "")),
            frameID: legacyScanner.id,
            context: context
        ))
    }

    func testDuplicateRollIdentifiersInvalidateOtherwiseDisjointMemberships() throws {
        let first = makeFrame(index: 1)
        let second = makeFrame(index: 2)
        let duplicateID = UUID()
        let firstRoll = try XCTUnwrap(LibraryRoll.physical(
            id: duplicateID,
            name: "First",
            filmType: .colorNegative,
            frameIDs: [first.id]
        ))
        let secondRoll = try XCTUnwrap(LibraryRoll.physical(
            id: duplicateID,
            name: "Second",
            filmType: .colorNegative,
            frameIDs: [second.id]
        ))

        let context = LibraryQueryContext.make(
            generation: 1,
            frames: [first, second],
            folders: [],
            rolls: [firstRoll, secondRoll],
            activeRollID: duplicateID,
            scanSessions: [],
            scannerProfiles: [],
            availabilityByFrameID: [:]
        )

        XCTAssertNil(context.factsByFrameID[first.id]?.rollID)
        XCTAssertNil(context.factsByFrameID[second.id]?.rollID)
        XCTAssertFalse(LibraryQuery(conditions: [.currentRoll]).matches(
            frameID: first.id,
            in: context
        ))
    }

    func testContextBuilderSeparatesCreativeCalibrationAndFutureUnknownStates() {
        let frame = makeFrame(index: 1)
        frame.updateParams {
            $0.redPrimary = 0.2
            $0.calibration.blueHue = 0.1
        }
        frame.defectEditsNeedRestore = true
        let context = makeContext(frames: [frame])
        let facts = try! XCTUnwrap(context.factsByFrameID[frame.id])

        XCTAssertTrue(facts.hasCreativeCalibrationAdjustments)
        XCTAssertTrue(facts.hasDefectRecipe)
        XCTAssertEqual(facts.exportState, .unknown)
        XCTAssertEqual(facts.userEditState, .unknown)
        XCTAssertEqual(facts.defectReviewState, .unknown)
        XCTAssertEqual(facts.deviceCalibrationState, .unknown)
    }

    private func matches(
        _ condition: LibraryQueryCondition,
        frameID: UUID,
        context: LibraryQueryContext
    ) -> Bool {
        LibraryQuery(conditions: [condition]).matches(frameID: frameID, in: context)
    }

    private func fact(
        id: UUID = UUID(),
        textValues: [LibraryTextField: [String]] = [:],
        unknownTextFields: Set<LibraryTextField> = [],
        sortName: String = "frame",
        folderPath: String = "/tmp",
        scannedAt: Date = Date(timeIntervalSince1970: 0),
        contentDate: Date? = nil,
        contentCalendarDate: LibraryCalendarDate? = nil,
        fileSizeBytes: Int64? = nil,
        rollID: UUID? = nil,
        filmType: FilmType = .colorNegative,
        rating: Int = 0,
        pickState: FramePickState = .unflagged,
        availability: LibrarySourceAvailability = .online,
        isVirtualCopy: Bool? = false,
        hasInfraredCapture: Bool = false,
        hasDefectRecipe: Bool = false,
        scannerProfileState: LibraryScannerProfileState = .none,
        metadataPresentFields: Set<LibraryMetadataField> = [],
        metadataReadProblem: Bool = false,
        hasCreativeCalibrationAdjustments: Bool = false,
        exportState: LibraryExportState = .unknown,
        userEditState: LibraryUserEditState = .unknown,
        defectReviewState: LibraryDefectReviewState = .unknown,
        deviceCalibrationState: LibraryDeviceCalibrationState = .unknown
    ) -> LibraryFrameQueryFacts {
        LibraryFrameQueryFacts(
            id: id,
            textValues: textValues,
            unknownTextFields: unknownTextFields,
            sortName: sortName,
            folderPath: folderPath,
            scannedAt: scannedAt,
            contentDate: contentDate,
            contentCalendarDate: contentCalendarDate,
            fileSizeBytes: fileSizeBytes,
            rollID: rollID,
            filmType: filmType,
            rating: rating,
            pickState: pickState,
            availability: availability,
            isVirtualCopy: isVirtualCopy,
            hasInfraredCapture: hasInfraredCapture,
            hasDefectRecipe: hasDefectRecipe,
            scannerProfileState: scannerProfileState,
            metadataPresentFields: metadataPresentFields,
            metadataReadProblem: metadataReadProblem,
            hasCreativeCalibrationAdjustments: hasCreativeCalibrationAdjustments,
            exportState: exportState,
            userEditState: userEditState,
            defectReviewState: defectReviewState,
            deviceCalibrationState: deviceCalibrationState
        )
    }

    private func makeContext(frames: [ScanFrame]) -> LibraryQueryContext {
        LibraryQueryContext.make(
            generation: 1,
            frames: frames,
            folders: [],
            rolls: [],
            activeRollID: nil,
            scanSessions: [],
            scannerProfiles: [],
            availabilityByFrameID: [:]
        )
    }

    private func makeFrame(
        index: Int,
        metadata: SourceMetadataSnapshot? = nil
    ) -> ScanFrame {
        ScanFrame(
            scanIndex: index,
            rawScanURL: URL(fileURLWithPath: "/tmp/query-\(index)-\(UUID().uuidString).tiff"),
            filmType: .colorNegative,
            sourceMetadata: metadata
        )
    }

    private func exif(
        date: String?,
        offset: String?,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lens: String? = nil
    ) -> SourceEXIFMetadata {
        SourceEXIFMetadata(
            dateTimeOriginalRaw: date,
            offsetTimeOriginalRaw: offset,
            subsecondTimeOriginalRaw: nil,
            cameraMake: cameraMake,
            cameraModel: cameraModel,
            lensModel: lens,
            software: nil,
            exposureTimeSeconds: nil,
            fNumber: nil,
            isoSpeedRatings: [],
            focalLengthMM: nil
        )
    }

    private func iptc(
        title: String? = nil,
        caption: String? = nil,
        keywords: [String] = []
    ) -> SourceIPTCMetadata {
        SourceIPTCMetadata(
            title: title,
            headline: nil,
            caption: caption,
            creators: [],
            credit: nil,
            copyrightNotice: nil,
            rightsUsageTerms: nil,
            source: nil,
            jobIdentifier: nil,
            keywords: keywords,
            city: nil,
            stateProvince: nil,
            country: nil,
            countryCode: nil,
            sublocation: nil
        )
    }

    private func xmp(
        createDate: String? = nil,
        dateCreated: String? = nil,
        keywords: [String] = [],
        title: [String: String]? = nil,
        description: [String: String]? = nil
    ) -> SourceXMPMetadata {
        SourceXMPMetadata(
            createDateRaw: createDate,
            dateCreatedRaw: dateCreated,
            title: title.map(SourceLocalizedText.init(valuesByLanguage:)),
            description: description.map(SourceLocalizedText.init(valuesByLanguage:)),
            creators: [],
            rights: nil,
            usageTerms: nil,
            headline: nil,
            credit: nil,
            jobIdentifier: nil,
            keywords: keywords,
            city: nil,
            stateProvince: nil,
            country: nil,
            sublocation: nil,
            rating: nil,
            label: nil
        )
    }

    private func makeSession(
        id: UUID,
        jobID: UUID,
        device: ScannerDescriptor
    ) throws -> ScanSession {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        var options = ScanOptions.strongDefault(scannerID: device.id)
        options.requestID = jobID
        options.temporaryOutputURL = URL(
            fileURLWithPath: "/tmp/query-\(jobID.uuidString).tiff"
        )
        let job = try ScanJob(
            id: jobID,
            sessionID: id,
            ordinal: 1,
            kind: .full,
            requestedOptions: options,
            framePublication: try ScanFramePublicationSnapshot(
                scanIndex: 1,
                initialTransform: .identity,
                developTarget: .main,
                storageGroupName: "query-test"
            ),
            createdAt: createdAt
        )
        return try ScanSession(
            id: id,
            createdAt: createdAt,
            device: device,
            backend: ScanBackendSnapshot(type: .mock, identifier: "query-test"),
            environment: ScanEnvironmentSnapshot(
                applicationName: "negaflow",
                applicationVersion: "1",
                operatingSystem: "macOS",
                operatingSystemVersion: "14"
            ),
            jobs: [job]
        )
    }

    private func makeSucceededSession(
        id: UUID,
        jobID: UUID,
        publicationFrameID: UUID,
        rawURL: URL,
        device: ScannerDescriptor
    ) throws -> ScanSession {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let startedAt = createdAt.addingTimeInterval(1)
        let completedAt = createdAt.addingTimeInterval(2)
        let succeededAt = createdAt.addingTimeInterval(3)
        var options = ScanOptions.strongDefault(scannerID: device.id)
        options.requestID = jobID
        options.temporaryOutputURL = rawURL
        let queued = try ScanJob(
            id: jobID,
            sessionID: id,
            ordinal: 1,
            kind: .full,
            requestedOptions: options,
            framePublication: try ScanFramePublicationSnapshot(
                frameID: publicationFrameID,
                scanIndex: 1,
                initialTransform: .identity,
                developTarget: .main,
                storageGroupName: "query-provenance"
            ),
            createdAt: createdAt
        )
        let running = try queued.started(at: startedAt)
        let pending = try PendingCaptureSnapshot(
            scanResult: ScanResult(
                rawFileURL: rawURL,
                width: 1,
                height: 1,
                resolution: options.resolution,
                bitDepth: options.bitDepth,
                backendUsed: .mock,
                appliedOptionsEvidence: .verified(options)
            ),
            captureStartedAt: startedAt,
            captureCompletedAt: completedAt
        )
        let finalizing = try running.finalizing(with: pending, at: completedAt)
        let manifest = try CaptureManifest.build(
            sessionID: id,
            jobID: jobID,
            attempt: finalizing.attempt,
            kind: .full,
            requestedOptions: options,
            pendingCapture: pending,
            chunkSize: 1
        )
        let succeeded = try finalizing.succeeded(with: manifest, at: succeededAt)
        return try ScanSession(
            id: id,
            createdAt: createdAt,
            device: device,
            backend: ScanBackendSnapshot(type: .mock, identifier: "query-test"),
            environment: ScanEnvironmentSnapshot(
                applicationName: "negaflow",
                applicationVersion: "1",
                operatingSystem: "macOS",
                operatingSystemVersion: "14"
            ),
            jobs: [succeeded]
        )
    }

    private func scannerProfile(
        id: String,
        status: ScannerProfileValidationStatus
    ) throws -> ScannerProfile {
        let json: [String: Any] = [
            "schemaVersion": 1,
            "id": id,
            "displayName": id,
            "scanner": "TEST",
            "kind": "color nega",
            "filmKey": "test-film",
            "validationStatus": status.rawValue,
            "rollCount": 1,
            "imageCount": 1,
            "singleRollLimited": false,
            "sourceProfiles": [],
            "tone": [:],
            "color": [:],
            "neutralAxis": [:],
            "texture": [:],
            "sceneBuckets": [],
            "coverageCandidates": [],
            "profileHash": String(repeating: "a", count: 64),
        ]
        return try JSONDecoder().decode(
            ScannerProfile.self,
            from: JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        )
    }
}
