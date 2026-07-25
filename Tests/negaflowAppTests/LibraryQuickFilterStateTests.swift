import XCTest
import Chromabase
@testable import negaflowApp

final class LibraryQuickFilterStateTests: XCTestCase {
    func testEmptyStateBuildsMatchAllQueryWithoutConditions() {
        let state = LibraryQuickFilterState()

        XCTAssertFalse(state.isActive)
        XCTAssertEqual(
            state.query(searchText: "  ", offlineSourceMode: false),
            LibraryQuery(matchMode: .all, conditions: [])
        )
    }

    func testQuickFilterGroupsUseANDWhilePickStatesShareOneORCondition() {
        let state = LibraryQuickFilterState(
            currentRoll: true,
            minimumRating: 3,
            picked: true,
            rejected: true,
            offline: true,
            infrared: true,
            defectRecipe: true,
            unvalidatedProfile: true,
            metadataUnknown: true
        )

        XCTAssertTrue(state.isActive)
        XCTAssertEqual(
            state.query(searchText: "john susan", offlineSourceMode: false),
            LibraryQuery(matchMode: .all, conditions: [
                .text(.init(
                    field: .anySearchable,
                    rule: .containsAll,
                    value: "john susan"
                )),
                .currentRoll,
                .rating(comparison: .greaterThanOrEqual, value: 3),
                .pickState(isAnyOf: [.picked, .rejected]),
                .sourceAvailability(isAnyOf: [.offline]),
                .infraredCapture(true),
                .defectRecipe(true),
                .scannerProfileState(isAnyOf: [
                    .missing, .draft, .realOnly, .pairedSmoke,
                ]),
                .metadata(field: .snapshot, presence: .unknown),
            ])
        )
    }

    func testOfflineViewAndOfflineChipProduceOneCondition() {
        var state = LibraryQuickFilterState()
        state.offline = true

        let chipQuery = state.query(searchText: "", offlineSourceMode: false)
        let modeQuery = LibraryQuickFilterState().query(
            searchText: "",
            offlineSourceMode: true
        )
        let bothQuery = state.query(searchText: "", offlineSourceMode: true)

        XCTAssertEqual(chipQuery, modeQuery)
        XCTAssertEqual(bothQuery, modeQuery)
        XCTAssertEqual(bothQuery.conditions.count, 1)
    }

    func testRatingIsClampedAndClearRestoresNeutralState() {
        var state = LibraryQuickFilterState(minimumRating: 99, picked: true)
        XCTAssertEqual(
            state.query(searchText: "", offlineSourceMode: false).conditions.first,
            .rating(comparison: .greaterThanOrEqual, value: 5)
        )

        state.clear()

        XCTAssertEqual(state, LibraryQuickFilterState())
        XCTAssertFalse(state.isActive)
    }
}
