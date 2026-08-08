import Foundation

extension AppModel {
    func moveSourceFiles(for requestedFrames: [ScanFrame], to destinationFolder: URL) {
        let sourcePairs = sourcePairs(for: requestedFrames)
        switch SourceMovePlanner.files(sourcePairs, to: destinationFolder) {
        case .success(let plan):
            Task { _ = await performSourceMove(plan) }
        case .failure(let error):
            reportSourceMovePlanError(error)
        }
    }

    func renameLibraryFolder(at sourceFolder: URL, to requestedName: String) {
        let name = FrameStorageNaming.sanitizeComponent(requestedName)
        guard !name.isEmpty else {
            statusMessage = text(AppLocalizedPhrase.sourceMoveFailedStatus)
            return
        }
        let destination = sourceFolder.deletingLastPathComponent()
            .appendingPathComponent(name, isDirectory: true)
        let memberFrames = frames.filter {
            LibraryPresentation.folderURL(for: $0) == sourceFolder.standardizedFileURL
        }
        let rollIDs = Set(memberFrames.compactMap { rollID(containing: $0.id) })
        let rollRename: (UUID, String)?
        if rollIDs.count == 1,
           let rollID = rollIDs.first,
           rolls.contains(where: { $0.id == rollID && $0.kind == .physical }) {
            rollRename = (rollID, name)
        } else {
            rollRename = nil
        }
        moveLibraryFolder(from: sourceFolder, to: destination, rollRename: rollRename)
    }

    private func moveLibraryFolder(
        from sourceFolder: URL,
        to destinationFolder: URL,
        rollRename: (UUID, String)? = nil
    ) {
        let containedFrames = frames.filter {
            Self.isSourceURL($0.rawScanURL, inside: sourceFolder)
        }
        switch SourceMovePlanner.folder(
            from: sourceFolder,
            to: destinationFolder,
            sources: sourcePairs(for: containedFrames)
        ) {
        case .success(let plan):
            Task { _ = await performSourceMove(plan, rollRename: rollRename) }
        case .failure(let error):
            reportSourceMovePlanError(error)
        }
    }

    @discardableResult
    func performSourceMove(
        _ plan: SourceMovePlan,
        rollRename: (UUID, String)? = nil
    ) async -> Bool {
        guard allowsLibraryMutation else { return false }
        isSourceMoveInProgress = true
        defer { isSourceMoveInProgress = false }
        guard beginAcknowledgedLibraryTransaction() else {
            statusMessage = text(AppLocalizedPhrase.sourceDeletionUnavailableStatus)
            return false
        }
        defer { endAcknowledgedLibraryTransaction() }

        let moves = plan.fileMoves
        let photoNumberAssignments = movedPhotoNumberAssignments(for: plan)
        let fileOutcome = await Task.detached(priority: .utility) {
            SourceMoveTransaction.move(moves)
        }.value
        guard case .moved(let rollbackToken) = fileOutcome else {
            switch fileOutcome {
            case .collision:
                statusMessage = text(AppLocalizedPhrase.sourceMoveCollisionStatus)
            case .sourceMissing:
                statusMessage = text(AppLocalizedPhrase.sourceMoveFailedStatus)
            case .failed(let rollbackFailures):
                statusMessage = text(AppLocalizedPhrase.sourceMoveFailedStatus)
                if !rollbackFailures.isEmpty {
                    statusMessage += "\n" + rollbackFailures.joined(separator: "\n")
                }
            case .moved:
                break
            }
            return false
        }

        let originalFolders = libraryFolders
        let originalRollState = rollStateSnapshot()
        let originalAssignments = scanRollAssignments
        let originalPhotoNames = applyMovedPhotoNumberAssignments(photoNumberAssignments)
        let applied = applySourceRelink(plan.relinkPlan, reprocess: false)
        var mutationSucceeded = applied.sourceCount == plan.sourceCount
        if mutationSucceeded, let rollRename {
            mutationSucceeded = rollStore.renamePhysicalRoll(
                id: rollRename.0,
                name: rollRename.1
            )
            if mutationSucceeded {
                for index in scanRollAssignments.indices
                    where scanRollAssignments[index].rollID == rollRename.0 {
                    scanRollAssignments[index].draftName = rollRename.1
                }
            }
        }
        let commitSucceeded = mutationSucceeded && {
            if case .success = commitAcknowledgedLibrarySnapshot(
                frames: frames,
                rolls: rolls,
                activeRollID: activeRollID,
                scanSessions: scanSessions,
                scanRollAssignments: scanRollAssignments
            ) {
                return true
            }
            return false
        }()

        guard commitSucceeded else {
            let rollbackFailures = await Task.detached(priority: .utility) {
                SourceMoveTransaction.rollback(rollbackToken)
            }.value
            libraryFolders = originalFolders
            replaceRollState(with: originalRollState)
            scanRollAssignments = originalAssignments
            restorePhotoNumberAssignments(originalPhotoNames)
            if rollbackFailures.isEmpty {
                _ = applySourceRelink(plan.inverseRelinkPlan, reprocess: false)
                libraryFolders = originalFolders
            }
            statusMessage = text(AppLocalizedPhrase.sourceMoveCatalogFailedStatus)
            if !rollbackFailures.isEmpty {
                statusMessage += "\n" + rollbackFailures.joined(separator: "\n")
            }
            return false
        }

        if let oldFolder = plan.relinkPlan.oldFolderURL?.standardizedFileURL,
           let newFolder = plan.relinkPlan.newFolderURL?.standardizedFileURL,
           diskStorage.recentCreatedScanFolderURL?.standardizedFileURL == oldFolder {
            diskStorage.recentCreatedScanFolderPath = newFolder.path
        }
        acknowledgeCurrentLibraryStateMatchesCommittedSnapshot()
        let destinationPaths = Set(plan.relinkPlan.mappings.map {
            $0.newSourceURL.standardizedFileURL.path
        })
        let affectedFrames = frames.filter {
            destinationPaths.contains($0.rawScanURL.standardizedFileURL.path)
        }
        refreshSourceAvailability()
        for frame in affectedFrames {
            if frame.defectEdits.isEmpty {
                Task { await developFrame(frame, preserveThumbnail: true) }
            } else {
                rebuildCleanedRaw(frame)
            }
        }
        statusMessage = text(AppLocalizedPhrase.sourceMoveCompleteFormat, plan.sourceCount)
        return true
    }

    private func sourcePairs(for requestedFrames: [ScanFrame]) -> [SourceMovePlanner.SourcePair] {
        Dictionary(grouping: requestedFrames, by: {
            $0.rawScanURL.standardizedFileURL.path
        })
        .values
        .compactMap { family in
            guard let frame = family.first else { return nil }
            return SourceMovePlanner.SourcePair(
                rawURL: frame.rawScanURL,
                infraredURL: family.compactMap(\.infraredScanURL).first
            )
        }
    }

    private func reportSourceMovePlanError(_ error: SourceMovePlanError) {
        statusMessage = error == .collision
            ? text(AppLocalizedPhrase.sourceMoveCollisionStatus)
            : text(AppLocalizedPhrase.sourceMoveFailedStatus)
    }

    private nonisolated static func isSourceURL(_ url: URL, inside folder: URL) -> Bool {
        let folderComponents = folder.standardizedFileURL.pathComponents
        let sourceComponents = url.standardizedFileURL.pathComponents
        return sourceComponents.count > folderComponents.count
            && Array(sourceComponents.prefix(folderComponents.count)) == folderComponents
    }
}
