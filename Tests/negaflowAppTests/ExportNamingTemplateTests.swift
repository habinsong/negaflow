import XCTest
import Chromabase
import ScannerKit
@testable import negaflowApp

@MainActor
final class ExportNamingTemplateTests: XCTestCase {
    func testEveryTokenRendersDeterministicallyAndSanitizesForbiddenCharacters() throws {
        let context = ExportNamingContext(
            date: Date(timeIntervalSince1970: 1_704_067_200),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            roll: "Roll/One",
            frameIndex: 7,
            frameName: "Frame:Name",
            preset: "Archive*Preset",
            sequence: 3
        )
        let pattern = "{date}_{roll}_{frame}_{name}_{preset}_{sequence}"

        XCTAssertEqual(
            ExportNamingTemplate.render(pattern, context: context),
            "20240101_RollOne_0007_FrameName_ArchivePreset_0003"
        )
        XCTAssertNil(ExportNamingTemplate.render("{unknown}", context: context))
        XCTAssertFalse(ExportNamingTemplate.isValid("{name"))
    }

    func testLegacyRecipePrefixMigratesToTemplateWithoutLosingFrameName() throws {
        let current = ExportRecipeSettings(
            format: .jpeg,
            options: .standard,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            filenameTemplate: ExportNamingTemplate.defaultPattern
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any]
        )
        object.removeValue(forKey: "filenameTemplate")
        object["filenamePrefix"] = "archive"

        let migrated = try JSONDecoder().decode(
            ExportRecipeSettings.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(migrated.filenameTemplate, "archive-{name}")
        XCTAssertTrue(migrated.isValid)
    }

    func testExportNameMatchesLocalizedPhotoNameInsteadOfScannerSourceFilename() throws {
        let model = AppModel()
        model.appLanguage = .korean
        let frame = ScanFrame(
            scanIndex: 48,
            rawScanURL: URL(fileURLWithPath: "/tmp/OpticFilm8200i_frame_4.tif"),
            filmType: .colorNegative
        )

        XCTAssertEqual(frame.displayName(language: .korean), "사진 4")
        XCTAssertEqual(
            model.exportBaseName(
                for: frame,
                namingTemplate: ExportNamingTemplate.defaultPattern,
                sequence: 1,
                date: Date(timeIntervalSince1970: 0),
                recipeIdentity: nil
            ),
            "사진 4"
        )
        model.quickExportFormat = .png
        XCTAssertEqual(model.quickExportNamingPreview(for: frame), "사진 4.png")
        XCTAssertEqual(
            model.exportBaseName(
                for: frame,
                namingTemplate: "{frame}",
                sequence: 1,
                date: Date(timeIntervalSince1970: 0),
                recipeIdentity: nil
            ),
            "0004"
        )

        frame.assignPhotoNumber(5)
        XCTAssertEqual(frame.displayName(language: .korean), "사진 5")
        XCTAssertEqual(model.quickExportNamingPreview(for: frame), "사진 5.png")
        XCTAssertEqual(
            model.exportBaseName(
                for: frame,
                namingTemplate: "{frame}",
                sequence: 1,
                date: Date(timeIntervalSince1970: 0),
                recipeIdentity: nil
            ),
            "0005"
        )
    }

    func testBatchLiteralCollisionAllocatesDistinctArtifactSets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-naming-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = AppModel()
        let frames = try (1...2).map { index -> ScanFrame in
            let source = root.appendingPathComponent("source-\(index).tif")
            try MockScannerBackend.writeSyntheticNegative(width: 8, height: 8, to: source)
            return ScanFrame(scanIndex: index, rawScanURL: source, filmType: .colorPositive)
        }

        let plans = model.makeExportBatchPlans(
            frames: frames,
            root: root,
            format: .jpeg,
            writeSidecar: true,
            writeMainFlatMaster: true,
            writeOriginalRaw: true,
            options: .standard,
            namingTemplate: "same"
        )

        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans[0].outputURL.deletingPathExtension().lastPathComponent, "same")
        XCTAssertEqual(plans[1].outputURL.deletingPathExtension().lastPathComponent, "same-1")
        let layouts = plans.map {
            ExportArtifactLayout(
                outputURL: $0.outputURL,
                format: $0.format,
                sourceURL: $0.frame.rawScanURL,
                writeSidecar: $0.writeSidecar,
                writeMainFlatMaster: $0.writeMainFlatMaster,
                writeOriginalRaw: $0.writeOriginalRaw
            )
        }
        XCTAssertTrue(layouts[0].standardizedPaths.isDisjoint(with: layouts[1].standardizedPaths))
    }

    func testBatchSequenceStartsAtRequestedNumber() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-sequence-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = AppModel()
        let frames = (1...3).map { index in
            ScanFrame(
                scanIndex: index,
                rawScanURL: root.appendingPathComponent("source-\(index).tif"),
                filmType: .colorPositive
            )
        }

        let plans = model.makeExportBatchPlans(
            frames: frames,
            root: root,
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard,
            namingTemplate: ExportNamingTemplate.sequenceOnlyPattern,
            sequenceStart: 4
        )

        XCTAssertEqual(plans.map { $0.outputURL.lastPathComponent }, [
            "0004.jpg", "0005.jpg", "0006.jpg",
        ])
    }
}
