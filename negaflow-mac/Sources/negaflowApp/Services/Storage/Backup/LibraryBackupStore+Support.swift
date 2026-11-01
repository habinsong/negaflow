import Foundation
import CryptoKit

extension LibraryBackupStore {
    static func pruneSnapshots(
        in backupDirectory: URL,
        keeping retentionCount: Int,
        fileManager: FileManager
    ) {
        // 새 세대부터 훑어 온전한 세대를 `retentionCount` 개 찾을 때까지만 검증한다(체크섬은
        // 세대 전체를 읽는다). 그보다 오래된 세대는 검증 없이 지운다 — 온전한 새 세대가 이미
        // 그만큼 있으니 잃는 것이 없고, 깨진 옛 세대도 영영 남지 않는다. 매니페스트조차 읽히지
        // 않는 폴더는 무엇인지 모르므로 건드리지 않는다.
        let generations = ((try? fileManager.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []).compactMap { url -> (url: URL, manifest: LibraryBackupManifest)? in
            guard url.lastPathComponent.hasPrefix("backup-"),
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let data = try? Data(contentsOf: manifestURL(in: url)),
                  let manifest = try? decodeManifest(data) else { return nil }
            return (url, manifest)
        }.sorted(by: LibraryBackupOrdering.isNewerManifest)
        var kept = 0
        for generation in generations {
            if kept >= retentionCount {
                // 이 앱보다 새 버전이 만든 세대는 무엇이 들었는지 모르므로 남긴다.
                guard generation.manifest.version <= LibraryBackupManifest.currentVersion else { continue }
                try? fileManager.removeItem(at: generation.url)
            } else if validateSnapshot(at: generation.url, fileManager: fileManager) != nil {
                kept += 1
            }
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
