import XCTest
@testable import negaflowApp

/// 1.2.4 이하의 v2 결함 기록(적외선 마스크 비압축)과 1.2.5 의 v3 기록(저장 압축) 사이의 이전.
/// 기존 기록·백업이 그대로 읽히고, 이전 뒤에도 recipe identity 가 같아 카탈로그가 어긋나지 않아야 한다.
final class DefectSidecarStorageMigrationTests: XCTestCase {
    func testV3WritePacksInfraredMasksAndReadsBackSameSnapshot() throws {
        let root = temporaryDirectory("v3")
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try makeSnapshot()

        XCTAssertEqual(
            try DefectSidecarFile.write(snapshot, in: root),
            .written(DefectSidecarFile.url(for: snapshot.frameID, in: root))
        )

        let url = DefectSidecarFile.url(for: snapshot.frameID, in: root)
        XCTAssertEqual(try storedVersion(at: url), 3)
        XCTAssertLessThan(try fileSize(url), rawMaskBytes(snapshot) / 20)
        guard case .loaded(.currentV2(_, let stored)) = DefectSidecarFile.read(
            for: snapshot.frameID, in: root
        ) else {
            return XCTFail("v3 recipe must read back")
        }
        XCTAssertEqual(stored, snapshot)
    }

    func testLegacyV2SidecarReadsAndCompactsWithoutChangingIdentity() throws {
        let root = temporaryDirectory("compact")
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try makeSnapshot()
        let url = DefectSidecarFile.url(for: snapshot.frameID, in: root)
        try writeLegacyV2(snapshot, to: url)
        let legacySize = try fileSize(url)

        guard case .loaded(.currentV2(_, let legacy)) = DefectSidecarFile.read(
            for: snapshot.frameID, in: root
        ) else {
            return XCTFail("1.2.4 recipe must stay readable")
        }
        XCTAssertEqual(legacy, snapshot)

        XCTAssertTrue(DefectSidecarFile.compactUnpackedStorage(for: snapshot.frameID, in: root))
        XCTAssertEqual(try storedVersion(at: url), 3)
        XCTAssertLessThan(try fileSize(url), legacySize / 20)
        guard case .loaded(.currentV2(_, let compacted)) = DefectSidecarFile.read(
            for: snapshot.frameID, in: root
        ) else {
            return XCTFail("compacted recipe must read back")
        }
        XCTAssertEqual(compacted, snapshot)
        XCTAssertEqual(compacted.identity, snapshot.identity)
        XCTAssertTrue(DefectSidecarCommitCache.shared.matches(snapshot.identity, at: url))

        // 두 번째 실행은 아무것도 쓰지 않는다.
        let compactedBytes = try Data(contentsOf: url)
        XCTAssertFalse(DefectSidecarFile.compactUnpackedStorage(for: snapshot.frameID, in: root))
        XCTAssertEqual(try Data(contentsOf: url), compactedBytes)

        // 이전한 기록 위에 다음 revision 이 평소처럼 쓰인다.
        let next = try DefectRecipeSnapshot(
            frameID: snapshot.frameID, revision: 2, sourceIdentity: nil, items: snapshot.items
        )
        XCTAssertEqual(try DefectSidecarFile.write(next, in: root), .written(url))
    }

    func testCompactionLeavesUnreadableAndLegacyV1RecordsUntouched() throws {
        let root = temporaryDirectory("untouched")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let broken = UUID()
        let brokenURL = DefectSidecarFile.url(for: broken, in: root)
        let snapshot = try makeSnapshot()
        let legacy = try legacyV2Data(snapshot)
        let truncated = legacy.prefix(legacy.count / 2)
        try truncated.write(to: brokenURL)
        XCTAssertFalse(DefectSidecarFile.compactUnpackedStorage(for: broken, in: root))
        XCTAssertEqual(try Data(contentsOf: brokenURL), truncated)

        let mismatched = UUID()
        let mismatchedURL = DefectSidecarFile.url(for: mismatched, in: root)
        try legacy.write(to: mismatchedURL)
        XCTAssertFalse(DefectSidecarFile.compactUnpackedStorage(for: mismatched, in: root))
        XCTAssertEqual(try Data(contentsOf: mismatchedURL), legacy)

        let v1 = UUID()
        try DefectSidecarFile.write(snapshot.items, for: v1, in: root)
        let v1Bytes = try Data(contentsOf: DefectSidecarFile.url(for: v1, in: root))
        XCTAssertFalse(DefectSidecarFile.compactUnpackedStorage(for: v1, in: root))
        XCTAssertEqual(try Data(contentsOf: DefectSidecarFile.url(for: v1, in: root)), v1Bytes)

        XCTAssertFalse(DefectSidecarFile.compactUnpackedStorage(for: UUID(), in: root))
    }

    /// 쓸 수 없는 폴더(권한, 잠긴 볼륨)에서는 이전이 실패하고 원래 v2 바이트가 그대로 남는다.
    func testCompactionFailureLeavesLegacyBytesUntouched() throws {
        let root = temporaryDirectory("readonly")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let snapshot = try makeSnapshot()
        let url = DefectSidecarFile.url(for: snapshot.frameID, in: root)
        try writeLegacyV2(snapshot, to: url)
        let legacy = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)

        XCTAssertFalse(DefectSidecarFile.compactUnpackedStorage(for: snapshot.frameID, in: root))
        XCTAssertEqual(try Data(contentsOf: url), legacy)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [url.lastPathComponent])
        guard case .loaded(.currentV2(_, let stored)) = DefectSidecarFile.read(
            for: snapshot.frameID, in: root
        ) else {
            return XCTFail("legacy recipe must stay readable after a failed compaction")
        }
        XCTAssertEqual(stored, snapshot)
    }

    func testPackedPayloadThatDoesNotRoundTripIsRejected() throws {
        let snapshot = try makeSnapshot()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        // 압축을 푼 길이가 폭×높이와 다르면 거부한다.
        var wrongLength = DefectSidecarV2(snapshot: snapshot)
        let packed = try XCTUnwrap(wrongLength.items[0].clusters?[0].mask)
        XCTAssertEqual(packed.storagePacked, true)
        wrongLength.items[0].clusters?[0].mask = DefectCompressedData(
            zlib: true,
            data: try XCTUnwrap((Data(count: 16) as NSData).compressed(using: .zlib) as Data),
            storagePacked: true
        )
        XCTAssertEqual(
            DefectSidecarFile.decode(
                try encoder.encode(wrongLength),
                expectedFrameID: snapshot.frameID,
                limits: .standard
            ),
            .invalid(rawData: try encoder.encode(wrongLength))
        )

        // v2 기록기는 저장 압축 표시를 쓰지 않았다.
        var markedV2 = DefectSidecarV2(snapshot: snapshot)
        markedV2.version = DefectSidecarV2.unpackedVersion
        let markedData = try encoder.encode(markedV2)
        XCTAssertEqual(
            DefectSidecarFile.decode(markedData, expectedFrameID: snapshot.frameID, limits: .standard),
            .invalid(rawData: markedData)
        )
    }

    /// 1.2.4 가 만든 백업 세대(v2 기록)로 복구해도 recipe 가 살아나고, 이전 뒤 새 백업은 작은
    /// v3 기록을 담는다.
    @MainActor
    func testLegacyBackupRestoresAndLaterBackupsCarryCompactedRecipe() throws {
        let root = temporaryDirectory("backup")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("support", isDirectory: true)
        let defects = support.appendingPathComponent("defects", isDirectory: true)
        let backups = support.appendingPathComponent("Backups", isDirectory: true)
        let catalogURL = support.appendingPathComponent("library.json")
        try FileManager.default.createDirectory(at: defects, withIntermediateDirectories: true)

        let snapshot = try makeSnapshot()
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/source.tiff"),
            filmType: .colorNegative,
            id: snapshot.frameID
        )
        var record = LibraryFrameRecord(frame: frame)
        record.hasDefectEdits = true
        try XCTUnwrap(LibraryCatalogFile.encode(LibraryCatalog(frames: [record])))
            .write(to: catalogURL, options: .atomic)
        let sidecarURL = DefectSidecarFile.url(for: snapshot.frameID, in: defects)
        try writeLegacyV2(snapshot, to: sidecarURL)
        let legacy = try LibraryBackupStore.createSnapshot(
            catalogURL: catalogURL,
            defectDirectory: defects,
            backupDirectory: backups,
            now: Date(timeIntervalSince1970: 10)
        )
        let legacyBackupSidecar = DefectSidecarFile.url(
            for: snapshot.frameID,
            in: legacy.appendingPathComponent("defects", isDirectory: true)
        )
        XCTAssertEqual(try storedVersion(at: legacyBackupSidecar), 2)

        try Data("{broken".utf8).write(to: catalogURL, options: .atomic)
        try FileManager.default.removeItem(at: sidecarURL)
        let restored = try XCTUnwrap(LibraryBackupStore.restoreLatest(
            catalogURL: catalogURL,
            defectDirectory: defects,
            backupDirectory: backups
        ))
        XCTAssertEqual(restored.frames.map(\.id), [snapshot.frameID])
        guard case .loaded(.currentV2(_, let recovered)) = DefectSidecarFile.read(
            for: snapshot.frameID, in: defects
        ) else {
            return XCTFail("recipe from a 1.2.4 backup must restore")
        }
        XCTAssertEqual(recovered, snapshot)

        XCTAssertTrue(DefectSidecarFile.compactUnpackedStorage(for: snapshot.frameID, in: defects))
        let compacted = try LibraryBackupStore.createSnapshot(
            catalogURL: catalogURL,
            defectDirectory: defects,
            backupDirectory: backups,
            now: Date(timeIntervalSince1970: 20)
        )
        let compactedBackupSidecar = DefectSidecarFile.url(
            for: snapshot.frameID,
            in: compacted.appendingPathComponent("defects", isDirectory: true)
        )
        XCTAssertEqual(try storedVersion(at: compactedBackupSidecar), 3)
        XCTAssertLessThan(
            try fileSize(compactedBackupSidecar),
            try fileSize(legacyBackupSidecar) / 20
        )
        XCTAssertNotNil(LibraryBackupStore.validateSnapshotDirectory(at: compacted))
        XCTAssertNotNil(LibraryBackupStore.validateSnapshotDirectory(at: legacy))
    }

    // MARK: - Fixtures

    /// 적외선 클러스터(비압축, 대부분 0) + 영역 마스크(메모리에서 이미 zlib) + 브러시.
    private func makeSnapshot() throws -> DefectRecipeSnapshot {
        let side = 512
        let clusters = (0..<4).map { index -> DefectClusterRecord in
            var mask = Data(count: side * side * 4)
            mask[index * 4 + 3] = 255
            var attenuation = Data(count: side * side * 2)
            attenuation[index] = 7
            return DefectClusterRecord(
                roi: CGRect(x: index * side, y: 0, width: side, height: side),
                mask: .raw(mask),
                attenuation: .raw(attenuation),
                width: side,
                height: side
            )
        }
        var infrared = item(kind: .infrared)
        infrared.clusters = clusters
        var region = item(kind: .region)
        region.regionMask = DefectCompressedData.raw(Data(count: 64 * 64 * 4)).compressed()
        region.regionROI = CGRect(x: 10, y: 10, width: 64, height: 64)
        region.regionWidth = 64
        region.regionHeight = 64
        var brush = item(kind: .brush)
        brush.strokes = [DefectStrokeRecord(points: [CGPoint(x: 1, y: 2)], thickness: 3)]
        return try DefectRecipeSnapshot(
            frameID: UUID(), revision: 1, sourceIdentity: nil, items: [infrared, region, brush]
        )
    }

    private func item(kind: DefectEditItemRecord.Kind) -> DefectEditItemRecord {
        DefectEditItemRecord(
            id: UUID(), kind: kind, enabled: true, strength: 1,
            label: .brush(strokeCount: 0), summaryKind: .brush, baseSize: nil, preview: [],
            strokes: nil, regionMask: nil, regionROI: nil,
            regionWidth: nil, regionHeight: nil, clusters: nil
        )
    }

    /// 1.2.4 기록기와 같은 바이트: version 2, 항목은 메모리 표현 그대로.
    private func legacyV2Data(_ snapshot: DefectRecipeSnapshot) throws -> Data {
        var sidecar = DefectSidecarV2(snapshot: snapshot)
        sidecar.version = DefectSidecarV2.unpackedVersion
        sidecar.items = snapshot.items
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(sidecar)
    }

    private func writeLegacyV2(_ snapshot: DefectRecipeSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try legacyV2Data(snapshot).write(to: url, options: .atomic)
    }

    private func storedVersion(at url: URL) throws -> Int {
        try PropertyListDecoder().decode(
            DefectSidecarFile.VersionProbe.self,
            from: Data(contentsOf: url)
        ).version
    }

    private func fileSize(_ url: URL) throws -> Int {
        try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        ).intValue
    }

    private func rawMaskBytes(_ snapshot: DefectRecipeSnapshot) -> Int {
        snapshot.items.flatMap { $0.clusters ?? [] }.reduce(0) {
            $0 + $1.mask.data.count + ($1.attenuation?.data.count ?? 0)
        }
    }

    private func temporaryDirectory(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-sidecar-migration-\(suffix)-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
