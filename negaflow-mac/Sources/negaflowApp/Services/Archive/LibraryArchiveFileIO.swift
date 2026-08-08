import CryptoKit
import Foundation

struct LibraryArchiveFileDigest: Equatable {
    var byteCount: Int64
    var sha256: String
}

enum LibraryArchiveFileIO {
    static let chunkSize = 1_048_576

    static func copyAndHash(
        from source: URL,
        to destination: URL,
        fileManager: FileManager
    ) throws -> LibraryArchiveFileDigest {
        let before = try sourceValues(source)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let reader = try FileHandle(forReadingFrom: source)
        let writer = try FileHandle(forWritingTo: destination)
        defer {
            try? reader.close()
            try? writer.close()
        }
        var hasher = SHA256()
        var byteCount: Int64 = 0
        while let chunk = try reader.read(upToCount: chunkSize), !chunk.isEmpty {
            try writer.write(contentsOf: chunk)
            hasher.update(data: chunk)
            byteCount += Int64(chunk.count)
        }
        try writer.synchronize()
        let after = try sourceValues(source)
        guard before.fileSize == after.fileSize,
              before.contentModificationDate == after.contentModificationDate,
              byteCount == Int64(after.fileSize ?? -1) else {
            throw LibraryArchiveError.sourceChanged(source.path)
        }
        return LibraryArchiveFileDigest(
            byteCount: byteCount,
            sha256: hex(hasher.finalize())
        )
    }

    static func hash(_ url: URL) throws -> LibraryArchiveFileDigest {
        let values = try sourceValues(url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteCount: Int64 = 0
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
            byteCount += Int64(chunk.count)
        }
        guard byteCount == Int64(values.fileSize ?? -1) else {
            throw LibraryArchiveError.sourceChanged(url.path)
        }
        return LibraryArchiveFileDigest(
            byteCount: byteCount,
            sha256: hex(hasher.finalize())
        )
    }

    static func regularFiles(
        below root: URL,
        fileManager: FileManager
    ) throws -> [String] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else { return [] }
        var paths: [String] = []
        let resolvedRoot = root.resolvingSymlinksInPath()
        let prefix = resolvedRoot.path.hasSuffix("/")
            ? resolvedRoot.path
            : resolvedRoot.path + "/"
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw LibraryArchiveError.invalidPackage("symbolic link: \(url.path)")
            }
            guard values.isRegularFile == true else { continue }
            let resolvedURL = url.resolvingSymlinksInPath()
            guard resolvedURL.path.hasPrefix(prefix) else {
                throw LibraryArchiveError.invalidPackage("escaped path: \(url.path)")
            }
            paths.append(String(resolvedURL.path.dropFirst(prefix.count)))
        }
        return paths.sorted()
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && !path.contains("\\")
            && !path.contains("\n")
            && !path.split(separator: "/", omittingEmptySubsequences: false)
                .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }

    private static func sourceValues(_ url: URL) throws -> URLResourceValues {
        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw LibraryArchiveError.unsafeSource(url.path)
        }
        return values
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
