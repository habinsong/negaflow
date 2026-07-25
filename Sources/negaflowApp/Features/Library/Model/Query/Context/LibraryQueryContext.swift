import Foundation
import Chromabase
import ScannerKit

struct LibraryFolderQueryFact: Equatable, Sendable {
    let id: String
    let folderID: UUID?
    let title: String
}

struct LibraryQueryContext: Equatable, Sendable {
    let generation: UInt64
    let factsByFrameID: [UUID: LibraryFrameQueryFacts]
    let activeRollID: UUID?
    let folderFacts: [LibraryFolderQueryFact]

    init(
        generation: UInt64,
        facts: [LibraryFrameQueryFacts],
        activeRollID: UUID? = nil,
        folderFacts: [LibraryFolderQueryFact] = []
    ) {
        self.generation = generation
        self.factsByFrameID = Self.uniqueFacts(facts)
        self.activeRollID = activeRollID
        self.folderFacts = Self.uniqueFolderFacts(folderFacts)
    }

    @MainActor
    static func make(
        generation: UInt64,
        frames: [ScanFrame],
        folders: [LibraryFolder],
        rolls: [LibraryRoll],
        activeRollID: UUID?,
        scanSessions: [ScanSession],
        scannerProfiles: [ScannerProfile],
        availabilityByFrameID: [UUID: LibrarySourceAvailability],
        collectionNamesByFrameID: [UUID: [String]] = [:],
        exportStatesByFrameID: [UUID: LibraryExportState] = [:],
        userEditStatesByFrameID: [UUID: LibraryUserEditState] = [:],
        defectReviewStatesByFrameID: [UUID: LibraryDefectReviewState] = [:],
        deviceCalibrationStatesByFrameID: [UUID: LibraryDeviceCalibrationState] = [:]
    ) -> LibraryQueryContext {
        let rollIndex = makeRollResolutionIndex(rolls)
        let frameGroups = Dictionary(grouping: frames, by: \.id)
        let sessionGroups = Dictionary(grouping: scanSessions, by: \.id)
        let jobGroupsBySessionID = sessionGroups.reduce(
            into: [UUID: [UUID: [ScanJob]]]()
        ) { result, entry in
            guard entry.value.count == 1, let session = entry.value.first else { return }
            result[entry.key] = Dictionary(grouping: session.jobs, by: \.id)
        }
        let profileGroups = Dictionary(grouping: scannerProfiles, by: \.id)

        let facts = frames.map { frame -> LibraryFrameQueryFacts in
            let roll = rollIndex.rollByFrameID[frame.id]
            let profile = profileResolution(for: frame, groups: profileGroups)
            let device = resolvedCaptureDevice(
                for: frame,
                frameGroups: frameGroups,
                sessionGroups: sessionGroups,
                jobGroupsBySessionID: jobGroupsBySessionID
            )
            let metadata = MetadataSearchSnapshot(
                frame.sourceMetadata,
                overlay: frame.appMetadataOverlay
            )
            let folderPath = LibraryPresentation.normalizedFolderPath(
                LibraryPresentation.folderURL(for: frame)
            )
            let displayNames = searchLanguages.map { frame.displayName(language: $0) }
            let filmNames = [frame.filmType.rawValue, frame.filmType.displayName]
                + searchLanguages.map { frame.filmType.displayName(language: $0) }
                + [frame.params.filmStockDminID].compactMap { $0 }
            let profileText = profile.value.map {
                [$0.id, $0.displayName, $0.scanner, $0.kind, $0.filmKey]
            } ?? [frame.params.scannerProfileID].compactMap { $0 }
            let deviceText = device.value.map {
                [$0.id, $0.displayName, $0.vendor, $0.model]
                    + [$0.serialNumber, $0.firmwareVersion, $0.driverVersion].compactMap { $0 }
            } ?? []
            var unknownTextFields = metadata.unknownTextFields
            if rollIndex.unknownFrameIDs.contains(frame.id) {
                unknownTextFields.insert(.roll)
            }
            if !profile.knowledgeIsComplete {
                unknownTextFields.insert(.scannerProfile)
            }
            if !device.knowledgeIsComplete {
                unknownTextFields.insert(.scannerDevice)
            }
            if collectionNamesByFrameID[frame.id] == nil {
                unknownTextFields.insert(.collection)
            }
            let textValues: [LibraryTextField: [String]] = [
                .displayName: displayNames
                    + [frame.literalCustomDisplayName, frame.sourceFrameDisplayName].compactMap { $0 },
                .fileName: [frame.sourceFileNameWithExtension],
                .folder: [folderPath, URL(fileURLWithPath: folderPath).lastPathComponent],
                .roll: [roll?.name].compactMap { $0 },
                .film: filmNames,
                .camera: metadata.camera,
                .lens: metadata.lens,
                .keywords: metadata.keywords,
                .titleDescription: metadata.titleDescription,
                .scannerProfile: profileText,
                .scannerDevice: deviceText,
                .lightSourceProfile: [frame.params.lightSourceProfileID].compactMap { $0 },
                .collection: collectionNamesByFrameID[frame.id] ?? [],
                .anySearchable: metadata.allSearchable,
            ]
            let hasDefectRecipe = frame.defectEditsNeedRestore || !frame.defectEdits.isEmpty
            let reviewState = defectReviewStatesByFrameID[frame.id]
                ?? (hasDefectRecipe ? .unknown : .notRequired)

            return LibraryFrameQueryFacts(
                id: frame.id,
                textValues: textValues,
                unknownTextFields: unknownTextFields,
                sortName: frame.displayName(language: .english),
                folderPath: folderPath,
                scannedAt: frame.scannedAt,
                contentDate: metadata.contentDate,
                contentCalendarDate: metadata.contentCalendarDate,
                contentCalendarDateInterval: metadata.contentCalendarDateInterval,
                fileSizeBytes: frame.sourceFileSizeBytes,
                rollID: roll?.id,
                filmType: frame.filmType,
                rating: frame.rating,
                pickState: frame.pickState,
                availability: availabilityByFrameID[frame.id] ?? .unknown,
                isVirtualCopy: virtualCopyState(frame),
                hasInfraredCapture: frame.infraredScanURL != nil,
                hasDefectRecipe: hasDefectRecipe,
                scannerProfileState: profile.state,
                metadataPresentFields: metadata.presentFields,
                metadataUnknownFields: metadata.unknownFields,
                metadataReadProblem: metadata.hasReadProblem,
                hasCreativeCalibrationAdjustments: hasCreativeCalibrationAdjustments(frame.params),
                exportState: exportStatesByFrameID[frame.id] ?? .unknown,
                userEditState: userEditStatesByFrameID[frame.id] ?? .unknown,
                defectReviewState: reviewState,
                deviceCalibrationState: deviceCalibrationStatesByFrameID[frame.id] ?? .unknown
            )
        }

        return LibraryQueryContext(
            generation: generation,
            facts: facts,
            activeRollID: activeRollID,
            folderFacts: makeFolderFacts(folders: folders, frames: frames)
        )
    }

    private static func uniqueFacts(
        _ facts: [LibraryFrameQueryFacts]
    ) -> [UUID: LibraryFrameQueryFacts] {
        var result: [UUID: LibraryFrameQueryFacts] = [:]
        var duplicates = Set<UUID>()
        for fact in facts {
            guard !duplicates.contains(fact.id) else { continue }
            if result.updateValue(fact, forKey: fact.id) != nil {
                result.removeValue(forKey: fact.id)
                duplicates.insert(fact.id)
            }
        }
        return result
    }

    private static func uniqueFolderFacts(
        _ facts: [LibraryFolderQueryFact]
    ) -> [LibraryFolderQueryFact] {
        let groups = Dictionary(grouping: facts, by: \.id)
        return facts.filter { fact in
            groups[fact.id]?.count == 1
        }
    }
}
