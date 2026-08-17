import ScannerKit
import XCTest
@testable import negaflowApp

/// 가져오기가 "본 스캔 + IR 채널" 짝을 알아본다.
///
/// 스캔 경로는 IR 을 본 스캔에 붙여 두므로 GrainMend IR 이 자동으로 돌지만, 같은 두 파일을
/// 가져오기로 넣으면 IR 이 사진 한 장으로 목록에 서고 본 스캔에는 IR 이 없어 GrainMend IR 이
/// 아예 돌지 않았다.
@MainActor
final class InfraredImportPairingTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-ir-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        try await super.tearDown()
    }

    // MARK: 짝짓기 규칙

    /// 스캔 경로가 쓰는 이름: `<본스캔 파일명>.ir.tiff`.
    func testScannerNamingPairsInfraredWithItsBaseScan() {
        let base = tempDir.appendingPathComponent("OpticFilm8200i_frame_1.tiff")
        let infrared = tempDir.appendingPathComponent("OpticFilm8200i_frame_1.tiff.ir.tiff")

        let pairing = InfraredImportPairing.resolve([base, infrared])

        XCTAssertEqual(pairing.baseURLs, [base], "IR 은 프레임 목록에 서지 않아야 한다.")
        XCTAssertEqual(pairing.pairedInfraredURLs, [infrared])
        XCTAssertEqual(
            pairing.infraredByBaseIdentity[AppModel.importIdentity(base)]?.path,
            infrared.standardizedFileURL.path
        )
    }

    /// 다른 스캔 소프트웨어의 이름 규칙과, 본 스캔과 확장자가 다른 경우.
    func testThirdPartySuffixesAndDifferingExtensionPair() {
        let cases: [(base: String, infrared: String)] = [
            ("roll-01.tif", "roll-01_ir.tif"),
            ("roll-02.tif", "roll-02-infrared.tiff"),
            ("roll-03.tiff", "roll-03.IR.tiff"),
            ("roll-04.tif", "roll-04_ir.tiff"),
        ]
        for item in cases {
            let base = tempDir.appendingPathComponent(item.base)
            let infrared = tempDir.appendingPathComponent(item.infrared)

            let pairing = InfraredImportPairing.resolve([base, infrared])

            XCTAssertEqual(pairing.baseURLs, [base], "\(item.infrared) 는 IR 로 인식돼야 한다.")
            XCTAssertEqual(
                pairing.infraredByBaseIdentity[AppModel.importIdentity(base)]?.path,
                infrared.standardizedFileURL.path
            )
        }
    }

    /// 짝이 없으면 평범한 사진으로 들어온다 — 잘못 감추는 것보다 낫다.
    func testInfraredWithoutABaseStaysAnOrdinaryImport() {
        let orphan = tempDir.appendingPathComponent("lonely_ir.tiff")

        let pairing = InfraredImportPairing.resolve([orphan])

        XCTAssertEqual(pairing.baseURLs, [orphan])
        XCTAssertTrue(pairing.pairedInfraredURLs.isEmpty)
    }

    /// 구분자 없는 `ir`, TIFF 가 아닌 확장자는 IR 이 아니다.
    func testMarkerRequiresASeparatorAndATiffExtension() {
        let noirBase = tempDir.appendingPathComponent("no.tiff")
        let noir = tempDir.appendingPathComponent("noir.tiff")
        XCTAssertNil(InfraredImportPairing.infraredCoreName(noir))
        XCTAssertEqual(InfraredImportPairing.resolve([noirBase, noir]).baseURLs, [noirBase, noir])

        let jpegBase = tempDir.appendingPathComponent("sunset.jpg")
        let jpegLookalike = tempDir.appendingPathComponent("sunset_ir.jpg")
        XCTAssertNil(InfraredImportPairing.infraredCoreName(jpegLookalike))
        XCTAssertEqual(
            InfraredImportPairing.resolve([jpegBase, jpegLookalike]).baseURLs,
            [jpegBase, jpegLookalike]
        )
    }

    /// 폴더가 다르면 같은 이름이어도 짝이 아니다(여러 폴더를 한 번에 가져올 때).
    func testPairingIsScopedToOneFolder() {
        let base = tempDir.appendingPathComponent("a/frame.tiff")
        let infrared = tempDir.appendingPathComponent("b/frame.tiff.ir.tiff")

        let pairing = InfraredImportPairing.resolve([base, infrared])

        XCTAssertEqual(pairing.baseURLs, [base, infrared])
        XCTAssertTrue(pairing.infraredByBaseIdentity.isEmpty)
    }

    /// 스템만 같은 파일이 여러 개면 확장자가 같은 쪽에 붙인다.
    func testAmbiguousStemPrefersTheMatchingExtension() {
        let tiff = tempDir.appendingPathComponent("frame.tiff")
        let jpeg = tempDir.appendingPathComponent("frame.jpg")
        let infrared = tempDir.appendingPathComponent("frame_ir.tiff")

        let pairing = InfraredImportPairing.resolve([tiff, jpeg, infrared])

        XCTAssertEqual(pairing.baseURLs, [tiff, jpeg])
        XCTAssertEqual(
            pairing.infraredByBaseIdentity[AppModel.importIdentity(tiff)]?.path,
            infrared.standardizedFileURL.path
        )
    }

    // MARK: 가져오기 통합

    /// 짝으로 가져오면 프레임은 본 스캔 하나이고, 그 프레임이 IR 을 들고 있다(= GrainMend IR 가동).
    func testImportingAPairCreatesOneFrameCarryingTheInfraredChannel() throws {
        let model = makeModel()
        let base = try writeTIFF(named: "pair_frame_1.tiff")
        let infrared = try writeTIFF(named: "pair_frame_1.tiff.ir.tiff")

        model.importImages(urls: [base, infrared])

        XCTAssertEqual(model.frames.count, 1, "IR 은 별도 사진으로 서지 않아야 한다.")
        let frame = try XCTUnwrap(model.frames.first)
        XCTAssertEqual(frame.rawScanURL.path, base.standardizedFileURL.path)
        XCTAssertEqual(frame.infraredScanURL?.path, infrared.standardizedFileURL.path)

        frame.filmType = .colorNegative
        model.runInfraredCleanIfNeeded(frame)
        XCTAssertTrue(frame.infraredAutoCleanAttempted, "가져온 짝도 자동으로 GrainMend IR 이 돌아야 한다.")
        model.cancelInfraredClean(frame)
    }

    /// 본 스캔을 먼저 가져온 뒤 IR 만 가져와도 새 사진이 아니라 그 프레임에 붙는다.
    func testInfraredImportedAfterItsBaseAttachesToTheExistingFrame() throws {
        let model = makeModel()
        let base = try writeTIFF(named: "late_frame_1.tiff")
        let infrared = try writeTIFF(named: "late_frame_1.tiff.ir.tiff")

        model.importImages(urls: [base])
        XCTAssertNil(model.frames.first?.infraredScanURL)

        model.importImages(urls: [infrared])

        XCTAssertEqual(model.frames.count, 1, "IR 은 새 프레임을 만들지 않는다.")
        XCTAssertEqual(
            model.frames.first?.infraredScanURL?.path,
            infrared.standardizedFileURL.path
        )
    }

    /// 짝짓기를 모르던 예전 가져오기가 남긴 IR 프레임은 접어서 본 스캔에 붙인다.
    /// 카탈로그에서만 빠지고 원본 IR 파일은 그대로 남는다.
    func testRepairFoldsAStrayInfraredFrameIntoItsBaseScan() throws {
        let model = makeModel()
        let base = try writeTIFF(named: "stray_frame_1.tiff")
        let infrared = try writeTIFF(named: "stray_frame_1.tiff.ir.tiff")

        // IR 을 먼저 가져오면 짝이 없으므로 사진으로 들어온다 — 예전 상태의 재현.
        model.importImages(urls: [infrared])
        model.importImages(urls: [base])
        XCTAssertEqual(model.frames.count, 2, "정리 전에는 IR 이 사진으로 서 있다.")

        model.repairStrayInfraredFrames()

        XCTAssertEqual(model.frames.count, 1)
        let frame = try XCTUnwrap(model.frames.first)
        XCTAssertEqual(frame.rawScanURL.path, base.standardizedFileURL.path)
        XCTAssertEqual(frame.infraredScanURL?.path, infrared.standardizedFileURL.path)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: infrared.path),
            "카탈로그에서만 빼고 원본 파일은 유지해야 한다."
        )
    }

    // MARK: 픽스처

    private func makeModel() -> AppModel {
        AppModel(
            libraryCatalogURL: tempDir.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: tempDir.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: tempDir.appendingPathComponent("backups", isDirectory: true)
        )
    }

    private func writeTIFF(named name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try MockScannerBackend.writeSyntheticNegative(width: 8, height: 6, to: url)
        return url
    }
}
