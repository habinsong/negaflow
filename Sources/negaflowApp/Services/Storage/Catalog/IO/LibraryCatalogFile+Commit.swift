import Foundation

extension LibraryCatalogFile {
    static func encode(_ catalog: LibraryCatalog) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(catalog)
    }

    @discardableResult
    static func write(
        _ data: Data,
        to url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        if LibraryCatalogSQLiteStore.isSQLiteURL(url) {
            guard let catalog = decode(data) else { return false }
            return writeCatalog(catalog, to: url, fileManager: fileManager)
        }
        do {
            let directory = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            // 직전 primary가 유효할 때만 backup 세대를 갱신한다. 손상 primary가 정상 backup을
            // 덮지 않으므로 다음 실행에서 마지막 유효 catalog를 복구할 수 있다.
            if loadPrimary(from: url) != nil {
                let current = try Data(contentsOf: url)
                try current.write(to: backupURL(for: url), options: .atomic)
            }
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func writeCatalog(
        _ catalog: LibraryCatalog,
        to url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard LibraryCatalogSQLiteStore.isSQLiteURL(url) else {
            guard let data = encode(catalog) else { return false }
            return write(data, to: url, fileManager: fileManager)
        }
        do {
            let primaryIsValid = LibraryCatalogSQLiteStore.isValidRecoverySource(at: url)
            if primaryIsValid,
               LibraryCatalogSQLiteWriteCache.shared.contains(catalog, for: url) {
                if !fileManager.fileExists(atPath: backupURL(for: url).path) {
                    try replaceSQLiteBackup(from: url, fileManager: fileManager)
                }
                return true
            }
            if primaryIsValid {
                try replaceSQLiteBackup(from: url, fileManager: fileManager)
            }
        } catch {
            return false
        }
        return LibraryCatalogSQLiteStore.write(catalog, to: url)
    }

    /// APFS의 clone-aware 파일 복사를 사용해 큰 SQLite primary를 메모리에 통째로 올리지 않고
    /// 직전 유효 세대를 교체한다. 임시 복사가 완성되기 전에는 기존 backup을 건드리지 않는다.
    private static func replaceSQLiteBackup(
        from sourceURL: URL,
        fileManager: FileManager
    ) throws {
        let destinationURL = backupURL(for: sourceURL)
        let temporaryURL = destinationURL.deletingLastPathComponent().appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    // 카탈로그 쓰기도 단일 직렬 큐로 정렬한다 — 디바운스 저장(비동기)과 종료 시 동기 저장이
    // 겹칠 때 오래된 내용이 최신 파일을 덮지 않도록(FIFO + sync 배리어).
    private static let ioQueueLabel = "negaflow.library-catalog-io"
    private static let ioQueue = DispatchQueue(label: ioQueueLabel, qos: .utility)

    static func writeAsync(
        _ data: Data,
        to url: URL,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        ioQueue.async {
            completion(write(data, to: url))
        }
    }

    static func writeCatalogAsync(
        _ catalog: LibraryCatalog,
        to url: URL,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        ioQueue.async {
            completion(writeCatalog(catalog, to: url))
        }
    }

    /// 앞서 예약된 쓰기까지 끝난 뒤 기록하고 반환한다(앱 종료 경로).
    @discardableResult
    static func writeSync(_ data: Data, to url: URL) -> Bool {
        ioQueue.sync { write(data, to: url) }
    }

    @discardableResult
    static func writeCatalogSync(_ catalog: LibraryCatalog, to url: URL) -> Bool {
        ioQueue.sync { writeCatalog(catalog, to: url) }
    }

    /// 앞선 비동기 write를 FIFO로 모두 소진한 뒤 한 catalog 세대를 원자적으로 기록하고,
    /// 디스크에서 다시 읽은 값의 schema/canonical payload/health가 모두 같은지 확인한다.
    /// write 이후 검증이 실패하면 같은 queue에서 캡처한 직전 primary bytes/부재 상태를 복구한다.
    /// 성공 반환 전에는 호출자가 대응하는 MainActor 상태를 publish하면 안 된다.
    static func commitAndVerify(
        _ catalog: LibraryCatalog,
        to url: URL,
        defectDirectory: URL = DefectSidecarFile.defaultDirectoryURL(),
        fileManager: FileManager = .default,
        catalogSafetyValidated: Bool = false
    ) -> Result<Void, LibraryCatalogCommitError> {
        if LibraryCatalogSQLiteStore.isSQLiteURL(url) {
            return ioQueue.sync {
                commitAndVerifySQLite(
                    catalog,
                    to: url,
                    defectDirectory: defectDirectory,
                    fileManager: fileManager,
                    catalogSafetyValidated: catalogSafetyValidated
                )
            }
        }
        return commitAndVerify(
            catalog,
            to: url,
            defectDirectory: defectDirectory,
            fileManager: fileManager,
            commitWriter: { data, destination, fileManager in
                write(data, to: destination, fileManager: fileManager)
            },
            readback: { source, fileManager in
                read(from: source, fileManager: fileManager)
            }
        )
    }

    /// write/read-back 실패를 결정적으로 재현하는 내부 테스트 seam.
    static func commitAndVerify(
        _ catalog: LibraryCatalog,
        to url: URL,
        defectDirectory: URL = DefectSidecarFile.defaultDirectoryURL(),
        fileManager: FileManager = .default,
        commitWriter: (_ data: Data, _ destination: URL, _ fileManager: FileManager) -> Bool,
        readback: (_ source: URL, _ fileManager: FileManager) -> LibraryCatalogReadResult,
        rollbackWriter: (_ data: Data, _ destination: URL) -> Bool = { data, destination in
            do {
                try data.write(to: destination, options: .atomic)
                return true
            } catch {
                return false
            }
        }
    ) -> Result<Void, LibraryCatalogCommitError> {
        ioQueue.sync {
            let health = LibraryCatalogHealthInspector.inspect(
                catalog,
                defectDirectory: defectDirectory,
                fileManager: fileManager,
                includeWarnings: false
            )
            guard health.canOpenSafely else {
                return .failure(.invalidCatalog)
            }
            guard let data = encode(catalog),
                  let expectedCanonicalData = canonicalData(catalog) else {
                return .failure(.encodingFailed)
            }

            let previousPrimary: Data?
            let primaryExisted = fileManager.fileExists(atPath: url.path)
            if primaryExisted {
                guard let data = try? Data(contentsOf: url) else {
                    return .failure(.writeFailed)
                }
                previousPrimary = data
            } else {
                previousPrimary = nil
            }

            guard commitWriter(data, url, fileManager) else {
                return restorePrimary(
                    previousPrimary,
                    existed: primaryExisted,
                    at: url,
                    fileManager: fileManager,
                    rollbackWriter: rollbackWriter
                ) ? .failure(.writeFailed) : .failure(.rollbackFailed)
            }
            guard case let .loaded(persisted, sourceVersion) = readback(url, fileManager),
                  sourceVersion == LibraryCatalog.currentVersion,
                  canonicalData(persisted) == expectedCanonicalData,
                  LibraryCatalogHealthInspector.inspect(
                      persisted,
                      defectDirectory: defectDirectory,
                      fileManager: fileManager,
                      includeWarnings: false
                  ).canOpenSafely else {
                return restorePrimary(
                    previousPrimary,
                    existed: primaryExisted,
                    at: url,
                    fileManager: fileManager,
                    rollbackWriter: rollbackWriter
                ) ? .failure(.readbackFailed) : .failure(.rollbackFailed)
            }
            return .success(())
        }
    }

    static func restorePrimary(
        _ data: Data?,
        existed: Bool,
        at url: URL,
        fileManager: FileManager,
        rollbackWriter: (_ data: Data, _ destination: URL) -> Bool
    ) -> Bool {
        do {
            if existed {
                guard let data, rollbackWriter(data, url) else { return false }
                let restored = try Data(contentsOf: url)
                return fileManager.fileExists(atPath: url.path)
                    && restored == data
            }
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            return !fileManager.fileExists(atPath: url.path)
        } catch {
            return false
        }
    }

    /// 앱이 카탈로그를 메모리에 적용하기 전에 실행하는 fail-closed 준비 단계.
    /// 이전 schema는 메모리에서 현재 버전으로 변환한 뒤 원본을 backup으로 보존하고 원자적으로 승격한다.
    /// 미래 버전, 손상 파일, authoritative recipe 유실은 빈 라이브러리로 취급하지 않는다.

}
