import Chromabase
import XCTest
@testable import negaflowApp

@MainActor
final class PrintLayoutTemplateStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-print-templates-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        try await super.tearDown()
    }

    func testTemplateRoundTripPersistsOnlyLayoutSettings() throws {
        let url = directory.appendingPathComponent("templates.json")
        let store = PrintLayoutTemplateStore(url: url)
        let settings = PrintLayoutTemplateSettings(
            paperSize: .eightByTen,
            orientation: .landscape,
            marginMM: 9,
            perforationStyle: .none,
            layoutMode: .contactSheet,
            packageSettings: PrintPackageSettings(
                mode: .contactSheet,
                contactRows: 2,
                contactColumns: 4,
                captionMode: .rating,
                showsCropMarks: true
            )
        )

        let saved = try XCTUnwrap(store.add(name: "  Proof Grid  ", settings: settings))
        let restored = PrintLayoutTemplateStore(url: url)

        XCTAssertEqual(saved.name, "Proof Grid")
        XCTAssertEqual(restored.templates, [saved])
        XCTAssertTrue(restored.canModify)
        XCTAssertEqual(restored.templates[0].settings, settings)
    }

    func testDuplicateNamesAreRejectedCaseInsensitively() throws {
        let store = PrintLayoutTemplateStore(url: directory.appendingPathComponent("templates.json"))
        let settings = validSettings()

        XCTAssertNotNil(store.add(name: "Contact", settings: settings))
        XCTAssertNil(store.add(name: "contact", settings: settings))
        XCTAssertEqual(store.templates.count, 1)
    }

    func testCorruptFileFailsClosedAndCannotBeOverwritten() throws {
        let url = directory.appendingPathComponent("templates.json")
        try Data("{broken".utf8).write(to: url)

        let store = PrintLayoutTemplateStore(url: url)

        XCTAssertFalse(store.canModify)
        XCTAssertTrue(store.templates.isEmpty)
        XCTAssertNil(store.add(name: "Blocked", settings: validSettings()))
        XCTAssertEqual(try Data(contentsOf: url), Data("{broken".utf8))
    }

    func testWorkspaceStoreAppliesTemplateAsOneValidatedSnapshot() {
        let suiteName = "PrintLayoutTemplateStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let workspace = PrintWorkspaceSettingsStore(defaults: defaults)
        let settings = validSettings()

        workspace.apply(settings)

        XCTAssertEqual(workspace.templateSettings(), settings)
        XCTAssertEqual(workspace.effectivePackageSettings()?.mode, .picturePackage)
    }

    func testKoreanTemplateNameUsesCharacterLimitInsteadOfUTF8ByteLimit() throws {
        let store = PrintLayoutTemplateStore(url: directory.appendingPathComponent("templates.json"))
        let eightyCharacters = String(repeating: "가", count: 80)

        let saved = try XCTUnwrap(store.add(name: eightyCharacters, settings: validSettings()))

        XCTAssertEqual(saved.name, eightyCharacters)
        XCTAssertEqual(saved.name.count, 80)
        XCTAssertEqual(PrintLayoutTemplateStore(url: store.url).templates.first?.name, eightyCharacters)
    }

    func testTemplateNameLongerThanLimitIsNormalizedToEightyCharacters() throws {
        let store = PrintLayoutTemplateStore(url: directory.appendingPathComponent("templates.json"))
        let eightyOneCharacters = String(repeating: "가", count: 81)

        let saved = try XCTUnwrap(store.add(name: eightyOneCharacters, settings: validSettings()))

        XCTAssertEqual(saved.name, String(eightyOneCharacters.prefix(80)))
        XCTAssertEqual(saved.name.count, 80)
    }

    private func validSettings() -> PrintLayoutTemplateSettings {
        PrintLayoutTemplateSettings(
            paperSize: .a4,
            orientation: .portrait,
            marginMM: 10,
            perforationStyle: .none,
            layoutMode: .picturePackage,
            packageSettings: PrintPackageSettings(
                mode: .picturePackage,
                pictureTemplate: .oneLargeTwoSmall
            )
        )
    }
}
