import Combine
import Foundation
import Chromabase

private struct LibraryFrameWorkflowQueryStates {
    let export: LibraryExportState
    let userEdit: LibraryUserEditState
    let defectReview: LibraryDefectReviewState

    @MainActor
    init(frame: ScanFrame) {
        let tracking = frame.libraryWorkflowTrackingState
        export = Self.exportState(tracking?.exportTracking)
        userEdit = Self.userEditState(frame: frame, tracking: tracking)
        defectReview = Self.defectReviewState(
            tracking?.defectReviewTracking,
            hasRecipe: frame.defectEditsNeedRestore || !frame.defectEdits.isEmpty
        )
    }

    private static func exportState(
        _ tracking: LibraryExportTracking?
    ) -> LibraryExportState {
        guard let tracking, tracking.coverage == .tracked else { return .unknown }
        return tracking.successfulEvents.isEmpty ? .never : .succeeded
    }

    @MainActor
    private static func userEditState(
        frame: ScanFrame,
        tracking: LibraryFrameWorkflowTrackingState?
    ) -> LibraryUserEditState {
        guard let tracking,
              let currentRecipeSHA256 = frame.currentLibraryDevelopRecipeSHA256(),
              let current = tracking.reconciled(
                  currentRecipeSHA256: currentRecipeSHA256
              )?.userEditTracking,
              current.coverage == .tracked,
              let ingestRecipeSHA256 = current.ingestRecipeSHA256,
              let trackedRecipeSHA256 = current.currentRecipeSHA256,
              validSHA256(ingestRecipeSHA256),
              validSHA256(trackedRecipeSHA256),
              current.revision != 0 || ingestRecipeSHA256 == trackedRecipeSHA256 else {
            return .unknown
        }
        return ingestRecipeSHA256 == trackedRecipeSHA256 ? .unedited : .edited
    }

    private static func defectReviewState(
        _ tracking: LibraryDefectReviewTracking?,
        hasRecipe: Bool
    ) -> LibraryDefectReviewState {
        guard hasRecipe else { return .notRequired }
        guard let tracking, tracking.coverage == .tracked else { return .unknown }
        let currentPresence = [
            tracking.currentRecipeRevision != nil,
            tracking.currentRecipeSHA256 != nil,
            tracking.currentSourceIdentitySHA256 != nil,
        ]
        guard currentPresence.allSatisfy({ $0 }) else { return .unknown }
        guard let currentRevision = tracking.currentRecipeRevision,
              let currentRecipeSHA256 = tracking.currentRecipeSHA256,
              let currentSourceIdentitySHA256 = tracking.currentSourceIdentitySHA256,
              validSHA256(currentRecipeSHA256),
              validSHA256(currentSourceIdentitySHA256) else { return .unknown }

        let reviewedPresence = [
            tracking.reviewedRecipeRevision != nil,
            tracking.reviewedRecipeSHA256 != nil,
            tracking.reviewedSourceIdentitySHA256 != nil,
        ]
        if reviewedPresence.allSatisfy({ !$0 }) { return .needsReview }
        guard reviewedPresence.allSatisfy({ $0 }),
              let reviewedRevision = tracking.reviewedRecipeRevision,
              let reviewedRecipeSHA256 = tracking.reviewedRecipeSHA256,
              let reviewedSourceIdentitySHA256 = tracking.reviewedSourceIdentitySHA256,
              reviewedRevision <= currentRevision,
              validSHA256(reviewedRecipeSHA256),
              validSHA256(reviewedSourceIdentitySHA256) else { return .unknown }
        guard reviewedRevision == currentRevision else { return .needsReview }
        guard reviewedRecipeSHA256 == currentRecipeSHA256,
              reviewedSourceIdentitySHA256 == currentSourceIdentitySHA256 else {
            return .unknown
        }
        return .reviewed
    }

    private static func validSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

struct LibraryFrameQueryObservation {
    let values: AnyCancellable
    let sourceLocation: AnyCancellable
}

struct LibraryBrowserProjectionCache {
    let generation: UInt64
    let sourceFrameIDs: [UUID]
    let query: LibraryQuery
    let sort: LibrarySortDescriptor
    let projection: LibraryBrowserProjection

    func reusedProjection(
        sourceFrameIDs: [UUID],
        query nextQuery: LibraryQuery,
        context: LibraryQueryContext,
        sort nextSort: LibrarySortDescriptor
    ) -> LibraryBrowserProjection? {
        guard generation == context.generation,
              projection.contextGeneration == generation,
              self.sourceFrameIDs == sourceFrameIDs,
              sort == nextSort else {
            return nil
        }
        if query == nextQuery { return projection }
        guard projection.queryWasValid,
              let refinement = LibraryQueryTextRefinement.make(
                previous: query,
                next: nextQuery
              ) else {
            return nil
        }
        return projection.refining(with: refinement, context: context)
    }
}

struct LibraryFolderTreeProjectionCache {
    let revision: UInt64
    let orderedFrameIDs: [UUID]?
    let sections: [LibraryFolderSection]
}

private struct LibrarySourceAvailabilityProbe: Sendable, Equatable {
    let frameID: UUID
    let path: String
}

private struct LibraryFolderAvailabilityProbe: Sendable, Equatable {
    let folderID: UUID
    let path: String
}

extension AppModel {
    private static let asynchronousSourceAvailabilityThreshold = 256

    func makeLibraryBrowserProjection(
        sourceFrameIDs requestedSourceFrameIDs: [UUID]? = nil,
        query: LibraryQuery,
        sort: LibrarySortDescriptor
    ) -> LibraryBrowserProjection {
        let sourceFrameIDs = requestedSourceFrameIDs ?? libraryFrameIDsSnapshot
        let context = makeLibraryQueryContext()
        if let projection = libraryBrowserProjectionCache?.reusedProjection(
            sourceFrameIDs: sourceFrameIDs,
            query: query,
            context: context,
            sort: sort
        ) {
            if libraryBrowserProjectionCache?.query != query {
                libraryBrowserProjectionCache = LibraryBrowserProjectionCache(
                    generation: libraryQueryGeneration,
                    sourceFrameIDs: sourceFrameIDs,
                    query: query,
                    sort: sort,
                    projection: projection
                )
            }
            return projection
        }
        let projection = LibraryBrowserProjection.make(
            sourceFrameIDs: sourceFrameIDs,
            query: query,
            context: context,
            sort: sort
        )
        libraryBrowserProjectionCache = LibraryBrowserProjectionCache(
            generation: libraryQueryGeneration,
            sourceFrameIDs: sourceFrameIDs,
            query: query,
            sort: sort,
            projection: projection
        )
        return projection
    }

    func makeLibraryQueryContext() -> LibraryQueryContext {
        if let cached = libraryQueryContextCache,
           cached.generation == libraryQueryGeneration {
            return cached
        }
        let workflowStates = libraryWorkflowQueryStatesByFrameID()
        let context = LibraryQueryContext.make(
            generation: libraryQueryGeneration,
            frames: frames,
            folders: libraryFolders,
            rolls: rolls,
            activeRollID: activeRollID,
            scanSessions: scanSessions,
            scannerProfiles: scannerProfiles,
            availabilityByFrameID: currentLibrarySourceAvailabilitySnapshot(),
            collectionNamesByFrameID: manualCollectionNamesByFrameID(),
            exportStatesByFrameID: workflowStates.mapValues(\.export),
            userEditStatesByFrameID: workflowStates.mapValues(\.userEdit),
            defectReviewStatesByFrameID: workflowStates.mapValues(\.defectReview)
        )
        libraryQueryContextCache = context
        return context
    }

    func librarySourceAvailability(for frame: ScanFrame) -> LibrarySourceAvailability {
        librarySourceAvailabilityCache?[frame.id] ?? .unknown
    }

    func uniqueLibraryFramesByID() -> [UUID: ScanFrame] {
        libraryFramesByIDCache
    }

    func makeLibraryFolderTreeSections(
        orderedFrameIDs: [UUID]?
    ) -> [LibraryFolderSection] {
        if let cached = libraryFolderTreeProjectionCache,
           cached.revision == libraryFolderProjectionRevision,
           cached.orderedFrameIDs == orderedFrameIDs {
            return cached.sections
        }
        let baseSections: [LibraryFolderSection]
        if let cached = libraryFolderSectionsCache {
            baseSections = cached
        } else {
            let orderedFrames = libraryFrameIDsSnapshot.compactMap { libraryFramesByIDCache[$0] }
            let built = LibraryPresentation.folderSections(
                frames: orderedFrames,
                folders: libraryFolders,
                sortKey: .inputOrder,
                ascending: true
            )
            libraryFolderSectionsCache = built
            baseSections = built
        }
        let projected = LibraryPresentation.projectedFolderSections(
            baseSections,
            orderedFrameIDs: orderedFrameIDs
        )
        libraryFolderTreeProjectionCache = LibraryFolderTreeProjectionCache(
            revision: libraryFolderProjectionRevision,
            orderedFrameIDs: orderedFrameIDs,
            sections: projected
        )
        return projected
    }

    func invalidateLibraryQueryContext() {
        libraryQueryContextCache = nil
        libraryBrowserProjectionCache = nil
        advanceLibraryQueryGeneration()
    }

    func refreshLibraryFrameQueryObservations(_ currentFrames: [ScanFrame]) {
        rebuildLibraryFrameIdentitySnapshot(currentFrames)
        var observations: [UUID: LibraryFrameQueryObservation] = [:]
        for frame in currentFrames {
            observations[frame.id] = frameQueryObservations[frame.id]
                ?? observeLibraryQueryChanges(frame)
        }
        frameQueryObservations = observations
        if currentFrames.count > Self.asynchronousSourceAvailabilityThreshold {
            scheduleLibrarySourceAvailabilitySnapshot(currentFrames)
        } else {
            rebuildLibrarySourceAvailabilitySnapshot(currentFrames)
        }
        invalidateLibraryQueryContext()
    }

    private func observeLibraryQueryChanges(
        _ frame: ScanFrame
    ) -> LibraryFrameQueryObservation {
        let valueChanges = Publishers.MergeMany([
            frame.$infraredScanURL.map { $0 != nil }.removeDuplicates().dropFirst()
                .map { _ in () }.eraseToAnyPublisher(),
            frame.$filmType.removeDuplicates().dropFirst()
                .map { _ in () }.eraseToAnyPublisher(),
            frame.$preset.map { $0?.id }.removeDuplicates().dropFirst()
                .map { _ in () }.eraseToAnyPublisher(),
            frame.$params.removeDuplicates().dropFirst()
                .map { _ in () }.eraseToAnyPublisher(),
            frame.$imageTransform.removeDuplicates().dropFirst()
                .map { _ in () }.eraseToAnyPublisher(),
            frame.$libraryWorkflowTrackingState.removeDuplicates().dropFirst()
                .map { _ in () }.eraseToAnyPublisher(),
            frame.$rating.removeDuplicates().dropFirst()
                .map { _ in () }.eraseToAnyPublisher(),
            frame.$pickState.removeDuplicates().dropFirst()
                .map { _ in () }.eraseToAnyPublisher(),
            frame.$customDisplayName.removeDuplicates().dropFirst()
                .map { _ in () }.eraseToAnyPublisher(),
            frame.$defectEdits.map { !$0.isEmpty }.removeDuplicates().dropFirst()
                .map { _ in () }.eraseToAnyPublisher(),
        ])
        .sink { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.invalidateLibraryQueryContext() }
        }
        let frameID = frame.id
        let sourceLocationChanges = frame.$rawScanURL.dropFirst().sink { [weak self] url in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.updateLibrarySourceAvailability(frameID: frameID, sourceURL: url)
                self.invalidateLibraryFolderProjection()
                self.invalidateLibraryQueryContext()
            }
        }
        return LibraryFrameQueryObservation(
            values: valueChanges,
            sourceLocation: sourceLocationChanges
        )
    }

    func rebuildLibrarySourceAvailabilitySnapshot(_ currentFrames: [ScanFrame]? = nil) {
        sourceAvailabilityRefreshTask?.cancel()
        sourceAvailabilityRefreshTask = nil
        sourceAvailabilityRefreshID = UUID()
        let currentFrames = currentFrames ?? frames
        var availabilityByPath: [String: LibrarySourceAvailability] = [:]
        var result: [UUID: LibrarySourceAvailability] = [:]
        result.reserveCapacity(currentFrames.count)
        for frame in currentFrames {
            let path = frame.rawScanURL.standardizedFileURL.path
            let availability = availabilityByPath[path] ?? {
                FileManager.default.fileExists(atPath: path) ? .online : .offline
            }()
            availabilityByPath[path] = availability
            result[frame.id] = availability
        }
        librarySourceAvailabilityCache = result
    }

    /// 원본 존재 확인은 외장 디스크·네트워크 볼륨에서 오래 막힐 수 있으므로 프레임 publish 경로의
    /// MainActor에서 실행하지 않는다. 요청 ID와 현재 frame/path를 모두 확인한 최신 결과만 반영한다.
    private func scheduleLibrarySourceAvailabilitySnapshot(_ currentFrames: [ScanFrame]) {
        sourceAvailabilityRefreshTask?.cancel()
        let refreshID = UUID()
        sourceAvailabilityRefreshID = refreshID
        let probes = currentFrames.map {
            LibrarySourceAvailabilityProbe(
                frameID: $0.id,
                path: $0.rawScanURL.standardizedFileURL.path
            )
        }
        let currentIDs = Set(probes.map(\.frameID))
        var pending = (librarySourceAvailabilityCache ?? [:]).filter {
            currentIDs.contains($0.key)
        }
        for probe in probes where pending[probe.frameID] == nil {
            pending[probe.frameID] = .unknown
        }
        librarySourceAvailabilityCache = pending

        sourceAvailabilityRefreshTask = Task { [weak self] in
            let probeTask = Task.detached(priority: .utility) {
                () -> [UUID: LibrarySourceAvailability]? in
                var availabilityByPath: [String: LibrarySourceAvailability] = [:]
                var result: [UUID: LibrarySourceAvailability] = [:]
                result.reserveCapacity(probes.count)
                for probe in probes {
                    guard !Task.isCancelled else { return nil }
                    let availability = availabilityByPath[probe.path] ?? (
                        FileManager.default.fileExists(atPath: probe.path) ? .online : .offline
                    )
                    availabilityByPath[probe.path] = availability
                    result[probe.frameID] = availability
                }
                return result
            }
            let result = await withTaskCancellationHandler {
                await probeTask.value
            } onCancel: {
                probeTask.cancel()
            }
            guard let self, !Task.isCancelled,
                  self.sourceAvailabilityRefreshID == refreshID,
                  let result else { return }
            let currentProbes = self.frames.map {
                LibrarySourceAvailabilityProbe(
                    frameID: $0.id,
                    path: $0.rawScanURL.standardizedFileURL.path
                )
            }
            guard currentProbes == probes else { return }
            self.librarySourceAvailabilityCache = result
            self.sourceAvailabilityRefreshTask = nil
            self.advanceSourceAvailabilityRevision()
            self.invalidateLibraryQueryContext()
        }
    }

    func rebuildLibraryFolderAvailabilitySnapshot(
        _ currentFolders: [LibraryFolder]? = nil
    ) {
        folderAvailabilityRefreshTask?.cancel()
        folderAvailabilityRefreshTask = nil
        folderAvailabilityRefreshID = UUID()
        let currentFolders = currentFolders ?? libraryFolders
        var snapshot: [UUID: Bool] = [:]
        var duplicates = Set<UUID>()
        for folder in currentFolders {
            guard !duplicates.contains(folder.id) else { continue }
            let available = FileManager.default.fileExists(atPath: folder.url.path)
            if snapshot.updateValue(available, forKey: folder.id) != nil {
                snapshot.removeValue(forKey: folder.id)
                duplicates.insert(folder.id)
            }
        }
        libraryFolderAvailabilityCache = snapshot
    }

    func scheduleLibraryFolderAvailabilitySnapshot(_ currentFolders: [LibraryFolder]) {
        folderAvailabilityRefreshTask?.cancel()
        let refreshID = UUID()
        folderAvailabilityRefreshID = refreshID
        var probes: [LibraryFolderAvailabilityProbe] = []
        var seenIDs = Set<UUID>()
        var duplicateIDs = Set<UUID>()
        for folder in currentFolders {
            guard !duplicateIDs.contains(folder.id) else { continue }
            guard seenIDs.insert(folder.id).inserted else {
                duplicateIDs.insert(folder.id)
                probes.removeAll { $0.folderID == folder.id }
                continue
            }
            probes.append(LibraryFolderAvailabilityProbe(
                folderID: folder.id,
                path: folder.url.standardizedFileURL.path
            ))
        }
        let currentIDs = Set(probes.map(\.folderID))
        libraryFolderAvailabilityCache = libraryFolderAvailabilityCache.filter {
            currentIDs.contains($0.key)
        }
        let availabilityProbes = probes
        let duplicateFolderIDs = duplicateIDs

        folderAvailabilityRefreshTask = Task { [weak self] in
            let probeTask = Task.detached(priority: .utility) {
                () -> [UUID: Bool]? in
                var result: [UUID: Bool] = [:]
                result.reserveCapacity(availabilityProbes.count)
                for probe in availabilityProbes {
                    guard !Task.isCancelled else { return nil }
                    result[probe.folderID] = FileManager.default.fileExists(atPath: probe.path)
                }
                return result
            }
            let result = await withTaskCancellationHandler {
                await probeTask.value
            } onCancel: {
                probeTask.cancel()
            }
            guard let self, !Task.isCancelled,
                  self.folderAvailabilityRefreshID == refreshID,
                  let result else { return }
            let currentProbes = self.libraryFolders.compactMap { folder -> LibraryFolderAvailabilityProbe? in
                guard !duplicateFolderIDs.contains(folder.id) else { return nil }
                return LibraryFolderAvailabilityProbe(
                    folderID: folder.id,
                    path: folder.url.standardizedFileURL.path
                )
            }
            guard currentProbes == availabilityProbes else { return }
            self.libraryFolderAvailabilityCache = result
            self.folderAvailabilityRefreshTask = nil
            self.advanceSourceAvailabilityRevision()
            self.invalidateLibraryQueryContext()
        }
    }

    private func updateLibrarySourceAvailability(frameID: UUID, sourceURL: URL) {
        var snapshot = librarySourceAvailabilityCache ?? [:]
        snapshot[frameID] = FileManager.default.fileExists(
            atPath: sourceURL.standardizedFileURL.path
        ) ? .online : .offline
        librarySourceAvailabilityCache = snapshot
    }

    private func currentLibrarySourceAvailabilitySnapshot() -> [UUID: LibrarySourceAvailability] {
        if let librarySourceAvailabilityCache { return librarySourceAvailabilityCache }
        return Dictionary(uniqueKeysWithValues: libraryFramesByIDCache.keys.map { ($0, .unknown) })
    }

    private func libraryWorkflowQueryStatesByFrameID() -> [UUID: LibraryFrameWorkflowQueryStates] {
        var states: [UUID: LibraryFrameWorkflowQueryStates] = [:]
        var duplicates = Set<UUID>()
        for frame in frames where !duplicates.contains(frame.id) {
            if states.updateValue(
                LibraryFrameWorkflowQueryStates(frame: frame),
                forKey: frame.id
            ) != nil {
                states.removeValue(forKey: frame.id)
                duplicates.insert(frame.id)
            }
        }
        return states
    }

    private func rebuildLibraryFrameIdentitySnapshot(_ currentFrames: [ScanFrame]) {
        libraryFrameIDsSnapshot = currentFrames.map(\.id)
        var framesByID: [UUID: ScanFrame] = [:]
        var duplicates = Set<UUID>()
        for frame in currentFrames where !duplicates.contains(frame.id) {
            if framesByID.updateValue(frame, forKey: frame.id) != nil {
                framesByID.removeValue(forKey: frame.id)
                duplicates.insert(frame.id)
            }
        }
        libraryFramesByIDCache = framesByID
        invalidateLibraryFolderProjection()
    }

    func invalidateLibraryFolderProjection() {
        libraryFolderProjectionRevision &+= 1
        libraryFolderSectionsCache = nil
        libraryFolderTreeProjectionCache = nil
    }
}
