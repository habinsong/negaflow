import Foundation
import CoreGraphics
import Chromabase

enum DefectSidecarFile {
    struct SidecarKey: Hashable {
        var directoryPath: String
        var frameID: UUID
    }

    final class RevisionFloorState: @unchecked Sendable {
        var values: [SidecarKey: UInt64] = [:]
    }

    static let ioQueue = DispatchQueue(label: "negaflow.defect-sidecar-io", qos: .utility)
    static let ioQueueKey = DispatchSpecificKey<UInt8>()
    static let configuredQueue: Void = {
        ioQueue.setSpecific(key: ioQueueKey, value: 1)
    }()
    static let revisionFloorState = RevisionFloorState()

    struct VersionProbe: Decodable {
        var version: Int
    }

    typealias AtomicDataWriter = (_ data: Data, _ destination: URL) throws -> Void

    static func writeAsync(
        _ items: [DefectEditItemRecord],
        for frameID: UUID,
        in directory: URL = defaultDirectoryURL()
    ) {
        _ = configuredQueue
        ioQueue.async { _ = try? writeLegacyLocked(items, for: frameID, in: directory) }
    }

    static func writeAsync(
        _ snapshot: DefectRecipeSnapshot,
        in directory: URL = defaultDirectoryURL(),
        completion: @escaping @Sendable (
            Result<DefectSidecarWriteOutcome, DefectSidecarWriteError>
        ) -> Void
    ) {
        _ = configuredQueue
        ioQueue.async {
            do {
                completion(.success(try writeV2Locked(
                    snapshot,
                    in: directory,
                    atomicWriter: atomicWriter
                )))
            } catch {
                completion(.failure(writeError(from: error)))
            }
        }
    }

    static func removeAsync(
        for frameID: UUID,
        in directory: URL = defaultDirectoryURL()
    ) {
        _ = configuredQueue
        ioQueue.async { try? removeLocked(for: frameID, in: directory, minimumRevision: nil) }
    }

    /// 진행 중인 낮은 revision write가 remove 뒤에 도착해 sidecar를 되살리지 못하게 하는
    /// revision-aware 삭제다. revision floor는 프로세스 내 직렬 queue 수명 동안 유지된다.
    static func removeAsync(
        for frameID: UUID,
        atRevision revision: UInt64,
        in directory: URL = defaultDirectoryURL()
    ) {
        _ = configuredQueue
        ioQueue.async {
            try? removeLocked(
                for: frameID,
                in: directory,
                minimumRevision: revision
            )
        }
    }

    static func flushSync() {
        _ = configuredQueue
        if DispatchQueue.getSpecific(key: ioQueueKey) == 1 { return }
        ioQueue.sync {}
    }

    static func defaultDirectoryURL(fileManager: FileManager = .default) -> URL {
        AppStorageRoot.applicationSupport(fileManager: fileManager)
            .appendingPathComponent("negaflow", isDirectory: true)
            .appendingPathComponent("defects", isDirectory: true)
    }

    static func url(for frameID: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(frameID.uuidString).plist")
    }

    @discardableResult
    static func write(
        _ items: [DefectEditItemRecord],
        for frameID: UUID,
        in directory: URL = defaultDirectoryURL()
    ) throws -> URL {
        try syncOnIOQueue {
            try writeLegacyLocked(items, for: frameID, in: directory)
        }
    }

    /// v2 synchronous writer. 같은 frame의 더 높은 revision이 이미 기록됐다면 낮은 요청을
    /// 성공처럼 덮지 않고 `skippedNewer`로 돌려준다.
    static func write(
        _ snapshot: DefectRecipeSnapshot,
        in directory: URL = defaultDirectoryURL()
    ) throws -> DefectSidecarWriteOutcome {
        try write(
            snapshot,
            in: directory,
            atomicWriter: atomicWriter
        )
    }

    /// 원자 쓰기 실패를 결정적으로 재현하는 내부 테스트 seam. 기존 production 호출부는 위 overload를 쓴다.
    static func write(
        _ snapshot: DefectRecipeSnapshot,
        in directory: URL = defaultDirectoryURL(),
        atomicWriter: @escaping AtomicDataWriter
    ) throws -> DefectSidecarWriteOutcome {
        do {
            return try syncOnIOQueue {
                try writeV2Locked(snapshot, in: directory, atomicWriter: atomicWriter)
            }
        } catch {
            throw writeError(from: error)
        }
    }

    static func read(
        for frameID: UUID,
        in directory: URL = defaultDirectoryURL()
    ) -> DefectSidecarLoadResult {
        read(
            for: frameID,
            in: directory,
            limits: .standard,
            fileManager: .default
        )
    }

    static func read(
        for frameID: UUID,
        in directory: URL,
        limits: DefectSidecarResourceLimits,
        fileManager: FileManager
    ) -> DefectSidecarLoadResult {
        let source = url(for: frameID, in: directory)
        guard fileManager.fileExists(atPath: source.path) else { return .missing }
        guard let attributes = try? fileManager.attributesOfItem(atPath: source.path),
              let fileSize = (attributes[.size] as? NSNumber)?.intValue else {
            return .unreadable
        }
        guard fileSize >= 0, fileSize <= limits.maxFileBytes else {
            return .invalid(rawData: nil)
        }
        let data: Data
        do {
            data = try Data(contentsOf: source, options: .mappedIfSafe)
        } catch {
            return .unreadable
        }
        guard data.count <= limits.maxFileBytes else {
            return .invalid(rawData: nil)
        }
        return decode(data, expectedFrameID: frameID, limits: limits)
    }

    static func validatedRawData(
        for frameID: UUID,
        in directory: URL = defaultDirectoryURL()
    ) -> Data? {
        switch read(for: frameID, in: directory) {
        case .loaded(.legacyV1(let rawData, _)),
             .loaded(.currentV2(let rawData, _)):
            rawData
        case .missing, .unsupportedVersion, .invalid, .unreadable:
            nil
        }
    }

    static func load(
        for frameID: UUID,
        in directory: URL = defaultDirectoryURL()
    ) -> [DefectEditItemRecord]? {
        guard case .loaded(let loaded) = read(for: frameID, in: directory) else {
            return nil
        }
        return loaded.items
    }

    static func remove(
        for frameID: UUID,
        in directory: URL = defaultDirectoryURL()
    ) throws {
        try syncOnIOQueue {
            try removeLocked(for: frameID, in: directory, minimumRevision: nil)
        }
    }

    static func remove(
        for frameID: UUID,
        atRevision revision: UInt64,
        in directory: URL = defaultDirectoryURL()
    ) throws {
        try syncOnIOQueue {
            try removeLocked(
                for: frameID,
                in: directory,
                minimumRevision: revision
            )
        }
    }

    private static func writeLegacyLocked(
        _ items: [DefectEditItemRecord],
        for frameID: UUID,
        in directory: URL
    ) throws -> URL {
        // frozen v1 writer가 이미 존재하는 v2/future document를 downgrade하지 않게 한다.
        switch read(for: frameID, in: directory) {
        case .loaded(.currentV2), .unsupportedVersion:
            throw DefectSidecarWriteError.legacyWriteWouldDowngrade
        case .missing, .loaded(.legacyV1), .invalid, .unreadable:
            break
        }
        let sidecar = DefectSidecar(items: items.map { $0.compressedForStorage() })
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(sidecar)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = url(for: frameID, in: directory)
        try data.write(to: destination, options: .atomic)
        return destination
    }


}
