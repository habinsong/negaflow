import Foundation
import SQLite3

enum LibraryCatalogSQLiteIncrementalVerifier {
    private enum VerificationError: Error {
        case invalid
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

    static func canVerify(
        _ catalog: LibraryCatalog,
        from previousCatalog: LibraryCatalog
    ) -> Bool {
        hasStableIdentity(catalog.folders, previousCatalog.folders, id: { $0 })
            && hasStableIdentity(catalog.frames, previousCatalog.frames, id: { $0.id.uuidString })
            && hasStableIdentity(catalog.rolls, previousCatalog.rolls, id: { $0.id.uuidString })
            && hasStableIdentity(
                catalog.scanSessions,
                previousCatalog.scanSessions,
                id: { $0.id.uuidString }
            )
            && hasStableIdentity(
                catalog.scanRollAssignments,
                previousCatalog.scanRollAssignments,
                id: { $0.sessionID.uuidString }
            )
            && hasStableIdentity(
                catalog.manualCollections,
                previousCatalog.manualCollections,
                id: { $0.id.uuidString }
            )
            && hasStableIdentity(
                catalog.smartCollections,
                previousCatalog.smartCollections,
                id: { $0.id.uuidString }
            )
            && hasStableIdentity(
                catalog.savedSearches,
                previousCatalog.savedSearches,
                id: { $0.id.uuidString }
            )
            && hasStableIdentity(catalog.stacks, previousCatalog.stacks, id: { $0.id.uuidString })
    }

    /// 직전 검증 세대와 identity/order가 같은 경우에만 변경 payload와 전체 table shape를
    /// 디스크에서 다시 확인한다. 어느 조건이든 어긋나면 caller가 전체 read-back으로 돌아간다.
    static func verify(
        _ catalog: LibraryCatalog,
        from previousCatalog: LibraryCatalog,
        at url: URL
    ) -> Bool {
        guard canVerify(catalog, from: previousCatalog) else { return false }
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
            guard try intScalar(database, sql: "PRAGMA user_version")
                    == Int(LibraryCatalogSQLiteStore.storageSchemaVersion) else {
                throw VerificationError.invalid
            }
            try verifyMetadata(database, catalog: catalog)
            try verifyRows(
                database,
                table: "folders",
                values: catalog.folders,
                previousValues: previousCatalog.folders,
                id: { $0 }
            )
            try verifyRows(
                database,
                table: "frames",
                values: catalog.frames,
                previousValues: previousCatalog.frames,
                id: { $0.id.uuidString }
            )
            try verifyRows(
                database,
                table: "rolls",
                values: catalog.rolls,
                previousValues: previousCatalog.rolls,
                id: { $0.id.uuidString }
            )
            try verifyRows(
                database,
                table: "scan_sessions",
                values: catalog.scanSessions,
                previousValues: previousCatalog.scanSessions,
                id: { $0.id.uuidString }
            )
            try verifyRows(
                database,
                table: "scan_roll_assignments",
                values: catalog.scanRollAssignments,
                previousValues: previousCatalog.scanRollAssignments,
                id: { $0.sessionID.uuidString }
            )
            try verifyRows(
                database,
                table: "manual_collections",
                values: catalog.manualCollections,
                previousValues: previousCatalog.manualCollections,
                id: { $0.id.uuidString }
            )
            try verifyRows(
                database,
                table: "smart_collections",
                values: catalog.smartCollections,
                previousValues: previousCatalog.smartCollections,
                id: { $0.id.uuidString }
            )
            try verifyRows(
                database,
                table: "saved_searches",
                values: catalog.savedSearches,
                previousValues: previousCatalog.savedSearches,
                id: { $0.id.uuidString }
            )
            try verifyRows(
                database,
                table: "stacks",
                values: catalog.stacks,
                previousValues: previousCatalog.stacks,
                id: { $0.id.uuidString }
            )
            return true
        } catch {
            return false
        }
    }

    private static func verifyMetadata(
        _ database: OpaquePointer,
        catalog: LibraryCatalog
    ) throws {
        let statement = try prepare(database, """
            SELECT catalog_version, minimum_reader_version, active_roll_id
            FROM catalog_metadata WHERE singleton=1
            """)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              Int(sqlite3_column_int64(statement, 0)) == catalog.version,
              Int(sqlite3_column_int64(statement, 1)) == catalog.minimumReaderVersion else {
            throw VerificationError.invalid
        }
        let activeRollID: UUID?
        if sqlite3_column_type(statement, 2) == SQLITE_NULL {
            activeRollID = nil
        } else if let raw = sqlite3_column_text(statement, 2) {
            activeRollID = UUID(uuidString: String(cString: raw))
            if activeRollID == nil { throw VerificationError.invalid }
        } else {
            throw VerificationError.invalid
        }
        guard activeRollID == catalog.activeRollID,
              sqlite3_step(statement) == SQLITE_DONE else {
            throw VerificationError.invalid
        }
    }

    private static func hasStableIdentity<Value>(
        _ values: [Value],
        _ previousValues: [Value],
        id: (Value) -> String
    ) -> Bool {
        values.count == previousValues.count
            && zip(previousValues, values).allSatisfy { id($0.0) == id($0.1) }
    }

    private static func verifyRows<Value: Encodable & Equatable>(
        _ database: OpaquePointer,
        table: String,
        values: [Value],
        previousValues: [Value],
        id: (Value) -> String
    ) throws {
        guard entityTables.contains(table),
              hasStableIdentity(values, previousValues, id: id),
              try intScalar(database, sql: "SELECT COUNT(*) FROM \(table)") == values.count else {
            throw VerificationError.invalid
        }
        let changed = zip(previousValues, values).enumerated().filter { $0.element.0 != $0.element.1 }
        guard !changed.isEmpty else { return }
        let statement = try prepare(
            database,
            "SELECT position, payload FROM \(table) WHERE id=?"
        )
        defer { sqlite3_finalize(statement) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        for (position, pair) in changed {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            guard sqlite3_bind_text(statement, 1, id(pair.1), -1, sqliteTransient) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW,
                  Int(sqlite3_column_int64(statement, 0)) == position,
                  let bytes = sqlite3_column_blob(statement, 1) else {
                throw VerificationError.invalid
            }
            let count = Int(sqlite3_column_bytes(statement, 1))
            let expectedPayload = try encoder.encode(pair.1)
            guard count > 0,
                  Data(bytes: bytes, count: count) == expectedPayload,
                  sqlite3_step(statement) == SQLITE_DONE else {
                throw VerificationError.invalid
            }
        }
    }

    private static func intScalar(
        _ database: OpaquePointer,
        sql: String
    ) throws -> Int {
        let statement = try prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw VerificationError.invalid }
        let value = Int(sqlite3_column_int64(statement, 0))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw VerificationError.invalid }
        return value
    }

    private static func prepare(
        _ database: OpaquePointer,
        _ sql: String
    ) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw VerificationError.invalid
        }
        return statement
    }

    private static var sqliteTransient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }
}
