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
                    rule: .containsPhrase,
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

    /// 사진 검색은 **입력한 말 그대로**를 찾는다.
    ///
    /// 낱말을 따로 떼어 서로 다른 값에서 하나씩 찾으면, "사진 1" 로 찾을 때 이름이 "사진 3"
    /// 이고 파일명이 `L1000003` 인 컷이 걸려 나온다 — 이름에서 "사진"을, 파일명에서 "1"을
    /// 각각 찾기 때문이다. 사용자가 실제로 겪은 증상이 이것이다.
    func testPhotoSearchMatchesThePhraseAndNotItsWordsScatteredAcrossFields() {
        let rule = LibraryTextMatchRule.containsPhrase

        // 이름과 파일명이 낱말을 나눠 가진 컷은 걸리지 않는다.
        XCTAssertFalse(LibrarySearchText.matches(
            values: ["사진 3", "L1000003.tif"],
            rule: rule,
            query: "사진 1"
        ))
        XCTAssertFalse(LibrarySearchText.matches(
            values: ["사진 2", "L1000002.tif"],
            rule: rule,
            query: "사진 1"
        ))

        // 붙여 쓴 것과 띄어 쓴 것은 함께 걸린다.
        XCTAssertTrue(LibrarySearchText.matches(
            values: ["사진 1", "L1000001.tif"],
            rule: rule,
            query: "사진 1"
        ))
        XCTAssertTrue(LibrarySearchText.matches(
            values: ["사진1", "L1000001.tif"],
            rule: rule,
            query: "사진 1"
        ))
        XCTAssertTrue(LibrarySearchText.matches(
            values: ["사진 1", "L1000001.tif"],
            rule: rule,
            query: "사진1"
        ))

        // 값 하나 안에 이어져 있으면 여러 낱말도 걸린다.
        XCTAssertTrue(LibrarySearchText.matches(
            values: ["Kodak Portra 400"],
            rule: rule,
            query: "portra 400"
        ))
    }

}
