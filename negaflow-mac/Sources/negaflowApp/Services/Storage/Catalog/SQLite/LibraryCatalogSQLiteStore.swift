import Foundation
import ScannerKit
import SQLite3

enum LibraryCatalogSQLiteReadResult {
    case loaded(LibraryCatalog)
    case unsupportedStorageVersion(Int)
    case invalid
}

enum LibraryCatalogSQLiteStore {
    static let storageSchemaVersion: Int32 = 1

    private struct Row {
        let id: String
        let position: Int
        let payload: Data
    }

    private enum StoreError: Error {
        case sqlite(String)
        case invalidValue
    }

    private static let entityTables = [
        "folders",
        "frames",
        "rolls",
        "scan_sessions",
        "scan_roll_assignments",
        "manual_collections",
        "smart_collections",
        "saved_searches",
        "stacks",
    ]

    static func isSQLiteURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "sqlite"
    }

    static func read(from url: URL) -> LibraryCatalogSQLiteReadResult {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            return .invalid
        }
        defer { sqlite3_close(database) }

        do {
            try requireIntegrity(database)
            let storageVersion = try int32Scalar(database, sql: "PRAGMA user_version")
            guard storageVersion == storageSchemaVersion else {
                return .unsupportedStorageVersion(Int(storageVersion))
            }
            let metadata = try metadataRow(database)
            let version = metadata.version
            guard version == LibraryCatalog.currentVersion,
                  metadata.minimumReaderVersion == LibraryCatalog.oldestReaderVersion else {
                return .invalid
            }
            let folders: [String] = try decodeRows(database, table: "folders")
            let frames: [LibraryFrameRecord] = try decodeRows(database, table: "frames")
            let rolls: [LibraryRoll] = try decodeRows(database, table: "rolls")
            let sessions: [ScanSession] = try decodeRows(database, table: "scan_sessions")
            let assignments: [LibraryScanRollAssignment] = try decodeRows(
                database,
                table: "scan_roll_assignments"
            )
            let manual: [LibraryManualCollection] = try decodeRows(
                database,
                table: "manual_collections"
            )
            let smart: [LibrarySmartCollection] = try decodeRows(
                database,
                table: "smart_collections"
            )
            let searches: [LibrarySavedSearch] = try decodeRows(
                database,
                table: "saved_searches"
            )
            let stacks: [LibraryPhotoStack] = try decodeRows(database, table: "stacks")
            let catalog = LibraryCatalog(
                version: version,
                minimumReaderVersion: metadata.minimumReaderVersion,
                folders: folders,
                frames: frames,
                rolls: rolls,
                activeRollID: metadata.activeRollID,
                scanSessions: sessions,
                scanRollAssignments: assignments,
                manualCollections: manual,
                smartCollections: smart,
                savedSearches: searches,
                stacks: stacks,
                lastActiveFrameID: metadata.lastActiveFrameID
            )
            LibraryCatalogSQLiteWriteCache.shared.store(catalog, for: url)
            return .loaded(catalog)
        } catch {
            LibraryCatalogSQLiteWriteCache.shared.remove(url)
            return .invalid
        }
    }

    /// recovery copy 직전에는 전체 5만 frame payload를 decode할 필요가 없다. SQLite 무결성과
    /// 저장소/catalog schema metadata만 확인해 손상 primary가 유효 backup을 덮지 않게 한다.
    static func isValidRecoverySource(at url: URL) -> Bool {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            return false
        }
        defer { sqlite3_close(database) }
        do {
            try requireIntegrity(database)
            guard try int32Scalar(database, sql: "PRAGMA user_version")
                    == storageSchemaVersion else { return false }
            let metadata = try metadataRow(database)
            return metadata.version == LibraryCatalog.currentVersion
                && metadata.minimumReaderVersion == LibraryCatalog.oldestReaderVersion
        } catch {
            return false
        }
    }

    static func write(_ catalog: LibraryCatalog, to url: URL) -> Bool {
        var database: OpaquePointer?
        let existed = FileManager.default.fileExists(atPath: url.path)
        let previousCatalog = existed
            ? LibraryCatalogSQLiteWriteCache.shared.currentCatalog(for: url)
            : nil
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard sqlite3_open_v2(
                url.path,
                &database,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                nil
            ) == SQLITE_OK, let database else {
                throw StoreError.sqlite("open failed")
            }
            defer { sqlite3_close(database) }
            try execute(database, "PRAGMA journal_mode=DELETE")
            try execute(database, "PRAGMA synchronous=FULL")
            try execute(database, "PRAGMA foreign_keys=ON")
            let existingStorageVersion = try int32Scalar(database, sql: "PRAGMA user_version")
            if existed {
                guard existingStorageVersion == storageSchemaVersion else {
                    throw StoreError.invalidValue
                }
                try createTables(database)
                if previousCatalog == catalog {
                    try requireIntegrity(database)
                    return true
                }
            } else {
                guard existingStorageVersion == 0 else { throw StoreError.invalidValue }
                try createTables(database)
                try execute(database, "PRAGMA user_version=\(storageSchemaVersion)")
            }
            try execute(database, "BEGIN IMMEDIATE")
            do {
                try upsertMetadata(database, catalog: catalog)
                try synchronizeRows(
                    database,
                    table: "folders",
                    values: catalog.folders,
                    previousValues: previousCatalog?.folders,
                    id: { $0 }
                )
                try synchronizeRows(
                    database,
                    table: "frames",
                    values: catalog.frames,
                    previousValues: previousCatalog?.frames,
                    id: { $0.id.uuidString }
                )
                try synchronizeRows(
                    database,
                    table: "rolls",
                    values: catalog.rolls,
                    previousValues: previousCatalog?.rolls,
                    id: { $0.id.uuidString }
                )
                try synchronizeRows(
                    database,
                    table: "scan_sessions",
                    values: catalog.scanSessions,
                    previousValues: previousCatalog?.scanSessions,
                    id: { $0.id.uuidString }
                )
                try synchronizeRows(
                    database,
                    table: "scan_roll_assignments",
                    values: catalog.scanRollAssignments,
                    previousValues: previousCatalog?.scanRollAssignments,
                    id: { $0.sessionID.uuidString }
                )
                try synchronizeRows(
                    database,
                    table: "manual_collections",
                    values: catalog.manualCollections,
                    previousValues: previousCatalog?.manualCollections,
                    id: { $0.id.uuidString }
                )
                try synchronizeRows(
                    database,
                    table: "smart_collections",
                    values: catalog.smartCollections,
                    previousValues: previousCatalog?.smartCollections,
                    id: { $0.id.uuidString }
                )
                try synchronizeRows(
                    database,
                    table: "saved_searches",
                    values: catalog.savedSearches,
                    previousValues: previousCatalog?.savedSearches,
                    id: { $0.id.uuidString }
                )
                try synchronizeRows(
                    database,
                    table: "stacks",
                    values: catalog.stacks,
                    previousValues: previousCatalog?.stacks,
                    id: { $0.id.uuidString }
                )
                try execute(database, "COMMIT")
                try requireIntegrity(database)
                LibraryCatalogSQLiteWriteCache.shared.store(catalog, for: url)
                return true
            } catch {
                try? execute(database, "ROLLBACK")
                throw error
            }
        } catch {
            if !existed { try? FileManager.default.removeItem(at: url) }
            LibraryCatalogSQLiteWriteCache.shared.remove(url)
            return false
        }
    }

    private static func synchronizeRows<Value: Encodable & Equatable>(
        _ database: OpaquePointer,
        table: String,
        values: [Value],
        previousValues: [Value]?,
        id: (Value) -> String
    ) throws {
        guard let previousValues,
              previousValues.count == values.count,
              zip(previousValues, values).allSatisfy({ id($0.0) == id($0.1) }) else {
            try replaceRows(database, table: table, rows: rows(values, id: id))
            return
        }

        let encoder = makeEncoder()
        var changedRows: [Row] = []
        for (position, pair) in zip(previousValues, values).enumerated()
        where pair.0 != pair.1 {
            changedRows.append(Row(
                id: id(pair.1),
                position: position,
                payload: try encoder.encode(pair.1)
            ))
        }
        try upsertRows(database, table: table, rows: changedRows)
    }

    private static func upsertRows(
        _ database: OpaquePointer,
        table: String,
        rows: [Row]
    ) throws {
        guard entityTables.contains(table) else { throw StoreError.invalidValue }
        guard !rows.isEmpty else { return }
        let statement = try prepare(database, """
            INSERT INTO \(table)(id, position, payload) VALUES(?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              position=excluded.position,
              payload=excluded.payload
            WHERE \(table).position != excluded.position
               OR \(table).payload != excluded.payload
            """)
        defer { sqlite3_finalize(statement) }
        for row in rows {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindText(statement, index: 1, value: row.id)
            sqlite3_bind_int64(statement, 2, sqlite3_int64(row.position))
            try bindData(statement, index: 3, value: row.payload)
            try stepDone(database, statement)
        }
    }

    private static func createTables(_ database: OpaquePointer) throws {
        try execute(database, """
            CREATE TABLE IF NOT EXISTS catalog_metadata (
              singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
              catalog_version INTEGER NOT NULL,
              minimum_reader_version INTEGER NOT NULL,
              active_roll_id TEXT
            )
            """)
        // 나중에 추가된 컬럼. 이미 만들어진 DB 에는 CREATE TABLE 이 걸리지 않으므로 ALTER 로
        // 붙인다(이미 있으면 SQLite 가 에러를 내므로 조용히 넘긴다).
        try? execute(database, "ALTER TABLE catalog_metadata ADD COLUMN last_active_frame_id TEXT")
        for table in entityTables {
            try execute(database, """
                CREATE TABLE IF NOT EXISTS \(table) (
                  id TEXT PRIMARY KEY NOT NULL,
                  position INTEGER NOT NULL UNIQUE CHECK (position >= 0),
                  payload BLOB NOT NULL
                )
                """)
        }
    }

    private static func upsertMetadata(
        _ database: OpaquePointer,
        catalog: LibraryCatalog
    ) throws {
        let statement = try prepare(database, """
            INSERT INTO catalog_metadata(
              singleton, catalog_version, minimum_reader_version, active_roll_id,
              last_active_frame_id
            ) VALUES(1, ?, ?, ?, ?)
            ON CONFLICT(singleton) DO UPDATE SET
              catalog_version=excluded.catalog_version,
              minimum_reader_version=excluded.minimum_reader_version,
              active_roll_id=excluded.active_roll_id,
              last_active_frame_id=excluded.last_active_frame_id
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(catalog.version))
        sqlite3_bind_int64(statement, 2, sqlite3_int64(catalog.minimumReaderVersion))
        if let activeRollID = catalog.activeRollID {
            try bindText(statement, index: 3, value: activeRollID.uuidString)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        if let lastActiveFrameID = catalog.lastActiveFrameID {
            try bindText(statement, index: 4, value: lastActiveFrameID.uuidString)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        try stepDone(database, statement)
    }

    private static func replaceRows(
        _ database: OpaquePointer,
        table: String,
        rows: [Row]
    ) throws {
        guard entityTables.contains(table),
              Set(rows.map(\.id)).count == rows.count else {
            throw StoreError.invalidValue
        }
        try execute(database, "DROP TABLE IF EXISTS temp.desired_ids")
        try execute(database, "CREATE TEMP TABLE desired_ids(id TEXT PRIMARY KEY NOT NULL)")
        let desired = try prepare(database, "INSERT INTO desired_ids(id) VALUES(?)")
        let upsert = try prepare(database, """
            INSERT INTO \(table)(id, position, payload) VALUES(?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              position=excluded.position,
              payload=excluded.payload
            WHERE \(table).position != excluded.position
               OR \(table).payload != excluded.payload
            """)
        defer {
            sqlite3_finalize(desired)
            sqlite3_finalize(upsert)
            try? execute(database, "DROP TABLE IF EXISTS temp.desired_ids")
        }
        for row in rows {
            sqlite3_reset(desired)
            sqlite3_clear_bindings(desired)
            try bindText(desired, index: 1, value: row.id)
            try stepDone(database, desired)
        }
        try execute(
            database,
            "DELETE FROM \(table) WHERE id NOT IN (SELECT id FROM desired_ids)"
        )
        for row in rows {
            sqlite3_reset(upsert)
            sqlite3_clear_bindings(upsert)
            try bindText(upsert, index: 1, value: row.id)
            sqlite3_bind_int64(upsert, 2, sqlite3_int64(row.position))
            try bindData(upsert, index: 3, value: row.payload)
            try stepDone(database, upsert)
        }
    }

    private static func rows<Value: Encodable>(
        _ values: [Value],
        id: (Value) -> String
    ) throws -> [Row] {
        let encoder = makeEncoder()
        return try values.enumerated().map { position, value in
            Row(id: id(value), position: position, payload: try encoder.encode(value))
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// 사진과 그 소속은 라이브러리의 뼈대라 한 줄이라도 못 읽으면 열지 않는다. 반면 스캔
    /// 이력이나 컬렉션 같은 부수 기록은 한 줄이 낡은 형식이어도 그 줄만 버리고 연다 —
    /// 예전 버전이 쓴 payload 하나 때문에 라이브러리 전체를 못 여는 일은 없어야 한다.
    /// (버려서 생기는 고아 참조는 `LibraryCatalogRepair` 가 정리한다.)
    private static let strictTables: Set<String> = ["folders", "frames", "rolls"]

    private static func decodeRows<Value: Decodable & Sendable>(
        _ database: OpaquePointer,
        table: String
    ) throws -> [Value] {
        guard entityTables.contains(table) else { throw StoreError.invalidValue }
        let statement = try prepare(
            database,
            "SELECT payload FROM \(table) ORDER BY position ASC"
        )
        defer { sqlite3_finalize(statement) }
        var payloads: [Data] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW,
                  let bytes = sqlite3_column_blob(statement, 0) else {
                throw StoreError.sqlite(errorMessage(database))
            }
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0 else { throw StoreError.invalidValue }
            payloads.append(Data(bytes: bytes, count: count))
        }
        return try decodePayloads(payloads, lenient: !strictTables.contains(table))
    }

    private static func decodePayloads<Value: Decodable & Sendable>(
        _ payloads: [Data],
        lenient: Bool = false
    ) throws -> [Value] {
        let processorCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let chunkCount = min(processorCount, max(1, payloads.count / 512))
        guard chunkCount > 1 else {
            let decoder = makeDecoder()
            if lenient {
                return payloads.compactMap { try? decoder.decode(Value.self, from: $0) }
            }
            return try payloads.map { try decoder.decode(Value.self, from: $0) }
        }

        let results = LibraryCatalogSQLiteDecodeResults<Value>(chunkCount: chunkCount)
        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunkIndex in
            let lowerBound = payloads.count * chunkIndex / chunkCount
            let upperBound = payloads.count * (chunkIndex + 1) / chunkCount
            do {
                let decoded: [Value] = try autoreleasepool {
                    let decoder = makeDecoder()
                    if lenient {
                        return payloads[lowerBound..<upperBound].compactMap {
                            try? decoder.decode(Value.self, from: $0)
                        }
                    }
                    return try payloads[lowerBound..<upperBound].map {
                        try decoder.decode(Value.self, from: $0)
                    }
                }
                results.store(.success(decoded), at: chunkIndex)
            } catch {
                results.store(.failure(error), at: chunkIndex)
            }
        }
        return try results.assembled()
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func metadataRow(
        _ database: OpaquePointer
    ) throws -> (
        version: Int,
        minimumReaderVersion: Int,
        activeRollID: UUID?,
        lastActiveFrameID: UUID?
    ) {
        // 나중에 붙은 컬럼은 예전 파일에 없다. 읽기는 READONLY 라 ALTER 로 붙일 수 없으니,
        // 없으면 없는 대로 읽는다 — 컬럼 하나 때문에 라이브러리 전체를 못 여는 일은 없어야 한다.
        let hasLastActiveFrameID = columnExists(
            database,
            table: "catalog_metadata",
            column: "last_active_frame_id"
        )
        let statement = try prepare(database, """
            SELECT catalog_version, minimum_reader_version, active_roll_id,
                   \(hasLastActiveFrameID ? "last_active_frame_id" : "NULL")
            FROM catalog_metadata WHERE singleton=1
            """)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw StoreError.invalidValue }
        let version = Int(sqlite3_column_int64(statement, 0))
        let minimumReaderVersion = Int(sqlite3_column_int64(statement, 1))
        let activeRollID: UUID?
        if sqlite3_column_type(statement, 2) == SQLITE_NULL {
            activeRollID = nil
        } else if let raw = sqlite3_column_text(statement, 2),
                  let value = UUID(uuidString: String(cString: raw)) {
            activeRollID = value
        } else {
            throw StoreError.invalidValue
        }
        // 기억해 둔 사진은 없어도 되고 값이 깨졌으면 조용히 버린다 — 이것 때문에 라이브러리
        // 전체를 못 여는 일은 없어야 한다.
        var lastActiveFrameID: UUID?
        if sqlite3_column_type(statement, 3) != SQLITE_NULL,
           let raw = sqlite3_column_text(statement, 3) {
            lastActiveFrameID = UUID(uuidString: String(cString: raw))
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.invalidValue }
        return (version, minimumReaderVersion, activeRollID, lastActiveFrameID)
    }

    static func columnExists(
        _ database: OpaquePointer,
        table: String,
        column: String
    ) -> Bool {
        guard let statement = try? prepare(database, "PRAGMA table_info(\(table))") else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: raw) == column { return true }
        }
        return false
    }

    private static func requireIntegrity(_ database: OpaquePointer) throws {
        let statement = try prepare(database, "PRAGMA integrity_check")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0),
              String(cString: value) == "ok",
              sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.invalidValue
        }
    }

    private static func int32Scalar(
        _ database: OpaquePointer,
        sql: String
    ) throws -> Int32 {
        let statement = try prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw StoreError.invalidValue }
        let value = sqlite3_column_int(statement, 0)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.invalidValue }
        return value
    }

    private static func execute(_ database: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.sqlite(errorMessage(database))
        }
    }

    private static func prepare(
        _ database: OpaquePointer,
        _ sql: String
    ) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw StoreError.sqlite(errorMessage(database))
        }
        return statement
    }

    private static func stepDone(_ database: OpaquePointer, _ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.sqlite(errorMessage(database))
        }
    }

    private static func bindText(
        _ statement: OpaquePointer,
        index: Int32,
        value: String
    ) throws {
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw StoreError.invalidValue
        }
    }

    private static func bindData(
        _ statement: OpaquePointer,
        index: Int32,
        value: Data
    ) throws {
        let result = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
        }
        guard result == SQLITE_OK else { throw StoreError.invalidValue }
    }

    private static var sqliteTransient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private static func errorMessage(_ database: OpaquePointer) -> String {
        sqlite3_errmsg(database).map(String.init(cString:)) ?? "unknown sqlite error"
    }
}

private final class LibraryCatalogSQLiteDecodeResults<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [[Value]?]
    private var firstError: Error?

    init(chunkCount: Int) {
        chunks = Array(repeating: nil, count: chunkCount)
    }

    func store(_ result: Result<[Value], Error>, at index: Int) {
        lock.lock()
        defer { lock.unlock() }
        switch result {
        case let .success(values):
            chunks[index] = values
        case let .failure(error):
            if firstError == nil { firstError = error }
        }
    }

    func assembled() throws -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        if let firstError { throw firstError }
        guard chunks.allSatisfy({ $0 != nil }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return chunks.flatMap { $0 ?? [] }
    }
}
