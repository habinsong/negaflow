import Foundation

enum LibraryArchiveChecksumValidator {
    static let tagPaths = [
        "bag-info.txt",
        "bagit.txt",
        "manifest-sha256.txt",
        "negaflow-archive.json"
    ]

    static func validate(
        root: URL,
        fileManager: FileManager
    ) throws -> [String: LibraryArchiveFileDigest] {
        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw LibraryArchiveError.invalidPackage("archive root is not a directory")
        }
        let bagItURL = root.appendingPathComponent("bagit.txt")
        guard try Data(contentsOf: bagItURL) == Data(LibraryArchiveBagIt.bagItText.utf8) else {
            throw LibraryArchiveError.invalidPackage("unsupported bagit.txt")
        }
        let payloadRecords = try LibraryArchiveBagIt.parseManifest(
            Data(contentsOf: root.appendingPathComponent("manifest-sha256.txt"))
        )
        let tagRecords = try LibraryArchiveBagIt.parseManifest(
            Data(contentsOf: root.appendingPathComponent("tagmanifest-sha256.txt"))
        )
        guard Set(tagRecords.keys) == Set(tagPaths) else {
            throw LibraryArchiveError.invalidPackage("unexpected tag manifest")
        }

        var digests: [String: LibraryArchiveFileDigest] = [:]
        for (path, expected) in payloadRecords.merging(tagRecords, uniquingKeysWith: { first, _ in first }) {
            let url = try confinedURL(for: path, below: root)
            let digest = try LibraryArchiveFileIO.hash(url)
            guard digest.sha256 == expected else {
                throw LibraryArchiveError.invalidPackage("checksum mismatch: \(path)")
            }
            digests[path] = digest
        }
        let expectedFiles = Set(Array(payloadRecords.keys)
            + Array(tagRecords.keys)
            + ["tagmanifest-sha256.txt"])
        let actualFiles = Set(try LibraryArchiveFileIO.regularFiles(
            below: root,
            fileManager: fileManager
        ))
        guard expectedFiles == actualFiles else {
            throw LibraryArchiveError.invalidPackage("payload or tag file set mismatch")
        }
        guard payloadRecords.keys.allSatisfy({ $0.hasPrefix("data/") }) else {
            throw LibraryArchiveError.invalidPackage("payload outside data directory")
        }
        return digests
    }

    private static func confinedURL(for path: String, below root: URL) throws -> URL {
        guard LibraryArchiveFileIO.isSafeRelativePath(path) else {
            throw LibraryArchiveError.invalidPackage("unsafe relative path")
        }
        let standardizedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let candidate = standardizedRoot.appendingPathComponent(path).standardizedFileURL
        let prefix = standardizedRoot.path.hasSuffix("/")
            ? standardizedRoot.path
            : standardizedRoot.path + "/"
        guard candidate.path.hasPrefix(prefix) else {
            throw LibraryArchiveError.invalidPackage("escaped relative path")
        }
        return candidate
    }
}
