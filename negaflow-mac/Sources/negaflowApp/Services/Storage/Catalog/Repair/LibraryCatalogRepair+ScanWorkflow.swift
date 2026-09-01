import Foundation
import ScannerKit

extension LibraryCatalogRepair {
    /// 스캔 이력을 정합한 상태로 되돌린다. 되돌릴 수 없는 세션은 통째로 버린다 — 세션은
    /// "이 사진이 어느 스캔에서 나왔는지" 라는 이력일 뿐이고, 사진과 현상값은 프레임에 있다.
    static func repairScanWorkflow(
        _ catalog: inout LibraryCatalog,
        report: inout LibraryCatalogRepairReport
    ) {
        var doomedSessionIDs = Set<UUID>()
        let sessions = survivingSessions(catalog.scanSessions, doomed: &doomedSessionIDs)
        let rollsByID = Dictionary(
            grouping: catalog.rolls,
            by: \.id
        )
        let sessionIDs = Set(sessions.map(\.id))
        let succeededSessionIDs = Set(
            sessions
                .filter { session in
                    session.jobs.contains { $0.kind == .full && $0.state == .succeeded }
                }
                .map(\.id)
        )

        var assignments: [LibraryScanRollAssignment] = []
        var seenSessionIDs = Set<UUID>()
        var claimedRollIDs = Set<UUID>()

        for assignment in catalog.scanRollAssignments {
            guard sessionIDs.contains(assignment.sessionID) else {
                report.record(.droppedOrphanScanRollAssignment)
                continue
            }
            guard seenSessionIDs.insert(assignment.sessionID).inserted else {
                report.record(.droppedDuplicateScanRollAssignment)
                continue
            }
            guard assignment.rollID != LibraryRoll.unassignedID,
                  assignment.createdAt.timeIntervalSinceReferenceDate.isFinite else {
                doomedSessionIDs.insert(assignment.sessionID)
                report.record(.droppedOrphanScanRollAssignment)
                continue
            }

            var updated = assignment
            let targetRolls = rollsByID[assignment.rollID, default: []]
            if targetRolls.count == 1 {
                let roll = targetRolls[0]
                guard roll.kind == .physical else {
                    doomedSessionIDs.insert(assignment.sessionID)
                    report.record(.droppedOrphanScanRollAssignment)
                    continue
                }
                if let filmType = roll.filmType, filmType != updated.filmType {
                    updated.filmType = filmType
                    report.record(.alignedScanRollAssignmentFilmType)
                }
            } else if targetRolls.isEmpty {
                // 롤이 아직 없는 예약은 정상이다 — 첫 성공 전까지는 롤을 만들지 않는다.
                // 이미 성공한 스캔이 있는데 롤이 없다면 그 롤은 지워진 것이고, 예약은 의미가 없다.
                let isDuplicateReservation = !claimedRollIDs.insert(assignment.rollID).inserted
                if succeededSessionIDs.contains(assignment.sessionID) || isDuplicateReservation {
                    doomedSessionIDs.insert(assignment.sessionID)
                    report.record(.droppedOrphanScanRollAssignment)
                    continue
                }
            } else {
                doomedSessionIDs.insert(assignment.sessionID)
                report.record(.droppedOrphanScanRollAssignment)
                continue
            }

            let trimmedName = updated.draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedName.isEmpty {
                guard let derived = targetRolls.first?.name?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ), !derived.isEmpty else {
                    doomedSessionIDs.insert(assignment.sessionID)
                    report.record(.droppedOrphanScanRollAssignment)
                    continue
                }
                updated.draftName = derived
                report.record(.filledScanRollAssignmentName)
            } else if trimmedName != updated.draftName {
                updated.draftName = trimmedName
                report.record(.filledScanRollAssignmentName)
            }

            assignments.append(updated)
        }

        // 예약을 잃은 세션은 어느 롤로 갈지 알 수 없다 — 이력만 버리고 사진은 그대로 둔다.
        for session in sessions where !seenSessionIDs.contains(session.id) {
            doomedSessionIDs.insert(session.id)
        }

        let keptSessions = sessions.filter { !doomedSessionIDs.contains($0.id) }
        report.record(
            .droppedInvalidScanSession,
            count: catalog.scanSessions.count - keptSessions.count
        )
        catalog.scanSessions = keptSessions
        let survivingSessionIDs = Set(keptSessions.map(\.id))
        catalog.scanRollAssignments = assignments.filter {
            survivingSessionIDs.contains($0.sessionID)
        }
    }

    /// 세션 자체가 유효한지. 내부 job 목록은 손대지 않는다 — `ScanSession` 은 만들 때
    /// 검증을 통과한 값이라, 일부만 들어내면 다시 유효한 세션이라고 보장할 수 없다.
    private static func survivingSessions(
        _ sessions: [ScanSession],
        doomed: inout Set<UUID>
    ) -> [ScanSession] {
        var seenSessionIDs = Set<UUID>()
        var seenJobIDs = Set<UUID>()
        var seenManifestIDs = Set<UUID>()
        var surviving: [ScanSession] = []

        for session in sessions {
            guard seenSessionIDs.insert(session.id).inserted,
                  !session.jobs.isEmpty,
                  passesOwnValidation(session),
                  !session.jobs.contains(where: { $0.kind == .preview }) else {
                doomed.insert(session.id)
                continue
            }
            let jobIDs = session.jobs.map(\.id)
            let manifestIDs = session.jobs.compactMap { $0.captureManifest?.id }
            guard Set(jobIDs).count == jobIDs.count,
                  jobIDs.allSatisfy({ !seenJobIDs.contains($0) }),
                  Set(manifestIDs).count == manifestIDs.count,
                  manifestIDs.allSatisfy({ !seenManifestIDs.contains($0) }) else {
                doomed.insert(session.id)
                continue
            }
            seenJobIDs.formUnion(jobIDs)
            seenManifestIDs.formUnion(manifestIDs)
            surviving.append(session)
        }
        return surviving
    }

    private static func passesOwnValidation(_ session: ScanSession) -> Bool {
        do {
            try session.validate()
            return true
        } catch {
            return false
        }
    }
}
