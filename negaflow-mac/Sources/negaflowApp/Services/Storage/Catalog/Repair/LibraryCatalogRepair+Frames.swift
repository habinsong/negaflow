import Foundation
import Chromabase

extension LibraryCatalogRepair {
    /// 프레임에 남은 error 를 되돌린다. 판정은 검사기의 결과를 그대로 쓴다 — 같은 규칙을
    /// 두 번 구현하면 한쪽만 고쳐질 때 수리가 조용히 어긋난다.
    static func repairFrames(
        _ catalog: inout LibraryCatalog,
        defectDirectory: URL,
        cleanedRawDirectory: URL,
        fileManager: FileManager,
        report: inout LibraryCatalogRepairReport
    ) {
        let health = LibraryCatalogHealthInspector.inspect(
            catalog,
            defectDirectory: defectDirectory,
            cleanedRawDirectory: cleanedRawDirectory,
            fileManager: fileManager,
            includeWarnings: false
        )
        let issues = health.repairableIssues
        guard !issues.isEmpty else { return }

        var provenanceCasualties = Set<UUID>()
        var ratingCasualties = Set<UUID>()
        var sourceMetadataCasualties = Set<UUID>()
        var overlayCasualties = Set<UUID>()
        var editTrackingCasualties = Set<UUID>()
        var exportTrackingCasualties = Set<UUID>()
        var defectReviewCasualties = Set<UUID>()
        var duplicateRootJobs: [(sessionID: UUID, jobID: UUID)] = []
        var hasDuplicateExportEvent = false

        for issue in issues {
            switch issue.code {
            case .partialFrameScanProvenance,
                 .frameScanSessionMissing,
                 .frameScanJobMissing,
                 .frameScanJobNotSucceededFull,
                 .frameScanRollMismatch,
                 .scanRootFrameCaptureMismatch,
                 .scanVirtualCopyRootMismatch:
                if let frameID = issue.frameID { provenanceCasualties.insert(frameID) }
            case .succeededScanJobDuplicateRootFrame:
                if let sessionID = issue.sessionID, let jobID = issue.jobID {
                    duplicateRootJobs.append((sessionID, jobID))
                }
            case .invalidRating:
                if let frameID = issue.frameID { ratingCasualties.insert(frameID) }
            case .invalidSourceMetadata, .unsupportedSourceMetadataVersion:
                if let frameID = issue.frameID { sourceMetadataCasualties.insert(frameID) }
            case .invalidAppMetadataOverlay:
                if let frameID = issue.frameID { overlayCasualties.insert(frameID) }
            case .invalidUserEditTracking:
                if let frameID = issue.frameID { editTrackingCasualties.insert(frameID) }
            case .invalidExportTracking:
                if let frameID = issue.frameID { exportTrackingCasualties.insert(frameID) }
            case .duplicateExportEventID:
                hasDuplicateExportEvent = true
            case .invalidDefectReviewTracking:
                if let frameID = issue.frameID { defectReviewCasualties.insert(frameID) }
            default:
                continue
            }
        }

        provenanceCasualties.formUnion(
            surplusRootFrameIDs(in: catalog, duplicateRootJobs: duplicateRootJobs)
        )

        for index in catalog.frames.indices {
            let frameID = catalog.frames[index].id

            if provenanceCasualties.contains(frameID) {
                catalog.frames[index].scanSessionID = nil
                catalog.frames[index].scanJobID = nil
                report.record(.clearedFrameScanProvenance)
            }
            if ratingCasualties.contains(frameID) {
                catalog.frames[index].rating = min(5, max(0, catalog.frames[index].rating))
                report.record(.clampedFrameRating)
            }
            if sourceMetadataCasualties.contains(frameID) {
                catalog.frames[index].sourceMetadata = nil
                report.record(.droppedInvalidSourceMetadata)
            }
            if overlayCasualties.contains(frameID) {
                catalog.frames[index].appMetadataOverlay = nil
                report.record(.droppedInvalidAppMetadataOverlay)
            }
            if defectReviewCasualties.contains(frameID) {
                catalog.frames[index].defectReviewTracking = .legacyUnknown
                report.record(.resetDefectReviewTracking)
            }
            if exportTrackingCasualties.contains(frameID) {
                repairExportTracking(&catalog.frames[index], report: &report)
            }
            if editTrackingCasualties.contains(frameID) {
                repairUserEditTracking(&catalog.frames[index], report: &report)
            }
        }

        if hasDuplicateExportEvent {
            dropDuplicateExportEvents(&catalog, report: &report)
        }
    }

    /// 성공한 job 하나가 여러 root frame 을 가리키면, 가장 먼저 오는 하나만 이력을 유지한다.
    private static func surplusRootFrameIDs(
        in catalog: LibraryCatalog,
        duplicateRootJobs: [(sessionID: UUID, jobID: UUID)]
    ) -> Set<UUID> {
        guard !duplicateRootJobs.isEmpty else { return [] }
        var surplus = Set<UUID>()
        for job in duplicateRootJobs {
            let rootFrameIDs = catalog.frames
                .filter {
                    $0.sourceFrameID == nil
                        && $0.scanSessionID == job.sessionID
                        && $0.scanJobID == job.jobID
                }
                .map(\.id)
            surplus.formUnion(rootFrameIDs.dropFirst())
        }
        return surplus
    }

    private static func repairUserEditTracking(
        _ frame: inout LibraryFrameRecord,
        report: inout LibraryCatalogRepairReport
    ) {
        guard let expected = try? LibraryDevelopRecipeFingerprint.sha256(
            filmType: frame.filmType,
            presetID: frame.presetID,
            params: frame.params,
            imageTransform: frame.imageTransform
        ) else { return }

        let tracking = frame.userEditTracking
        if tracking.coverage == .tracked,
           let ingest = tracking.ingestRecipeSHA256,
           LibraryCatalogHealthInspector.validSHA256(ingest) {
            // 편집 이력이 살아 있으면 지문만 현재 값으로 맞춘다.
            frame.userEditTracking = LibraryUserEditTracking(
                coverage: .tracked,
                ingestRecipeSHA256: ingest,
                currentRecipeSHA256: expected,
                revision: ingest == expected ? tracking.revision : max(tracking.revision, 1)
            )
        } else {
            // 이력이 성립하지 않으면 "모름" 으로 되돌린다 — 편집 여부를 지어내지 않는다.
            frame.userEditTracking = .legacyUnknown(currentRecipeSHA256: expected)
        }
        report.record(.recomputedUserEditTracking)
    }

    private static func repairExportTracking(
        _ frame: inout LibraryFrameRecord,
        report: inout LibraryCatalogRepairReport
    ) {
        let events = frame.exportTracking.successfulEvents
        let valid = events.filter(LibraryCatalogHealthInspector.validExportEvent)
        report.record(.droppedInvalidExportEvent, count: events.count - valid.count)

        var tracking = frame.exportTracking
        tracking.successfulEvents = valid
        if !valid.isEmpty, tracking.coverage != .tracked {
            tracking.coverage = .tracked
            report.record(.resetExportTrackingCoverage)
        }
        frame.exportTracking = tracking
    }

    private static func dropDuplicateExportEvents(
        _ catalog: inout LibraryCatalog,
        report: inout LibraryCatalogRepairReport
    ) {
        var seen = Set<UUID>()
        for index in catalog.frames.indices {
            let events = catalog.frames[index].exportTracking.successfulEvents
            guard !events.isEmpty else { continue }
            let kept = events.filter { seen.insert($0.id).inserted }
            guard kept.count != events.count else { continue }
            catalog.frames[index].exportTracking.successfulEvents = kept
            report.record(.droppedDuplicateExportEvent, count: events.count - kept.count)
        }
    }
}
