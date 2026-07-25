import XCTest
@testable import negaflowApp

final class DefectEditPersistenceTests: XCTestCase {
    private enum ForcedFailure: Error {
        case write
    }

    func testCleanedRawCacheFileNameRoundTrip() {
        let frameID = UUID()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-cleaned-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = CleanedRawCacheFile.makeBuildURL(frameID: frameID, in: directory)

        XCTAssertEqual(url.pathExtension, "tiff")
        XCTAssertEqual(CleanedRawCacheFile.frameID(fromFileName: url.lastPathComponent), frameID)
        XCTAssertNil(CleanedRawCacheFile.frameID(fromFileName: "garbage.tiff"))
    }

    func testUnknownDefectSidecarVersionIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-defect-version-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let frameID = UUID()
        let sidecar = DefectSidecar(version: 999, items: [])
        let encoder = PropertyListEncoder()
        try encoder.encode(sidecar).write(to: DefectSidecarFile.url(for: frameID, in: directory))

        XCTAssertNil(DefectSidecarFile.load(for: frameID, in: directory))
        guard case .unsupportedVersion(let version, let rawData) = DefectSidecarFile.read(
            for: frameID,
            in: directory
        ) else {
            return XCTFail("future sidecar should remain distinguishable")
        }
        XCTAssertEqual(version, 999)
        XCTAssertEqual(rawData, try Data(contentsOf: DefectSidecarFile.url(for: frameID, in: directory)))
    }

    func testFrozenV1ReadPreservesExactRawBytesAndLegacyLoadAPI() throws {
        let directory = temporaryDirectory("v1-raw")
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let record = makeBrushRecord(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        )

        let url = try DefectSidecarFile.write([record], for: frameID, in: directory)
        let originalBytes = try Data(contentsOf: url)
        let frozenEncoder = PropertyListEncoder()
        frozenEncoder.outputFormat = .binary
        XCTAssertEqual(
            originalBytes,
            try frozenEncoder.encode(DefectSidecar(items: [record.compressedForStorage()]))
        )

        guard case .loaded(.legacyV1(let rawData, let items)) = DefectSidecarFile.read(
            for: frameID,
            in: directory
        ) else {
            return XCTFail("v1 sidecar should use the frozen decoder")
        }
        XCTAssertEqual(rawData, originalBytes)
        XCTAssertEqual(items, [record])
        XCTAssertEqual(DefectSidecarFile.load(for: frameID, in: directory), [record])
        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
    }

    func testFrozenV1RejectsCorruptCompressedMaskWithoutDegradingToEmptyMask() throws {
        let directory = temporaryDirectory("v1-corrupt-zlib")
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameID = UUID()
        var record = makeRegionRecord(id: UUID())
        record.regionMask = DefectCompressedData(zlib: true, data: Data([0x01, 0x02, 0x03]))

        let rawData = try writeFrozenV1([record], frameID: frameID, directory: directory)

        guard case .invalid(let preserved) = DefectSidecarFile.read(
            for: frameID,
            in: directory
        ) else {
            return XCTFail("corrupt v1 mask must remain invalid")
        }
        XCTAssertEqual(preserved, rawData)
        XCTAssertNil(DefectSidecarFile.load(for: frameID, in: directory))
    }

    func testFrozenV1RejectsMaskDimensionMismatch() throws {
        let directory = temporaryDirectory("v1-mask-dimensions")
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameID = UUID()
        var record = makeRegionRecord(id: UUID())
        record.regionWidth = 3

        let rawData = try writeFrozenV1([record], frameID: frameID, directory: directory)

        guard case .invalid(let preserved) = DefectSidecarFile.read(
            for: frameID,
            in: directory
        ) else {
            return XCTFail("v1 mask dimensions must match the decoded byte count")
        }
        XCTAssertEqual(preserved, rawData)
    }

    func testFrozenV1RejectsNonFiniteRenderScalar() throws {
        let directory = temporaryDirectory("v1-invalid-scalar")
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameID = UUID()
        var record = makeBrushRecord(id: UUID())
        record.strength = .nan

        let rawData = try writeFrozenV1([record], frameID: frameID, directory: directory)

        guard case .invalid(let preserved) = DefectSidecarFile.read(
            for: frameID,
            in: directory
        ) else {
            return XCTFail("v1 non-finite scalar must be rejected")
        }
        XCTAssertEqual(preserved, rawData)
    }

    func testRecipeFingerprintIsDeterministicAndIgnoresPresentationOnlyFields() throws {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let record = makeBrushRecord(id: id)

        let first = try DefectRecipeFingerprint.sha256(items: [record])
        let repeated = try DefectRecipeFingerprint.sha256(items: [record])
        var presentationOnly = record
        presentationOnly.title = "localized title"
        presentationOnly.summary = "localized summary"
        presentationOnly.baseSize = CGSize(width: 4000, height: 3000)
        presentationOnly.preview = [DefectPreviewComponentRecord(
            classification: .dust,
            confidence: 0.42,
            points: [CGPoint(x: 0.2, y: 0.3)]
        )]

        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first, try DefectRecipeFingerprint.sha256(items: [presentationOnly]))
        XCTAssertEqual(first, "b3a3a3717fa04e52e003c33152f40f02bc5d539ba7152f4a461ea95e577dd83c")
    }

    func testRecipeFingerprintChangesForRenderAffectingStateAndOrder() throws {
        let firstID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let secondID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let base = makeBrushRecord(id: firstID)
        let second = makeBrushRecord(id: secondID, pointX: 0.75)
        let hash = try DefectRecipeFingerprint.sha256(items: [base, second])

        var disabled = base
        disabled.enabled = false
        XCTAssertNotEqual(hash, try DefectRecipeFingerprint.sha256(items: [disabled, second]))

        var strength = base
        strength.strength = 0.5
        XCTAssertNotEqual(hash, try DefectRecipeFingerprint.sha256(items: [strength, second]))

        var geometry = base
        geometry.strokes?[0].points[0].x = 0.9
        XCTAssertNotEqual(hash, try DefectRecipeFingerprint.sha256(items: [geometry, second]))
        XCTAssertNotEqual(hash, try DefectRecipeFingerprint.sha256(items: [second, base]))
    }

    func testRecipeFingerprintNeverDecompressesMasks() throws {
        // v2: 마스크 내용을 읽지 않는다(항목 UUID + 형태가 recipe를 대변). 같은 표현끼리는
        // 결정적이고, 저장 표현(raw/zlib)이 다르면 지문이 달라도 된다 — 세션 안에서 한 항목의
        // 표현은 생성 후 불변이다.
        let raw = makeRegionRecord(
            id: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        )
        var compressed = raw
        compressed.regionMask = compressed.regionMask?.compressed()

        XCTAssertEqual(
            try DefectRecipeFingerprint.sha256(items: [raw]),
            try DefectRecipeFingerprint.sha256(items: [raw])
        )
        XCTAssertEqual(
            try DefectRecipeFingerprint.sha256(items: [compressed]),
            try DefectRecipeFingerprint.sha256(items: [compressed])
        )
        XCTAssertNotEqual(
            try DefectRecipeFingerprint.sha256(items: [raw]),
            try DefectRecipeFingerprint.sha256(items: [compressed])
        )
    }

    func testRecipeFingerprintRejectsInvalidRenderState() {
        var invalidStrength = makeBrushRecord(id: UUID())
        invalidStrength.strength = .nan
        XCTAssertThrowsError(try DefectRecipeFingerprint.sha256(items: [invalidStrength]))

        var invalidMask = makeRegionRecord(id: UUID())
        invalidMask.regionMask = .raw(Data([0, 1, 2]))
        XCTAssertThrowsError(try DefectRecipeFingerprint.sha256(items: [invalidMask]))
    }

    func testDefectSourceIdentityValidatesStoredFixity() throws {
        let valid = try DefectSourceIdentity(
            byteCount: 42,
            sha256: String(repeating: "a", count: 64)
        )
        XCTAssertEqual(valid.byteCount, 42)
        XCTAssertThrowsError(try DefectSourceIdentity(
            byteCount: 0,
            sha256: String(repeating: "a", count: 64)
        ))
        XCTAssertThrowsError(try DefectSourceIdentity(
            byteCount: 42,
            sha256: String(repeating: "A", count: 64)
        ))
    }

    func testV2RoundTripProvidesTypedSnapshotAndLegacyLoadCompatibility() throws {
        let directory = temporaryDirectory("v2-roundtrip")
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let snapshot = try makeSnapshot(frameID: frameID, revision: 7)

        XCTAssertEqual(
            try DefectSidecarFile.write(snapshot, in: directory),
            .written(DefectSidecarFile.url(for: frameID, in: directory))
        )
        guard case .loaded(.currentV2(let rawData, let restored)) = DefectSidecarFile.read(
            for: frameID,
            in: directory
        ) else {
            return XCTFail("v2 sidecar should return a verified snapshot")
        }
        XCTAssertFalse(rawData.isEmpty)
        XCTAssertEqual(restored, snapshot)
        XCTAssertEqual(DefectSidecarFile.load(for: frameID, in: directory), snapshot.items)
        XCTAssertEqual(
            try DefectSidecarFile.write(snapshot, in: directory),
            .alreadyCurrent(DefectSidecarFile.url(for: frameID, in: directory))
        )
    }

    func testFrozenV1WriterCannotDowngradeExistingV2Document() throws {
        let directory = temporaryDirectory("v2-no-downgrade")
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameID = UUID(uuidString: "27272727-2727-2727-2727-272727272727")!
        let snapshot = try makeSnapshot(frameID: frameID, revision: 4)
        _ = try DefectSidecarFile.write(snapshot, in: directory)

        XCTAssertThrowsError(try DefectSidecarFile.write(
            [makeBrushRecord(id: UUID())],
            for: frameID,
            in: directory
        )) { error in
            XCTAssertEqual(error as? DefectSidecarWriteError, .legacyWriteWouldDowngrade)
        }
        XCTAssertEqual(currentSnapshot(frameID: frameID, directory: directory), snapshot)
    }

    func testV2TamperedRenderPayloadIsRejected() throws {
        let directory = temporaryDirectory("v2-tamper")
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let snapshot = try makeSnapshot(frameID: frameID, revision: 1)
        let url = DefectSidecarFile.url(for: frameID, in: directory)
        _ = try DefectSidecarFile.write(snapshot, in: directory)

        let data = try Data(contentsOf: url)
        var plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any]
        )
        var items = try XCTUnwrap(plist["items"] as? [[String: Any]])
        items[0]["strength"] = 0.25
        plist["items"] = items
        let tampered = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .binary,
            options: 0
        )
        try tampered.write(to: url, options: .atomic)

        guard case .invalid(let preserved) = DefectSidecarFile.read(for: frameID, in: directory) else {
            return XCTFail("tampered v2 document should be invalid")
        }
        XCTAssertEqual(preserved, tampered)
        XCTAssertNil(DefectSidecarFile.load(for: frameID, in: directory))
    }

    func testV2SynchronousWriteNeverRegressesRevision() throws {
        let directory = temporaryDirectory("v2-sync-revision")
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let newer = try makeSnapshot(frameID: frameID, revision: 2, strength: 0.6)
        let older = try makeSnapshot(frameID: frameID, revision: 1, strength: 1.0)

        _ = try DefectSidecarFile.write(newer, in: directory)
        XCTAssertEqual(
            try DefectSidecarFile.write(older, in: directory),
            .skippedNewer(existingRevision: 2)
        )
        XCTAssertEqual(currentSnapshot(frameID: frameID, directory: directory), newer)

        let conflict = try makeSnapshot(frameID: frameID, revision: 2, strength: 0.2)
        XCTAssertThrowsError(try DefectSidecarFile.write(conflict, in: directory)) { error in
            XCTAssertEqual(error as? DefectSidecarWriteError, .conflictingSameRevision(2))
        }
        XCTAssertEqual(currentSnapshot(frameID: frameID, directory: directory), newer)
    }

    func testV2MayBindSourceAtSameRecipeRevisionButCannotUnbindIt() throws {
        let directory = temporaryDirectory("v2-source-binding")
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameID = UUID()
        let record = makeBrushRecord(id: UUID())
        let unbound = try DefectRecipeSnapshot(
            frameID: frameID,
            revision: 1,
            sourceIdentity: nil,
            items: [record]
        )
        let bound = try DefectRecipeSnapshot(
            frameID: frameID,
            revision: 1,
            sourceIdentity: DefectSourceIdentity(
                byteCount: 42,
                sha256: String(repeating: "e", count: 64)
            ),
            items: [record]
        )

        _ = try DefectSidecarFile.write(unbound, in: directory)
        XCTAssertEqual(
            try DefectSidecarFile.write(bound, in: directory),
            .written(DefectSidecarFile.url(for: frameID, in: directory))
        )
        XCTAssertEqual(currentSnapshot(frameID: frameID, directory: directory), bound)
        XCTAssertThrowsError(try DefectSidecarFile.write(unbound, in: directory)) { error in
            XCTAssertEqual(error as? DefectSidecarWriteError, .conflictingSameRevision(1))
        }
    }

    func testRevisionAwareRemoveBlocksDelayedOlderWrite() throws {
        let directory = temporaryDirectory("v2-remove-floor")
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameID = UUID()
        let older = try makeSnapshot(frameID: frameID, revision: 1)

        try DefectSidecarFile.remove(
            for: frameID,
            atRevision: 2,
            in: directory
        )

        XCTAssertEqual(
            try DefectSidecarFile.write(older, in: directory),
            .skippedNewer(existingRevision: 2)
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: DefectSidecarFile.url(for: frameID, in: directory).path
        ))
    }

    func testV2AsyncWriteNeverRegressesRevision() throws {
        let directory = temporaryDirectory("v2-async-revision")
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let newer = try makeSnapshot(frameID: frameID, revision: 3, strength: 0.4)
        let older = try makeSnapshot(frameID: frameID, revision: 2, strength: 0.8)
        let newerDone = expectation(description: "newer write")
        let olderDone = expectation(description: "older write")

        DefectSidecarFile.writeAsync(newer, in: directory) { result in
            if case .failure(let error) = result { XCTFail("newer write failed: \(error)") }
            newerDone.fulfill()
        }
        DefectSidecarFile.writeAsync(older, in: directory) { result in
            if case .failure(let error) = result { XCTFail("older write failed: \(error)") }
            olderDone.fulfill()
        }
        DefectSidecarFile.flushSync()
        wait(for: [newerDone, olderDone], timeout: 1)

        XCTAssertEqual(currentSnapshot(frameID: frameID, directory: directory), newer)
    }

    func testFailedV2AtomicWriteLeavesFrozenV1BytesUntouched() throws {
        let directory = temporaryDirectory("v1-upgrade-failure")
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let v1Record = makeBrushRecord(id: UUID())
        let url = try DefectSidecarFile.write([v1Record], for: frameID, in: directory)
        let original = try Data(contentsOf: url)
        let snapshot = try makeSnapshot(frameID: frameID, revision: 1)

        XCTAssertThrowsError(try DefectSidecarFile.write(
            snapshot,
            in: directory,
            atomicWriter: { _, _ in throw ForcedFailure.write }
        )) { error in
            XCTAssertEqual(error as? DefectSidecarWriteError, .ioFailure)
        }
        XCTAssertEqual(try Data(contentsOf: url), original)
        guard case .loaded(.legacyV1(let rawData, _)) = DefectSidecarFile.read(
            for: frameID,
            in: directory
        ) else {
            return XCTFail("failed upgrade should leave v1 authoritative")
        }
        XCTAssertEqual(rawData, original)
    }

    private func temporaryDirectory(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-defect-\(suffix)-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func writeFrozenV1(
        _ records: [DefectEditItemRecord],
        frameID: UUID,
        directory: URL
    ) throws -> Data {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(DefectSidecar(items: records))
        try data.write(to: DefectSidecarFile.url(for: frameID, in: directory), options: .atomic)
        return data
    }

    private func makeBrushRecord(
        id: UUID,
        pointX: CGFloat = 0.25,
        strength: Double = 1.0
    ) -> DefectEditItemRecord {
        DefectEditItemRecord(
            id: id,
            kind: .brush,
            enabled: true,
            strength: strength,
            title: "brush",
            summary: "dust",
            baseSize: nil,
            preview: [],
            strokes: [DefectStrokeRecord(
                points: [CGPoint(x: pointX, y: 0.5), CGPoint(x: 0.6, y: 0.7)],
                thickness: 0.05
            )],
            regionMask: nil,
            regionROI: nil,
            regionWidth: nil,
            regionHeight: nil,
            clusters: nil
        )
    }

    private func makeRegionRecord(id: UUID) -> DefectEditItemRecord {
        DefectEditItemRecord(
            id: id,
            kind: .region,
            enabled: true,
            strength: 0.75,
            title: "region",
            summary: "dust",
            baseSize: CGSize(width: 2, height: 2),
            preview: [],
            strokes: nil,
            regionMask: .raw(Data(repeating: 255, count: 2 * 2 * 4)),
            regionROI: CGRect(x: 1, y: 2, width: 2, height: 2),
            regionWidth: 2,
            regionHeight: 2,
            clusters: nil
        )
    }

    private func makeSnapshot(
        frameID: UUID,
        revision: UInt64,
        strength: Double = 1.0
    ) throws -> DefectRecipeSnapshot {
        try DefectRecipeSnapshot(
            frameID: frameID,
            revision: revision,
            sourceIdentity: DefectSourceIdentity(
                byteCount: 1234,
                sha256: String(repeating: "b", count: 64)
            ),
            items: [makeBrushRecord(
                id: UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!,
                strength: strength
            )]
        )
    }

    private func currentSnapshot(
        frameID: UUID,
        directory: URL
    ) -> DefectRecipeSnapshot? {
        guard case .loaded(.currentV2(_, let snapshot)) = DefectSidecarFile.read(
            for: frameID,
            in: directory
        ) else { return nil }
        return snapshot
    }
}
