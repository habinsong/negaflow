import XCTest
import Chromabase
import ScannerKit
@testable import negaflowApp

/// standard 검증이 strict 와 **같은 결과물**을 만들고, strict 가 잡던 변조를 그대로 잡는지 확인한다.
/// standard 는 재확인 지점에서 전체 재해시를 건너뛰되 stat identity 가 어긋나면 실제 해시로
/// 되돌아가므로, 잡아내는 사건 집합이 좁아지면 안 된다.
@MainActor
final class ExportVerificationLevelTests: XCTestCase {
    private var tempDirectory: URL!
    private var cleanedRawIsolation: CleanedRawFolderIsolation?

    override func setUp() async throws {
        try await super.setUp()
        cleanedRawIsolation = CleanedRawFolderIsolation()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-export-verification-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        cleanedRawIsolation?.restore()
        cleanedRawIsolation = nil
        try await super.tearDown()
    }

    private func makeSource(_ name: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try MockScannerBackend.writeSyntheticNegative(width: 24, height: 16, to: url)
        return url
    }

    /// 두 수준의 산출물을 바이트로 비교하려면 **같은 프레임**을 써야 한다. ScanFrame 을 새로 만들면
    /// `scannedAt` 이 갱신되고 그 값이 EXIF DateTimeOriginal 로 들어가 초 단위로 갈린다.
    private func makePlan(
        frame: ScanFrame,
        source rawURL: URL,
        output outputURL: URL,
        level: ExportVerificationLevel,
        writeSidecar: Bool = false,
        writeOriginalRaw: Bool = false,
        metadataDate: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) throws -> ExportFrameBuildPlan {
        ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: rawURL),
            outputURL: outputURL,
            format: .jpeg,
            writeSidecar: writeSidecar,
            writeMainFlatMaster: false,
            writeOriginalRaw: writeOriginalRaw,
            options: .standard,
            scannerModel: nil,
            backendUsed: nil,
            metadataDate: metadataDate,
            sourceFileIdentity: ExportArtifactFileIdentityInspector.sourceFile(at: rawURL),
            verificationLevel: level
        )
    }

    func testStandardAndStrictProduceIdenticalArtifacts() throws {
        let rawURL = try makeSource("equivalence-source.tiff")
        let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
        let standardURL = tempDirectory.appendingPathComponent("standard.jpg")
        let strictURL = tempDirectory.appendingPathComponent("strict.jpg")

        _ = try ExportFrameWriter.write(
            try makePlan(frame: frame, source: rawURL, output: standardURL, level: .standard).snapshot
        )
        _ = try ExportFrameWriter.write(
            try makePlan(frame: frame, source: rawURL, output: strictURL, level: .strict).snapshot
        )

        XCTAssertEqual(try Data(contentsOf: standardURL), try Data(contentsOf: strictURL))
    }

    func testStandardAndStrictProduceIdenticalSidecarBackedArtifacts() throws {
        let rawURL = try makeSource("equivalence-sidecar-source.tiff")
        let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
        let standardURL = tempDirectory.appendingPathComponent("standard-sidecar.jpg")
        let strictURL = tempDirectory.appendingPathComponent("strict-sidecar.jpg")

        _ = try ExportFrameWriter.write(
            try makePlan(
                frame: frame,
                source: rawURL,
                output: standardURL,
                level: .standard,
                writeSidecar: true,
                writeOriginalRaw: true
            ).snapshot
        )
        _ = try ExportFrameWriter.write(
            try makePlan(
                frame: frame,
                source: rawURL,
                output: strictURL,
                level: .strict,
                writeSidecar: true,
                writeOriginalRaw: true
            ).snapshot
        )

        XCTAssertEqual(try Data(contentsOf: standardURL), try Data(contentsOf: strictURL))
        // 사이드카는 산출물 해시를 실제로 담아야 한다 — standard 라고 비워두면 안 된다.
        let sidecarURL = try XCTUnwrap(
            ExportArtifactLayout(
                outputURL: standardURL,
                format: .jpeg,
                sourceURL: rawURL,
                writeSidecar: true,
                writeMainFlatMaster: false,
                writeOriginalRaw: true
            ).sidecarURL
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sidecar = try decoder.decode(Sidecar.self, from: Data(contentsOf: sidecarURL))
        let manifest = try XCTUnwrap(sidecar.renderManifest)
        XCTAssertEqual(
            manifest.outputArtifact?.identity,
            try RenderManifest.sourceIdentity(for: standardURL)
        )
        XCTAssertNoThrow(try manifest.validate())
    }

    /// 렌더 뒤 커밋 전에 원본이 바뀌면 두 수준 모두 산출물을 하나도 남기지 않아야 한다.
    func testBothLevelsRejectSourceReplacedBeforeCommit() throws {
        for level in ExportVerificationLevel.allCases {
            let rawURL = try makeSource("swap-source-\(level.rawValue).tiff")
            let outputURL = tempDirectory.appendingPathComponent("swap-\(level.rawValue).jpg")
            let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
            let plan = try makePlan(frame: frame, source: rawURL, output: outputURL, level: level)

            XCTAssertThrowsError(try ExportFrameWriter.write(plan.snapshot) {
                try MockScannerBackend.writeSyntheticNegative(width: 32, height: 20, to: rawURL)
            }, "\(level.rawValue) must reject a replaced source")
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: outputURL.path),
                "\(level.rawValue) must not publish an artifact"
            )
            XCTAssertFalse(
                try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path).contains {
                    $0.hasPrefix(".negaflow-export-")
                },
                "\(level.rawValue) must clean up staging"
            )
        }
    }

    /// 크기가 같은 다른 바이트로 원본을 제자리에 덮어써도 두 수준 모두 잡아야 한다
    /// (standard 는 mtime/ctime 변화를 보고 실제 해시로 되돌아간다).
    func testBothLevelsRejectInPlaceSourceRewriteOfSameLength() throws {
        for level in ExportVerificationLevel.allCases {
            let rawURL = try makeSource("inplace-\(level.rawValue).tiff")
            let outputURL = tempDirectory.appendingPathComponent("inplace-\(level.rawValue).jpg")
            let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
            let plan = try makePlan(frame: frame, source: rawURL, output: outputURL, level: level)
            let original = try Data(contentsOf: rawURL)

            XCTAssertThrowsError(try ExportFrameWriter.write(plan.snapshot) {
                var mutated = original
                let tail = mutated.count - 1
                mutated[tail] = mutated[tail] ^ 0xFF
                try mutated.write(to: rawURL)
                XCTAssertEqual(
                    try Data(contentsOf: rawURL).count,
                    original.count,
                    "fixture must keep the byte count identical"
                )
            }, "\(level.rawValue) must reject an in-place rewrite")
            XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    /// 스테이징 산출물이 커밋 직전에 바뀌면 두 수준 모두 거부해야 한다.
    func testBothLevelsRejectStagedArtifactRewrittenBeforeCommit() throws {
        for level in ExportVerificationLevel.allCases {
            let rawURL = try makeSource("staged-\(level.rawValue).tiff")
            let outputURL = tempDirectory.appendingPathComponent("staged-\(level.rawValue).jpg")
            let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
            let plan = try makePlan(frame: frame, source: rawURL, output: outputURL, level: level)
            let finalLayout = ExportArtifactLayout(
                outputURL: outputURL,
                format: .jpeg,
                sourceURL: rawURL,
                writeSidecar: false,
                writeMainFlatMaster: false,
                writeOriginalRaw: false
            )

            XCTAssertThrowsError(try ExportFrameWriter.write(plan.snapshot) {
                let stagingName = try XCTUnwrap(
                    FileManager.default.contentsOfDirectory(atPath: self.tempDirectory.path).first {
                        $0.hasPrefix(".negaflow-export-") && $0.hasSuffix(".tmp")
                    }
                )
                let stagingDirectory = self.tempDirectory.appendingPathComponent(
                    stagingName,
                    isDirectory: true
                )
                let stagedOutputURL = finalLayout.staged(in: stagingDirectory).outputURL
                var bytes = try Data(contentsOf: stagedOutputURL)
                bytes.append(contentsOf: [0x00, 0x01, 0x02])
                try bytes.write(to: stagedOutputURL)
            }, "\(level.rawValue) must reject a rewritten staged artifact")
            XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    func testSourceGenerationReusesBaselineOnlyWhenFileIdentityMatches() async throws {
        let rawURL = try makeSource("baseline-source.tiff")
        let captured = await ExportFrameSourceGeneration.capture(at: rawURL)
        let baseline = try XCTUnwrap(captured)
        let generation = ExportFrameSourceGeneration(
            rawScanURL: rawURL,
            sourceIdentity: baseline.sourceIdentity
        )
        let baselines = [rawURL.standardizedFileURL.path: baseline]

        let unchanged = await ExportFrameSourceGeneration.currentVerifications(
            for: [generation],
            level: .standard,
            baselines: baselines
        ).first ?? nil
        XCTAssertEqual(unchanged, baseline)

        try MockScannerBackend.writeSyntheticNegative(width: 40, height: 24, to: rawURL)
        let changed = await ExportFrameSourceGeneration.currentVerifications(
            for: [generation],
            level: .standard,
            baselines: baselines
        ).first ?? nil
        // stat 이 달라졌으므로 실제 해시로 되돌아가 "바뀐 세대"를 보고해야 한다.
        XCTAssertNotNil(changed)
        XCTAssertNotEqual(changed?.sourceIdentity, baseline.sourceIdentity)
    }

    func testVerificationLevelDefaultsToStandard() {
        XCTAssertEqual(ExportVerificationLevel.default, .standard)
        XCTAssertFalse(ExportVerificationLevel.standard.rehashesOnRecheck)
        XCTAssertTrue(ExportVerificationLevel.strict.rehashesOnRecheck)
    }
}
