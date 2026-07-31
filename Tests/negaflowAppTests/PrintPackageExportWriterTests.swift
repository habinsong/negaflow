import Chromabase
import CoreImage
import ImageIO
import ScannerKit
import XCTest
@testable import negaflowApp

@MainActor
final class PrintPackageExportWriterTests: XCTestCase {
    private var root: URL!
    private var journalDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-print-writer-\(UUID().uuidString)",
            isDirectory: true
        )
        journalDirectory = root.appendingPathComponent("journals", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
        journalDirectory = nil
        try await super.tearDown()
    }

    func testContactSheetPublishesOneFullResolutionPageFromTwoSources() throws {
        let printerOutputProfile = try ICCOutputProfileTestFixture.snapshot()
        let sources = try [
            makeSource(index: 1, width: 24, height: 16, format: .png),
            makeSource(index: 2, width: 16, height: 24, format: .png),
        ]
        let package = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 1,
            contactColumns: 2,
            horizontalSpacingMM: 2,
            verticalSpacingMM: 0
        )
        let artifacts = try XCTUnwrap(PrintPackageArtifactLayout(
            folder: root,
            stem: "contact",
            pageCount: 1,
            format: .png
        ))
        let result = try PrintPackageExportWriter.write(
            request(
                sources: sources,
                package: package,
                artifacts: artifacts,
                format: .png,
                printerOutputProfile: printerOutputProfile
            ),
            journalDirectory: journalDirectory
        )

        XCTAssertEqual(result.outputURLs, artifacts.outputURLs)
        XCTAssertEqual(result.contributorPageIndices, [0: [0], 1: [0]])
        XCTAssertEqual(result.outputIdentities.count, 1)
        let properties = try imageProperties(at: artifacts.outputURLs[0])
        XCTAssertEqual(properties.width, 432)
        XCTAssertEqual(properties.height, 288)
        XCTAssertEqual(
            try embeddedICCProfileSHA256(at: artifacts.outputURLs[0]),
            printerOutputProfile.profileSHA256
        )
        XCTAssertTrue(ExportArtifactCommitJournal.journalExists(
            transactionID: result.transactionID,
            in: journalDirectory
        ))
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: result.transactionID,
            in: journalDirectory
        )
        try ExportArtifactCommitJournal.complete(
            transactionID: result.transactionID,
            in: journalDirectory
        )
    }

    func testWriterReportsCompletedPageProgressForMultiPageContactSheet() throws {
        let sources = try (1...3).map {
            try makeSource(index: $0, width: 24, height: 16, format: .png)
        }
        let artifacts = try XCTUnwrap(PrintPackageArtifactLayout(
            folder: root,
            stem: "progress",
            pageCount: 3,
            format: .png
        ))
        let recorder = PageProgressRecorder()

        _ = try PrintPackageExportWriter.write(
            request(
                sources: sources,
                package: PrintPackageSettings(
                    mode: .contactSheet,
                    contactRows: 1,
                    contactColumns: 1
                ),
                artifacts: artifacts,
                format: .png,
                printerOutputProfile: nil
            ),
            journalDirectory: journalDirectory,
            progress: { recorder.append(completed: $0, total: $1) }
        )

        XCTAssertEqual(
            recorder.values,
            [
                PageProgressRecorder.Value(completed: 0, total: 3),
                PageProgressRecorder.Value(completed: 1, total: 3),
                PageProgressRecorder.Value(completed: 2, total: 3),
                PageProgressRecorder.Value(completed: 3, total: 3),
            ]
        )
    }

    func testCompositePreparationDecodesAtCellResolutionBeforeDeveloping() throws {
        let source = try makeSource(index: 90, width: 2_400, height: 1_600, format: .png)

        let prepared = try ExportDevelopedFrameRenderer.prepareForPrintComposite(
            source.snapshot,
            proxyLongEdge: 300
        )

        XCTAssertLessThanOrEqual(
            max(prepared.rawInput.extent.width, prepared.rawInput.extent.height),
            315
        )
        XCTAssertLessThanOrEqual(
            max(prepared.developedImage.extent.width, prepared.developedImage.extent.height),
            315
        )
    }

    func testTIFF16CompositeKeepsSourceDecodePrecisionButDevelopsAtCellResolution() throws {
        let source = try makeSource(index: 91, width: 2_400, height: 1_600, format: .tiff16)

        let prepared = try ExportDevelopedFrameRenderer.prepareForPrintComposite(
            source.snapshot,
            proxyLongEdge: 300
        )

        XCTAssertEqual(
            max(prepared.rawInput.extent.width, prepared.rawInput.extent.height),
            2_400
        )
        XCTAssertLessThanOrEqual(
            max(prepared.developedImage.extent.width, prepared.developedImage.extent.height),
            315
        )
    }

    func testPicturePackagePublishesSelectedSourcesTogetherOnOnePage() throws {
        let printerOutputProfile = try ICCOutputProfileTestFixture.snapshot()
        let sources = try [
            makeSource(index: 1, width: 24, height: 16, format: .jpeg),
            makeSource(index: 2, width: 16, height: 24, format: .jpeg),
        ]
        let package = PrintPackageSettings(
            mode: .picturePackage,
            pictureTemplate: .fourUp
        )
        let artifacts = try XCTUnwrap(PrintPackageArtifactLayout(
            folder: root,
            stem: "package",
            pageCount: 1,
            format: .jpeg
        ))
        let result = try PrintPackageExportWriter.write(
            request(
                sources: sources,
                package: package,
                artifacts: artifacts,
                format: .jpeg,
                printerOutputProfile: printerOutputProfile
            ),
            journalDirectory: journalDirectory
        )

        XCTAssertEqual(result.contributorPageIndices, [0: [0], 1: [0]])
        XCTAssertEqual(result.outputURLs.count, 1)
        XCTAssertTrue(result.outputURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        for outputURL in result.outputURLs {
            XCTAssertEqual(
                try embeddedICCProfileSHA256(at: outputURL),
                printerOutputProfile.profileSHA256
            )
        }
        try ExportArtifactCommitJournal.markCatalogCommitIntent(
            transactionID: result.transactionID,
            in: journalDirectory
        )
        try ExportArtifactCommitJournal.complete(
            transactionID: result.transactionID,
            in: journalDirectory
        )
    }

    func testSourceChangeBeforePublishLeavesNoPageOrJournal() throws {
        let printerOutputProfile = try ICCOutputProfileTestFixture.snapshot()
        let source = try makeSource(index: 1, width: 24, height: 16, format: .png)
        let artifacts = try XCTUnwrap(PrintPackageArtifactLayout(
            folder: root,
            stem: "changed",
            pageCount: 1,
            format: .png
        ))

        XCTAssertThrowsError(try PrintPackageExportWriter.write(
            request(
                sources: [source],
                package: PrintPackageSettings(
                    mode: .contactSheet,
                    contactRows: 1,
                    contactColumns: 1
                ),
                artifacts: artifacts,
                format: .png,
                printerOutputProfile: printerOutputProfile
            ),
            journalDirectory: journalDirectory,
            beforePublish: {
                try MockScannerBackend.writeSyntheticNegative(
                    width: 30,
                    height: 20,
                    to: source.snapshot.rawScanURL
                )
            }
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifacts.outputURLs[0].path))
        let journals = (try? FileManager.default.contentsOfDirectory(
            at: journalDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertTrue(journals.isEmpty)
    }

    func testPageProfileChangeBeforePublishLeavesNoPageOrJournal() throws {
        let printerOutputProfile = try ICCOutputProfileTestFixture.snapshot()
        let source = try makeSource(index: 1, width: 24, height: 16, format: .png)
        let artifacts = try XCTUnwrap(PrintPackageArtifactLayout(
            folder: root,
            stem: "profile-changed",
            pageCount: 1,
            format: .png
        ))

        XCTAssertThrowsError(try PrintPackageExportWriter.write(
            request(
                sources: [source],
                package: PrintPackageSettings(
                    mode: .contactSheet,
                    contactRows: 1,
                    contactColumns: 1
                ),
                artifacts: artifacts,
                format: .png,
                printerOutputProfile: printerOutputProfile
            ),
            journalDirectory: journalDirectory,
            beforePublish: {
                let stagingURL = try XCTUnwrap(
                    FileManager.default.contentsOfDirectory(
                        at: root,
                        includingPropertiesForKeys: [.isDirectoryKey]
                    ).first {
                        $0.lastPathComponent.hasPrefix(".negaflow-export-")
                            && $0.lastPathComponent.hasSuffix(".tmp")
                    }
                )
                let stagedPageURL = try XCTUnwrap(artifacts.staged(in: stagingURL).first)
                let replacement = CIImage(
                    color: CIColor(red: 0.13, green: 0.72, blue: 0.34)
                ).cropped(to: CGRect(x: 0, y: 0, width: 432, height: 288))
                try ExportEngine.write(
                    replacement,
                    to: stagedPageURL,
                    format: .png,
                    using: CIContext()
                )
            }
        )) { error in
            guard case let ChromabaseError.writeFailed(message) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(message, "invalid staged print package page")
        }
        XCTAssertTrue(artifacts.outputURLs.allSatisfy {
            !FileManager.default.fileExists(atPath: $0.path)
        })
        let rootEntries = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(rootEntries.contains {
            $0.lastPathComponent.hasPrefix(".negaflow-export-")
        })
        let journals = (try? FileManager.default.contentsOfDirectory(
            at: journalDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertTrue(journals.isEmpty)
    }

    func testMissingPrinterOutputProfileUsesDeliveryColorSpace() throws {
        let source = try makeSource(index: 1, width: 24, height: 16, format: .png)
        let artifacts = try XCTUnwrap(PrintPackageArtifactLayout(
            folder: root,
            stem: "missing-profile",
            pageCount: 1,
            format: .png
        ))

        let result = try PrintPackageExportWriter.write(
            request(
                sources: [source],
                package: PrintPackageSettings(
                    mode: .contactSheet,
                    contactRows: 1,
                    contactColumns: 1
                ),
                artifacts: artifacts,
                format: .png,
                printerOutputProfile: nil
            ),
            journalDirectory: journalDirectory
        )

        XCTAssertEqual(result.outputURLs, artifacts.outputURLs)
        let expectedData = try XCTUnwrap(
            ExportColorSpace.sRGB.cgColorSpace.copyICCData() as Data?
        )
        XCTAssertEqual(
            try embeddedICCProfileSHA256(at: artifacts.outputURLs[0]),
            ICCOutputProfileSnapshot.sha256(expectedData)
        )
    }

    func testPageRasterBudgetRejectsOverlappingFullPageSourcesButAllowsContactSheet() throws {
        let sourceCount = PrintPackageSettings.maximumCustomItemCount
        let pagePixelSize = CGSize(width: 4_961, height: 7_016)
        let sourceSizes = Array(repeating: pagePixelSize, count: sourceCount)
        let composition = PrintCompositionSettings(
            paperSize: .a4,
            orientation: .portrait,
            marginMM: 0,
            dpi: 600
        )
        let overlapping = PrintPackageSettings(
            mode: .customPackage,
            customItems: (0..<sourceCount).map { sourceIndex in
                PrintCustomPackageItem(
                    sourceIndex: sourceIndex,
                    normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                    zIndex: sourceIndex
                )
            }
        )
        let overlappingPage = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: sourceSizes,
            composition: composition,
            package: overlapping
        )?.first)
        let overlappingBytes = try XCTUnwrap(
            PrintPackageExportWriter.estimatedPageSourceRasterByteCount(
                sourceSizes: sourceSizes,
                layout: overlappingPage,
                dpi: composition.dpi,
                format: .tiff16
            )
        )
        XCTAssertGreaterThan(
            overlappingBytes,
            PrintPackageExportWriter.maximumPageSourceRasterBytes
        )

        let previewLimitedSizes = Array(
            repeating: CGSize(width: 2_545, height: 3_600),
            count: 4
        )
        let fourOverlapping = PrintPackageSettings(
            mode: .customPackage,
            customItems: (0..<4).map { sourceIndex in
                PrintCustomPackageItem(
                    sourceIndex: sourceIndex,
                    normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                    zIndex: sourceIndex
                )
            }
        )
        let previewLimitedPage = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: previewLimitedSizes,
            composition: composition,
            package: fourOverlapping
        )?.first)
        let previewLimitedBytes = try XCTUnwrap(
            PrintPackageExportWriter.estimatedPageSourceRasterByteCount(
                sourceSizes: previewLimitedSizes,
                layout: previewLimitedPage,
                dpi: composition.dpi,
                format: .tiff16
            )
        )
        XCTAssertGreaterThan(
            previewLimitedBytes,
            PrintPackageExportWriter.maximumPageSourceRasterBytes
        )

        let contact = PrintPackageSettings(
            mode: .contactSheet,
            contactRows: 12,
            contactColumns: 12,
            horizontalSpacingMM: 1,
            verticalSpacingMM: 1
        )
        let contactPage = try XCTUnwrap(PrintPackageLayout.make(
            sourceSizes: sourceSizes,
            composition: composition,
            package: contact
        )?.first)
        let contactBytes = try XCTUnwrap(
            PrintPackageExportWriter.estimatedPageSourceRasterByteCount(
                sourceSizes: sourceSizes,
                layout: contactPage,
                dpi: composition.dpi,
                format: .tiff16
            )
        )
        XCTAssertLessThanOrEqual(
            contactBytes,
            PrintPackageExportWriter.maximumPageSourceRasterBytes
        )
    }

    private func makeSource(
        index: Int,
        width: Int,
        height: Int,
        format: ExportFormat
    ) throws -> PrintPackageExportSource {
        let rawURL = root.appendingPathComponent("source-\(index).tiff")
        try MockScannerBackend.writeSyntheticNegative(width: width, height: height, to: rawURL)
        let frame = ScanFrame(
            scanIndex: index,
            rawScanURL: rawURL,
            filmType: .colorPositive,
            sourcePixelWidth: width,
            sourcePixelHeight: height
        )
        let plan = ExportFrameSnapshotBuilder.build(
            frame: frame,
            sourceIdentity: try RenderManifest.sourceIdentity(for: rawURL),
            outputURL: root.appendingPathComponent("unused-\(index).\(format.fileExtension)"),
            format: format,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: ExportOptions(dpi: 72),
            scannerModel: nil,
            backendUsed: nil
        )
        return PrintPackageExportSource(
            snapshot: plan.snapshot,
            layoutSize: CGSize(width: width, height: height),
            caption: "source-\(index).tiff"
        )
    }

    private func request(
        sources: [PrintPackageExportSource],
        package: PrintPackageSettings,
        artifacts: PrintPackageArtifactLayout,
        format: ExportFormat,
        printerOutputProfile: ICCOutputProfileSnapshot?
    ) -> PrintPackageExportRequest {
        PrintPackageExportRequest(
            sources: sources,
            composition: PrintCompositionSettings(
                paperSize: .fourBySix,
                orientation: .landscape,
                marginMM: 5,
                dpi: 72,
                perforationStyle: .none
            ),
            package: package,
            artifactLayout: artifacts,
            format: format,
            options: ExportOptions(dpi: 72),
            printerOutputProfile: printerOutputProfile,
            appVersion: "test"
        )
    }

    private func embeddedICCProfileSHA256(at url: URL) throws -> String {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let data = try XCTUnwrap(image.colorSpace?.copyICCData() as Data?)
        return ICCOutputProfileSnapshot.sha256(data)
    }

    private func imageProperties(at url: URL) throws -> (width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        return (
            try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int),
            try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        )
    }
}

private final class PageProgressRecorder: @unchecked Sendable {
    struct Value: Equatable {
        let completed: Int
        let total: Int
    }

    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(completed: Int, total: Int) {
        lock.lock()
        storage.append(Value(completed: completed, total: total))
        lock.unlock()
    }
}
