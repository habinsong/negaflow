import Foundation
import CoreGraphics
import Chromabase

extension DefectSidecarFile {
    static func writeV2Locked(
        _ snapshot: DefectRecipeSnapshot,
        in directory: URL,
        atomicWriter: AtomicDataWriter
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
        var allowsSourceBindingAtSameRevision = false
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
                if current == snapshot {
                    revisionFloorState.values[key] = max(
                        revisionFloorState.values[key] ?? 0,
                        diskRevision
                    )
                    return .alreadyCurrent(url(for: snapshot.frameID, in: directory))
                }
                let currentIdentity = current.identity
                let nextIdentity = snapshot.identity
                guard current.items == snapshot.items,
                      currentIdentity.fingerprintVersion == nextIdentity.fingerprintVersion,
                      currentIdentity.recipeSHA256 == nextIdentity.recipeSHA256,
                      currentIdentity.sourceIdentity == nil,
                      nextIdentity.sourceIdentity != nil else {
                    throw DefectSidecarWriteError.conflictingSameRevision(diskRevision)
                }
                allowsSourceBindingAtSameRevision = true
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
           !allowsSourceBindingAtSameRevision {
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
        return .written(destination)
    }


}
