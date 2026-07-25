import AppKit

extension AppModel {
    var rolls: [LibraryRoll] { rollStore.rolls }
    var activeRollID: UUID? { rollStore.activeRollID }
    var activeRoll: LibraryRoll? { rollStore.activeRoll }

    var selectedFrameID: UUID? {
        get { frameStore.selectedFrameID }
        set {
            selectedFrameIDs = newValue.map { [$0] } ?? []
            frameSelectionAnchorID = newValue
            activateFrame(newValue)
        }
    }

    var selectedFrames: [ScanFrame] {
        libraryFrameIDsSnapshot.compactMap { frameID in
            selectedFrameIDs.contains(frameID) ? libraryFramesByIDCache[frameID] : nil
        }
    }

    var interactionFrameIDs: [UUID] {
        normalizedInteractionFrameIDs(interactionScopeFrameIDs ?? frames.map(\.id))
    }

    var actionableFrame: ScanFrame? {
        guard let selectedFrameID,
              interactionFrameIDs.contains(selectedFrameID) else { return nil }
        return libraryFramesByIDCache[selectedFrameID]
    }

    var actionableSelectedFrames: [ScanFrame] {
        let selectedIDs = selectedFrameIDs
        let framesByID = libraryFramesByIDCache
        return interactionFrameIDs.compactMap { id in
            selectedIDs.contains(id) ? framesByID[id] : nil
        }
    }

    func isFrameSelected(_ frame: ScanFrame) -> Bool {
        selectedFrameIDs.contains(frame.id)
    }

    func selectFrame(
        _ frame: ScanFrame,
        orderedFrameIDs: [UUID],
        modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags
    ) {
        let orderedFrameIDs = normalizedInteractionFrameIDs(orderedFrameIDs)
        guard orderedFrameIDs.contains(frame.id) else { return }
        updateInteractionScope(orderedFrameIDs)
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift),
           let anchor = frameSelectionAnchorID,
           let anchorIndex = orderedFrameIDs.firstIndex(of: anchor),
           let targetIndex = orderedFrameIDs.firstIndex(of: frame.id) {
            let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
            selectedFrameIDs = Set(orderedFrameIDs[range])
            activateFrame(frame.id)
            return
        }

        if flags.contains(.command) {
            if selectedFrameIDs.contains(frame.id) {
                selectedFrameIDs.remove(frame.id)
            } else {
                selectedFrameIDs.insert(frame.id)
            }
            frameSelectionAnchorID = frame.id
            let activeID: UUID?
            if selectedFrameIDs.contains(frame.id) {
                activeID = frame.id
            } else if let current = frameStore.selectedFrameID, selectedFrameIDs.contains(current) {
                activeID = current
            } else {
                activeID = orderedFrameIDs.first(where: { selectedFrameIDs.contains($0) })
            }
            activateFrame(activeID)
            return
        }

        selectedFrameIDs = [frame.id]
        frameSelectionAnchorID = frame.id
        activateFrame(frame.id)
    }

    func clearFrameSelection() {
        selectedFrameIDs = []
        frameSelectionAnchorID = nil
        activateFrame(nil)
    }

    @discardableResult
    func selectMostRecentAvailableFrameIfNeeded() -> Bool {
        guard actionableFrame == nil else { return false }
        let scope = Set(interactionFrameIDs)
        let candidate = frames.enumerated()
            .filter { _, frame in
                !frame.isPreviewScan
                    && scope.contains(frame.id)
                    && isSourceAvailable(frame)
            }
            .max { lhs, rhs in
                if lhs.element.scannedAt == rhs.element.scannedAt {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.scannedAt < rhs.element.scannedAt
            }?
            .element
        guard let candidate else { return false }
        selectedFrameID = candidate.id
        return true
    }

    func includeFrameInInteractionScopeIfNeeded(_ frameID: UUID) {
        guard var interactionScopeFrameIDs,
              !interactionScopeFrameIDs.contains(frameID) else { return }
        interactionScopeFrameIDs.append(frameID)
        self.interactionScopeFrameIDs = interactionScopeFrameIDs
    }

    func updateInteractionScope(_ orderedFrameIDs: [UUID]) {
        let previouslyActionableFrameID = actionableFrame?.id
        let normalizedIDs = normalizedInteractionFrameIDs(orderedFrameIDs)
        if interactionScopeFrameIDs != normalizedIDs {
            interactionScopeFrameIDs = normalizedIDs
        }

        let scope = Set(normalizedIDs)
        let projectedSelection = selectedFrameIDs.intersection(scope)
        if selectedFrameIDs != projectedSelection {
            selectedFrameIDs = projectedSelection
        }
        let survivingActiveID = frameStore.selectedFrameID.flatMap { activeID in
            projectedSelection.contains(activeID) ? activeID : nil
        }
        if frameSelectionAnchorID.map(scope.contains) != true,
           !projectedSelection.isEmpty {
            frameSelectionAnchorID = survivingActiveID
                ?? normalizedIDs.first(where: { projectedSelection.contains($0) })
        } else if projectedSelection.isEmpty {
            frameSelectionAnchorID = nil
        }

        if let survivingActiveID {
            if previouslyActionableFrameID != survivingActiveID {
                handleSelectedFrameChange(from: nil)
            }
            return
        }
        activateFrame(normalizedIDs.first(where: { projectedSelection.contains($0) }))
    }

    func reconcileSelection(with orderedFrameIDs: [UUID]) {
        let normalizedIDs = normalizedInteractionFrameIDs(orderedFrameIDs)
        let scope = Set(normalizedIDs)
        let activeIsHidden = selectedFrameID.map { !scope.contains($0) } ?? false
        guard activeIsHidden || !selectedFrameIDs.isSubset(of: scope) else { return }
        updateInteractionScope(normalizedIDs)
    }

    func framesForContextAction(
        _ frame: ScanFrame,
        within orderedFrameIDs: [UUID]? = nil
    ) -> [ScanFrame] {
        let scopeIDs = normalizedInteractionFrameIDs(orderedFrameIDs ?? interactionFrameIDs)
        guard scopeIDs.contains(frame.id) else { return [] }
        if !selectedFrameIDs.contains(frame.id) { return [frame] }

        let framesByID = libraryFramesByIDCache
        return scopeIDs.compactMap { id in
            selectedFrameIDs.contains(id) ? framesByID[id] : nil
        }
    }

    func activateFrame(_ id: UUID?) {
        let oldValue = frameStore.selectedFrameID
        guard id != oldValue else { return }
        developController.cancelPendingDevelopRequest()
        selectedFrameDevelopTask?.cancel()
        selectedFrameDevelopTask = nil
        frameStore.selectedFrameID = id
        handleSelectedFrameChange(from: oldValue)
    }

    var selectedFrame: ScanFrame? { frameStore.selectedFrame }
    var residentCleanedRawIDs: [UUID] { frameCacheManager.residentCleanedRawIDs }
    var residentDevelopedIDs: [UUID] { frameCacheManager.residentDevelopedIDs }
    var maxResidentCleanedRaw: Int { frameCacheManager.maxResidentCleanedRaw }
    var maxResidentDeveloped: Int { frameCacheManager.maxResidentDeveloped }
    var processingActive: Bool { developController.processingActive }
    var processingDetail: String { developController.processingDetail }

    func handleSelectedFrameChange(from oldValue: UUID?) {
        if let previous = frames.first(where: { $0.id == oldValue }),
           previous.defectActive || previous.defectIsDetecting {
            cancelRegionDefect(previous)
        }
        guard let frame = actionableFrame else { return }
        guard restoreProofCopyConfigurationIfNeeded(for: frame) else {
            frame.destinationGamutOverlayImage = nil
            return
        }
        if !frame.defectEdits.isEmpty,
           frame.identityMatchedCleanedRawImage == nil,
           frame.identityMatchedCleanedRawDiskURL == nil,
           frame.cleanRawTask == nil {
            discardCleanedRaw(frame, preservingDefectSidecar: true)
            rebuildCleanedRaw(frame)
        }
        markDevelopedResident(frame)
        let softProofIsStale = frame.displayedSoftProofRevision != softProofConfigurationRevision
        let restoredDevelopmentIsMissing = frame.developedImage == nil
            && frame.initialThumbnailSeedTask == nil
            && frame.isSourceAvailable
        let selectedDevelopmentIsNeeded = restoredDevelopmentIsMissing
            || (softProofIsStale && frame.hasDevelopedOnce)
        if selectedDevelopmentIsNeeded {
            let selectedID = frame.id
            selectedFrameDevelopTask = Task { [weak self, weak frame] in
                guard let self, let frame,
                      self.selectedFrameID == selectedID else { return }
                await self.developFrame(
                    frame,
                    preserveThumbnail: true,
                    selectionBoundFrameID: selectedID
                )
            }
        } else if clippingOverlayEnabled,
                  frame.hasDevelopedOnce,
                  frame.clippingOverlayImage == nil {
            requestDevelop(frame)
        } else if destinationGamutWarningEnabled,
                  softProofEnabled,
                  destinationGamutWarningAvailable,
                  frame.hasDevelopedOnce,
                  frame.destinationGamutOverlayImage == nil {
            requestDevelop(frame)
        }
    }

    private func normalizedInteractionFrameIDs(_ orderedFrameIDs: [UUID]) -> [UUID] {
        let availableIDs = Set(libraryFramesByIDCache.keys)
        var seen = Set<UUID>()
        return orderedFrameIDs.filter { id in
            availableIDs.contains(id) && seen.insert(id).inserted
        }
    }
}
