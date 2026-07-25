import Chromabase
import CryptoKit
import XCTest
@testable import negaflowApp

@MainActor
final class ProofCopyTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "negaflow.proof-copy.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    func testProofCopySharesSourceButKeepsIndependentDevelopAdjustments() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-proof-copy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("source.tiff")
        let sourceData = Data("immutable-source".utf8)
        try sourceData.write(to: sourceURL)

        let model = makeModel()
        let original = ScanFrame(
            scanIndex: 1,
            rawScanURL: sourceURL,
            filmType: .colorNegative
        )
        original.updateParams { $0.exposure = 0.4 }
        model.frames = [original]
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Proof Roll",
            filmType: .colorNegative
        ))
        XCTAssertTrue(model.assignNewPersistentFrames([original], toRollID: roll.id))
        model.exportColorSpace = .displayP3
        model.softProofEnabled = true
        model.softProofSimulation = .paperAndBlackInk
        let beforeFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()

        let copy = try XCTUnwrap(model.createProofCopy(from: original))

        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.rawScanURL, original.rawScanURL)
        XCTAssertEqual(copy.rootFrameID, original.id)
        XCTAssertEqual(copy.params.exposure, original.params.exposure)
        XCTAssertEqual(copy.proofCopyConfiguration?.colorSpace, .displayP3)
        XCTAssertEqual(copy.proofCopyConfiguration?.simulation, .paperAndBlackInk)
        XCTAssertNotNil(copy.proofCopyConfiguration?.resolvedSoftProofSettings)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(),
            beforeFiles
        )

        copy.updateParams { $0.exposure = 1.2 }
        XCTAssertEqual(copy.params.exposure, 1.2)
        XCTAssertEqual(original.params.exposure, 0.4)
    }

    func testCustomICCProofCopyRoundTripsThroughCurrentCatalogRecord() throws {
        let model = makeModel()
        let original = makeFrame()
        model.frames = [original]
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Custom ICC",
            filmType: .colorNegative
        ))
        XCTAssertTrue(model.assignNewPersistentFrames([original], toRollID: roll.id))
        let icc = try XCTUnwrap(SoftProof.profile(for: .displayP3)?.iccData)
        XCTAssertTrue(model.setSoftProofICCProfile(data: icc, name: "Embedded P3"))
        model.softProofEnabled = true

        let copy = try XCTUnwrap(model.createProofCopy(from: original))
        let encoded = try JSONEncoder().encode(LibraryFrameRecord(frame: copy))
        let decoded = try JSONDecoder().decode(LibraryFrameRecord.self, from: encoded)
        let restored = decoded.makeFrame(presets: [])

        let configuration = try XCTUnwrap(restored.proofCopyConfiguration)
        XCTAssertTrue(configuration.usesCustomProfile)
        XCTAssertEqual(configuration.profileName, "Embedded P3")
        XCTAssertEqual(configuration.embeddedICCProfileData, icc)
        XCTAssertEqual(configuration.resolvedSoftProofSettings?.iccProfileData, icc)
        XCTAssertEqual(
            configuration.profileSHA256,
            SHA256.hash(data: icc).map { String(format: "%02x", $0) }.joined()
        )
    }

    func testLegacyCurrentRecordWithoutOptionalProofKeyStillDecodes() throws {
        let record = LibraryFrameRecord(frame: makeFrame())
        let encoded = try JSONEncoder().encode(record)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "proofCopyConfiguration")
        let legacyPayload = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(LibraryFrameRecord.self, from: legacyPayload)

        XCTAssertNil(decoded.proofCopyConfiguration)
    }

    func testTamperedEmbeddedProofProfileFailsClosed() throws {
        let icc = try XCTUnwrap(SoftProof.profile(for: .displayP3)?.iccData)
        let configuration = try XCTUnwrap(ProofCopyConfiguration(
            settings: SoftProofSettings(
                isEnabled: true,
                colorSpace: .displayP3,
                iccProfileData: icc
            ),
            profileName: "Tamper Test"
        ))
        let encoded = try JSONEncoder().encode(configuration)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["profileSHA256"] = String(repeating: "0", count: 64)
        let tampered = try JSONDecoder().decode(
            ProofCopyConfiguration.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(tampered.resolvedSoftProofSettings)
    }

    func testSelectingProofCopyRestoresItsExactProofConfiguration() throws {
        let model = makeModel()
        let original = makeFrame()
        model.frames = [original]
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Restore",
            filmType: .colorNegative
        ))
        XCTAssertTrue(model.assignNewPersistentFrames([original], toRollID: roll.id))
        let printerProfile = try ICCOutputProfileTestFixture.snapshot()
        XCTAssertTrue(model.setPrinterOutputICCProfile(
            data: printerProfile.iccProfileData,
            name: printerProfile.profileName
        ))
        let icc = try XCTUnwrap(SoftProof.profile(for: .displayP3)?.iccData)
        XCTAssertTrue(model.setSoftProofICCProfile(data: icc, name: "Proof Target"))
        model.softProofSimulation = .paperAndBlackInk
        model.softProofEnabled = true
        let copy = try XCTUnwrap(model.createProofCopy(from: original))

        model.selectedFrameID = original.id
        model.clearSoftProofICCProfile()
        model.exportColorSpace = .sRGB
        model.softProofSimulation = .profileOnly
        model.softProofEnabled = false
        model.selectedFrameID = copy.id

        XCTAssertTrue(model.softProofEnabled)
        XCTAssertEqual(model.softProofICCProfileData, icc)
        XCTAssertEqual(model.softProofICCProfileName, "Proof Target")
        XCTAssertEqual(model.softProofSimulation, .paperAndBlackInk)
        XCTAssertEqual(model.printerOutputICCProfileData, printerProfile.iccProfileData)
        XCTAssertEqual(
            model.selectedPrinterOutputProfile?.profileSHA256,
            printerProfile.profileSHA256
        )
    }

    func testPrintWorkspaceMainPreviewAndProofCopyUsePinnedPrinterProfile() throws {
        let model = makeModel()
        let original = makeFrame()
        model.frames = [original]
        let roll = try XCTUnwrap(model.createPhysicalRoll(
            name: "Printer Proof",
            filmType: .colorNegative
        ))
        XCTAssertTrue(model.assignNewPersistentFrames([original], toRollID: roll.id))
        let printerProfile = try ICCOutputProfileTestFixture.snapshot()
        XCTAssertTrue(model.setPrinterOutputICCProfile(
            data: printerProfile.iccProfileData,
            name: printerProfile.profileName
        ))
        model.softProofEnabled = true
        model.activeWorkspaceModule = .print
        original.updateParams { $0.developTarget = .main }

        let workspaceSettings = model.displaySoftProofSettings(for: original)
        XCTAssertEqual(
            workspaceSettings.iccProfileData.map(ICCOutputProfileSnapshot.sha256),
            printerProfile.profileSHA256
        )

        let copy = try XCTUnwrap(model.createProofCopy(from: original))
        XCTAssertEqual(copy.proofCopyConfiguration?.profileName, printerProfile.profileName)
        XCTAssertEqual(copy.proofCopyConfiguration?.profileSHA256, printerProfile.profileSHA256)

        model.clearPrinterOutputICCProfile()
        model.activeWorkspaceModule = .develop
        let pinnedSettings = model.displaySoftProofSettings(for: copy)
        XCTAssertEqual(
            pinnedSettings.iccProfileData.map(ICCOutputProfileSnapshot.sha256),
            printerProfile.profileSHA256
        )
    }

    private func makeFrame() -> ScanFrame {
        ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/offline/proof-source.tiff"),
            filmType: .colorNegative
        )
    }

    private func makeModel() -> AppModel {
        AppModel(exportSettingsStore: ExportSettingsStore(defaults: defaults))
    }
}
