import XCTest
import Chromabase
import CoreImage
import ScannerKit
import ImageIO
@testable import negaflowApp

@MainActor
final class ExportFrameSnapshotBuilderTests: XCTestCase {
    private var tempDirectory: URL!
    private var ownedCleanedCacheURLs: [URL] = []
    // cleaned-raw persist 가 사용자 머신의 실제/iCloud 폴더를 쓰지 않게 per-test temp 로 격리한다.
    private var cleanedRawIsolation: CleanedRawFolderIsolation?

    override func setUp() async throws {
        try await super.setUp()
        cleanedRawIsolation = CleanedRawFolderIsolation()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-export-builder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        for url in ownedCleanedCacheURLs {
            try? FileManager.default.removeItem(at: url)
        }
        ownedCleanedCacheURLs = []
        tempDirectory = nil
        cleanedRawIsolation?.restore()
        cleanedRawIsolation = nil
        try await super.tearDown()
    }

    private static func makeOnePixelImage() -> CGImage {
        let provider = CGDataProvider(data: Data([0, 0, 0, 255]) as CFData)!
        return CGImage(
            width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    private func makeDefectRecipeIdentity(boundTo rawURL: URL) throws -> DefectRecipeIdentity {
        try DefectRecipeIdentity(
            fingerprintVersion: DefectRecipeFingerprint.currentVersion,
            revision: 1,
            recipeSHA256: String(repeating: "a", count: 64),
            // 현상/내보내기 입력 검증이 recipe의 원본 바인딩과 현재 원본을 비교하므로
            // 실제 파일의 stat identity로 바인드한다.
            sourceIdentity: AppModel.defectSourceIdentity(for: rawURL)
        )
    }

    private func installTrustedMemoryCache(_ image: CGImage, on frame: ScanFrame) throws {
        let identity = try makeDefectRecipeIdentity(boundTo: frame.rawScanURL)
        frame.defectRecipeIdentity = identity
        frame.defectRecipeRevision = identity.revision
        frame.cleanedRawImage = image
        frame.cleanedRawMemoryIdentity = identity
    }

    private func installTrustedDiskCache(from sourceURL: URL, on frame: ScanFrame) throws -> URL {
        let cacheURL = CleanedRawCacheFile.makeBuildURL(frameID: frame.id)
        try Data(contentsOf: sourceURL).write(to: cacheURL, options: .atomic)
        let identity = try makeDefectRecipeIdentity(boundTo: frame.rawScanURL)
        frame.defectRecipeIdentity = identity
        frame.defectRecipeRevision = identity.revision
        frame.cleanedRawDiskURL = cacheURL
        frame.cleanedRawDiskIdentity = identity
        ownedCleanedCacheURLs.append(cacheURL)
        return cacheURL
    }

    private func writeAndComplete(
        _ snapshot: ExportFrameSnapshot
    ) throws -> ExportFrameResult {
        let result = try ExportFrameWriter.write(snapshot)
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: result.commitTransactionID
        )
        try ExportArtifactCommitJournal.complete(
            transactionID: result.commitTransactionID
        )
        return result
    }

    private func exportJournalURLs(referencing directory: URL) throws -> Set<URL> {
        let journalDirectory = ExportArtifactCommitJournal.defaultDirectoryURL()
        guard FileManager.default.fileExists(atPath: journalDirectory.path) else { return [] }
        let directoryPath = directory.standardizedFileURL.path + "/"
        return Set(try FileManager.default.contentsOfDirectory(
            at: journalDirectory,
            includingPropertiesForKeys: nil
        ).compactMap { url in
            guard ["plist", "prep"].contains(url.pathExtension),
                  let data = try? Data(contentsOf: url),
                  let propertyList = try? PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                  ),
                  let dictionary = propertyList as? [String: Any],
                  let stagingDirectoryPath = dictionary["stagingDirectoryPath"] as? String,
                  URL(fileURLWithPath: stagingDirectoryPath)
                    .standardizedFileURL.path.hasPrefix(directoryPath) else {
                return nil
            }
            return url
        })
    }

    func testBuildUsesCleanedRawForDevelopedExportSnapshot() throws {
        let rawURL = tempDirectory.appendingPathComponent("raw.tif")
        let outputURL = tempDirectory.appendingPathComponent("out.jpg")
        try Data("raw-source".utf8).write(to: rawURL)
        let sourceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let metadataDate = Date(timeIntervalSince1970: 1_800_000_000)
        let frame = ScanFrame(
            scanIndex: 7,
            rawScanURL: rawURL,
            filmType: .colorNegative,
            sourceResolutionDPI: 3600,
            sourceBitDepth: 16,
            scannedAt: sourceDate
        )
        try installTrustedMemoryCache(Self.makeOnePixelImage(), on: frame)
        frame.setRating(4)
        frame.pickState = .picked
        frame.updateParams {
            $0.developTarget = .print
            $0.scannerProfileID = "noritsu-hs-1800"
        }

        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL),
            outputURL: outputURL,
            format: .jpeg,
            writeSidecar: true,
            writeMainFlatMaster: true,
            writeOriginalRaw: true,
            options: ExportOptions(colorSpace: .displayP3, dpi: 300, longEdge: 2048),
            scannerModel: "Nikon LS-9000",
            backendUsed: "mock",
            scannerMake: "Nikon",
            scannerDeviceModel: "LS-9000",
            metadataDate: metadataDate,
            appVersion: "1.2.3",
            rendererVersion: "chromabase/1.2.3"
        )

        XCTAssertEqual(plan.snapshot.rawScanURL, rawURL)
        XCTAssertNil(plan.snapshot.cleanedRawURL)          // 디스크 캐시 없음
        XCTAssertNotNil(plan.snapshot.preloadedRaw)        // 결함 제거는 RAM cleaned raw 로 내보낸다
        XCTAssertEqual(plan.snapshot.outputURL, outputURL)
        XCTAssertEqual(plan.snapshot.format, .jpeg)
        XCTAssertEqual(plan.snapshot.params.developTarget, .print)
        XCTAssertEqual(plan.snapshot.scannerProfileID, "noritsu-hs-1800")
        XCTAssertEqual(plan.snapshot.scannerMake, "Nikon")
        XCTAssertEqual(plan.snapshot.scannerDeviceModel, "LS-9000")
        XCTAssertEqual(plan.snapshot.scannerModel, "Nikon LS-9000")
        XCTAssertEqual(plan.snapshot.backendUsed, "mock")
        XCTAssertEqual(plan.snapshot.resolutionDPI, 3600)
        XCTAssertEqual(plan.snapshot.sourceBitDepth, 16)
        XCTAssertEqual(plan.snapshot.rating, 4)
        XCTAssertEqual(plan.snapshot.pickState, .picked)
        XCTAssertEqual(plan.snapshot.sourceDate, sourceDate)
        XCTAssertEqual(plan.snapshot.metadataDate, metadataDate)
        XCTAssertEqual(plan.snapshot.appVersion, "1.2.3")
        XCTAssertEqual(plan.snapshot.rendererVersion, "chromabase/1.2.3")
        XCTAssertTrue(plan.snapshot.writeSidecar)
        XCTAssertTrue(plan.snapshot.writeMainFlatMaster)
        XCTAssertTrue(plan.snapshot.writeOriginalRaw)
        XCTAssertEqual(plan.snapshot.exportOptions.colorSpace, .displayP3)
        XCTAssertEqual(plan.snapshot.exportOptions.dpi, 300)
        XCTAssertEqual(plan.snapshot.exportOptions.longEdge, 2048)
        XCTAssertNil(plan.snapshot.printComposition)
        XCTAssertEqual(plan.baseKey.filmType, .colorNegative)
    }

    func testBuildCapturesImmutablePrinterOutputProfileSnapshot() throws {
        let rawURL = tempDirectory.appendingPathComponent("profile-source.tiff")
        try Data("profile-source".utf8).write(to: rawURL)
        let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
        var profileData = try ICCOutputProfileTestFixture.data()
        let expectedData = profileData
        let profile = try XCTUnwrap(ICCOutputProfileSnapshot(
            profileName: "Synthetic RGB Printer",
            iccProfileData: profileData,
            expectedSHA256: ICCOutputProfileTestFixture.expectedSHA256
        ))

        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: rawURL),
            outputURL: tempDirectory.appendingPathComponent("profile-output.jpg"),
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard,
            printerOutputProfile: profile,
            scannerModel: nil,
            backendUsed: nil
        )
        profileData.append(0)

        let capturedProfile = try XCTUnwrap(plan.snapshot.printerOutputProfile)
        XCTAssertNotEqual(profileData, expectedData)
        XCTAssertEqual(capturedProfile.profileName, "Synthetic RGB Printer")
        XCTAssertEqual(capturedProfile.iccProfileData, expectedData)
        XCTAssertEqual(
            capturedProfile.profileSHA256,
            ICCOutputProfileTestFixture.expectedSHA256
        )
    }

    func testPrintWriterRejectsMissingProfileWithoutArtifactsStagingOrJournal() throws {
        let printTargetRawURL = tempDirectory.appendingPathComponent("missing-profile-target.tiff")
        try MockScannerBackend.writeSyntheticNegative(
            width: 16,
            height: 12,
            to: printTargetRawURL
        )
        let printTargetFrame = ScanFrame(
            scanIndex: 1,
            rawScanURL: printTargetRawURL,
            filmType: .colorPositive
        )
        printTargetFrame.updateParams { $0.developTarget = .print }
        let printTargetPlan = ExportFrameSnapshotBuilder.build(
            frame: printTargetFrame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: printTargetRawURL),
            outputURL: tempDirectory.appendingPathComponent("missing-profile-target.jpg"),
            format: .jpeg,
            writeSidecar: true,
            writeMainFlatMaster: true,
            writeOriginalRaw: true,
            options: .standard,
            scannerModel: nil,
            backendUsed: nil
        )

        let compositionRawURL = tempDirectory.appendingPathComponent("missing-profile-layout.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: compositionRawURL)
        let compositionFrame = ScanFrame(
            scanIndex: 2,
            rawScanURL: compositionRawURL,
            filmType: .colorPositive
        )
        let compositionPlan = ExportFrameSnapshotBuilder.build(
            frame: compositionFrame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: compositionRawURL),
            outputURL: tempDirectory.appendingPathComponent("missing-profile-layout.jpg"),
            format: .jpeg,
            writeSidecar: true,
            writeMainFlatMaster: true,
            writeOriginalRaw: true,
            options: .standard,
            printComposition: PrintCompositionSettings(
                paperSize: .a4,
                orientation: .portrait,
                marginMM: 10,
                dpi: 72,
                perforationStyle: .none
            ),
            scannerModel: nil,
            backendUsed: nil
        )

        XCTAssertTrue(try exportJournalURLs(referencing: tempDirectory).isEmpty)
        for plan in [printTargetPlan, compositionPlan] {
            XCTAssertThrowsError(try ExportFrameWriter.write(plan.snapshot)) { error in
                guard case let ChromabaseError.writeFailed(message) = error else {
                    return XCTFail("unexpected error: \(error)")
                }
                XCTAssertEqual(
                    message,
                    "PRINT export requires a valid RGB printer-class ICC profile"
                )
            }
            let layout = ExportArtifactLayout(
                outputURL: plan.snapshot.outputURL,
                format: plan.snapshot.format,
                sourceURL: plan.snapshot.rawScanURL,
                writeSidecar: plan.snapshot.writeSidecar,
                writeMainFlatMaster: plan.snapshot.writeMainFlatMaster,
                writeOriginalRaw: plan.snapshot.writeOriginalRaw
            )
            for url in layout.allURLs {
                XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            }
        }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path).contains {
            $0.hasPrefix(".negaflow-export-") && $0.hasSuffix(".tmp")
        })
        XCTAssertTrue(try exportJournalURLs(referencing: tempDirectory).isEmpty)
    }

    func testPrintWriterRecordsExactOutputProfileSHA256InRenderManifest() throws {
        let rawURL = tempDirectory.appendingPathComponent("profile-manifest-source.tiff")
        let outputURL = tempDirectory.appendingPathComponent("profile-manifest-output.jpg")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: rawURL)
        let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
        frame.updateParams { $0.developTarget = .print }
        let profile = try ICCOutputProfileTestFixture.snapshot()
        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: rawURL),
            outputURL: outputURL,
            format: .jpeg,
            writeSidecar: true,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard,
            printerOutputProfile: profile,
            scannerModel: nil,
            backendUsed: nil
        )

        _ = try writeAndComplete(plan.snapshot)

        let sidecarURL = outputURL.deletingPathExtension().appendingPathExtension("negaflow.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sidecar = try decoder.decode(Sidecar.self, from: Data(contentsOf: sidecarURL))
        XCTAssertEqual(
            sidecar.renderManifest?.outputProfileSHA256,
            ICCOutputProfileTestFixture.expectedSHA256
        )
    }

    func testPrintCompositionIsRenderedIntoPublishedExportDimensions() throws {
        let rawURL = tempDirectory.appendingPathComponent("print-source.tiff")
        let outputURL = tempDirectory.appendingPathComponent("print-output.jpg")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: rawURL)
        let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
        let settings = PrintCompositionSettings(
            paperSize: .a4,
            orientation: .portrait,
            marginMM: 10,
            dpi: 72,
            perforationStyle: .thirtyFiveMillimeter
        )
        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: rawURL),
            outputURL: outputURL,
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: ExportOptions(dpi: 72),
            printerOutputProfile: try ICCOutputProfileTestFixture.snapshot(),
            printComposition: settings,
            scannerModel: nil,
            backendUsed: nil
        )

        _ = try writeAndComplete(plan.snapshot)

        XCTAssertEqual(plan.snapshot.printComposition, settings)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 595)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 842)
    }

    func testImportedFrameDoesNotMislabelImportTimeAsOriginalDate() throws {
        let sourceURL = tempDirectory.appendingPathComponent("imported.jpg")
        try Data("imported-source".utf8).write(to: sourceURL)
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: sourceURL,
            filmType: .colorPositive,
            sourceKind: .importedFile,
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL),
            outputURL: tempDirectory.appendingPathComponent("out.jpg"),
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard,
            scannerModel: nil,
            backendUsed: nil
        )

        XCTAssertNil(plan.snapshot.sourceDate)
    }

    func testExportProvenanceUsesPersistedScanSessionInsteadOfCurrentDeviceState() throws {
        let sessionID = UUID()
        let jobID = UUID()
        let device = ScannerDescriptor(
            id: "plugin:archive-scanner:device-1",
            displayName: "Archive Scanner Model A",
            vendor: "Archive Imaging",
            model: "Model A",
            backendType: .plugin
        )
        let backend = ScanBackendSnapshot(
            type: .plugin,
            identifier: "archive-scanner",
            version: "2.0",
            pluginIdentifier: "archive-scanner",
            pluginVersion: "3.0"
        )
        let session = try makeSucceededSession(
            sessionID: sessionID,
            jobID: jobID,
            device: device,
            backend: backend
        )
        let model = AppModel(
            libraryCatalogURL: tempDirectory.appendingPathComponent("catalog.json"),
            libraryDefectDirectoryURL: tempDirectory.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: tempDirectory.appendingPathComponent("backups", isDirectory: true)
        )
        model.scanSessions = [session]
        model.demoMode = true
        model.devices = [
            ScannerDescriptor(
                id: "plugin:current-scanner:device-2",
                displayName: "Current Scanner Model B",
                vendor: "Current",
                model: "Model B",
                backendType: .plugin
            ),
        ]
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: tempDirectory.appendingPathComponent("scan.tif"),
            filmType: .colorNegative,
            scanSessionID: sessionID,
            scanJobID: jobID
        )

        let provenance = try XCTUnwrap(model.exportScanSourceSnapshot(for: frame))

        XCTAssertEqual(provenance.sessionID, sessionID)
        XCTAssertEqual(provenance.jobID, jobID)
        XCTAssertEqual(provenance.device, device)
        XCTAssertEqual(provenance.backend, backend)
    }

    func testExportProvenanceDoesNotGuessForImportedOrLegacyScannerFrames() {
        let model = AppModel(
            libraryCatalogURL: tempDirectory.appendingPathComponent("catalog.json"),
            libraryDefectDirectoryURL: tempDirectory.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: tempDirectory.appendingPathComponent("backups", isDirectory: true)
        )
        model.demoMode = true
        let imported = ScanFrame(
            scanIndex: 1,
            rawScanURL: tempDirectory.appendingPathComponent("imported.jpg"),
            filmType: .colorPositive,
            sourceKind: .importedFile
        )
        let legacyScan = ScanFrame(
            scanIndex: 2,
            rawScanURL: tempDirectory.appendingPathComponent("legacy.tif"),
            filmType: .colorNegative
        )

        XCTAssertNil(model.exportScanSourceSnapshot(for: imported))
        XCTAssertNil(model.exportScanSourceSnapshot(for: legacyScan))
    }

    func testBuildUsesCleanedRawDiskCacheAfterMemoryEviction() throws {
        let rawURL = tempDirectory.appendingPathComponent("raw.tif")
        let cleanedURL = tempDirectory.appendingPathComponent("cleaned.tif")
        let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorNegative)
        try Data("raw-source".utf8).write(to: rawURL)
        try Data("cleaned-cache".utf8).write(to: cleanedURL)
        let trustedCleanedURL = try installTrustedDiskCache(from: cleanedURL, on: frame)

        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL),
            outputURL: tempDirectory.appendingPathComponent("out.jpg"),
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard,
            scannerModel: nil,
            backendUsed: nil
        )

        XCTAssertEqual(plan.snapshot.cleanedRawURL, trustedCleanedURL)
        XCTAssertNil(plan.snapshot.preloadedRaw)
    }

    func testExportSidecarDoesNotOverwriteSourceXMP() throws {
        let sourceDirectory = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let exportDirectory = tempDirectory.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let rawURL = sourceDirectory.appendingPathComponent("scan.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: rawURL)
        let existingXMP = rawURL.deletingPathExtension().appendingPathExtension("xmp")
        try Data("third-party-xmp".utf8).write(to: existingXMP)
        let outputURL = exportDirectory.appendingPathComponent("scan.jpg")
        let sourceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let metadataDate = Date(timeIntervalSince1970: 1_800_000_000)
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: rawURL,
            filmType: .colorPositive,
            scannedAt: sourceDate
        )
        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL),
            outputURL: outputURL,
            format: .jpeg,
            writeSidecar: true,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard,
            scannerModel: nil,
            backendUsed: nil,
            metadataDate: metadataDate,
            appVersion: "1.2.3",
            rendererVersion: "chromabase/1.2.3"
        )

        _ = try writeAndComplete(plan.snapshot)

        XCTAssertEqual(try Data(contentsOf: existingXMP), Data("third-party-xmp".utf8))
        let xmpURL = outputURL.deletingPathExtension().appendingPathExtension("xmp")
        let sidecarURL = outputURL.deletingPathExtension().appendingPathExtension("negaflow.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: xmpURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sidecarData = try Data(contentsOf: sidecarURL)
        let sidecar = try decoder.decode(Sidecar.self, from: sidecarData)
        let expectedSource = try RenderManifest.sourceIdentity(for: rawURL)
        let xmp = try String(contentsOf: xmpURL, encoding: .utf8)

        XCTAssertEqual(sidecar.appVersion, "1.2.3")
        XCTAssertEqual(sidecar.engineVersion, "chromabase/1.2.3")
        XCTAssertEqual(sidecar.sourceDate, sourceDate)
        XCTAssertEqual(sidecar.metadataDate, metadataDate)
        XCTAssertEqual(sidecar.renderManifest?.source, expectedSource)
        XCTAssertEqual(sidecar.renderManifest?.rendererVersion, "chromabase/1.2.3")
        XCTAssertEqual(sidecar.renderManifest?.renderInputKind, .source)
        XCTAssertEqual(sidecar.renderManifest?.coverage, .completeRenderInput)
        XCTAssertNil(sidecar.renderManifest?.renderInput)
        XCTAssertEqual(sidecar.renderManifest?.schemaVersion, 3)
        XCTAssertEqual(sidecar.renderManifest?.outputArtifact?.format, .jpeg)
        XCTAssertEqual(
            sidecar.renderManifest?.outputArtifact?.identity,
            try RenderManifest.sourceIdentity(for: outputURL)
        )
        XCTAssertGreaterThan(sidecar.renderManifest?.outputArtifact?.pixelWidth ?? 0, 0)
        XCTAssertGreaterThan(sidecar.renderManifest?.outputArtifact?.pixelHeight ?? 0, 0)
        XCTAssertEqual(
            sidecar.renderManifest?.developRecipeSHA256,
            try RenderManifest.developRecipeSHA256(for: plan.snapshot.params)
        )
        XCTAssertFalse(try XCTUnwrap(String(data: sidecarData, encoding: .utf8)).contains(rawURL.path))
        XCTAssertTrue(xmp.contains("xmp:CreateDate=\"2023-11-14T22:13:20Z\""))
        XCTAssertTrue(xmp.contains("xmp:ModifyDate=\"2027-01-15T08:00:00Z\""))
        XCTAssertTrue(xmp.contains("xmp:MetadataDate=\"2027-01-15T08:00:00Z\""))
    }

    func testRepeatedWriterExportFromFixedSnapshotIsDeterministicAndMarksMemoryCleanedInput() throws {
        let rawURL = tempDirectory.appendingPathComponent("source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: rawURL)
        let outputURL = tempDirectory.appendingPathComponent("repeat.jpg")
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: rawURL,
            filmType: .colorPositive,
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try installTrustedMemoryCache(Self.makeOnePixelImage(), on: frame)
        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL),
            outputURL: outputURL,
            format: .jpeg,
            writeSidecar: true,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard,
            scannerModel: nil,
            backendUsed: nil,
            metadataDate: Date(timeIntervalSince1970: 1_800_000_000),
            appVersion: "1.2.3",
            rendererVersion: "chromabase/1.2.3"
        )

        _ = try writeAndComplete(plan.snapshot)
        let firstImage = try Data(contentsOf: outputURL)
        let sidecarURL = outputURL.deletingPathExtension().appendingPathExtension("negaflow.json")
        let firstSidecar = try Data(contentsOf: sidecarURL)

        let firstLayout = ExportArtifactLayout(
            outputURL: outputURL,
            format: .jpeg,
            sourceURL: rawURL,
            writeSidecar: true,
            writeMainFlatMaster: false,
            writeOriginalRaw: false
        )
        for url in firstLayout.allURLs {
            try FileManager.default.removeItem(at: url)
        }

        _ = try writeAndComplete(plan.snapshot)
        let secondImage = try Data(contentsOf: outputURL)
        let secondSidecar = try Data(contentsOf: sidecarURL)

        XCTAssertEqual(secondImage, firstImage)
        XCTAssertEqual(secondSidecar, firstSidecar)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sidecar = try decoder.decode(Sidecar.self, from: secondSidecar)
        XCTAssertEqual(sidecar.renderManifest?.renderInputKind, .cleanedMemory)
        XCTAssertEqual(sidecar.renderManifest?.coverage, .sourceAndDevelopRecipe)
        XCTAssertNil(sidecar.renderManifest?.renderInput)
        XCTAssertEqual(
            sidecar.renderManifest?.defectRecipeSHA256,
            plan.snapshot.cleanedRawIdentity?.recipeSHA256
        )
    }

    func testSameDirectorySourceXMPConflictDoesNotPublishOrOverwriteAnything() throws {
        let rawURL = tempDirectory.appendingPathComponent("scan.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: rawURL)
        let existingXMP = tempDirectory.appendingPathComponent("scan.xmp")
        let existingBytes = Data("third-party-source-xmp".utf8)
        try existingBytes.write(to: existingXMP)
        let outputURL = tempDirectory.appendingPathComponent("scan.jpg")
        let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL),
            outputURL: outputURL,
            format: .jpeg,
            writeSidecar: true,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard,
            scannerModel: nil,
            backendUsed: nil
        )

        XCTAssertThrowsError(try ExportFrameWriter.write(plan.snapshot))

        XCTAssertEqual(try Data(contentsOf: existingXMP), existingBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: outputURL.deletingPathExtension().appendingPathExtension("negaflow.json").path
        ))
    }

    func testExistingPairArtifactStopsWholeExportWithoutChangingExistingFile() throws {
        let rawURL = tempDirectory.appendingPathComponent("source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: rawURL)
        let outputURL = tempDirectory.appendingPathComponent("pair.jpg")
        let mainFlatURL = ExportPairing.mainFlatMasterURL(for: outputURL)
        let existingBytes = Data("existing-main-flat".utf8)
        try existingBytes.write(to: mainFlatURL)
        let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL),
            outputURL: outputURL,
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: true,
            writeOriginalRaw: false,
            options: .standard,
            scannerModel: nil,
            backendUsed: nil
        )

        XCTAssertThrowsError(try ExportFrameWriter.write(plan.snapshot))

        XCTAssertEqual(try Data(contentsOf: mainFlatURL), existingBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testExistingOriginalPairIsNeverDeletedBeforeExport() throws {
        let rawURL = tempDirectory.appendingPathComponent("source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: rawURL)
        let outputURL = tempDirectory.appendingPathComponent("pair.jpg")
        let originalURL = ExportPairing.originalRawURL(for: outputURL, sourceExtension: "tiff")
        let existingBytes = Data("existing-original-pair".utf8)
        try existingBytes.write(to: originalURL)
        let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL),
            outputURL: outputURL,
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: true,
            options: .standard,
            scannerModel: nil,
            backendUsed: nil
        )

        XCTAssertThrowsError(try ExportFrameWriter.write(plan.snapshot))

        XCTAssertEqual(try Data(contentsOf: originalURL), existingBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testUniqueExportNameAdvancesWholeSetWhenOnlySidecarExists() throws {
        let existingXMP = tempDirectory.appendingPathComponent("frame.xmp")
        try Data("existing".utf8).write(to: existingXMP)
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: tempDirectory.appendingPathComponent("source.tiff"),
            filmType: .colorPositive
        )
        let model = AppModel(
            libraryCatalogURL: tempDirectory.appendingPathComponent("catalog.json"),
            libraryDefectDirectoryURL: tempDirectory.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: tempDirectory.appendingPathComponent("backups", isDirectory: true)
        )

        let selected = model.uniqueExportURL(
            in: tempDirectory,
            baseName: "frame",
            frame: frame,
            format: .jpeg,
            writeSidecar: true,
            writeMainFlatMaster: true,
            writeOriginalRaw: true
        )

        XCTAssertEqual(selected.lastPathComponent, "frame-1.jpg")
        XCTAssertEqual(try Data(contentsOf: existingXMP), Data("existing".utf8))
    }

    private func makeSucceededSession(
        sessionID: UUID,
        jobID: UUID,
        device: ScannerDescriptor,
        backend: ScanBackendSnapshot
    ) throws -> ScanSession {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let startedAt = createdAt.addingTimeInterval(1)
        let completedAt = createdAt.addingTimeInterval(2)
        let succeededAt = createdAt.addingTimeInterval(3)
        let rawURL = tempDirectory.appendingPathComponent("provenance-\(jobID).tiff")
        try Data([1]).write(to: rawURL)
        var options = ScanOptions.strongDefault(scannerID: device.id)
        options.requestID = jobID
        options.temporaryOutputURL = rawURL
        let queued = try ScanJob(
            id: jobID,
            sessionID: sessionID,
            ordinal: 1,
            kind: .full,
            requestedOptions: options,
            framePublication: try ScanFramePublicationSnapshot(
                frameID: UUID(),
                scanIndex: 1,
                initialTransform: .identity,
                developTarget: .main,
                storageGroupName: "ArchiveScanner"
            ),
            createdAt: createdAt
        )
        let running = try queued.started(at: startedAt)
        let result = ScanResult(
            rawFileURL: rawURL,
            width: 1,
            height: 1,
            resolution: options.resolution,
            bitDepth: options.bitDepth,
            backendUsed: backend.type,
            appliedOptionsEvidence: .verified(options)
        )
        let pending = try PendingCaptureSnapshot(
            scanResult: result,
            captureStartedAt: startedAt,
            captureCompletedAt: completedAt
        )
        let finalizing = try running.finalizing(with: pending, at: completedAt)
        let manifest = try CaptureManifest.build(
            sessionID: sessionID,
            jobID: jobID,
            attempt: finalizing.attempt,
            kind: .full,
            requestedOptions: options,
            pendingCapture: pending,
            chunkSize: 1
        )
        let succeeded = try finalizing.succeeded(with: manifest, at: succeededAt)
        return try ScanSession(
            id: sessionID,
            createdAt: createdAt,
            device: device,
            backend: backend,
            environment: ScanEnvironmentSnapshot(
                applicationName: "negaflow",
                applicationVersion: "1.0",
                operatingSystem: "macOS",
                operatingSystemVersion: "14.0"
            ),
            jobs: [succeeded]
        )
    }

    func testSidecarHashesCleanedDiskRenderInputWithoutExposingPath() throws {
        let rawURL = tempDirectory.appendingPathComponent("source.tiff")
        let cleanedURL = tempDirectory.appendingPathComponent("cleaned.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: rawURL)
        try MockScannerBackend.writeSyntheticNegative(width: 12, height: 8, to: cleanedURL)
        let outputURL = tempDirectory.appendingPathComponent("cleaned.jpg")
        let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
        let trustedCleanedURL = try installTrustedDiskCache(from: cleanedURL, on: frame)
        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL),
            outputURL: outputURL,
            format: .jpeg,
            writeSidecar: true,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard,
            scannerModel: nil,
            backendUsed: nil,
            metadataDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        _ = try writeAndComplete(plan.snapshot)

        let sidecarURL = outputURL.deletingPathExtension().appendingPathExtension("negaflow.json")
        let sidecarData = try Data(contentsOf: sidecarURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sidecar = try decoder.decode(Sidecar.self, from: sidecarData)
        XCTAssertEqual(sidecar.renderManifest?.renderInputKind, .cleanedFile)
        XCTAssertEqual(sidecar.renderManifest?.coverage, .completeRenderInput)
        XCTAssertEqual(
            sidecar.renderManifest?.renderInput,
            try RenderManifest.sourceIdentity(for: trustedCleanedURL)
        )
        XCTAssertEqual(
            sidecar.renderManifest?.defectRecipeSHA256,
            plan.snapshot.cleanedRawIdentity?.recipeSHA256
        )
        let json = try XCTUnwrap(String(data: sidecarData, encoding: .utf8))
        XCTAssertFalse(json.contains(rawURL.path))
        XCTAssertFalse(json.contains(trustedCleanedURL.path))
    }

    func testManifestRecordsSourceWhenUnreadableCleanedCacheFallsBackToSource() throws {
        let rawURL = tempDirectory.appendingPathComponent("source.tiff")
        let corruptCleanedURL = tempDirectory.appendingPathComponent("corrupt-cleaned.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: rawURL)
        try Data("not-an-image".utf8).write(to: corruptCleanedURL)
        let outputURL = tempDirectory.appendingPathComponent("fallback.jpg")
        let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
        frame.cleanedRawDiskURL = corruptCleanedURL
        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL),
            outputURL: outputURL,
            format: .jpeg,
            writeSidecar: true,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard,
            scannerModel: nil,
            backendUsed: nil,
            metadataDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        _ = try writeAndComplete(plan.snapshot)

        let sidecarURL = outputURL.deletingPathExtension().appendingPathExtension("negaflow.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sidecar = try decoder.decode(Sidecar.self, from: Data(contentsOf: sidecarURL))
        XCTAssertEqual(sidecar.renderManifest?.renderInputKind, .source)
        XCTAssertEqual(sidecar.renderManifest?.coverage, .completeRenderInput)
        XCTAssertNil(sidecar.renderManifest?.renderInput)
    }

    func testRequiredCleanedRawNeverFallsBackToSourceWhenCacheIsCorrupt() throws {
        let rawURL = tempDirectory.appendingPathComponent("required-source.tiff")
        let corruptCleanedURL = tempDirectory.appendingPathComponent("required-corrupt-cleaned.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: rawURL)
        try Data("not-an-image".utf8).write(to: corruptCleanedURL)
        let outputURL = tempDirectory.appendingPathComponent("required.jpg")
        let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
        frame.defectEdits = [
            DefectEditItem(
                edit: .brush([]),
                label: .guided(count: 1),
                summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)),
                preview: [],
                baseSize: nil
            ),
        ]
        frame.cleanedRawDiskURL = corruptCleanedURL
        frame.cleanedRawEditCount = 1
        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL),
            outputURL: outputURL,
            format: .jpeg,
            writeSidecar: true,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard,
            scannerModel: nil,
            backendUsed: nil
        )

        XCTAssertTrue(plan.snapshot.requiresCleanedRaw)
        XCTAssertThrowsError(try ExportFrameWriter.write(plan.snapshot))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path).contains {
            $0.hasPrefix(".negaflow-export-")
        })
    }

    func testExportPreparationRebuildsCorruptCleanedCacheFromAuthoritativeRecipe() async throws {
        let rawURL = tempDirectory.appendingPathComponent("rebuild-source.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: rawURL)
        let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
        let corruptCleanedURL = CleanedRawCacheFile.makeBuildURL(frameID: frame.id)
        defer { try? FileManager.default.removeItem(at: corruptCleanedURL) }
        try Data("not-an-image".utf8).write(to: corruptCleanedURL)
        frame.defectEdits = [
            DefectEditItem(
                edit: .brush([]),
                label: .guided(count: 1),
                summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)),
                preview: [],
                baseSize: nil
            ),
        ]
        frame.cleanedRawDiskURL = corruptCleanedURL
        frame.cleanedRawEditCount = 1
        let model = AppModel(
            libraryCatalogURL: tempDirectory.appendingPathComponent("catalog.json"),
            libraryDefectDirectoryURL: tempDirectory.appendingPathComponent("defects", isDirectory: true),
            libraryBackupDirectoryURL: tempDirectory.appendingPathComponent("backups", isDirectory: true)
        )
        model.frames = [frame]

        let ready = await model.prepareCleanedRawForExport(frame, format: .jpeg)

        XCTAssertTrue(ready)
        XCTAssertEqual(frame.cleanedRawEditCount, 1)
        XCTAssertTrue(frame.cleanedRawImage != nil || frame.cleanedRawDiskURL != nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptCleanedURL.path))
        model.discardCleanedRaw(frame, preservingDefectSidecar: true)
    }

    func testBuildKeepsRawScanTIFFOnOriginalRawInput() throws {
        let rawURL = tempDirectory.appendingPathComponent("raw.tif")
        let outputURL = tempDirectory.appendingPathComponent("raw-copy.tif")
        try Data("raw-source".utf8).write(to: rawURL)
        let frame = ScanFrame(scanIndex: 2, rawScanURL: rawURL, filmType: .colorPositive)
        frame.cleanedRawImage = Self.makeOnePixelImage()

        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL),
            outputURL: outputURL,
            format: .rawScanTIFF,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard,
            scannerModel: nil,
            backendUsed: nil
        )

        XCTAssertNil(plan.snapshot.cleanedRawURL)
        XCTAssertNil(plan.snapshot.preloadedRaw)
        XCTAssertEqual(plan.snapshot.rawScanURL, rawURL)
        XCTAssertEqual(plan.snapshot.format, .rawScanTIFF)
    }

    func testPrintWriterRejectsStagedPrimaryProfileChangeWithoutSidecar() throws {
        let rawURL = tempDirectory.appendingPathComponent("profile-swap-source.tiff")
        let outputURL = tempDirectory.appendingPathComponent("profile-swap-output.tif")
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 12, to: rawURL)
        let frame = ScanFrame(scanIndex: 1, rawScanURL: rawURL, filmType: .colorPositive)
        frame.updateParams { $0.developTarget = .print }
        let profile = try ICCOutputProfileTestFixture.snapshot()
        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: rawURL),
            outputURL: outputURL,
            format: .tiff16,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard,
            printerOutputProfile: profile,
            scannerModel: nil,
            backendUsed: nil
        )
        let finalLayout = ExportArtifactLayout(
            outputURL: outputURL,
            format: .tiff16,
            sourceURL: rawURL,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false
        )

        XCTAssertThrowsError(try ExportFrameWriter.write(plan.snapshot) {
            let stagingName = try XCTUnwrap(
                FileManager.default.contentsOfDirectory(atPath: tempDirectory.path).first {
                    $0.hasPrefix(".negaflow-export-") && $0.hasSuffix(".tmp")
                }
            )
            let stagingDirectory = tempDirectory.appendingPathComponent(
                stagingName,
                isDirectory: true
            )
            let stagedOutputURL = finalLayout.staged(in: stagingDirectory).outputURL
            let replacement = CIImage(
                color: CIColor(red: 0.82, green: 0.16, blue: 0.31)
            ).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 12))
            try ExportEngine.write(
                replacement,
                to: stagedOutputURL,
                format: .tiff16,
                using: CIContext()
            )
        }) { error in
            guard case let ChromabaseError.writeFailed(message) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(message, "rendered artifact ICC profile does not match request")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path).contains {
            $0.hasPrefix(".negaflow-export-") && $0.hasSuffix(".tmp")
        })
    }

    func testRawScanTIFFTrackingIgnoresUnboundActiveDefectRecipe() throws {
        let rawURL = tempDirectory.appendingPathComponent("raw-with-unbound-defect.tif")
        let frame = ScanFrame(scanIndex: 3, rawScanURL: rawURL, filmType: .colorPositive)
        frame.defectEdits = [
            DefectEditItem(
                edit: .brush([]),
                label: .guided(count: 1),
                summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)),
                preview: [],
                baseSize: nil
            ),
        ]
        frame.establishLibraryWorkflowBaselineIfNeeded()
        var workflow = try XCTUnwrap(frame.libraryWorkflowTrackingState)
        workflow.defectReviewTracking = LibraryDefectReviewTracking(
            coverage: .tracked,
            currentRecipeRevision: 2,
            currentRecipeSHA256: nil,
            currentSourceIdentitySHA256: nil,
            reviewedRecipeRevision: nil,
            reviewedRecipeSHA256: nil,
            reviewedSourceIdentitySHA256: nil
        )
        frame.libraryWorkflowTrackingState = workflow

        let tracking = try XCTUnwrap(
            ExportFrameTrackingIdentity.capture(frame: frame, format: .rawScanTIFF)
        )

        XCTAssertEqual(tracking.renderKind, .rawSource)
        XCTAssertNil(tracking.defectRecipeIdentity)
        XCTAssertTrue(tracking.matchesCurrentState(
            of: frame,
            format: .rawScanTIFF,
            isOwnedByModel: true
        ))
        XCTAssertNil(ExportFrameTrackingIdentity.capture(frame: frame, format: .jpeg))
    }

    func testDevelopedExportRejectsCleanedMemoryAfterSourceBytesChange() throws {
        let rawURL = tempDirectory.appendingPathComponent("source-before-change.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 12, height: 8, to: rawURL)
        let outputURL = tempDirectory.appendingPathComponent("changed-source.jpg")
        let frame = ScanFrame(scanIndex: 4, rawScanURL: rawURL, filmType: .colorPositive)
        let item = DefectEditItem(
            edit: .brush([]),
            label: .guided(count: 1),
            summaryKind: .classBreakdown(DefectClassBreakdown(counts: [], meanConfidence: 0)),
            preview: [],
            baseSize: nil
        )
        frame.defectEdits = [item]
        let identity = try DefectRecipeSnapshot(
            frameID: frame.id,
            revision: 1,
            sourceIdentity: AppModel.defectSourceIdentity(for: rawURL),
            items: [DefectEditItemRecord(item: item)]
        ).identity
        frame.defectRecipeIdentity = identity
        frame.defectRecipeRevision = identity.revision
        frame.cleanedRawImage = Self.makeOnePixelImage()
        frame.cleanedRawMemoryIdentity = identity
        frame.cleanedRawEditCount = 1
        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: frame.rawScanURL),
            outputURL: outputURL,
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard,
            scannerModel: nil,
            backendUsed: nil
        )
        try Data("same path, different bytes".utf8).write(to: rawURL, options: .atomic)

        XCTAssertThrowsError(try ExportFrameWriter.write(plan.snapshot))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testDefectFreeExportRejectsSourceChangeAfterSnapshot() throws {
        let rawURL = tempDirectory.appendingPathComponent("source-without-defects.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 12, height: 8, to: rawURL)
        let outputURL = tempDirectory.appendingPathComponent("changed-without-defects.jpg")
        let frame = ScanFrame(scanIndex: 5, rawScanURL: rawURL, filmType: .colorPositive)
        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: rawURL),
            outputURL: outputURL,
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: .standard,
            scannerModel: nil,
            backendUsed: nil
        )
        try MockScannerBackend.writeSyntheticNegative(width: 16, height: 10, to: rawURL)

        XCTAssertThrowsError(try ExportFrameWriter.write(plan.snapshot))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testSourceChangeBeforeCommitPreventsPublishingEveryArtifact() throws {
        let rawURL = tempDirectory.appendingPathComponent("source-before-commit.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 12, height: 8, to: rawURL)
        let outputURL = tempDirectory.appendingPathComponent("before-commit.jpg")
        let frame = ScanFrame(scanIndex: 6, rawScanURL: rawURL, filmType: .colorPositive)
        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: rawURL),
            outputURL: outputURL,
            format: .jpeg,
            writeSidecar: true,
            writeMainFlatMaster: true,
            writeOriginalRaw: true,
            options: .standard,
            scannerModel: nil,
            backendUsed: nil
        )
        let layout = ExportArtifactLayout(
            outputURL: outputURL,
            format: .jpeg,
            sourceURL: rawURL,
            writeSidecar: true,
            writeMainFlatMaster: true,
            writeOriginalRaw: true
        )

        XCTAssertThrowsError(try ExportFrameWriter.write(plan.snapshot) {
            try MockScannerBackend.writeSyntheticNegative(width: 16, height: 10, to: rawURL)
        })
        for url in layout.allURLs {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path).contains {
            $0.hasPrefix(".negaflow-export-")
        })
    }

    func testOriginalPairUsesCapturedImmutableSourceGeneration() throws {
        let rawURL = tempDirectory.appendingPathComponent("source-paired.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 12, height: 8, to: rawURL)
        let outputURL = tempDirectory.appendingPathComponent("paired.jpg")
        let frame = ScanFrame(scanIndex: 7, rawScanURL: rawURL, filmType: .colorPositive)
        let sourceIdentity = try RenderManifest.sourceIdentity(for: rawURL)
        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: sourceIdentity,
            outputURL: outputURL,
            format: .jpeg,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: true,
            options: .standard,
            scannerModel: nil,
            backendUsed: nil
        )

        let result = try writeAndComplete(plan.snapshot)
        let originalURL = try XCTUnwrap(result.originalRawURL)

        XCTAssertEqual(try RenderManifest.sourceIdentity(for: originalURL), sourceIdentity)
    }
}
