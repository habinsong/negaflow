import XCTest
@testable import negaflowApp

/// 실제 라이브러리 사본으로 버전 이전을 대조한다. 환경 변수가 없으면 건너뛴다.
///
/// - `NEGAFLOW_MIGRATION_PRE`: 이전 전 사본 루트(`Library/catalog.sqlite`, `Library/Defects`,
///   `Library/Backups`). 읽기만 한다.
/// - `NEGAFLOW_MIGRATION_POST`: 같은 사본을 새 버전 앱이 연 뒤의 루트(구조 동일).
/// - `NEGAFLOW_MIGRATION_REPORT`: 결과를 쓸 파일(선택).
///
/// 복구 연습은 POST 를 임시 폴더에 클론해서 한다. 두 루트는 건드리지 않는다.
@MainActor
final class LibraryMigrationAuditTests: XCTestCase {
    private var lines: [String] = []

    func testMigratedLibraryMatchesOriginalRecordForRecord() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let prePath = environment["NEGAFLOW_MIGRATION_PRE"],
              let postPath = environment["NEGAFLOW_MIGRATION_POST"] else {
            throw XCTSkip("NEGAFLOW_MIGRATION_PRE/POST not set")
        }
        let pre = Root(URL(fileURLWithPath: prePath, isDirectory: true))
        let post = Root(URL(fileURLWithPath: postPath, isDirectory: true))
        defer {
            if let report = environment["NEGAFLOW_MIGRATION_REPORT"] {
                try? lines.joined(separator: "\n").write(
                    to: URL(fileURLWithPath: report), atomically: true, encoding: .utf8
                )
            }
        }

        let preCatalog = try loadCatalog(pre.catalog, label: "pre")
        let postCatalog = try loadCatalog(post.catalog, label: "post")
        compareCatalogs(preCatalog, postCatalog)
        try compareDefects(pre: pre, post: post, postCatalog: postCatalog)
        inspectHealth(postCatalog, post: post)
        inspectBackups(post)
        try restoreDrill(post: post, postCatalog: postCatalog)
    }

    /// `NEGAFLOW_SCHEDULE_RESTORE_ROOT` 사본의 가장 새 백업 세대를 앱과 같은 함수로 예약 복원한다.
    /// 다음 실행이 적용하고, `testLibraryMatchesBackupGeneration` 이 결과를 대조한다.
    func testScheduleRestoreOfNewestGeneration() throws {
        guard let path = ProcessInfo.processInfo.environment["NEGAFLOW_SCHEDULE_RESTORE_ROOT"] else {
            throw XCTSkip("NEGAFLOW_SCHEDULE_RESTORE_ROOT not set")
        }
        let root = Root(URL(fileURLWithPath: path, isDirectory: true))
        let newest = try XCTUnwrap(LibraryBackupStore.generations(in: root.backups).first)
        XCTAssertEqual(newest.state, .checksummed)
        let marker = try LibraryPendingRestoreStore.schedule(
            generationID: newest.id,
            catalogURL: root.catalog,
            backupDirectory: root.backups
        )
        print("[migration-audit] scheduled \(newest.id) marker=\(marker.directoryName)")
    }

    /// `NEGAFLOW_LIBRARY_ROOT` 의 라이브러리가 백업 세대 `NEGAFLOW_GENERATION_DIR` 과 같은지 본다.
    func testLibraryMatchesBackupGeneration() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let libraryPath = environment["NEGAFLOW_LIBRARY_ROOT"],
              let generationPath = environment["NEGAFLOW_GENERATION_DIR"] else {
            throw XCTSkip("NEGAFLOW_LIBRARY_ROOT/NEGAFLOW_GENERATION_DIR not set")
        }
        let root = Root(URL(fileURLWithPath: libraryPath, isDirectory: true))
        let generation = URL(fileURLWithPath: generationPath, isDirectory: true)
        let snapshot = try XCTUnwrap(LibraryBackupStore.validateSnapshotDirectory(at: generation))
        let library = try loadCatalog(root.catalog, label: "library")
        compareCatalogs(snapshot.catalog, library)
        let generationDefects = LibraryBackupStore.defectsDirectory(in: generation)
        var same = 0
        for frameID in snapshot.manifest.defectFrameIDs {
            let expected = DefectSidecarFile.read(for: frameID, in: generationDefects)
            let actual = DefectSidecarFile.read(for: frameID, in: root.defects)
            guard case let .loaded(.currentV2(_, want)) = expected,
                  case let .loaded(.currentV2(_, got)) = actual else {
                XCTFail("recipe \(frameID): generation=\(describe(expected)) library=\(describe(actual))")
                continue
            }
            XCTAssertEqual(want, got, "recipe differs from generation: \(frameID)")
            if want == got { same += 1 }
        }
        note("library vs generation: recipes same=\(same)/\(snapshot.manifest.defectFrameIDs.count)")
        inspectHealth(library, post: root)
    }

    // MARK: - Catalog

    private func loadCatalog(_ url: URL, label: String) throws -> LibraryCatalog {
        guard case let .loaded(catalog, version) = LibraryCatalogFile.read(from: url) else {
            XCTFail("\(label) catalog did not load: \(url.path)")
            throw XCTSkip("catalog missing")
        }
        note("\(label) catalog v\(version): \(catalog.frames.count) frames, \(catalog.folders.count) folders")
        return catalog
    }

    private func compareCatalogs(_ pre: LibraryCatalog, _ post: LibraryCatalog) {
        let preFrames = Dictionary(uniqueKeysWithValues: pre.frames.map { ($0.id, $0) })
        let postFrames = Dictionary(uniqueKeysWithValues: post.frames.map { ($0.id, $0) })
        let missing = Set(preFrames.keys).subtracting(postFrames.keys)
        let added = Set(postFrames.keys).subtracting(preFrames.keys)
        XCTAssertTrue(missing.isEmpty, "frames lost: \(missing)")
        note("frames lost=\(missing.count) added=\(added.count)")

        var changedFields: [String: Int] = [:]
        for (id, before) in preFrames {
            guard let after = postFrames[id] else { continue }
            for key in diffKeys(before, after) { changedFields[key, default: 0] += 1 }
        }
        note("frame fields changed: " + (changedFields.isEmpty
            ? "none"
            : changedFields.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: ", ")))

        var preRest = pre
        var postRest = post
        preRest.frames = []
        postRest.frames = []
        let restKeys = diffKeys(preRest, postRest)
        note("catalog sections changed: " + (restKeys.isEmpty ? "none" : restKeys.joined(separator: ", ")))
    }

    private func diffKeys<T: Encodable>(_ lhs: T, _ rhs: T) -> [String] {
        guard let left = jsonObject(lhs), let right = jsonObject(rhs) else { return ["<encode>"] }
        return Set(left.keys).union(right.keys).filter { key in
            !NSDictionary(dictionary: [key: left[key] ?? NSNull()])
                .isEqual(to: [key: right[key] ?? NSNull()])
        }.sorted()
    }

    private func jsonObject<T: Encodable>(_ value: T) -> [String: Any]? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(value) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Defect recipes

    private func compareDefects(pre: Root, post: Root, postCatalog: LibraryCatalog) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: pre.defects, includingPropertiesForKeys: [.fileSizeKey]
        ).filter { $0.pathExtension == "plist" }
        let identities = Dictionary(
            postCatalog.frames.compactMap { frame in frame.defectRecipeIdentity.map { (frame.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        var preBytes = 0
        var postBytes = 0
        var versions: [Int: Int] = [:]
        var identical = 0
        var rebound = 0
        for file in files {
            guard let frameID = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else {
                continue
            }
            preBytes += size(file)
            let postFile = DefectSidecarFile.url(for: frameID, in: post.defects)
            postBytes += size(postFile)
            versions[storedVersion(postFile) ?? -1, default: 0] += 1
            let before = DefectSidecarFile.read(for: frameID, in: pre.defects)
            let after = DefectSidecarFile.read(for: frameID, in: post.defects)
            switch (before, after) {
            case let (.loaded(.currentV2(_, old)), .loaded(.currentV2(_, new))):
                // 항목(마스크 바이트까지)과 recipe 지문은 같아야 한다. 원본 identity 를 새로 묶는
                // 것(같은 내용, revision 증가)은 앱의 정상 동작이라 따로 센다.
                XCTAssertEqual(old.items, new.items, "recipe items changed: \(frameID)")
                XCTAssertEqual(old.identity.recipeSHA256, new.identity.recipeSHA256, "recipe fingerprint changed: \(frameID)")
                if old == new {
                    identical += 1
                } else if old.items == new.items {
                    XCTAssertGreaterThan(new.identity.revision, old.identity.revision, "rebound without new revision: \(frameID)")
                    rebound += 1
                }
                if let identity = identities[frameID] {
                    XCTAssertEqual(identity, new.identity, "catalog identity mismatch: \(frameID)")
                }
            case let (.loaded(.legacyV1(_, old)), .loaded(.legacyV1(_, new))):
                XCTAssertEqual(old, new, "legacy recipe changed: \(frameID)")
                if old == new { identical += 1 }
            default:
                XCTFail("recipe \(frameID): pre=\(describe(before)) post=\(describe(after))")
            }
        }
        let catalogFramesWithDefects = postCatalog.frames.filter { $0.hasDefectEdits == true }
        for frame in catalogFramesWithDefects {
            guard case .loaded = DefectSidecarFile.read(for: frame.id, in: post.defects) else {
                XCTFail("catalog frame with defects has no readable recipe: \(frame.id)")
                continue
            }
        }
        note("recipes \(files.count): identical=\(identical) rebound=\(rebound), post versions=\(versions.sorted { $0.key < $1.key })")
        note("recipe bytes pre=\(preBytes / 1_000_000)MB post=\(postBytes / 1_000_000)MB")
        note("catalog frames with defects=\(catalogFramesWithDefects.count)")
    }

    private func describe(_ result: DefectSidecarLoadResult) -> String {
        switch result {
        case .missing: "missing"
        case .loaded(.legacyV1): "v1"
        case .loaded(.currentV2): "v2/v3"
        case .unsupportedVersion(let version, _): "unsupported(\(version))"
        case .invalid: "invalid"
        case .unreadable: "unreadable"
        }
    }

    // MARK: - Health and backups

    private func inspectHealth(_ catalog: LibraryCatalog, post: Root) {
        let report = LibraryCatalogHealthInspector.inspect(catalog, defectDirectory: post.defects)
        XCTAssertTrue(report.canOpenSafely, "health errors: \(report.issues.filter { $0.severity == .error })")
        let codes = Dictionary(grouping: report.issues, by: { "\($0.severity):\($0.code)" })
            .mapValues(\.count)
        note("health errors=\(report.errorCount) warnings=\(report.warningCount) \(codes.sorted { $0.key < $1.key })")
    }

    private func inspectBackups(_ post: Root) {
        let generations = (try? LibraryBackupStore.generations(in: post.backups)) ?? []
        XCTAssertFalse(generations.isEmpty, "no backup generations")
        for generation in generations {
            XCTAssertEqual(generation.state, .checksummed, "backup \(generation.id) is \(generation.state)")
            if generation.state != .checksummed {
                explainInvalidGeneration(post.backups.appendingPathComponent(generation.id, isDirectory: true))
            }
            let defects = LibraryBackupStore.defectsDirectory(
                in: post.backups.appendingPathComponent(generation.id, isDirectory: true)
            )
            let files = (try? FileManager.default.contentsOfDirectory(at: defects, includingPropertiesForKeys: nil)) ?? []
            let bytes = files.reduce(0) { $0 + size($1) }
            let versions = Dictionary(grouping: files.compactMap(storedVersion), by: { $0 }).mapValues(\.count)
            note("backup #\(generation.sequence ?? 0) \(generation.state) frames=\(generation.frameCount ?? -1) recipes=\(files.count) \(bytes / 1_000_000)MB versions=\(versions.sorted { $0.key < $1.key })")
        }
    }

    /// `validateSnapshot` 의 어느 조건에서 떨어지는지 하나씩 짚는다.
    private func explainInvalidGeneration(_ directory: URL) {
        let id = directory.lastPathComponent.prefix(27)
        guard let catalogData = try? Data(contentsOf: LibraryBackupStore.catalogURL(in: directory)),
              let catalog = LibraryCatalogFile.decode(catalogData) else {
            return note("  \(id): catalog does not decode")
        }
        let defects = LibraryBackupStore.defectsDirectory(in: directory)
        let unreadable = catalog.frames.filter { $0.hasDefectEdits == true }
            .filter { DefectSidecarFile.load(for: $0.id, in: defects) == nil }
        note("  \(id): frames=\(catalog.frames.count) unreadable recipes=\(unreadable.count)")
        let health = LibraryCatalogHealthInspector.inspect(catalog, defectDirectory: defects)
        let errors = Dictionary(grouping: health.issues.filter { $0.severity == .error }, by: { "\($0.code)" })
            .mapValues(\.count)
        note("  \(id): health errors \(errors.sorted { $0.key < $1.key }) blocksOpen=\(health.blocksOpen)")
        if !health.canOpenSafely {
            let repaired = LibraryCatalogRepair.repairedCatalogIfOpenable(catalog, defectDirectory: defects)
            note("  \(id): repairable=\(repaired != nil)")
        }
    }

    /// 최신 백업으로 실제 복구를 해 본다. 카탈로그를 부순 클론에서 `restoreLatest` 가 프레임과
    /// 결함 기록을 모두 돌려놓아야 한다.
    private func restoreDrill(post: Root, postCatalog: LibraryCatalog) throws {
        let drill = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-restore-drill-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: drill) }
        let library = drill.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: drill, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: post.library, to: library)
        let root = Root(drill)
        // 새 버전이 만드는 첫 백업: v3 기록을 담고, 정리가 3세대로 줄인다.
        let started = Date()
        let generation = try LibraryBackupStore.createSnapshot(
            catalogURL: root.catalog,
            defectDirectory: root.defects,
            backupDirectory: root.backups
        )
        let newDefects = LibraryBackupStore.defectsDirectory(in: generation)
        let newFiles = try FileManager.default.contentsOfDirectory(at: newDefects, includingPropertiesForKeys: nil)
        let newVersions = Dictionary(grouping: newFiles.compactMap(storedVersion), by: { $0 }).mapValues(\.count)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.backups.path)
        note(String(
            format: "new backup: %.1fs recipes=%d %dMB versions=%@ entries after prune=%d",
            -started.timeIntervalSinceNow, newFiles.count,
            newFiles.reduce(0) { $0 + size($1) } / 1_000_000,
            "\(newVersions.sorted { $0.key < $1.key })", remaining.count
        ))
        XCTAssertEqual(remaining.filter { $0.hasPrefix("backup-") }.count, LibraryBackupStore.defaultRetentionCount)
        XCTAssertTrue(remaining.allSatisfy { $0.hasPrefix("backup-") })

        try Data("not a catalog".utf8).write(to: root.catalog)
        let restored = try XCTUnwrap(LibraryBackupStore.restoreLatest(
            catalogURL: root.catalog,
            defectDirectory: root.defects,
            backupDirectory: root.backups
        ))
        guard let latest = try LibraryBackupStore.generations(in: root.backups).first else {
            return XCTFail("restore drill: no generation")
        }
        XCTAssertEqual(restored.frames.count, latest.frameCount)
        var unreadable = 0
        for frame in restored.frames where frame.hasDefectEdits == true {
            guard case .loaded = DefectSidecarFile.read(for: frame.id, in: root.defects) else {
                unreadable += 1
                continue
            }
        }
        XCTAssertEqual(unreadable, 0, "restored recipes unreadable")
        let lost = Set(postCatalog.frames.map(\.id)).subtracting(restored.frames.map(\.id))
        note("restore drill: frames=\(restored.frames.count) (post \(postCatalog.frames.count), not in latest backup \(lost.count)) unreadable recipes=\(unreadable)")
    }

    // MARK: - Helpers

    private struct Root {
        let library: URL
        let catalog: URL
        let defects: URL
        let backups: URL

        init(_ root: URL) {
            library = root.appendingPathComponent("Library", isDirectory: true)
            catalog = library.appendingPathComponent("catalog.sqlite")
            defects = library.appendingPathComponent("Defects", isDirectory: true)
            backups = library.appendingPathComponent("Backups", isDirectory: true)
        }
    }

    private func size(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
    }

    private func storedVersion(_ url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return try? PropertyListDecoder().decode(DefectSidecarFile.VersionProbe.self, from: data).version
    }

    private func note(_ line: String) {
        lines.append(line)
        print("[migration-audit] \(line)")
    }
}
