import Chromabase
import CoreImage
import Foundation
import ScannerKit
import XCTest
@testable import negaflowApp

/// [작업 5] 내보내기 파일명 토큰 — 9개 토큰 패턴으로 실제 파일을 만들고 그 이름을 남긴다.
///
/// 실행 예:
/// ```
/// NEGAFLOW_GOLDEN_DIR=/path/to/docs/verification/macos-golden/task5-naming \
/// swift test --filter MacGoldenExportNamingHarnessTests
/// ```
///
/// `{name}` 이 무엇인지 확실히 가르기 위해 두 변형을 돌린다. 원본 **파일 이름**은 둘 다
/// `source-7.tif` 이고, **카드 표시 이름**만 다르다.
@MainActor
final class MacGoldenExportNamingHarnessTests: XCTestCase {

    private static let pattern =
        "{date}-{roll}-{frame}-{name}-{preset}-{sequence}-{rollcode}-{film}-{camera}"
    /// 고정 날짜: 2026-08-12 12:00:00 UTC → `{date}` = 20260812.
    ///
    /// `makeExportBatchPlans` 는 내부에서 `Date()` 를 쓰므로 실제 생성 파일의 `{date}` 는
    /// **실행일**이 된다. 그래서 고정 날짜 결과(exportBaseName)와 실제 파일 이름을 둘 다 적는다.
    private static let fixedDate = Date(timeIntervalSince1970: 1_786_536_000)

    private var workDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-golden-naming-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: workDirectory)
        workDirectory = nil
        try await super.tearDown()
    }

    func testEmitsExportNamingGolden() async throws {
        guard let outputDirectory = MacGoldenAppHarness.outputDirectory() else {
            throw XCTSkip("NEGAFLOW_GOLDEN_DIR 를 지정하면 golden 을 생성합니다.")
        }
        XCTAssertTrue(ExportNamingTemplate.isValid(Self.pattern))

        var variants: [[String: Any]] = []
        for (label, customDisplayName) in [
            ("default-display-name", String?.none),
            ("renamed-card-display-name", "Sunset At Han River"),
        ] {
            variants.append(try await run(
                label: label,
                customDisplayName: customDisplayName,
                exportRoot: outputDirectory.appendingPathComponent(label, isDirectory: true)
            ))
        }

        let manifest: [String: Any] = [
            "task": "5 · export filename tokens",
            "pattern": Self.pattern,
            "fixedSettings": [
                "appLanguage": "english",
                "exportBaseNameDate": "2026-08-12T12:00:00Z (UTC) → {date}=20260812",
                "createdFileDate": "makeExportBatchPlans 는 Date() 를 쓴다 → {date}=실행일",
                "timeZone": "UTC",
                "sequenceStart": 3,
                "format": "tiff16 (.tif)",
                "rollName": "Roll 12",
                "rollCode": "H250729a",
                "filmStock": "Portra 400",
                "camera": "Nikon FM2",
                "preset": "rich-neutral",
                "sourceFileName": "source-7.tif",
                "frameScanIndex": 7,
            ],
            "tokenSources": [
                "{date}": "FrameStorageNaming.dateFolderName(exportDate, gregorian/en_US_POSIX/TZ)",
                "{roll}": "롤 이름(단일 소속일 때) 또는 frame.storageGroupName ?? \"unassigned\"",
                "{frame}": "frame.presentationIndex, %04d",
                "{name}": "frame.displayName(language:) — 카드 표시 이름",
                "{preset}": "recipeIdentity?.presetName ?? frame.preset?.id ?? \"manual\"",
                "{sequence}": "내보내기 순번, %04d",
                "{rollcode}": "rollRecord(for:)?.code",
                "{film}": "appMetadataOverlay?.filmShot?.filmStock",
                "{camera}": "filmShot.cameraMake + \" \" + cameraModel",
            ],
            "variants": variants,
        ]
        try MacGoldenAppHarness.writeJSON(
            manifest,
            to: outputDirectory.appendingPathComponent("export-naming.json")
        )
    }

    private func run(
        label: String,
        customDisplayName: String?,
        exportRoot: URL
    ) async throws -> [String: Any] {
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let model = AppModel(
            libraryCatalogURL: workDirectory.appendingPathComponent("\(label)-library.json"),
            libraryDefectDirectoryURL: workDirectory.appendingPathComponent("\(label)-defects"),
            libraryBackupDirectoryURL: workDirectory.appendingPathComponent("\(label)-backups")
        )
        await model.restoreLibraryOnLaunch()
        model.appLanguage = .english

        let source = workDirectory.appendingPathComponent("\(label)-source-7.tif")
        try MockScannerBackend.writeSyntheticNegative(width: 64, height: 48, to: source)
        let frame = ScanFrame(
            scanIndex: 7,
            rawScanURL: source,
            filmType: .colorNegative,
            sourceMetadata: SourceMetadataReader.read(from: source)
        )
        frame.customDisplayName = customDisplayName
        frame.preset = PresetRegistry.load(named: "rich-neutral")
        model.frames = [frame]

        let roll = try XCTUnwrap(
            model.createPhysicalRoll(name: "Roll 12", filmType: .colorNegative)
        )
        XCTAssertTrue(model.assignNewPersistentFrames([frame], toRollID: roll.id))
        XCTAssertTrue(model.updateRollRecord(id: roll.id, record: RollRecord(
            code: "H250729a",
            shot: FilmShotMetadata(
                cameraMake: "Nikon",
                cameraModel: "FM2",
                filmStock: "Portra 400"
            )
        )))

        let baseName = model.exportBaseName(
            for: frame,
            namingTemplate: Self.pattern,
            sequence: 3,
            date: Self.fixedDate,
            timeZone: TimeZone(identifier: "UTC")!,
            recipeIdentity: nil
        )
        let plans = model.makeExportBatchPlans(
            frames: [frame],
            root: exportRoot,
            format: .tiff16,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: ExportOptions(
                colorSpace: .sRGB,
                tiffCompression: .none,
                tiffBitDepth: .sixteen,
                metadataPolicy: .minimal
            ),
            namingTemplate: Self.pattern,
            sequenceStart: 3
        )
        let plan = try XCTUnwrap(plans.first, "내보내기 계획이 비었습니다")

        // 계획된 경로에 실제로 파일을 쓴다 — "실제로 생성된 파일 이름"이 되도록.
        let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48))
        try FileManager.default.createDirectory(
            at: plan.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ExportEngine.write(
            image,
            to: plan.outputURL,
            format: plan.format,
            using: ChromabaseEngine.sharedLinearRenderContext,
            metadata: nil,
            options: plan.options
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.outputURL.path))

        return [
            "variant": label,
            "sourceFileName": source.lastPathComponent,
            "cardDisplayName": frame.displayName(language: .english),
            "customDisplayName": customDisplayName ?? "nil",
            "presentationIndex": frame.presentationIndex,
            "exportBaseName": baseName,
            "createdFileName": plan.outputURL.lastPathComponent,
            "createdFilePathRelativeToRoot": plan.outputURL.path
                .replacingOccurrences(of: exportRoot.path + "/", with: ""),
        ]
    }
}
