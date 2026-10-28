import Foundation
import CoreGraphics
import Chromabase

/// Rebuildable pixel cache. Losing this file never loses the recipe because the defect
/// sidecar above remains authoritative.

enum CleanedRawCacheFile {
    static let customDirectoryDefaultsKey = "disk.cleanedRawFolder"
    private final class DirectoryRegistry: @unchecked Sendable {
        let lock = NSLock()
        var paths: Set<String> = []
    }
    private static let directoryRegistry = DirectoryRegistry()

    static func registerDirectory(_ directory: URL) {
        let path = directory.standardizedFileURL.path
        directoryRegistry.lock.lock()
        directoryRegistry.paths.insert(path)
        directoryRegistry.lock.unlock()
    }

    static func registeredDirectories() -> [URL] {
        directoryRegistry.lock.lock()
        let paths = directoryRegistry.paths
        directoryRegistry.lock.unlock()
        return paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func defaultDirectoryURL(fileManager: FileManager = .default) -> URL {
        // 테스트 프로세스에서는 사용자가 지정한 폴더를 따르지 않는다. 그 값이 iCloud Drive 를
        // 가리키면 스크래치 TIFF 가 사용자 클라우드를 오염시키고, dematerialize 된 플레이스홀더
        // 때문에 디렉터리 목록이 비결정적이 된다. 프로세스별 격리 루트가 그 자리를 대신한다.
        if !AppStorageRoot.isolatesTestProcess,
           let path = UserDefaults.standard.string(forKey: customDirectoryDefaultsKey),
           !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return platformDefaultDirectoryURL(fileManager: fileManager)
    }

    static func platformDefaultDirectoryURL(fileManager: FileManager = .default) -> URL {
        AppStorageRoot.caches(fileManager: fileManager)
            .appendingPathComponent("negaflow", isDirectory: true)
            .appendingPathComponent("cleaned-raw", isDirectory: true)
    }

    static func removeAll(
        for frameID: UUID,
        additionalDirectories: [URL] = [],
        fileManager: FileManager = .default
    ) {
        let directories = Set(
            [defaultDirectoryURL(fileManager: fileManager),
             platformDefaultDirectoryURL(fileManager: fileManager)]
                + registeredDirectories()
                + additionalDirectories
        )
        for directory in directories {
            guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
                continue
            }
            for name in names where self.frameID(fromFileName: name) == frameID {
                try? fileManager.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    static func makeBuildURL(frameID: UUID, in directory: URL = defaultDirectoryURL()) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(frameID.uuidString)_\(UUID().uuidString)_raw-v2.tiff")
    }

    static func frameID(fromFileName name: String) -> UUID? {
        guard let separator = name.firstIndex(of: "_") else { return nil }
        return UUID(uuidString: String(name[name.startIndex..<separator]))
    }

    /// ImageIO 가 쓰다 만 임시 파일(`.<캐시 파일 이름>-XXXXXX`). 강제 종료로 이름 바꾸기 전에
    /// 멈추면 남는다.
    static func isLeftoverTemporaryFileName(_ name: String) -> Bool {
        guard name.hasPrefix("."), let dash = name.lastIndex(of: "-") else { return false }
        let cacheName = name[name.index(after: name.startIndex)..<dash]
        return cacheName.lowercased().hasSuffix(".tiff") && frameID(fromFileName: String(cacheName)) != nil
    }

    // MARK: 읽는 중인 파일 보호

    private final class LeaseRegistry: @unchecked Sendable {
        let lock = NSLock()
        var counts: [String: Int] = [:]
    }
    private static let leases = LeaseRegistry()

    /// 내보내기처럼 파일 경로를 쥐고 오래 읽는 쪽이 정리 작업보다 먼저 잡는다. 반환한 키로 풀어 준다.
    static func acquireLease(_ url: URL?) -> String? {
        guard let path = url?.standardizedFileURL.path else { return nil }
        leases.lock.withLock { leases.counts[path, default: 0] += 1 }
        return path
    }

    static func releaseLease(_ key: String?) {
        guard let key else { return }
        leases.lock.withLock {
            let remaining = (leases.counts[key] ?? 1) - 1
            leases.counts[key] = remaining > 0 ? remaining : nil
        }
    }

    static func leasedPaths() -> Set<String> {
        leases.lock.withLock { Set(leases.counts.keys) }
    }

    /// `directory` 에서 이 캐시가 만든 파일 가운데 `keeping` 에 없는 것을 지운다. 방금 쓰는 중일 수
    /// 있는 파일은 `minimumAge` 보다 오래된 것만 지운다. 지운 바이트 수를 돌려준다.
    @discardableResult
    static func removeUnreferenced(
        in directory: URL,
        keeping paths: Set<String>,
        minimumAge: TimeInterval,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> Int64 {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        let keep = paths.union(leasedPaths())
        var removed: Int64 = 0
        for name in names {
            let url = directory.appendingPathComponent(name)
            if isLeftoverTemporaryFileName(name) {
                // 임시 파일은 어느 프레임 소유든 상관없다 — 끝난 쓰기는 이 이름을 남기지 않는다.
            } else if let frameID = frameID(fromFileName: name),
                      isOwnedCacheURL(url, frameID: frameID, directory: directory) {
                guard !keep.contains(url.standardizedFileURL.path) else { continue }
            } else {
                continue
            }
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let modified = attributes[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) >= minimumAge else { continue }
            // 목록을 읽은 뒤 새 내보내기가 임대를 잡을 수 있다. 삭제와 임대 획득을 같은 잠금으로
            // 직렬화해 이미 읽기 시작한 파일이 사라지지 않게 한다.
            leases.lock.withLock {
                guard leases.counts[url.standardizedFileURL.path] == nil else { return }
                if (try? fileManager.removeItem(at: url)) != nil {
                    removed += (attributes[.size] as? NSNumber)?.int64Value ?? 0
                }
            }
        }
        return removed
    }

    static func isOwnedCacheURL(
        _ url: URL,
        frameID: UUID,
        directory: URL? = nil
    ) -> Bool {
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        let directories = directory.map { [$0] }
            ?? ([defaultDirectoryURL()] + registeredDirectories())
        return directories.contains {
            resolvedURL.deletingLastPathComponent()
                == $0.resolvingSymlinksInPath().standardizedFileURL
        }
        && resolvedURL.pathExtension.lowercased() == "tiff"
        && self.frameID(fromFileName: resolvedURL.lastPathComponent) == frameID
    }
}
