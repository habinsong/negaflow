import Foundation
import ScannerKit
import Chromabase

enum LibraryCatalogHealthInspector {

    static func inspect(
        _ catalog: LibraryCatalog,
        defectDirectory: URL = DefectSidecarFile.defaultDirectoryURL(),
        cleanedRawDirectory: URL = CleanedRawCacheFile.defaultDirectoryURL(),
        fileManager: FileManager = .default,
        includeWarnings: Bool = true,
        validatedPreviousCatalog: LibraryCatalog? = nil
    ) -> LibraryCatalogHealthReport {
        var issues: [LibraryCatalogHealthIssue] = []
        let frameIDs = Set(catalog.frames.map(\.id))
        let framesByID = Dictionary(grouping: catalog.frames, by: \.id)
        let frameIDCounts = framesByID
            .mapValues(\.count)
        let rollIDCounts = Dictionary(grouping: catalog.rolls, by: \.id)
            .mapValues(\.count)
        let exportEventIDCounts = Dictionary(
            grouping: catalog.frames.flatMap(\.exportTracking.successfulEvents),
            by: \.id
        ).mapValues(\.count)
        var rollMemberships: [UUID: [(rollID: UUID, rollIndex: Int)]] = [:]
        let previousFrames: [LibraryFrameRecord]?
        if let validatedPreviousCatalog,
           validatedPreviousCatalog.frames.count == catalog.frames.count,
           zip(validatedPreviousCatalog.frames, catalog.frames).allSatisfy({
               $0.0.id == $0.1.id
           }) {
            previousFrames = validatedPreviousCatalog.frames
        } else {
            previousFrames = nil
        }

        if includeWarnings {
            for (index, path) in catalog.folders.enumerated() {
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    issues.append(issue(.emptyFolder, .warning, folderIndex: index))
                } else if !fileManager.fileExists(atPath: URL(fileURLWithPath: path).path) {
                    issues.append(issue(.offlineFolder, .warning, folderIndex: index))
                }
            }
            let duplicateFolders = Dictionary(
                grouping: catalog.folders.enumerated(),
                by: { URL(fileURLWithPath: $0.element).standardizedFileURL.path }
            ).values.flatMap { entries in
                entries.count > 1 ? entries.dropFirst().map(\.offset) : []
            }.sorted()
            for index in duplicateFolders {
                issues.append(issue(.duplicateFolder, .warning, folderIndex: index))
            }
        }

        inspectOrganizer(
            catalog,
            frameIDCounts: frameIDCounts,
            includeWarnings: includeWarnings,
            issues: &issues
        )
        issues.append(contentsOf: LibraryCatalogStackHealthInspector.inspect(
            catalog,
            frameIDCounts: frameIDCounts
        ))

        for (rollIndex, roll) in catalog.rolls.enumerated() {
            if rollIDCounts[roll.id, default: 0] > 1 {
                issues.append(issue(
                    .duplicateRollID,
                    .error,
                    rollID: roll.id,
                    rollIndex: rollIndex
                ))
            }
            switch roll.kind {
            case .physical:
                let hasName = roll.name?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty == false
                if roll.id == LibraryRoll.unassignedID || !hasName || roll.filmType == nil {
                    issues.append(issue(
                        .invalidPhysicalRoll,
                        .error,
                        rollID: roll.id,
                        rollIndex: rollIndex
                    ))
                }
            case .unassigned:
                if roll.id != LibraryRoll.unassignedID || roll.name != nil || roll.filmType != nil {
                    issues.append(issue(
                        .invalidUnassignedRoll,
                        .error,
                        rollID: roll.id,
                        rollIndex: rollIndex
                    ))
                }
            }

            for frameID in roll.frameIDs {
                rollMemberships[frameID, default: []].append((roll.id, rollIndex))
                if !frameIDs.contains(frameID) {
                    issues.append(issue(
                        .rollReferencesMissingFrame,
                        .error,
                        frameID: frameID,
                        rollID: roll.id,
                        rollIndex: rollIndex
                    ))
                }
            }
        }

        if let activeRollID = catalog.activeRollID {
            let matches = catalog.rolls.enumerated().filter { $0.element.id == activeRollID }
            if matches.isEmpty {
                issues.append(issue(.missingActiveRoll, .error, rollID: activeRollID))
            } else if matches.count == 1, matches[0].element.kind != .physical {
                issues.append(issue(
                    .activeRollNotPhysical,
                    .error,
                    rollID: activeRollID,
                    rollIndex: matches[0].offset
                ))
            }
        }

        inspectScanWorkflow(
            catalog,
            rollMemberships: rollMemberships,
            issues: &issues
        )

        for (frameIndex, frame) in catalog.frames.enumerated() {
            if frameIDCounts[frame.id, default: 0] > 1 {
                issues.append(issue(
                    .duplicateFrameID,
                    .error,
                    frameID: frame.id,
                    frameIndex: frameIndex
                ))
            }
            let memberships = rollMemberships[frame.id, default: []]
            if memberships.isEmpty {
                issues.append(issue(
                    .frameMissingRollMembership,
                    .error,
                    frameID: frame.id,
                    frameIndex: frameIndex
                ))
            } else if memberships.count > 1 {
                issues.append(issue(
                    .duplicateRollMembership,
                    .error,
                    frameID: frame.id,
                    frameIndex: frameIndex
                ))
            }
            if previousFrames?[frameIndex] != frame {
                inspectFrame(
                    frame,
                    frameIndex: frameIndex,
                    allFrameIDs: frameIDs,
                    defectDirectory: defectDirectory,
                    cleanedRawDirectory: cleanedRawDirectory,
                    fileManager: fileManager,
                    includeWarnings: includeWarnings,
                    issues: &issues
                )
                inspectWorkflowTracking(
                    frame,
                    frameIndex: frameIndex,
                    exportEventIDCounts: exportEventIDCounts,
                    issues: &issues
                )
            }
        }
        for (frameIndex, frame) in catalog.frames.enumerated() {
            guard let sourceFrameID = frame.sourceFrameID,
                  frameIDs.contains(sourceFrameID) else { continue }
            let frameMembership = rollMemberships[frame.id, default: []]
            let sourceMembership = rollMemberships[sourceFrameID, default: []]
            if frameMembership.count == 1,
               sourceMembership.count == 1,
               frameMembership[0].rollIndex != sourceMembership[0].rollIndex {
                issues.append(issue(
                    .splitVirtualCopyFamily,
                    .error,
                    frameID: frame.id,
                    frameIndex: frameIndex,
                    rollID: frameMembership[0].rollID,
                    rollIndex: frameMembership[0].rollIndex
                ))
            }
            if let sourceFrames = framesByID[sourceFrameID],
               sourceFrames.count == 1,
               frame.sourceMetadata != sourceFrames[0].sourceMetadata {
                issues.append(issue(
                    .inconsistentVirtualCopyMetadata,
                    .error,
                    frameID: frame.id,
                    frameIndex: frameIndex
                ))
            }
        }
        issues.sort(by: issueSort)
        return LibraryCatalogHealthReport(
            catalogVersion: catalog.version,
            frameCount: catalog.frames.count,
            rollCount: catalog.rolls.count,
            folderCount: catalog.folders.count,
            issues: issues
        )
    }


}
