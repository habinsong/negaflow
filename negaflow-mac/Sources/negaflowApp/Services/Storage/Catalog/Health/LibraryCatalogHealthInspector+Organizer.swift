import Foundation
import ScannerKit
import Chromabase

extension LibraryCatalogHealthInspector {
    static func inspectOrganizer(
        _ catalog: LibraryCatalog,
        frameIDCounts: [UUID: Int],
        includeWarnings: Bool,
        issues: inout [LibraryCatalogHealthIssue]
    ) {
        let manualIDCounts = Dictionary(grouping: catalog.manualCollections, by: \.id)
            .mapValues(\.count)
        for (collectionIndex, collection) in catalog.manualCollections.enumerated() {
            if manualIDCounts[collection.id, default: 0] > 1 {
                issues.append(issue(
                    .duplicateManualCollectionID,
                    .error,
                    collectionID: collection.id,
                    collectionIndex: collectionIndex
                ))
            }
            if !validOrganizerName(collection.name) {
                issues.append(issue(
                    .invalidManualCollectionName,
                    .error,
                    collectionID: collection.id,
                    collectionIndex: collectionIndex
                ))
            }
            let membershipCounts = Dictionary(grouping: collection.frameIDs, by: { $0 })
                .mapValues(\.count)
            for frameID in membershipCounts.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                if membershipCounts[frameID, default: 0] > 1 {
                    issues.append(issue(
                        .duplicateManualCollectionMembership,
                        .error,
                        frameID: frameID,
                        collectionID: collection.id,
                        collectionIndex: collectionIndex
                    ))
                }
                if frameIDCounts[frameID, default: 0] != 1 {
                    issues.append(issue(
                        .manualCollectionMissingFrame,
                        .error,
                        frameID: frameID,
                        collectionID: collection.id,
                        collectionIndex: collectionIndex
                    ))
                }
            }
        }

        let smartIDCounts = Dictionary(grouping: catalog.smartCollections, by: \.id)
            .mapValues(\.count)
        for (collectionIndex, collection) in catalog.smartCollections.enumerated() {
            if smartIDCounts[collection.id, default: 0] > 1 {
                issues.append(issue(
                    .duplicateSmartCollectionID,
                    .error,
                    collectionID: collection.id,
                    collectionIndex: collectionIndex
                ))
            }
            if !validOrganizerName(collection.name) {
                issues.append(issue(
                    .invalidSmartCollectionName,
                    .error,
                    collectionID: collection.id,
                    collectionIndex: collectionIndex
                ))
            }
            if includeWarnings, collection.definition.decodedDefinition() == nil {
                issues.append(issue(
                    .invalidSmartCollectionQuery,
                    .warning,
                    collectionID: collection.id,
                    collectionIndex: collectionIndex
                ))
            }
        }

        let savedIDCounts = Dictionary(grouping: catalog.savedSearches, by: \.id)
            .mapValues(\.count)
        for (savedSearchIndex, savedSearch) in catalog.savedSearches.enumerated() {
            if savedIDCounts[savedSearch.id, default: 0] > 1 {
                issues.append(issue(
                    .duplicateSavedSearchID,
                    .error,
                    savedSearchID: savedSearch.id,
                    savedSearchIndex: savedSearchIndex
                ))
            }
            if !validOrganizerName(savedSearch.name) {
                issues.append(issue(
                    .invalidSavedSearchName,
                    .error,
                    savedSearchID: savedSearch.id,
                    savedSearchIndex: savedSearchIndex
                ))
            }
            if includeWarnings, savedSearch.definition.decodedDefinition() == nil {
                issues.append(issue(
                    .invalidSavedSearchQuery,
                    .warning,
                    savedSearchID: savedSearch.id,
                    savedSearchIndex: savedSearchIndex
                ))
            }
        }
    }

    static func inspectWorkflowTracking(
        _ frame: LibraryFrameRecord,
        frameIndex: Int,
        exportEventIDCounts: [UUID: Int],
        issues: inout [LibraryCatalogHealthIssue]
    ) {
        let expectedRecipeSHA256 = try? LibraryDevelopRecipeFingerprint.sha256(
            filmType: frame.filmType,
            presetID: frame.presetID,
            params: frame.params,
            imageTransform: frame.imageTransform
        )
        let editTracking = frame.userEditTracking
        let validEditCoverage: Bool
        switch editTracking.coverage {
        case .legacyUnknown:
            validEditCoverage = editTracking.ingestRecipeSHA256 == nil
                && editTracking.revision == 0
        case .tracked:
            validEditCoverage = requiredSHA256(editTracking.ingestRecipeSHA256)
                && (editTracking.revision != 0
                    || editTracking.ingestRecipeSHA256 == editTracking.currentRecipeSHA256)
        }
        if !validEditCoverage
            || !requiredSHA256(editTracking.currentRecipeSHA256)
            || editTracking.currentRecipeSHA256 != expectedRecipeSHA256 {
            issues.append(issue(
                .invalidUserEditTracking,
                .error,
                frameID: frame.id,
                frameIndex: frameIndex
            ))
        }

        let exportTracking = frame.exportTracking
        var exportTrackingIsValid = exportTracking.coverage == .tracked
            || exportTracking.successfulEvents.isEmpty
        for (exportEventIndex, event) in exportTracking.successfulEvents.enumerated() {
            if exportEventIDCounts[event.id, default: 0] > 1 {
                issues.append(issue(
                    .duplicateExportEventID,
                    .error,
                    frameID: frame.id,
                    frameIndex: frameIndex,
                    exportEventID: event.id,
                    exportEventIndex: exportEventIndex
                ))
            }
            if !validExportEvent(event) {
                exportTrackingIsValid = false
            }
        }
        if !exportTrackingIsValid {
            issues.append(issue(
                .invalidExportTracking,
                .error,
                frameID: frame.id,
                frameIndex: frameIndex
            ))
        }

        if !validDefectReviewTracking(frame.defectReviewTracking) {
            issues.append(issue(
                .invalidDefectReviewTracking,
                .error,
                frameID: frame.id,
                frameIndex: frameIndex
            ))
        }
    }

    static func validExportEvent(_ event: LibraryExportEvent) -> Bool {
        let primaryPath = event.primaryOutputPath.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let artifactPaths = event.artifactPaths.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let standardizedArtifactPaths = artifactPaths.compactMap(standardizedAbsolutePath)
        guard let standardizedPrimaryPath = standardizedAbsolutePath(primaryPath),
              event.completedAt.timeIntervalSinceReferenceDate.isFinite,
              primaryPath == event.primaryOutputPath,
              !artifactPaths.isEmpty,
              artifactPaths == event.artifactPaths,
              standardizedArtifactPaths.count == artifactPaths.count,
              Set(standardizedArtifactPaths).count == artifactPaths.count,
              standardizedArtifactPaths.contains(standardizedPrimaryPath),
              validOrganizerName(event.formatRawValue),
              validSHA256(event.defectRecipeSHA256),
              validSHA256(event.exportRecipeSHA256),
              (event.exportRecipePresetID == nil || requiredSHA256(event.exportRecipeSHA256)),
              event.sourceIdentity.map(validSourceIdentity) ?? true else {
            return false
        }
        switch event.renderKind {
        case .developed:
            return requiredSHA256(event.developRecipeSHA256)
        case .rawSource:
            return event.developRecipeSHA256 == nil
                && event.defectRecipeSHA256 == nil
        }
    }

    static func validSourceIdentity(
        _ identity: RenderManifest.SourceIdentity
    ) -> Bool {
        identity.byteCount > 0 && requiredSHA256(identity.sha256)
    }

    static func validDefectReviewTracking(
        _ tracking: LibraryDefectReviewTracking
    ) -> Bool {
        let currentValuesPresent = [
            tracking.currentRecipeRevision != nil,
            tracking.currentRecipeSHA256 != nil,
            tracking.currentSourceIdentitySHA256 != nil,
        ]
        let reviewedValuesPresent = [
            tracking.reviewedRecipeRevision != nil,
            tracking.reviewedRecipeSHA256 != nil,
            tracking.reviewedSourceIdentitySHA256 != nil,
        ]
        let currentIsComplete = currentValuesPresent.allSatisfy { $0 }
            || currentValuesPresent.allSatisfy { !$0 }
        let reviewedIsComplete = reviewedValuesPresent.allSatisfy { $0 }
            || reviewedValuesPresent.allSatisfy { !$0 }
        guard currentIsComplete, reviewedIsComplete else { return false }

        if tracking.coverage == .legacyUnknown {
            return currentValuesPresent.allSatisfy { !$0 }
                && reviewedValuesPresent.allSatisfy { !$0 }
        }
        if let currentRevision = tracking.currentRecipeRevision {
            guard requiredSHA256(tracking.currentRecipeSHA256),
                  requiredSHA256(tracking.currentSourceIdentitySHA256) else {
                return false
            }
            if let reviewedRevision = tracking.reviewedRecipeRevision {
                guard reviewedRevision <= currentRevision,
                      requiredSHA256(tracking.reviewedRecipeSHA256),
                      requiredSHA256(tracking.reviewedSourceIdentitySHA256) else {
                    return false
                }
                if reviewedRevision == currentRevision {
                    return tracking.reviewedRecipeSHA256 == tracking.currentRecipeSHA256
                        && tracking.reviewedSourceIdentitySHA256
                            == tracking.currentSourceIdentitySHA256
                }
            }
            return true
        }
        return tracking.reviewedRecipeRevision == nil
    }

    static func validOrganizerName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
    }

    static func standardizedAbsolutePath(_ value: String) -> String? {
        guard NSString(string: value).isAbsolutePath else { return nil }
        return URL(fileURLWithPath: value).standardizedFileURL.path
    }


}
