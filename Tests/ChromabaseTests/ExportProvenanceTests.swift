import XCTest
@testable import Chromabase

final class ExportProvenanceTests: XCTestCase {
    func testProductAndRendererVersionsUseSharedResource() {
        let components = NegaflowProductVersion.current.split(separator: ".")
        XCTAssertGreaterThanOrEqual(components.count, 3)
        XCTAssertTrue(components.prefix(3).allSatisfy { Int($0) != nil })
        XCTAssertEqual(
            NegaflowProductVersion.rendererVersion,
            "chromabase/\(NegaflowProductVersion.current)"
        )
        XCTAssertEqual(NegaflowProductVersion.applicationVersion(), NegaflowProductVersion.current)
    }

    func testApplicationVersionUsesActualAppBundleInfo() throws {
        let appURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NegaflowVersion-\(UUID().uuidString).app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: appURL) }
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.negaflow.version-test",
            "CFBundleName": "NegaflowVersionTest",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "9.8.7",
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contentsURL.appendingPathComponent("Info.plist"))

        let bundle = try XCTUnwrap(Bundle(url: appURL))

        XCTAssertEqual(NegaflowProductVersion.applicationVersion(in: bundle), "9.8.7")
    }

    func testSourceIdentityStreamsKnownFileWithoutRecordingPath() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-source-identity-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)

        let identity = try RenderManifest.sourceIdentity(for: url, chunkSize: 1)
        let manifest = RenderManifest(
            source: identity,
            developRecipeSHA256: String(repeating: "1", count: 64),
            scannerProfileID: nil,
            scannerProfileHash: nil,
            rendererVersion: "chromabase/test",
            decodeProvenance: ImageLoader.DecodeProvenance(
                decoder: .coreImageRAW,
                rawDecoderVersion: "9.dng",
                rawBoostAmount: 0,
                rawScaleFactor: 1
            )
        )
        let encoded = try JSONEncoder().encode(manifest)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertEqual(identity.byteCount, 3)
        XCTAssertEqual(
            identity.sha256,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertFalse(json.contains(url.path))
        XCTAssertFalse(json.contains("sourcePath"))
        XCTAssertEqual(identity.algorithm, .sha256)
        XCTAssertEqual(manifest.schemaVersion, 3)
    }

    func testDevelopRecipeHashIsStableAndChangesWithParameters() throws {
        var first = DevelopParameters()
        first.scannerProfileID = "profile-a"
        let firstHash = try RenderManifest.developRecipeSHA256(for: first)
        let repeatedHash = try RenderManifest.developRecipeSHA256(for: first)

        var changed = first
        changed.exposure = 0.25
        let changedHash = try RenderManifest.developRecipeSHA256(for: changed)

        XCTAssertEqual(firstHash, repeatedHash)
        XCTAssertEqual(firstHash.count, 64)
        XCTAssertNotEqual(firstHash, changedHash)
    }

    func testSidecarRoundTripsOptionalRenderManifestAndXMPDates() throws {
        let sourceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let metadataDate = Date(timeIntervalSince1970: 1_800_000_000)
        var sidecar = Sidecar(
            filmType: .colorNegative,
            parameters: DevelopParameters(),
            appVersion: "1.2.3",
            engineVersion: "chromabase/1.2.3"
        )
        sidecar.sourceDate = sourceDate
        sidecar.metadataDate = metadataDate
        sidecar.renderManifest = RenderManifest(
            source: .init(byteCount: 123, sha256: String(repeating: "a", count: 64)),
            developRecipeSHA256: String(repeating: "b", count: 64),
            scannerProfileID: "profile-a",
            scannerProfileHash: "profile-hash",
            rendererVersion: "chromabase/1.2.3"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(sidecar)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Sidecar.self, from: data)
        let xmp = sidecar.xmpPacket()

        XCTAssertEqual(decoded.sourceDate, sourceDate)
        XCTAssertEqual(decoded.metadataDate, metadataDate)
        XCTAssertEqual(decoded.renderManifest, sidecar.renderManifest)
        XCTAssertEqual(decoded.renderManifest?.renderInputKind, .source)
        XCTAssertEqual(decoded.renderManifest?.coverage, .completeRenderInput)
        XCTAssertTrue(xmp.contains("xmp:CreateDate=\"2023-11-14T22:13:20Z\""))
        XCTAssertTrue(xmp.contains("xmp:ModifyDate=\"2027-01-15T08:00:00Z\""))
        XCTAssertTrue(xmp.contains("xmp:MetadataDate=\"2027-01-15T08:00:00Z\""))
    }

    func testOlderSidecarWithoutProvenanceFieldsStillDecodes() throws {
        let sidecar = Sidecar(filmType: .colorNegative, parameters: DevelopParameters())
        let encoded = try JSONEncoder().encode(sidecar)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "sourceDate")
        object.removeValue(forKey: "metadataDate")
        object.removeValue(forKey: "renderManifest")

        let oldData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Sidecar.self, from: oldData)

        XCTAssertNil(decoded.sourceDate)
        XCTAssertNil(decoded.metadataDate)
        XCTAssertNil(decoded.renderManifest)
    }

    func testOlderRenderManifestWithoutInputCoverageFieldsStillDecodes() throws {
        let oldManifest = Data(#"""
        {
          "schemaVersion": 1,
          "source": {
            "byteCount": 3,
            "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
          },
          "developRecipeSHA256": "1111111111111111111111111111111111111111111111111111111111111111",
          "rendererVersion": "chromabase/1.0.0"
        }
        """#.utf8)

        let decoded = try JSONDecoder().decode(RenderManifest.self, from: oldManifest)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.renderInputKind, .source)
        XCTAssertNil(decoded.renderInput)
        XCTAssertEqual(decoded.coverage, .completeRenderInput)
        XCTAssertEqual(decoded.source.algorithm, .sha256)
        XCTAssertNil(decoded.decodeProvenance)
        XCTAssertNil(decoded.defectRecipeSHA256)
        XCTAssertNil(decoded.outputArtifact)
    }
}
