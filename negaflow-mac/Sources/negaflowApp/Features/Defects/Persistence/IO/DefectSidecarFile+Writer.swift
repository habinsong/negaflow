import Foundation
import CoreGraphics
import Chromabase

extension DefectSidecarFile {
    static func writeV2Locked(
        _ snapshot: DefectRecipeSnapshot,
        in directory: URL,
        atomicWriter: AtomicDataWriter,
        rewritesUnpackedStorage: Bool = false
    ) throws -> DefectSidecarWriteOutcome {
        guard snapshot.identity.fingerprintVersion == DefectRecipeFingerprint.currentVersion,
              snapshot.identity.revision > 0,
              try DefectRecipeFingerprint.sha256(items: snapshot.items)
                  == snapshot.identity.recipeSHA256 else {
            throw DefectSidecarWriteError.invalidSnapshot
        }

        let key = sidecarKey(frameID: snapshot.frameID, directory: directory)
        let existing = read(for: snapshot.frameID, in: directory)
        var diskRevision: UInt64 = 0
        var allowsSameRevisionWrite = false
        switch existing {
        case .missing, .loaded(.legacyV1):
            break
        case .loaded(.currentV2(_, let current)):
            diskRevision = current.identity.revision
            if diskRevision > snapshot.identity.revision {
                revisionFloorState.values[key] = max(
                    revisionFloorState.values[key] ?? 0,
                    diskRevision
                )
                return .skippedNewer(existingRevision: diskRevision)
            }
            if diskRevision == snapshot.identity.revision {
                if current == snapshot, rewritesUnpackedStorage {
                    // v2 → v3 저장 이전. 내용·revision·identity 는 같고 파일 표현만 바뀐다.
                    allowsSameRevisionWrite = true
                } else if current == snapshot {
                    DefectSidecarCommitCache.shared.record(snapshot.identity, at: url(for: snapshot.frameID, in: directory))
                    revisionFloorState.values[key] = max(
                        revisionFloorState.values[key] ?? 0,
                        diskRevision
                    )
                    return .alreadyCurrent(url(for: snapshot.frameID, in: directory))
                } else {
                    let currentIdentity = current.identity
                    let nextIdentity = snapshot.identity
                    guard current.items == snapshot.items,
                          currentIdentity.fingerprintVersion == nextIdentity.fingerprintVersion,
                          currentIdentity.recipeSHA256 == nextIdentity.recipeSHA256,
                          currentIdentity.sourceIdentity == nil,
                          nextIdentity.sourceIdentity != nil else {
                        throw DefectSidecarWriteError.conflictingSameRevision(diskRevision)
                    }
                    allowsSameRevisionWrite = true
                }
            }
        case .unsupportedVersion(let version, _):
            throw DefectSidecarWriteError.existingUnsupportedVersion(version)
        case .invalid:
            throw DefectSidecarWriteError.existingInvalid
        case .unreadable:
            throw DefectSidecarWriteError.existingUnreadable
        }

        let floor = max(revisionFloorState.values[key] ?? 0, diskRevision)
        if floor > snapshot.identity.revision {
            return .skippedNewer(existingRevision: floor)
        }
        if floor == snapshot.identity.revision,
           floor > 0,
           !allowsSameRevisionWrite {
            throw DefectSidecarWriteError.conflictingSameRevision(floor)
        }

        let sidecar = DefectSidecarV2(snapshot: snapshot)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(sidecar)
        guard case .loaded(.currentV2(_, let encodedSnapshot)) = decode(
            data,
            expectedFrameID: snapshot.frameID,
            limits: .standard
        ), encodedSnapshot == snapshot else {
            throw DefectSidecarWriteError.invalidSnapshot
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = url(for: snapshot.frameID, in: directory)
        let previousData = try? Data(contentsOf: destination)
        do {
            try atomicWriter(data, destination)
            guard case .loaded(.currentV2(_, let persisted)) = read(
                for: snapshot.frameID,
                in: directory
            ), persisted == snapshot else {
                throw DefectSidecarWriteError.ioFailure
            }
        } catch {
            if let previousData {
                try? previousData.write(to: destination, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: destination)
            }
            throw error
        }
        revisionFloorState.values[key] = snapshot.identity.revision
        DefectSidecarCommitCache.shared.record(snapshot.identity, at: destination)
        return .written(destination)
    }

    /// 1.2.4 이하가 쓴 v2 기록을 같은 revision 의 v3 로 다시 쓴다. 위 기록기의 검증(인코딩 왕복,
    /// 원자 교체, 되읽기, 실패 시 원래 바이트 복원)을 그대로 거치고 recipe identity 는 바뀌지
    /// 않는다. v2 가 아니거나 온전히 읽히지 않는 기록은 손대지 않는다.
    @discardableResult
    static func compactUnpackedStorage(for frameID: UUID, in directory: URL) -> Bool {
        let compacted = try? syncOnIOQueue { () throws -> Bool in
            guard storedVersion(for: frameID, in: directory) == DefectSidecarV2.unpackedVersion,
                  case .loaded(.currentV2(_, let snapshot)) = read(for: frameID, in: directory) else {
                return false
            }
            let outcome = try writeV2Locked(
                snapshot,
                in: directory,
                atomicWriter: atomicWriter,
                rewritesUnpackedStorage: true
            )
            return outcome == .written(url(for: frameID, in: directory))
        }
        return compacted ?? false
    }

    private static func storedVersion(for frameID: UUID, in directory: URL) -> Int? {
        guard let data = try? Data(
            contentsOf: url(for: frameID, in: directory),
            options: .mappedIfSafe
        ) else { return nil }
        return try? PropertyListDecoder().decode(VersionProbe.self, from: data).version
    }


}
