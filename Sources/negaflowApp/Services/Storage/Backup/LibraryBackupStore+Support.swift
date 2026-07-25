import Foundation
import CryptoKit

extension LibraryBackupStore {
    static func pruneSnapshots(
        in backupDirectory: URL,
        keeping retentionCount: Int,
        fileManager: FileManager
    ) {
        let snapshots = validSnapshots(in: backupDirectory, fileManager: fileManager)
            .sorted(by: LibraryBackupOrdering.isNewerSnapshot)
        for snapshot in snapshots.dropFirst(retentionCount) {
            try? fileManager.removeItem(at: snapshot.directoryURL)
        }
        if let urls = try? fileManager.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for url in urls where url.lastPathComponent.hasPrefix("staging-") {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    static func catalogURL(in directory: URL) -> URL {
        directory.appendingPathComponent("library.json")
    }

    static func defectsDirectory(in directory: URL) -> URL {
        directory.appendingPathComponent("defects", isDirectory: true)
    }

    static func manifestURL(in directory: URL) -> URL {
        directory.appendingPathComponent("manifest.json")
    }

    static func encodeManifest(_ manifest: LibraryBackupManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(manifest)
    }

    static func decodeManifest(_ data: Data) throws -> LibraryBackupManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LibraryBackupManifest.self, from: data)
    }

    static func sourceCatalogVersion(in data: Data) -> Int? {
        struct VersionProbe: Decodable { let version: Int }
        return try? JSONDecoder().decode(VersionProbe.self, from: data).version
    }

    static func backupFileRecords(
        defectFrameIDs: [UUID],
        in directory: URL,
        fileManager: FileManager
    ) throws -> [LibraryBackupFileRecord] {
        let paths = ["library.json"] + defectFrameIDs.map {
            "defects/\($0.uuidString).plist"
        }
        return try paths.sorted().map { relativePath in
            try backupFileRecord(
                relativePath: relativePath,
                in: directory,
                fileManager: fileManager
            )
        }
    }

    static func backupFileRecord(
        relativePath: String,
        in directory: URL,
        fileManager: FileManager
    ) throws -> LibraryBackupFileRecord {
        let url = directory.appendingPathComponent(relativePath)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw LibraryBackupError.invalidSnapshot
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteCount: Int64 = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
            byteCount += Int64(chunk.count)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return LibraryBackupFileRecord(
            relativePath: relativePath,
            byteCount: byteCount,
            sha256: digest
        )
    }

}
