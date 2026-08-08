import XCTest
import Chromabase
import ScannerKit
@testable import negaflowApp

@MainActor
final class RollRecordTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-roll-record-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try await super.tearDown()
    }

    func testRollRecordFillsEmptyFieldsAndKeepsFrameValues() async throws {
        let model = try await makeModelWithLibrary()
        let first = try makeFrame(index: 1)
        let second = try makeFrame(index: 2)
        model.frames = [first, second]
        // 두 번째 프레임만 롤 중간에 렌즈를 바꿔 적어 둔 상태.
        XCTAssertTrue(model.applyFilmShot(FilmShotMetadata(lensModel: "Nikkor 105mm"), to: second))

        let roll = try XCTUnwrap(model.createPhysicalRoll(name: "Roll 12", filmType: .colorNegative))
        XCTAssertTrue(model.assignNewPersistentFrames([first, second], toRollID: roll.id))
        XCTAssertTrue(model.updateRollRecord(id: roll.id, record: RollRecord(
            code: "H250729a",
            shot: FilmShotMetadata(
                cameraMake: "Nikon",
                cameraModel: "FM2",
                lensModel: "Nikkor 50mm",
                filmStock: "Kodak Portra 400",
                isoSpeed: 400
            )
        )))

        XCTAssertEqual(first.appMetadataOverlay?.filmShot?.cameraModel, "FM2")
        XCTAssertEqual(first.appMetadataOverlay?.filmShot?.lensModel, "Nikkor 50mm")
        XCTAssertEqual(first.appMetadataOverlay?.filmShot?.filmStock, "Kodak Portra 400")
        XCTAssertEqual(first.appMetadataOverlay?.filmShot?.isoSpeed, 400)
        // 프레임에 적힌 값이 롤 기록보다 우선한다.
        XCTAssertEqual(second.appMetadataOverlay?.filmShot?.lensModel, "Nikkor 105mm")
        XCTAssertEqual(second.appMetadataOverlay?.filmShot?.cameraModel, "FM2")
    }

    func testFrameJoiningARollInheritsTheRecord() async throws {
        let model = try await makeModelWithLibrary()
        let existing = try makeFrame(index: 1)
        model.frames = [existing]
        let roll = try XCTUnwrap(model.createPhysicalRoll(name: "Roll 13", filmType: .colorNegative))
        XCTAssertTrue(model.assignNewPersistentFrames([existing], toRollID: roll.id))
        XCTAssertTrue(model.updateRollRecord(id: roll.id, record: RollRecord(
            shot: FilmShotMetadata(cameraModel: "FM2", filmStock: "Fujicolor C200")
        )))

        let joined = try makeFrame(index: 2)
        model.frames = [existing, joined]
        XCTAssertTrue(model.assignNewPersistentFrames([joined], toRollID: roll.id))

        XCTAssertEqual(joined.appMetadataOverlay?.filmShot?.cameraModel, "FM2")
        XCTAssertEqual(joined.appMetadataOverlay?.filmShot?.filmStock, "Fujicolor C200")
    }

    func testEmptyRecordIsDroppedAndUnassignedRollTakesNoRecord() async throws {
        let model = try await makeModelWithLibrary()
        let roll = try XCTUnwrap(model.createPhysicalRoll(name: "Roll 14", filmType: .colorNegative))

        XCTAssertTrue(model.updateRollRecord(id: roll.id, record: RollRecord()))
        XCTAssertNil(model.rolls.first(where: { $0.id == roll.id })?.record)
        XCTAssertFalse(model.updateRollRecord(
            id: LibraryRoll.unassignedID,
            record: RollRecord(code: "X")
        ))
    }

    func testRollRecordSurvivesACatalogRoundTrip() throws {
        let record = RollRecord(
            code: "H250729a",
            shot: FilmShotMetadata(cameraModel: "FM2", filmStock: "Kodak Portra 400"),
            notes: "Lab: Seoul, N+1"
        )
        let roll = try XCTUnwrap(LibraryRoll.physical(name: "Roll 12", filmType: .colorNegative))
        var stored = roll
        stored.record = record

        let encoded = try JSONEncoder().encode(stored)
        XCTAssertEqual(try JSONDecoder().decode(LibraryRoll.self, from: encoded), stored)

        // 기록이 없던 카탈로그도 그대로 열려야 한다.
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "record")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(try JSONDecoder().decode(LibraryRoll.self, from: legacy).record)
    }

    func testShotRecordIsSearchableAsCameraLensAndFilm() {
        let snapshot = MetadataSearchSnapshot(nil, overlay: AppMetadataOverlay(
            filmShot: FilmShotMetadata(
                cameraMake: "Nikon",
                cameraModel: "FM2",
                lensModel: "Nikkor 50mm",
                filmStock: "Kodak Portra 400",
                isoSpeed: 400
            ),
            sourceMetadataSHA256: nil,
            revision: 1
        ))

        XCTAssertTrue(snapshot.camera.contains("Nikon FM2"))
        XCTAssertTrue(snapshot.lens.contains("Nikkor 50mm"))
        XCTAssertTrue(snapshot.allSearchable.contains("Kodak Portra 400"))
        XCTAssertTrue(snapshot.presentFields.contains(.camera))
        XCTAssertTrue(snapshot.presentFields.contains(.lens))
        XCTAssertFalse(snapshot.unknownTextFields.contains(.camera))
    }

    func testNamingTemplateUsesRollCodeFilmAndCamera() async throws {
        let model = try await makeModelWithLibrary()
        let frame = try makeFrame(index: 7)
        model.frames = [frame]
        let roll = try XCTUnwrap(model.createPhysicalRoll(name: "Roll 12", filmType: .colorNegative))
        XCTAssertTrue(model.assignNewPersistentFrames([frame], toRollID: roll.id))
        XCTAssertTrue(model.updateRollRecord(id: roll.id, record: RollRecord(
            code: "H250729a",
            shot: FilmShotMetadata(cameraMake: "Nikon", cameraModel: "FM2", filmStock: "Portra 400")
        )))

        let pattern = "{rollcode}-{frame}-{film}-{camera}"
        XCTAssertTrue(ExportNamingTemplate.isValid(pattern))
        let name = model.exportBaseName(
            for: frame,
            namingTemplate: pattern,
            sequence: 1,
            date: Date(timeIntervalSince1970: 1_800_000_000),
            recipeIdentity: nil
        )
        XCTAssertTrue(name.hasPrefix("H250729a-"), name)
        XCTAssertTrue(name.contains("Portra"), name)
        XCTAssertTrue(name.contains("Nikon"), name)
    }

    private func makeModelWithLibrary() async throws -> AppModel {
        let model = AppModel(
            libraryCatalogURL: directory.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: directory.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: directory.appendingPathComponent("backups")
        )
        await model.restoreLibraryOnLaunch()
        return model
    }

    private func makeFrame(index: Int) throws -> ScanFrame {
        let source = directory.appendingPathComponent("source-\(index).tif")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: source)
        return ScanFrame(
            scanIndex: index,
            rawScanURL: source,
            filmType: .colorNegative,
            sourceMetadata: SourceMetadataReader.read(from: source)
        )
    }
}
