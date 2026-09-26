import Foundation
import CoreGraphics
import Chromabase

extension DefectSidecarFile {
    static func removeLocked(
        for frameID: UUID,
        in directory: URL,
        minimumRevision: UInt64?
    ) throws {
        if let minimumRevision {
            guard minimumRevision > 0 else {
                throw DefectSidecarWriteError.invalidSnapshot
            }
            let key = sidecarKey(frameID: frameID, directory: directory)
            revisionFloorState.values[key] = max(
                revisionFloorState.values[key] ?? 0,
                minimumRevision
            )
        }
        let destination = url(for: frameID, in: directory)
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.removeItem(at: destination)
    }

    static func decode(
        _ data: Data,
        expectedFrameID: UUID,
        limits: DefectSidecarResourceLimits
    ) -> DefectSidecarLoadResult {
        let decoder = PropertyListDecoder()
        let version: Int
        do {
            version = try decoder.decode(VersionProbe.self, from: data).version
        } catch {
            return .invalid(rawData: data)
        }
        switch version {
        case 1:
            guard let sidecar = try? decoder.decode(DefectSidecar.self, from: data),
                  sidecar.version == 1,
                  let items = try? DefectSidecarResourcePolicy.normalizedItems(
                      sidecar.items,
                      limits: limits
                  ) else {
                return .invalid(rawData: data)
            }
            return .loaded(.legacyV1(
                rawData: data,
                items: items
            ))
        case DefectSidecarV2.currentVersion:
            do {
                let sidecar = try decoder.decode(DefectSidecarV2.self, from: data)
                return .loaded(.currentV2(
                    rawData: data,
                    snapshot: try sidecar.validatedSnapshot(
                        expectedFrameID: expectedFrameID,
                        limits: limits
                    )
                ))
            } catch {
                return .invalid(rawData: data)
            }
        default:
            return .unsupportedVersion(version: version, rawData: data)
        }
    }

    static func sidecarKey(frameID: UUID, directory: URL) -> SidecarKey {
        SidecarKey(
            directoryPath: directory.standardizedFileURL.path,
            frameID: frameID
        )
    }

    /// 이 frame 에 대해 디스크와 이번 프로세스가 이미 본 가장 높은 revision. 기록이 사라졌거나
    /// 어긋난 recipe 를 다시 쓸 때 이보다 높은 revision 을 써야 revision floor 에 막히지 않는다.
    static func highestKnownRevision(for frameID: UUID, in directory: URL) -> UInt64 {
        syncOnIOQueue {
            let floor = revisionFloorState.values[sidecarKey(frameID: frameID, directory: directory)] ?? 0
            guard case .loaded(.currentV2(_, let stored)) = read(for: frameID, in: directory) else {
                return floor
            }
            return max(floor, stored.identity.revision)
        }
    }

    static func syncOnIOQueue<T>(_ body: () throws -> T) rethrows -> T {
        _ = configuredQueue
        if DispatchQueue.getSpecific(key: ioQueueKey) == 1 {
            return try body()
        }
        return try ioQueue.sync(execute: body)
    }

    static func atomicWriter(_ data: Data, _ destination: URL) throws {
        try data.write(to: destination, options: .atomic)
    }

    static func writeError(from error: Error) -> DefectSidecarWriteError {
        error as? DefectSidecarWriteError ?? .ioFailure
    }
}
