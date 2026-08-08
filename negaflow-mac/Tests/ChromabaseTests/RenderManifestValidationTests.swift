import XCTest
@testable import Chromabase

final class RenderManifestValidationTests: XCTestCase {
    private let hashA = String(repeating: "a", count: 64)
    private let hashB = String(repeating: "b", count: 64)

    func testCurrentManifestRequiresAndValidatesOutputHardBinding() throws {
        let manifest = makeManifest()

        XCTAssertNoThrow(try manifest.validate())
        XCTAssertEqual(manifest.outputArtifact?.identity.algorithm, .sha256)
    }

    func testCurrentManifestRejectsMissingOutputHardBinding() {
        var manifest = makeManifest()
        manifest.outputArtifact = nil

        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(error as? RenderManifestValidationError, .missingOutputArtifact)
        }
    }

    func testCleanedInputRequiresMatchingIdentityAndDefectRecipe() {
        var manifest = makeManifest()
        manifest.renderInputKind = .cleanedFile
        manifest.renderInput = .init(byteCount: 10, sha256: hashB)
        manifest.defectRecipeSHA256 = nil

        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(error as? RenderManifestValidationError, .missingDefectRecipeHash)
        }

        manifest.defectRecipeSHA256 = hashB
        XCTAssertNoThrow(try manifest.validate())
    }

    func testCoverageContradictionFailsClosed() {
        var manifest = makeManifest()
        manifest.renderInputKind = .cleanedMemory
        manifest.coverage = .completeRenderInput
        manifest.defectRecipeSHA256 = hashB

        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(error as? RenderManifestValidationError, .inconsistentRenderInput)
        }
    }

    func testOutputProfileHashValidatesAndRoundTrips() throws {
        var manifest = makeManifest()
        manifest.outputProfileSHA256 = hashA

        XCTAssertNoThrow(try manifest.validate())
        let decoded = try JSONDecoder().decode(
            RenderManifest.self,
            from: JSONEncoder().encode(manifest)
        )

        XCTAssertEqual(decoded, manifest)
        XCTAssertEqual(decoded.outputProfileSHA256, hashA)
    }

    func testOutputProfileHashRejectsInvalidSHA256() {
        var manifest = makeManifest()
        manifest.outputProfileSHA256 = "sha256:\(hashA)"

        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(
                error as? RenderManifestValidationError,
                .invalidRecipeHash("outputProfileSHA256")
            )
        }
    }

    func testLegacyManifestDefaultsHashAlgorithmAndDoesNotRequireOutput() throws {
        let data = Data(#"""
        {
          "schemaVersion": 1,
          "source": {"byteCount": 3, "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
          "developRecipeSHA256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "rendererVersion": "chromabase/legacy"
        }
        """#.utf8)

        let manifest = try JSONDecoder().decode(RenderManifest.self, from: data)

        XCTAssertEqual(manifest.source.algorithm, .sha256)
        XCTAssertNil(manifest.outputArtifact)
        XCTAssertNoThrow(try manifest.validate())
    }

    func testHashingRejectsInvalidChunkSizeWithoutTrapping() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("render-manifest-chunk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("x".utf8).write(to: url)

        XCTAssertThrowsError(try RenderManifest.sourceIdentity(for: url, chunkSize: 0)) { error in
            XCTAssertEqual(error as? RenderManifestValidationError, .invalidChunkSize)
        }
    }

    private func makeManifest() -> RenderManifest {
        RenderManifest(
            source: .init(byteCount: 3, sha256: hashA),
            developRecipeSHA256: hashB,
            scannerProfileID: nil,
            scannerProfileHash: nil,
            rendererVersion: "chromabase/test",
            outputArtifact: .init(
                identity: .init(byteCount: 100, sha256: hashA),
                format: .jpeg,
                pixelWidth: 10,
                pixelHeight: 8
            )
        )
    }
}
