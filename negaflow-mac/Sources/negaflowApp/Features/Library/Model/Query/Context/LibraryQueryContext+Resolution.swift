import Foundation
import Chromabase
import ScannerKit

extension LibraryQueryContext {
    static let searchLanguages = AppLanguage.allCases.filter { $0 != .system }

    struct RollResolutionIndex {
        let rollByFrameID: [UUID: LibraryRoll]
        let unknownFrameIDs: Set<UUID>
    }

    @MainActor
    static func makeRollResolutionIndex(
        _ rolls: [LibraryRoll]
    ) -> RollResolutionIndex {
        let rollIDCounts = Dictionary(grouping: rolls, by: \.id).mapValues(\.count)
        let memberships = Dictionary(grouping: rolls.flatMap { roll in
            roll.frameIDs.map { ($0, roll) }
        }, by: { $0.0 })
        var resolved: [UUID: LibraryRoll] = [:]
        var unknown = Set<UUID>()
        for (frameID, entries) in memberships {
            guard entries.count == 1,
                  let roll = entries.first?.1,
                  rollIDCounts[roll.id] == 1 else {
                unknown.insert(frameID)
                continue
            }
            resolved[frameID] = roll
        }
        return RollResolutionIndex(rollByFrameID: resolved, unknownFrameIDs: unknown)
    }

    @MainActor
    static func profileResolution(
        for frame: ScanFrame,
        groups: [String: [ScannerProfile]]
    ) -> ProfileResolution {
        guard let profileID = frame.params.scannerProfileID else { return .none }
        guard let matches = groups[profileID] else { return .missing(profileID) }
        guard matches.count == 1, let profile = matches.first else {
            return .unknown(profileID)
        }
        return .resolved(profile)
    }

    @MainActor
    static func resolvedCaptureDevice(
        for frame: ScanFrame,
        frameGroups: [UUID: [ScanFrame]],
        sessionGroups: [UUID: [ScanSession]],
        jobGroupsBySessionID: [UUID: [UUID: [ScanJob]]]
    ) -> TextJoinResolution<ScannerDescriptor> {
        if frame.sourceKind == .importedFile,
           frame.scanSessionID == nil,
           frame.scanJobID == nil {
            return .known(nil)
        }
        switch (frame.scanSessionID, frame.scanJobID) {
        case (nil, nil):
            return .unknown
        case (nil, _), (_, nil):
            return .unknown
        case let (sessionID?, jobID?):
            guard frame.sourceKind == .scannerTIFF,
                  !frame.isPreviewScan,
              let sessions = sessionGroups[sessionID],
              sessions.count == 1,
              let session = sessions.first,
                  let jobs = jobGroupsBySessionID[sessionID]?[jobID],
                  jobs.count == 1,
                  let job = jobs.first,
                  job.kind == .full,
                  job.state == .succeeded,
                  let manifest = job.captureManifest,
                  let publication = job.framePublication,
                  manifest.sessionID == session.id,
                  manifest.jobID == job.id,
                  manifest.attempt == job.attempt,
                  manifest.kind == .full,
                  manifest.requestedOptions == job.requestedOptions,
                  job.requestedOptions.scannerID == session.device.id else {
                return .unknown
            }
            let rootID = frame.sourceFrameID ?? frame.id
            guard let roots = frameGroups[rootID],
                  roots.count == 1,
                  let root = roots.first,
                  matchesPublishedRoot(
                    root,
                    sessionID: session.id,
                    job: job,
                    publication: publication,
                    manifest: manifest
                  ) else {
                return .unknown
            }
            if frame.id == root.id {
                guard frame.sourceFrameID == nil, frame.virtualCopyNumber == nil else {
                    return .unknown
                }
            } else {
                guard frame.sourceFrameID == publication.frameID,
                      frame.virtualCopyNumber.map({ $0 > 0 }) == true,
                      matchesVirtualCopyCaptureIdentity(frame, root: root) else {
                    return .unknown
                }
            }
            return .known(session.device)
        }
    }

    @MainActor
    static func matchesPublishedRoot(
        _ root: ScanFrame,
        sessionID: UUID,
        job: ScanJob,
        publication: ScanFramePublicationSnapshot,
        manifest: CaptureManifest
    ) -> Bool {
        root.id == publication.frameID
            && root.sourceFrameID == nil
            && root.virtualCopyNumber == nil
            && root.scanSessionID == sessionID
            && root.scanJobID == job.id
            && root.sourceKind == .scannerTIFF
            && !root.isPreviewScan
            && root.scanIndex == publication.scanIndex
            && root.storageGroupName == publication.storageGroupName
            && root.sourcePixelWidth == manifest.result.width
            && root.sourcePixelHeight == manifest.result.height
            && root.sourceResolutionDPI == manifest.result.reportedResolution?.dpi
            && root.sourceBitDepth == manifest.result.reportedBitDepth?.rawValue
            && root.scannedAt == manifest.captureCompletedAt
    }

    @MainActor
    static func matchesVirtualCopyCaptureIdentity(
        _ copy: ScanFrame,
        root: ScanFrame
    ) -> Bool {
        copy.scanSessionID == root.scanSessionID
            && copy.scanJobID == root.scanJobID
            && copy.sourceKind == root.sourceKind
            && copy.scanIndex == root.scanIndex
            && copy.storageGroupName == root.storageGroupName
            && copy.sourcePixelWidth == root.sourcePixelWidth
            && copy.sourcePixelHeight == root.sourcePixelHeight
            && copy.sourceResolutionDPI == root.sourceResolutionDPI
            && copy.sourceBitDepth == root.sourceBitDepth
            && copy.scannedAt == root.scannedAt
    }

    static func hasCreativeCalibrationAdjustments(_ params: DevelopParameters) -> Bool {
        !params.calibration.isIdentity
            || abs(params.redPrimary) >= 1e-4
            || abs(params.greenPrimary) >= 1e-4
            || abs(params.bluePrimary) >= 1e-4
    }

    @MainActor
    static func virtualCopyState(_ frame: ScanFrame) -> Bool? {
        switch (frame.sourceFrameID, frame.virtualCopyNumber) {
        case (nil, nil):
            return false
        case let (sourceFrameID?, copyNumber?)
            where sourceFrameID != frame.id && copyNumber > 0:
            return true
        default:
            return nil
        }
    }

    @MainActor
    static func makeFolderFacts(
        folders: [LibraryFolder],
        frames: [ScanFrame]
    ) -> [LibraryFolderQueryFact] {
        let registered = folders.map { folder in
            let path = LibraryPresentation.normalizedFolderPath(folder.url)
            return LibraryFolderQueryFact(id: path, folderID: folder.id, title: folder.name)
        }.sorted { lhs, rhs in
            let nameOrder = LibrarySearchText.normalize(lhs.title)
                .compare(LibrarySearchText.normalize(rhs.title), options: .numeric)
            return nameOrder == .orderedSame ? lhs.id < rhs.id : nameOrder == .orderedAscending
        }
        let registeredPaths = Set(registered.map(\.id))
        let implicitPaths = Set(frames.map {
            LibraryPresentation.normalizedFolderPath(LibraryPresentation.folderURL(for: $0))
        }).subtracting(registeredPaths).sorted()
        let implicit = implicitPaths.map { path in
            let title = URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
            return LibraryFolderQueryFact(
                id: path,
                folderID: nil,
                title: title.isEmpty ? path : title
            )
        }
        return registered + implicit
    }
}
