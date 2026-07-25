import Foundation
import Chromabase

struct LibraryQuickFilterState: Equatable {
    var currentRoll = false
    var minimumRating: Int?
    var picked = false
    var rejected = false
    var offline = false
    var infrared = false
    var defectRecipe = false
    var unvalidatedProfile = false
    var metadataUnknown = false

    var isActive: Bool {
        currentRoll
            || minimumRating != nil
            || picked
            || rejected
            || offline
            || infrared
            || defectRecipe
            || unvalidatedProfile
            || metadataUnknown
    }

    mutating func clear() {
        self = LibraryQuickFilterState()
    }

    func query(searchText: String, offlineSourceMode: Bool) -> LibraryQuery {
        var conditions: [LibraryQueryCondition] = []
        if !LibrarySearchText.normalize(searchText).isEmpty {
            conditions.append(.text(.init(
                field: .anySearchable,
                rule: .containsAll,
                value: searchText
            )))
        }
        if currentRoll { conditions.append(.currentRoll) }
        if let minimumRating {
            conditions.append(.rating(
                comparison: .greaterThanOrEqual,
                value: min(max(minimumRating, 1), 5)
            ))
        }
        let pickStates: [FramePickState] = [
            picked ? .picked : nil,
            rejected ? .rejected : nil,
        ].compactMap { $0 }
        if !pickStates.isEmpty {
            conditions.append(.pickState(isAnyOf: pickStates))
        }
        if offline || offlineSourceMode {
            conditions.append(.sourceAvailability(isAnyOf: [.offline]))
        }
        if infrared { conditions.append(.infraredCapture(true)) }
        if defectRecipe { conditions.append(.defectRecipe(true)) }
        if unvalidatedProfile {
            conditions.append(.scannerProfileState(isAnyOf: [
                .missing, .draft, .realOnly, .pairedSmoke,
            ]))
        }
        if metadataUnknown {
            conditions.append(.metadata(field: .snapshot, presence: .unknown))
        }
        return LibraryQuery(matchMode: .all, conditions: conditions)
    }
}
