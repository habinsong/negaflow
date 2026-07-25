import Foundation

/// 마지막으로 검증해 읽거나 기록한 SQLite catalog 값만 보관한다. 파일 지문이 달라지면
/// 외부 교체/변경으로 간주해 cache를 쓰지 않고 기존 전체 교체 경로로 돌아간다.
final class LibraryCatalogSQLiteWriteCache: @unchecked Sendable {
    static let shared = LibraryCatalogSQLiteWriteCache()

    private struct FileFingerprint: Equatable {
        let fileSize: UInt64
        let modificationTime: TimeInterval
        let fileNumber: UInt64
        let systemNumber: UInt64
    }

    private struct Entry {
        let fingerprint: FileFingerprint
        let catalog: LibraryCatalog
        var safetyValidated: Bool
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func currentCatalog(for url: URL, fileManager: FileManager = .default) -> LibraryCatalog? {
        guard let fingerprint = fingerprint(for: url, fileManager: fileManager) else {
            remove(url)
            return nil
        }
        return lock.withLock {
            guard let entry = entries[url.standardizedFileURL.path],
                  entry.fingerprint == fingerprint else {
                return nil
            }
            return entry.catalog
        }
    }

    func contains(
        _ catalog: LibraryCatalog,
        for url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        currentCatalog(for: url, fileManager: fileManager) == catalog
    }

    func store(
        _ catalog: LibraryCatalog,
        for url: URL,
        fileManager: FileManager = .default
    ) {
        guard let fingerprint = fingerprint(for: url, fileManager: fileManager) else {
            remove(url)
            return
        }
        lock.withLock {
            let key = url.standardizedFileURL.path
            let preservesSafety = entries[key].map {
                $0.fingerprint == fingerprint && $0.catalog == catalog && $0.safetyValidated
            } ?? false
            entries[key] = Entry(
                fingerprint: fingerprint,
                catalog: catalog,
                safetyValidated: preservesSafety
            )
        }
    }

    func safetyValidatedCatalog(
        for url: URL,
        fileManager: FileManager = .default
    ) -> LibraryCatalog? {
        guard let fingerprint = fingerprint(for: url, fileManager: fileManager) else {
            remove(url)
            return nil
        }
        return lock.withLock {
            guard let entry = entries[url.standardizedFileURL.path],
                  entry.fingerprint == fingerprint,
                  entry.safetyValidated else {
                return nil
            }
            return entry.catalog
        }
    }

    func markSafetyValidated(
        _ catalog: LibraryCatalog,
        for url: URL,
        fileManager: FileManager = .default
    ) {
        guard let fingerprint = fingerprint(for: url, fileManager: fileManager) else {
            remove(url)
            return
        }
        lock.withLock {
            let key = url.standardizedFileURL.path
            guard var entry = entries[key],
                  entry.fingerprint == fingerprint,
                  entry.catalog == catalog else { return }
            entry.safetyValidated = true
            entries[key] = entry
        }
    }

    func remove(_ url: URL) {
        _ = lock.withLock {
            entries.removeValue(forKey: url.standardizedFileURL.path)
        }
    }

    private func fingerprint(
        for url: URL,
        fileManager: FileManager
    ) -> FileFingerprint? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileSize = (attributes[.size] as? NSNumber)?.uint64Value,
              let modificationDate = attributes[.modificationDate] as? Date,
              let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let systemNumber = (attributes[.systemNumber] as? NSNumber)?.uint64Value else {
            return nil
        }
        return FileFingerprint(
            fileSize: fileSize,
            modificationTime: modificationDate.timeIntervalSinceReferenceDate,
            fileNumber: fileNumber,
            systemNumber: systemNumber
        )
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
