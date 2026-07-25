import Foundation
import Chromabase
import ScannerKit

enum LibraryQueryCondition: Codable, Equatable, Sendable {
    case text(LibraryTextCondition)
    /// 같은 metadata 열의 여러 정확한 값은 OR, 다른 condition과는 query matchMode로 결합한다.
    case textIsAnyOf(field: LibraryTextField, values: [String])
    case rating(comparison: LibraryNumericComparison, value: Int)
    case pickState(isAnyOf: [FramePickState])
    case date(LibraryDateCondition)
    case calendarDate(LibraryCalendarDateCondition)
    case roll(isAnyOf: [UUID])
    case currentRoll
    case filmType(isAnyOf: [FilmType])
    case sourceAvailability(isAnyOf: [LibrarySourceAvailability])
    case virtualCopy(Bool)
    case infraredCapture(Bool)
    case defectRecipe(Bool)
    case scannerProfileState(isAnyOf: [LibraryScannerProfileState])
    case metadata(field: LibraryMetadataField, presence: LibraryMetadataPresence)
    case metadataReadProblem(Bool)
    case creativeCalibrationAdjusted(Bool)
    case exportState(isAnyOf: [LibraryExportState])
    case userEditState(isAnyOf: [LibraryUserEditState])
    case defectReviewState(isAnyOf: [LibraryDefectReviewState])
    case deviceCalibrationState(isAnyOf: [LibraryDeviceCalibrationState])

    private enum Kind: String, Codable {
        case text
        case textIsAnyOf
        case rating
        case pickState
        case date
        case calendarDate
        case roll
        case currentRoll
        case filmType
        case sourceAvailability
        case virtualCopy
        case infraredCapture
        case defectRecipe
        case scannerProfileState
        case metadata
        case metadataReadProblem
        case creativeCalibrationAdjusted
        case exportState
        case userEditState
        case defectReviewState
        case deviceCalibrationState
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case textCondition
        case textField
        case stringValues
        case comparison
        case integerValue
        case pickStates
        case dateCondition
        case calendarDateCondition
        case rollIDs
        case filmTypes
        case availabilityStates
        case booleanValue
        case scannerProfileStates
        case metadataField
        case metadataPresence
        case exportStates
        case userEditStates
        case defectReviewStates
        case deviceCalibrationStates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .text:
            self = .text(try container.decode(
                LibraryTextCondition.self,
                forKey: .textCondition
            ))
        case .textIsAnyOf:
            self = .textIsAnyOf(
                field: try container.decode(LibraryTextField.self, forKey: .textField),
                values: try container.decode([String].self, forKey: .stringValues)
            )
        case .rating:
            self = .rating(
                comparison: try container.decode(
                    LibraryNumericComparison.self,
                    forKey: .comparison
                ),
                value: try container.decode(Int.self, forKey: .integerValue)
            )
        case .pickState:
            self = .pickState(isAnyOf: try container.decode(
                [FramePickState].self,
                forKey: .pickStates
            ))
        case .date:
            self = .date(try container.decode(
                LibraryDateCondition.self,
                forKey: .dateCondition
            ))
        case .calendarDate:
            self = .calendarDate(try container.decode(
                LibraryCalendarDateCondition.self,
                forKey: .calendarDateCondition
            ))
        case .roll:
            self = .roll(isAnyOf: try container.decode([UUID].self, forKey: .rollIDs))
        case .currentRoll:
            self = .currentRoll
        case .filmType:
            self = .filmType(isAnyOf: try container.decode(
                [FilmType].self,
                forKey: .filmTypes
            ))
        case .sourceAvailability:
            self = .sourceAvailability(isAnyOf: try container.decode(
                [LibrarySourceAvailability].self,
                forKey: .availabilityStates
            ))
        case .virtualCopy:
            self = .virtualCopy(try container.decode(Bool.self, forKey: .booleanValue))
        case .infraredCapture:
            self = .infraredCapture(try container.decode(Bool.self, forKey: .booleanValue))
        case .defectRecipe:
            self = .defectRecipe(try container.decode(Bool.self, forKey: .booleanValue))
        case .scannerProfileState:
            self = .scannerProfileState(isAnyOf: try container.decode(
                [LibraryScannerProfileState].self,
                forKey: .scannerProfileStates
            ))
        case .metadata:
            self = .metadata(
                field: try container.decode(LibraryMetadataField.self, forKey: .metadataField),
                presence: try container.decode(
                    LibraryMetadataPresence.self,
                    forKey: .metadataPresence
                )
            )
        case .metadataReadProblem:
            self = .metadataReadProblem(try container.decode(Bool.self, forKey: .booleanValue))
        case .creativeCalibrationAdjusted:
            self = .creativeCalibrationAdjusted(try container.decode(
                Bool.self,
                forKey: .booleanValue
            ))
        case .exportState:
            self = .exportState(isAnyOf: try container.decode(
                [LibraryExportState].self,
                forKey: .exportStates
            ))
        case .userEditState:
            self = .userEditState(isAnyOf: try container.decode(
                [LibraryUserEditState].self,
                forKey: .userEditStates
            ))
        case .defectReviewState:
            self = .defectReviewState(isAnyOf: try container.decode(
                [LibraryDefectReviewState].self,
                forKey: .defectReviewStates
            ))
        case .deviceCalibrationState:
            self = .deviceCalibrationState(isAnyOf: try container.decode(
                [LibraryDeviceCalibrationState].self,
                forKey: .deviceCalibrationStates
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(condition):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(condition, forKey: .textCondition)
        case let .textIsAnyOf(field, values):
            try container.encode(Kind.textIsAnyOf, forKey: .kind)
            try container.encode(field, forKey: .textField)
            try container.encode(values, forKey: .stringValues)
        case let .rating(comparison, value):
            try container.encode(Kind.rating, forKey: .kind)
            try container.encode(comparison, forKey: .comparison)
            try container.encode(value, forKey: .integerValue)
        case let .pickState(values):
            try container.encode(Kind.pickState, forKey: .kind)
            try container.encode(values, forKey: .pickStates)
        case let .date(condition):
            try container.encode(Kind.date, forKey: .kind)
            try container.encode(condition, forKey: .dateCondition)
        case let .calendarDate(condition):
            try container.encode(Kind.calendarDate, forKey: .kind)
            try container.encode(condition, forKey: .calendarDateCondition)
        case let .roll(values):
            try container.encode(Kind.roll, forKey: .kind)
            try container.encode(values, forKey: .rollIDs)
        case .currentRoll:
            try container.encode(Kind.currentRoll, forKey: .kind)
        case let .filmType(values):
            try container.encode(Kind.filmType, forKey: .kind)
            try container.encode(values, forKey: .filmTypes)
        case let .sourceAvailability(values):
            try container.encode(Kind.sourceAvailability, forKey: .kind)
            try container.encode(values, forKey: .availabilityStates)
        case let .virtualCopy(value):
            try container.encode(Kind.virtualCopy, forKey: .kind)
            try container.encode(value, forKey: .booleanValue)
        case let .infraredCapture(value):
            try container.encode(Kind.infraredCapture, forKey: .kind)
            try container.encode(value, forKey: .booleanValue)
        case let .defectRecipe(value):
            try container.encode(Kind.defectRecipe, forKey: .kind)
            try container.encode(value, forKey: .booleanValue)
        case let .scannerProfileState(values):
            try container.encode(Kind.scannerProfileState, forKey: .kind)
            try container.encode(values, forKey: .scannerProfileStates)
        case let .metadata(field, presence):
            try container.encode(Kind.metadata, forKey: .kind)
            try container.encode(field, forKey: .metadataField)
            try container.encode(presence, forKey: .metadataPresence)
        case let .metadataReadProblem(value):
            try container.encode(Kind.metadataReadProblem, forKey: .kind)
            try container.encode(value, forKey: .booleanValue)
        case let .creativeCalibrationAdjusted(value):
            try container.encode(Kind.creativeCalibrationAdjusted, forKey: .kind)
            try container.encode(value, forKey: .booleanValue)
        case let .exportState(values):
            try container.encode(Kind.exportState, forKey: .kind)
            try container.encode(values, forKey: .exportStates)
        case let .userEditState(values):
            try container.encode(Kind.userEditState, forKey: .kind)
            try container.encode(values, forKey: .userEditStates)
        case let .defectReviewState(values):
            try container.encode(Kind.defectReviewState, forKey: .kind)
            try container.encode(values, forKey: .defectReviewStates)
        case let .deviceCalibrationState(values):
            try container.encode(Kind.deviceCalibrationState, forKey: .kind)
            try container.encode(values, forKey: .deviceCalibrationStates)
        }
    }
}
