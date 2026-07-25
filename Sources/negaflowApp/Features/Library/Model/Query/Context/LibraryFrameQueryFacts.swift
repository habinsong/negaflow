import Foundation
import Chromabase
import ScannerKit

struct LibraryFrameQueryFacts: Equatable, Sendable {
    let id: UUID
    let textValues: [LibraryTextField: [String]]
    /// 빠른 전체 검색에서 값 배열을 매번 중첩 순회하지 않도록 만든 공백 무시 인덱스다.
    /// 값 내부 공백만 제거하며 NUL 경계는 서로 다른 metadata 값을 가로지르는 오탐을 막는다.
    let anySearchableSubstringIndex: String
    /// 모호한 join 또는 legacy metadata 때문에 값의 부재를 확정할 수 없는 text field다.
    /// positive match는 보존하되 empty/negative match는 fail closed한다.
    let unknownTextFields: Set<LibraryTextField>
    let sortName: String
    let folderPath: String
    let scannedAt: Date
    let contentDate: Date?
    let contentCalendarDate: LibraryCalendarDate?
    let contentCalendarDateInterval: LibraryCalendarDateInterval?
    let fileSizeBytes: Int64?
    let rollID: UUID?
    let filmType: FilmType
    let rating: Int
    let pickState: FramePickState
    let availability: LibrarySourceAvailability
    let isVirtualCopy: Bool?
    let hasInfraredCapture: Bool
    let hasDefectRecipe: Bool
    let scannerProfileState: LibraryScannerProfileState
    let metadataPresentFields: Set<LibraryMetadataField>
    let metadataPresenceByField: [LibraryMetadataField: LibraryMetadataPresence]
    let metadataReadProblem: Bool?
    let hasCreativeCalibrationAdjustments: Bool
    let exportState: LibraryExportState
    let userEditState: LibraryUserEditState
    let defectReviewState: LibraryDefectReviewState
    let deviceCalibrationState: LibraryDeviceCalibrationState

    init(
        id: UUID,
        textValues: [LibraryTextField: [String]] = [:],
        unknownTextFields: Set<LibraryTextField> = [],
        sortName: String,
        folderPath: String,
        scannedAt: Date,
        contentDate: Date? = nil,
        contentCalendarDate: LibraryCalendarDate? = nil,
        contentCalendarDateInterval: LibraryCalendarDateInterval? = nil,
        fileSizeBytes: Int64? = nil,
        rollID: UUID? = nil,
        filmType: FilmType,
        rating: Int,
        pickState: FramePickState,
        availability: LibrarySourceAvailability,
        isVirtualCopy: Bool?,
        hasInfraredCapture: Bool,
        hasDefectRecipe: Bool,
        scannerProfileState: LibraryScannerProfileState,
        metadataPresentFields: Set<LibraryMetadataField>,
        metadataUnknownFields: Set<LibraryMetadataField> = [],
        metadataReadProblem: Bool?,
        hasCreativeCalibrationAdjustments: Bool,
        exportState: LibraryExportState = .unknown,
        userEditState: LibraryUserEditState = .unknown,
        defectReviewState: LibraryDefectReviewState = .unknown,
        deviceCalibrationState: LibraryDeviceCalibrationState = .unknown
    ) {
        self.id = id
        var normalizedText = Dictionary(uniqueKeysWithValues: textValues.map { field, values in
            (field, LibrarySearchText.normalizeValues(values))
        })
        let derivedSearchable = LibraryTextField.allCases
            .filter { $0 != .anySearchable }
            .sorted { $0.rawValue < $1.rawValue }
            .flatMap { normalizedText[$0] ?? [] }
        normalizedText[.anySearchable] = LibrarySearchText.normalizeValues(
            (normalizedText[.anySearchable] ?? []) + derivedSearchable
        )
        self.textValues = normalizedText
        self.anySearchableSubstringIndex = normalizedText[.anySearchable, default: []]
            .map(LibrarySearchText.removingWhitespace)
            .joined(separator: "\0")
        var resolvedUnknownTextFields = unknownTextFields
        if !unknownTextFields.subtracting([.anySearchable]).isEmpty {
            resolvedUnknownTextFields.insert(.anySearchable)
        }
        self.unknownTextFields = resolvedUnknownTextFields
        let normalizedName = LibrarySearchText.normalize(sortName)
        self.sortName = normalizedName.isEmpty ? id.uuidString.lowercased() : normalizedName
        self.folderPath = URL(fileURLWithPath: folderPath, isDirectory: true)
            .standardizedFileURL.path
        self.scannedAt = scannedAt
        self.contentDate = contentDate
        self.contentCalendarDate = contentCalendarDate
        self.contentCalendarDateInterval = contentCalendarDateInterval
            ?? contentCalendarDate.map(LibraryCalendarDateInterval.init)
        self.fileSizeBytes = fileSizeBytes.flatMap { $0 >= 0 ? $0 : nil }
        self.rollID = rollID
        self.filmType = filmType
        self.rating = min(max(rating, 0), 5)
        self.pickState = pickState
        self.availability = availability
        self.isVirtualCopy = isVirtualCopy
        self.hasInfraredCapture = hasInfraredCapture
        self.hasDefectRecipe = hasDefectRecipe
        self.scannerProfileState = scannerProfileState
        self.metadataPresentFields = metadataPresentFields
        self.metadataPresenceByField = Dictionary(uniqueKeysWithValues: LibraryMetadataField.allCases.map {
            field in
            let presence: LibraryMetadataPresence
            if metadataPresentFields.contains(field) {
                presence = .present
            } else if metadataUnknownFields.contains(field) {
                presence = .unknown
            } else {
                presence = .missing
            }
            return (field, presence)
        })
        self.metadataReadProblem = metadataReadProblem
        self.hasCreativeCalibrationAdjustments = hasCreativeCalibrationAdjustments
        self.exportState = exportState
        self.userEditState = userEditState
        self.defectReviewState = defectReviewState
        self.deviceCalibrationState = deviceCalibrationState
    }
}
