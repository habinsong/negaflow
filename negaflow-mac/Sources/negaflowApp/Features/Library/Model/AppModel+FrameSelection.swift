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

    /// 이 프레임에 대한 일괄 동작이 몇 장을 대상으로 하는지. 드래그 배지처럼 표시에만 쓰는
    /// 값이라 실제 목록(`framesForContextAction`)을 만들지 않고 O(1)로 답한다.
    func contextActionFrameCount(for frame: ScanFrame) -> Int {
        selectedFrameIDs.contains(frame.id) ? selectedFrameIDs.count : 1
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
        // 취소만 하고 핸들은 남긴다 — handleSelectedFrameChange 가 이 루프의 정리를 기다린 뒤
        // 새 현상을 시작해야 "이미 진행 중"으로 오인돼 요청이 버려지지 않는다.
        selectedFrameDevelopTask?.cancel()
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
        if selectedFrameNeedsDevelopment(frame) || developmentWaitsForThumbnailSeed(frame) {
            let selectedID = frame.id
            // 방금 취소한 이전 선택 현상 루프가 정리(endFrame)될 때까지 기다린 뒤 시작한다.
            // 정리 전에 시작하면 beginFrame 이 "이미 진행 중"으로 보고 요청을 버리는데, 그 진행 중
            // 루프는 이미 취소돼 아무도 다시 렌더하지 않는다(프리뷰가 영영 갱신되지 않던 경로).
            let previousDevelopTask = selectedFrameDevelopTask
            selectedFrameDevelopTask = Task { [weak self, weak frame] in
                await previousDevelopTask?.value
                guard let self, let frame, !Task.isCancelled,
                      self.selectedFrameID == selectedID else { return }
                // 시드가 도는 동안 현상을 시작하면 같은 원본을 두 번 디코드한다 — 기다렸다가
                // 다시 판정한다. 기다리지 않고 요청을 버리면, 자동 현상이 꺼진 상태에서 방금
                // 가져와 선택된 사진은 아무도 현상하지 않아 시드 썸네일 해상도로 고착된다.
                if let seed = frame.initialThumbnailSeedTask {
                    await seed.value
                }
                guard !Task.isCancelled,
                      self.selectedFrameID == selectedID,
                      self.selectedFrameNeedsDevelopment(frame) else { return }
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

    /// 선택된 프레임이 지금 현상(또는 정착 마무리)을 필요로 하는가.
    ///  - 복원 직후처럼 현상 결과가 아예 없을 때
    ///  - 인터랙티브 프록시만 발행되고 정착 패스가 취소된 채 남았을 때(저화질 프리뷰 고착)
    ///  - 프루프 설정 세대가 표시본보다 앞설 때
    func selectedFrameNeedsDevelopment(_ frame: ScanFrame) -> Bool {
        guard frame.isSourceAvailable else {
            return frame.displayedSoftProofRevision != softProofConfigurationRevision
                && frame.hasDevelopedOnce
        }
        // 라이브러리에서 처음 선택하거나 가져왔다는 이유만으로 현상을 시작하지 않는다.
        // 한 번도 현상하지 않은 프레임은 폴더 일괄 적용 또는 현상 작업공간 진입이 명시적 시작점이다.
        if activeWorkspaceModule == .library, !frame.hasDevelopedOnce {
            return false
        }
        if frame.developedImage == nil {
            return frame.initialThumbnailSeedTask == nil
        }
        if !frame.developedIsSettled { return true }
        return frame.displayedSoftProofRevision != softProofConfigurationRevision
            && frame.hasDevelopedOnce
    }

    /// 시드가 끝나면 현상해야 하는 프레임인가.
    ///
    /// selectedFrameNeedsDevelopment 는 같은 원본을 두 번 디코드하지 않으려고 시드가 도는 동안
    /// false 를 돌려준다. 가져오기는 시드 태스크를 건 **직후** 그 사진을 선택하므로 선택 시점의
    /// 판정은 항상 false 다 — 그때 요청을 그냥 버리면 시드가 끝난 뒤 아무도 현상을 다시 걸지
    /// 않는다(자동 현상 OFF 가 기본값). 그래서 미루기만 하고 요청은 유지한다.
    func developmentWaitsForThumbnailSeed(_ frame: ScanFrame) -> Bool {
        guard frame.initialThumbnailSeedTask != nil,
              frame.isSourceAvailable,
              frame.developedImage == nil else { return false }
        return !(activeWorkspaceModule == .library && !frame.hasDevelopedOnce)
    }

    private func normalizedInteractionFrameIDs(_ orderedFrameIDs: [UUID]) -> [UUID] {
        let availableIDs = Set(libraryFramesByIDCache.keys)
        var seen = Set<UUID>()
        return orderedFrameIDs.filter { id in
            availableIDs.contains(id) && seen.insert(id).inserted
        }
    }
}
