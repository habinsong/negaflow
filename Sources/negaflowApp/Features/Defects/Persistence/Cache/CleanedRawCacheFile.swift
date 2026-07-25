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
        if let path = UserDefaults.standard.string(forKey: customDirectoryDefaultsKey),
           !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return platformDefaultDirectoryURL(fileManager: fileManager)
    }

    static func platformDefaultDirectoryURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
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
