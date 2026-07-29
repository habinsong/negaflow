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
        return directory.appendingPathComponent("\(frameID.uuidString)_\(UUID().uuidString).tiff")
    }

    static func frameID(fromFileName name: String) -> UUID? {
        guard let separator = name.firstIndex(of: "_") else { return nil }
        return UUID(uuidString: String(name[name.startIndex..<separator]))
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
