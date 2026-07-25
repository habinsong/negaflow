import Foundation
import XCTest
import Chromabase
@testable import negaflowApp

final class LibraryQueryRefinementCacheTests: XCTestCase {
    func testRefinementSequenceMatchesColdProjectionForSupportedSorts() throws {
        let facts = [
            fact(index: 0, name: "Night 02", searchable: "night archive", rating: 4),
            fact(index: 1, name: "Nitrogen", searchable: "nitrogen", rating: 3),
            fact(index: 2, name: "Train", searchable: "train", rating: 5),
            fact(index: 3, name: "Night 01", searchable: "night portrait", rating: 1),
        ]
        let context = LibraryQueryContext(
            generation: 7,
            facts: facts,
            folderFacts: [
                LibraryFolderQueryFact(id: "/roll-a", folderID: nil, title: "roll-a"),
                LibraryFolderQueryFact(id: "/roll-b", folderID: nil, title: "roll-b"),
            ]
        )
        let sourceIDs = [facts[0].id, facts[1].id, facts[0].id, facts[2].id, facts[3].id]
        let baseQuery = LibraryQuery(conditions: [
            .rating(comparison: .greaterThanOrEqual, value: 2),
        ])
        let queries = ["n", "ni", "nig", "night"].map { searchQuery($0) }
        let sorts: [LibrarySortDescriptor] = [
            .init(key: .inputOrder, ascending: true),
            .init(key: .inputOrder, ascending: false),
            .init(key: .name, ascending: true),
        ]

        for sort in sorts {
            var cache = LibraryBrowserProjectionCache(
                generation: context.generation,
                sourceFrameIDs: sourceIDs,
                query: baseQuery,
                sort: sort,
                projection: LibraryBrowserProjection.make(
                    sourceFrameIDs: sourceIDs,
                    query: baseQuery,
                    context: context,
                    sort: sort
                )
            )
            for query in queries {
                let refined = try XCTUnwrap(cache.reusedProjection(
                    sourceFrameIDs: sourceIDs,
                    query: query,
                    context: context,
                    sort: sort
                ))
                let cold = LibraryBrowserProjection.make(
                    sourceFrameIDs: sourceIDs,
                    query: query,
                    context: context,
                    sort: sort
                )
                XCTAssertEqual(refined, cold)
                XCTAssertEqual(refined.sourceCount, 4)
                cache = LibraryBrowserProjectionCache(
                    generation: context.generation,
                    sourceFrameIDs: sourceIDs,
                    query: query,
                    sort: sort,
                    projection: refined
                )
            }
        }
    }

    func testRefinementAcceptsTermStrengtheningButRejectsBroadening() throws {
        let old = searchQuery("night arch")
        XCTAssertNotNil(LibraryQueryTextRefinement.make(
            previous: old,
            next: searchQuery("night archive")
        ))
        XCTAssertNotNil(LibraryQueryTextRefinement.make(
            previous: old,
            next: searchQuery("archive nightfall")
        ))
        XCTAssertNil(LibraryQueryTextRefinement.make(
            previous: searchQuery("night"),
            next: searchQuery("nig")
        ))
        XCTAssertNil(LibraryQueryTextRefinement.make(
            previous: old,
            next: searchQuery("night")
        ))
    }

    func testCacheRejectsChangedScopeSortGenerationAndQuerySemantics() throws {
        let facts = [fact(index: 0, name: "Night", searchable: "night", rating: 4)]
        let context = LibraryQueryContext(generation: 3, facts: facts)
        let sourceIDs = facts.map(\.id)
        let sort = LibrarySortDescriptor(key: .inputOrder, ascending: true)
        let oldQuery = searchQuery("n")
        let projection = LibraryBrowserProjection.make(
            sourceFrameIDs: sourceIDs,
            query: oldQuery,
            context: context,
            sort: sort
        )
        let cache = LibraryBrowserProjectionCache(
            generation: context.generation,
            sourceFrameIDs: sourceIDs,
            query: oldQuery,
            sort: sort,
            projection: projection
        )

        XCTAssertNil(cache.reusedProjection(
            sourceFrameIDs: sourceIDs + sourceIDs,
            query: searchQuery("ni"),
            context: context,
            sort: sort
        ))
        XCTAssertNil(cache.reusedProjection(
            sourceFrameIDs: sourceIDs,
            query: searchQuery("ni"),
            context: context,
            sort: .init(key: .name, ascending: true)
        ))
        XCTAssertNil(cache.reusedProjection(
            sourceFrameIDs: sourceIDs,
            query: searchQuery("ni"),
            context: LibraryQueryContext(generation: 4, facts: facts),
            sort: sort
        ))
        XCTAssertNil(cache.reusedProjection(
            sourceFrameIDs: sourceIDs,
            query: LibraryQuery(matchMode: .any, conditions: searchQuery("ni").conditions),
            context: context,
            sort: sort
        ))
        XCTAssertNil(cache.reusedProjection(
            sourceFrameIDs: sourceIDs,
            query: LibraryQuery(conditions: [
                .text(.init(
                    field: .anySearchable,
                    rule: .doesNotContainAny,
                    value: "ni"
                )),
            ]),
            context: context,
            sort: sort
        ))
        XCTAssertNil(cache.reusedProjection(
            sourceFrameIDs: sourceIDs,
            query: LibraryQuery(conditions: [
                .text(.init(field: .fileName, rule: .containsAll, value: "ni")),
            ]),
            context: context,
            sort: sort
        ))
    }

    private func searchQuery(_ value: String) -> LibraryQuery {
        LibraryQuery(conditions: [
            .text(.init(field: .anySearchable, rule: .containsAll, value: value)),
            .rating(comparison: .greaterThanOrEqual, value: 2),
        ])
    }

    private func fact(
        index: Int,
        name: String,
        searchable: String,
        rating: Int
    ) -> LibraryFrameQueryFacts {
        LibraryFrameQueryFacts(
            id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", index + 1))!,
            textValues: [.displayName: [name], .anySearchable: [searchable]],
            sortName: name,
            folderPath: index.isMultiple(of: 2) ? "/roll-a" : "/roll-b",
            scannedAt: Date(timeIntervalSinceReferenceDate: Double(index)),
            filmType: .colorNegative,
            rating: rating,
            pickState: .unflagged,
            availability: .online,
            isVirtualCopy: false,
            hasInfraredCapture: false,
            hasDefectRecipe: false,
            scannerProfileState: .none,
            metadataPresentFields: [],
            metadataReadProblem: false,
            hasCreativeCalibrationAdjustments: false
        )
    }
}
