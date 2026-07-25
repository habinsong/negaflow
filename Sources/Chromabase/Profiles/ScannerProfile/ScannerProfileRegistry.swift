import Foundation
import CryptoKit

public struct ScannerProfileBundleEntryIdentity: Codable, Equatable, Sendable {
    public let id: String
    public let profileHash: String
    public let fileSHA256: String
}

public struct ScannerProfileBundleIdentity: Codable, Equatable, Sendable {
    public let manifestSHA256: String
    public let declaredProfileCount: Int
    public let entries: [ScannerProfileBundleEntryIdentity]
}

public struct ScannerProfileBundleSnapshot: Sendable {
    public let identity: ScannerProfileBundleIdentity
    public let profiles: [ScannerProfile]
}

public enum ScannerProfileRegistry {
    // 프로파일은 immutable 리소스다. 과거엔 load(named:)가 매 현상마다(슬라이더 한 번에 한 번)
    // 번들 JSON을 다시 읽고 디코드해 핫패스에 디스크 I/O + JSON 파싱 비용을 매번 지불했다.
    // 리소스 상태가 바뀌면 파일 바이트의 SHA를 다시 확인하되, 변경되지 않은 완전 검증 snapshot과
    // 동일한 manifest identity로 디코드한 결과는 캐시한다. 여러 백그라운드 현상 스레드가 동시에
    // 접근하므로 락으로 보호한다.
    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cache: [ProfileCacheKey: ScannerProfile] = [:]
    private nonisolated(unsafe) static var bundleCache: [String: BundleCacheEntry] = [:]

    private struct ProfileCacheKey: Hashable {
        let id: String
        let profileHash: String
        let fileSHA256: String
    }

    private struct BundleCacheEntry {
        let fileStates: [ProfileFileState]
        let snapshot: ScannerProfileBundleSnapshot
    }

    private struct ProfileFileState: Equatable {
        let path: String
        let fileSize: UInt64
        let modificationDate: Date
        let systemNumber: UInt64
        let systemFileNumber: UInt64
    }

    public static func loadAll() -> [ScannerProfile] {
        loadValidatedBundle()?.profiles ?? []
    }

    /// manifest와 모든 프로파일 파일이 전부 검증될 때만 snapshot을 반환한다. 일부 파일만
    /// 누락된 상태에서 남은 pair로 상대 시그니처를 조용히 바꾸지 않도록 fail-closed다.
    public static func loadValidatedBundle() -> ScannerProfileBundleSnapshot? {
        guard let profilesDirectoryURL = bundledProfilesDirectoryURL else { return nil }
        return loadValidatedBundle(profilesDirectoryURL: profilesDirectoryURL)
    }

    static var bundledProfilesDirectoryURL: URL? {
        Bundle.module.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: "ScannerProfiles"
        )?.deletingLastPathComponent()
    }

    static func loadValidatedBundle(
        profilesDirectoryURL: URL
    ) -> ScannerProfileBundleSnapshot? {
        let cacheKey = profilesDirectoryURL.standardizedFileURL.path
        if let cached = cachedBundle(cacheKey: cacheKey),
           currentFileStates(for: cached.fileStates.map(\.path)) == cached.fileStates {
            return cached.snapshot
        }
        cacheLock.lock()
        bundleCache.removeValue(forKey: cacheKey)
        cacheLock.unlock()

        let manifestURL = profilesDirectoryURL.appendingPathComponent("manifest.json")
        guard let manifestStateBeforeRead = currentFileState(at: manifestURL) else { return nil }
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(ScannerProfileManifest.self, from: data),
              manifest.isValid else {
            return nil
        }
        let profileURLs = manifest.profiles.map {
            profilesDirectoryURL
                .appendingPathComponent($0.id)
                .appendingPathExtension("json")
        }
        guard let fileStatesBeforeRead = currentFileStates(
            for: [manifestURL.path] + profileURLs.map(\.path)
        ), fileStatesBeforeRead.first == manifestStateBeforeRead else {
            return nil
        }
        let profiles = manifest.profiles.compactMap { entry in
            load(
                entry: entry,
                profilesDirectoryURL: profilesDirectoryURL
            )
        }
        guard profiles.count == manifest.profiles.count,
              currentFileStates(for: fileStatesBeforeRead.map(\.path)) == fileStatesBeforeRead else {
            return nil
        }
        let snapshot = ScannerProfileBundleSnapshot(
            identity: ScannerProfileBundleIdentity(
                manifestSHA256: fileSHA256(data),
                declaredProfileCount: manifest.profileCount,
                entries: manifest.profiles.map {
                    ScannerProfileBundleEntryIdentity(
                        id: $0.id,
                        profileHash: $0.profileHash,
                        fileSHA256: $0.fileSHA256
                    )
                }
            ),
            profiles: profiles
        )
        cacheLock.lock()
        bundleCache[cacheKey] = BundleCacheEntry(
            fileStates: fileStatesBeforeRead,
            snapshot: snapshot
        )
        cacheLock.unlock()
        return snapshot
    }

    public static func load(named id: String) -> ScannerProfile? {
        guard let profilesDirectoryURL = bundledProfilesDirectoryURL else { return nil }
        return load(named: id, profilesDirectoryURL: profilesDirectoryURL)
    }

    static func load(named id: String, profilesDirectoryURL: URL) -> ScannerProfile? {
        loadValidatedBundle(profilesDirectoryURL: profilesDirectoryURL)?
            .profiles
            .first(where: { $0.id == id })
    }

    private static func load(
        entry: ScannerProfileManifest.Entry,
        profilesDirectoryURL: URL
    ) -> ScannerProfile? {
        let url = profilesDirectoryURL
            .appendingPathComponent(entry.id)
            .appendingPathExtension("json")
        guard let data = try? Data(contentsOf: url),
              fileSHA256(data) == entry.fileSHA256 else {
            return nil
        }

        let cacheKey = ProfileCacheKey(
            id: entry.id,
            profileHash: entry.profileHash,
            fileSHA256: entry.fileSHA256
        )
        cacheLock.lock()
        if let cached = cache[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let profile = decodeValidatedProfileContents(
            data,
            expectedID: entry.id,
            expectedHash: entry.profileHash
        ) else { return nil }

        cacheLock.lock()
        cache[cacheKey] = profile
        cacheLock.unlock()
        return profile
    }

    private struct ScannerProfileManifest: Codable {
        var schemaVersion: Int
        var profileCount: Int
        var profiles: [Entry]
        struct Entry: Codable {
            var id: String
            var profileHash: String
            var fileSHA256: String
        }

        var isValid: Bool {
            schemaVersion == 2
                && profileCount == profiles.count
                && profileCount > 0
                && Set(profiles.map(\.id)).count == profiles.count
                && profiles.allSatisfy {
                    !$0.id.isEmpty
                        && Self.isValidHash($0.profileHash)
                        && Self.isValidHash($0.fileSHA256)
                }
        }

        private static func isValidHash(_ value: String) -> Bool {
            guard value.hasPrefix("sha256:") else { return false }
            let digest = value.dropFirst("sha256:".count)
            return digest.count == 64 && digest.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (97...102).contains(byte)
            }
        }
    }

    static func decodeValidatedProfile(
        _ data: Data,
        expectedID: String,
        expectedHash: String,
        expectedFileSHA256: String
    ) -> ScannerProfile? {
        guard fileSHA256(data) == expectedFileSHA256 else {
            return nil
        }
        return decodeValidatedProfileContents(
            data,
            expectedID: expectedID,
            expectedHash: expectedHash
        )
    }

    private static func decodeValidatedProfileContents(
        _ data: Data,
        expectedID: String,
        expectedHash: String
    ) -> ScannerProfile? {
        guard let profile = try? JSONDecoder().decode(ScannerProfile.self, from: data),
              profile.schemaVersion == 2,
              profile.id == expectedID,
              profile.profileHash == expectedHash else {
            return nil
        }
        return profile
    }

    private static func cachedBundle(cacheKey: String) -> BundleCacheEntry? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return bundleCache[cacheKey]
    }

    private static func currentFileStates(for paths: [String]) -> [ProfileFileState]? {
        let states = paths.compactMap { currentFileState(at: URL(fileURLWithPath: $0)) }
        return states.count == paths.count ? states : nil
    }

    private static func currentFileState(at url: URL) -> ProfileFileState? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let fileSize = attributes[.size] as? NSNumber,
              let modificationDate = attributes[.modificationDate] as? Date,
              let systemNumber = attributes[.systemNumber] as? NSNumber,
              let systemFileNumber = attributes[.systemFileNumber] as? NSNumber else {
            return nil
        }
        return ProfileFileState(
            path: url.standardizedFileURL.path,
            fileSize: fileSize.uint64Value,
            modificationDate: modificationDate,
            systemNumber: systemNumber.uint64Value,
            systemFileNumber: systemFileNumber.uint64Value
        )
    }

    static func computedFileSHA256(named id: String) -> String? {
        guard let url = Bundle.module.url(
            forResource: id,
            withExtension: "json",
            subdirectory: "ScannerProfiles"
        ), let data = try? Data(contentsOf: url) else {
            return nil
        }
        return fileSHA256(data)
    }
    private static func fileSHA256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return "sha256:\(digest)"
    }
}
