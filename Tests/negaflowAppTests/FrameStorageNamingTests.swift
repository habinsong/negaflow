import XCTest
import Chromabase
@testable import negaflowApp

final class FrameStorageNamingTests: XCTestCase {
    func testDateFolderNameUsesYYYYMMDD() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 9
        let date = calendar.date(from: components)!
        XCTAssertEqual(FrameStorageNaming.dateFolderName(for: date, calendar: calendar), "20260709")
    }

    func testScannerAbbreviationDropsVendorParenthesesAndSpaces() {
        XCTAssertEqual(
            FrameStorageNaming.scannerAbbreviation("Plustek OpticFilm 8200i (Demo)"),
            "OpticFilm8200i"
        )
        XCTAssertEqual(FrameStorageNaming.scannerAbbreviation("EPSON Perfection V850"), "PerfectionV850")
        XCTAssertEqual(FrameStorageNaming.scannerAbbreviation("SP-3000"), "SP-3000")
        XCTAssertEqual(FrameStorageNaming.scannerAbbreviation("   "), "scanner")
    }

    func testLegacyScannerRollNameRequiresExactScannerAndEightDigitDate() {
        XCTAssertTrue(FrameStorageNaming.isLegacyScannerRollName(
            "OpticFilm8100 20260712",
            scannerAbbreviation: "OpticFilm8100"
        ))
        XCTAssertFalse(FrameStorageNaming.isLegacyScannerRollName(
            "무제 필름",
            scannerAbbreviation: "OpticFilm8100"
        ))
        XCTAssertFalse(FrameStorageNaming.isLegacyScannerRollName(
            "OpticFilm8100 제주",
            scannerAbbreviation: "OpticFilm8100"
        ))
        XCTAssertFalse(FrameStorageNaming.isLegacyScannerRollName(
            "OtherScanner 20260712",
            scannerAbbreviation: "OpticFilm8100"
        ))
    }

    func testSanitizeComponentRemovesPathSeparatorsAndControlCharacters() {
        XCTAssertEqual(FrameStorageNaming.sanitizeComponent("roll/01:test?"), "roll01test")
        XCTAssertEqual(FrameStorageNaming.sanitizeComponent("  My Roll  "), "My Roll")
    }

    func testFilmTypeFolderNamesAreStableASCII() {
        let names = FilmType.allCases.map { FrameStorageNaming.filmTypeFolderName($0) }
        XCTAssertEqual(Set(names).count, FilmType.allCases.count)
        XCTAssertEqual(FrameStorageNaming.filmTypeFolderName(.colorNegative), "color-negative")
        XCTAssertEqual(FrameStorageNaming.filmTypeFolderName(.colorPositive), "color-slide")
        XCTAssertEqual(FrameStorageNaming.filmTypeFolderName(.bwNegative), "bw-negative")
        XCTAssertEqual(FrameStorageNaming.filmTypeFolderName(.bwPositive), "bw-slide")
        for name in names {
            XCTAssertTrue(name.allSatisfy { $0.isASCII }, "folder name must stay ASCII: \(name)")
        }
    }

    func testStoredFilmTypeUsesImmediateParentTypeFolder() {
        let root = URL(fileURLWithPath: "/Volumes/Scans/20260724", isDirectory: true)
        let filmFolder = root
            .appendingPathComponent("color-negative", isDirectory: true)
            .appendingPathComponent("Portra 400", isDirectory: true)
        let source = filmFolder.appendingPathComponent("frame-001.tiff")

        XCTAssertEqual(
            FrameStorageNaming.storedFilmType(forSourceURL: source),
            .colorNegative
        )
        XCTAssertEqual(
            FrameStorageNaming.storedFilmType(forFilmFolderURL: filmFolder),
            .colorNegative
        )
        XCTAssertNil(
            FrameStorageNaming.storedFilmType(
                forSourceURL: root
                    .appendingPathComponent("color-negative", isDirectory: true)
                    .appendingPathComponent("frame-001.tiff")
            )
        )
        XCTAssertNil(
            FrameStorageNaming.storedFilmType(
                forSourceURL: root
                    .appendingPathComponent("imports", isDirectory: true)
                    .appendingPathComponent("Portra 400", isDirectory: true)
                    .appendingPathComponent("frame-001.tiff")
            )
        )
    }

    func testAvailableFilmFolderNameKeepsDefaultAndAddsStableSuffix() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-film-name-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(FrameStorageNaming.availableFilmFolderName("무제 필름", in: root), "무제 필름")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("무제 필름"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("무제 필름 2"),
            withIntermediateDirectories: true
        )
        XCTAssertEqual(FrameStorageNaming.availableFilmFolderName("무제 필름", in: root), "무제 필름 3")
        XCTAssertEqual(FrameStorageNaming.availableFilmFolderName(" roll/01 ", in: root), "roll01")
    }

    func testNextFrameNumberContinuesFromExistingFiles() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-naming-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        XCTAssertEqual(FrameStorageNaming.nextFrameNumber(in: folder, prefix: "OpticFilm8200i"), 1)

        for number in [1, 2, 7] {
            let name = FrameStorageNaming.scanFileBaseName(prefix: "OpticFilm8200i", number: number)
            FileManager.default.createFile(atPath: folder.appendingPathComponent("\(name).tiff").path, contents: Data())
        }
        // 다른 스캐너 파일은 번호 계산에 끼어들지 않는다.
        FileManager.default.createFile(
            atPath: folder.appendingPathComponent("OtherScanner_frame_99.tiff").path, contents: Data()
        )

        XCTAssertEqual(FrameStorageNaming.nextFrameNumber(in: folder, prefix: "OpticFilm8200i"), 8)
        XCTAssertEqual(
            FrameStorageNaming.nextFrameNumber(in: folder.appendingPathComponent("missing"), prefix: "OpticFilm8200i"),
            1
        )
    }
}
