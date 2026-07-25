import AppKit
import Chromabase
import CoreGraphics
import Darwin
import ImageIO
import XCTest
@testable import negaflowApp

@MainActor
final class RollStabilityPixelStressTests: XCTestCase {
    func testFortyEightFrameRollUsesRealPixelInputsWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["NEGAFLOW_REAL_PIXEL_ROLL_STRESS"] == "1" else {
            throw XCTSkip("Set NEGAFLOW_REAL_PIXEL_ROLL_STRESS=1 to run the real 24MP/48MP/3600DPI/7200DPI pixel roll stress.")
        }

        let mode = ProcessInfo.processInfo.environment["NEGAFLOW_REAL_PIXEL_ROLL_MODE"] ?? "develop"
        let fastPreviewMode = mode == "fast-preview"
        let startedAt = Date()
        let startUsage = Self.currentResourceUsage()
        let preflightCleanupStartedAt = Date()
        let preflightRemovedTempFiles = Self.removeRealPixelTempFiles()
        let preflightCleanupSeconds = Date().timeIntervalSince(preflightCleanupStartedAt)
        let fixtureStartedAt = Date()
        let fixtures = try Self.makeFixtures()
        let fixtureCreationSeconds = Date().timeIntervalSince(fixtureStartedAt)
        defer { fixtures.forEach { try? FileManager.default.removeItem(at: $0.url) } }

        let setupStartedAt = Date()
        let model = AppModel()
        let frames = (1...48).map { index in
            let fixture = fixtures[(index - 1) % fixtures.count]
            return Self.makeFrame(index: index, fixture: fixture)
        }
        let selected = frames[23]
        model.frames = frames
        model.selectedFrameID = selected.id
        let modelSetupSeconds = Date().timeIntervalSince(setupStartedAt)

        var outputLongEdges: [Int] = []
        var readableOutputs = 0
        let processingStartedAt = Date()
        for (offset, frame) in frames.enumerated() {
            let index = offset + 1
            let fixture = fixtures[offset % fixtures.count]
            let transform = FrameCacheManagerTestsSupport.makeTransform(index: index)
            frame.imageTransform = transform
            frame.updateParams {
                $0.exposure = Double(index % 5) * 0.05
                $0.contrast = Double(index % 4) * 0.04
                $0.scannerProfileID = "real-pixel-profile-\(index)"
                $0.defectRemoval = index.isMultiple(of: 3) ? 0.35 : 0.0
                $0.imageTransform = transform
            }
            frame.defectEdits = [FrameCacheManagerTestsSupport.makeDefectEdit(index: index)]

            if fastPreviewMode {
                let result = try DevelopFrameRenderer.renderFastPreview(Self.snapshot(
                    for: frame,
                    proxyMaxDimension: DevelopFrameRenderer.fastPreviewMaxDimension
                ))
                if let thumbnail = result.thumbnail {
                    frame.thumbnailImage = NSImage(
                        cgImage: thumbnail,
                        size: NSSize(width: thumbnail.width, height: thumbnail.height)
                    )
                }
                outputLongEdges.append(max(result.preview.width, result.preview.height))
                if fixture.isReadable && result.preview.width > 0 && result.preview.height > 0 {
                    readableOutputs += 1
                }
            } else {
                let result = try DevelopFrameRenderer.render(Self.snapshot(for: frame))
                let developed = NSImage(
                    cgImage: result.developed,
                    size: NSSize(width: result.developed.width, height: result.developed.height)
                )
                frame.developedImage = developed
                frame.thumbnailImage = result.thumbnail.map {
                    NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
                }
                frame.cachedDevelopedBase = result.developedBase
                if let rawBase = result.rawBase { frame.cachedRawBase = rawBase }
                frame.hasDevelopedOnce = true
                model.markDevelopedResident(frame)

                outputLongEdges.append(max(result.developed.width, result.developed.height))
                if fixture.isReadable && result.developed.width > 0 && result.developed.height > 0 {
                    readableOutputs += 1
                }
            }
        }

        let processingSeconds = Date().timeIntervalSince(processingStartedAt)
        let developedResidents = Set(model.residentDevelopedIDs)
        let elapsedSeconds = Date().timeIntervalSince(startedAt)
        let cleanupStartedAt = Date()
        let removedTempFilesAfterRun = Self.removeRealPixelTempFiles()
        let temporaryFilesCleanedUp = Self.realPixelTempFileURLs().isEmpty
        let cleanupSeconds = Date().timeIntervalSince(cleanupStartedAt)
        let endUsage = Self.currentResourceUsage()
        let workloadCounts = Dictionary(grouping: frames, by: { $0.sourceFrameDisplayName ?? "unknown" })
            .mapValues(\.count)
        let stateRoundtripsExactly = frames.enumerated().allSatisfy { offset, frame in
            let index = offset + 1
            return frame.params.scannerProfileID == "real-pixel-profile-\(index)"
                && frame.defectEdits.first?.title == "dust layer \(index)"
                && frame.imageTransform == FrameCacheManagerTestsSupport.makeTransform(index: index)
                && (fastPreviewMode ? !frame.hasDevelopedOnce : frame.hasDevelopedOnce)
        }
        let selectedFramePreserved = fastPreviewMode
            ? frames.contains { $0.id == selected.id }
            : developedResidents.contains(selected.id)

        XCTAssertEqual(frames.count, 48)
        XCTAssertEqual(workloadCounts["digital 24MP"], 12)
        XCTAssertEqual(workloadCounts["digital 48MP"], 12)
        XCTAssertEqual(workloadCounts["scanner 3600DPI"], 12)
        XCTAssertEqual(workloadCounts["scanner 7200DPI"], 12)
        XCTAssertLessThanOrEqual(model.residentDevelopedIDs.count, model.maxResidentDeveloped)
        XCTAssertTrue(selectedFramePreserved)
        XCTAssertEqual(readableOutputs, 48)
        XCTAssertTrue(stateRoundtripsExactly)
        XCTAssertTrue(outputLongEdges.allSatisfy { $0 <= Int(
            fastPreviewMode ? DevelopFrameRenderer.fastPreviewMaxDimension : DevelopFrameRenderer.interactiveMaxDimension
        ) })

        try Self.writeJSONReportIfRequested(
            RealPixelRollStressReport(
                mode: mode,
                framesProcessed: frames.count,
                workloadCounts: workloadCounts,
                fixturePixelCounts: Dictionary(uniqueKeysWithValues: fixtures.map { ($0.label, $0.width * $0.height) }),
                actualPixelFiles: true,
                fixtureFilesReadable: fixtures.allSatisfy(\.isReadable),
                outputsReadable: readableOutputs == frames.count,
                outputLongEdgeMax: outputLongEdges.max() ?? 0,
                proxyLongEdgeLimit: Int(fastPreviewMode
                    ? DevelopFrameRenderer.fastPreviewMaxDimension
                    : DevelopFrameRenderer.interactiveMaxDimension),
                developedResidentCount: model.residentDevelopedIDs.count,
                developedResidentLimit: model.maxResidentDeveloped,
                cleanedRawResidentCount: model.residentCleanedRawIDs.count,
                cleanedRawResidentLimit: model.maxResidentCleanedRaw,
                selectedFramePreserved: selectedFramePreserved,
                stateRoundtripsExactly: stateRoundtripsExactly,
                stateBleedDetected: !stateRoundtripsExactly,
                elapsedSeconds: elapsedSeconds,
                averageSecondsPerFrame: elapsedSeconds / Double(frames.count),
                phaseTimings: RealPixelRollPhaseTimings(
                    preflightCleanupSeconds: preflightCleanupSeconds,
                    fixtureCreationSeconds: fixtureCreationSeconds,
                    modelSetupSeconds: modelSetupSeconds,
                    previewProcessingSeconds: fastPreviewMode ? processingSeconds : 0,
                    developProcessingSeconds: fastPreviewMode ? 0 : processingSeconds,
                    fixtureCleanupSeconds: cleanupSeconds
                ),
                startMaxRSSBytes: startUsage.maxRSSBytes,
                endMaxRSSBytes: endUsage.maxRSSBytes,
                cpuUserSeconds: max(0, endUsage.userSeconds - startUsage.userSeconds),
                cpuSystemSeconds: max(0, endUsage.systemSeconds - startUsage.systemSeconds),
                gpuMetricsStatus: "not-captured",
                gpuMetricsUnavailableReason: "XCTest does not expose per-test GPU counters",
                preflightRemovedTempFiles: preflightRemovedTempFiles,
                removedTempFilesAfterRun: removedTempFilesAfterRun,
                temporaryFilesCleanedUp: temporaryFilesCleanedUp
            )
        )
    }

    private static func snapshot(
        for frame: ScanFrame,
        proxyMaxDimension: CGFloat = DevelopFrameRenderer.interactiveMaxDimension
    ) -> DevelopFrameSnapshot {
        let baseKey = FilmBaseCacheKey(
            filmType: frame.filmType,
            mode: frame.params.baseEstimationMode,
            manualBaseRGB: frame.params.manualBaseRGB,
            filmStockDminID: frame.params.filmStockDminID,
            lightSourceProfileID: frame.params.lightSourceProfileID
        )
        return DevelopFrameSnapshot(
            rawScanURL: frame.rawScanURL,
            sourceKind: frame.sourceKind,
            preloadedRaw: nil,
            cleanedRawURL: nil,
            filmType: frame.filmType,
            params: frame.params,
            preset: nil,
            imageTransform: frame.imageTransform,
            cachedBase: nil,
            baseKey: baseKey,
            needsRawPreview: false,
            needsNeutralPreview: false,
            needsDebugPreviews: false,
            proxyMaxDimension: proxyMaxDimension,
            needsThumbnail: true
        )
    }

    private static func makeFrame(index: Int, fixture: RealPixelFixture) -> ScanFrame {
        ScanFrame(
            scanIndex: index,
            rawScanURL: fixture.url,
            filmType: .colorNegative,
            sourceKind: fixture.sourceKind,
            sourcePixelWidth: fixture.width,
            sourcePixelHeight: fixture.height,
            sourceResolutionDPI: fixture.dpi,
            sourceBitDepth: fixture.bitDepth,
            sourceFrameDisplayName: fixture.label
        )
    }

    private static func makeFixtures() throws -> [RealPixelFixture] {
        [
            try makeFixture(label: "digital 24MP", width: 6_000, height: 4_000, dpi: nil, sourceKind: .importedFile),
            try makeFixture(label: "digital 48MP", width: 8_000, height: 6_000, dpi: nil, sourceKind: .importedFile),
            try makeFixture(label: "scanner 3600DPI", width: 5_100, height: 3_400, dpi: 3_600, sourceKind: .scannerTIFF),
            try makeFixture(label: "scanner 7200DPI", width: 10_200, height: 6_800, dpi: 7_200, sourceKind: .scannerTIFF),
        ]
    }

    private static func makeFixture(
        label: String,
        width: Int,
        height: Int,
        dpi: Int?,
        sourceKind: FrameSource
    ) throws -> RealPixelFixture {
        let url = try autoreleasepool {
            try makeRGBTIFF(width: width, height: height, dpi: dpi)
        }
        return RealPixelFixture(
            label: label,
            url: url,
            sourceKind: sourceKind,
            width: width,
            height: height,
            dpi: dpi,
            bitDepth: 8,
            isReadable: Self.imageSourceMatches(url: url, width: width, height: height)
        )
    }

    private static func makeRGBTIFF(width: Int, height: Int, dpi: Int?) throws -> URL {
        let bytesPerPixel = 3
        let byteCount = width * height * bytesPerPixel
        let data = Data(count: byteCount)
        let provider = CGDataProvider(data: data as CFData)!
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 24,
            bytesPerRow: width * bytesPerPixel,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw CocoaError(.coderInvalidValue)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-real-pixel-roll-\(UUID().uuidString).tiff")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var tiff: [CFString: Any] = [kCGImagePropertyTIFFCompression: 5]
        if let dpi {
            tiff[kCGImagePropertyTIFFXResolution] = dpi
            tiff[kCGImagePropertyTIFFYResolution] = dpi
        }
        var properties: [CFString: Any] = [kCGImagePropertyTIFFDictionary: tiff]
        if let dpi {
            properties[kCGImagePropertyDPIWidth] = dpi
            properties[kCGImagePropertyDPIHeight] = dpi
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    private static func imageSourceMatches(url: URL, width: Int, height: Int) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return false
        }
        return pixelWidth.intValue == width && pixelHeight.intValue == height
    }

    private static func currentResourceUsage() -> ResourceUsage {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return ResourceUsage(
            maxRSSBytes: Int64(usage.ru_maxrss),
            userSeconds: seconds(usage.ru_utime),
            systemSeconds: seconds(usage.ru_stime)
        )
    }

    private static func seconds(_ value: timeval) -> TimeInterval {
        TimeInterval(value.tv_sec) + TimeInterval(value.tv_usec) / 1_000_000
    }

    private static func realPixelTempFileURLs() -> [URL] {
        let directory = FileManager.default.temporaryDirectory
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls.filter {
            $0.lastPathComponent.hasPrefix("negaflow-real-pixel-roll-")
                && $0.pathExtension.lowercased() == "tiff"
        }
    }

    private static func removeRealPixelTempFiles() -> Int {
        var removed = 0
        for url in realPixelTempFileURLs() {
            do {
                try FileManager.default.removeItem(at: url)
                removed += 1
            } catch {
                continue
            }
        }
        return removed
    }

    private static func writeJSONReportIfRequested(_ report: RealPixelRollStressReport) throws {
        guard let path = ProcessInfo.processInfo.environment["NEGAFLOW_REAL_PIXEL_ROLL_REPORT"], !path.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url)
    }

    private struct ResourceUsage {
        let maxRSSBytes: Int64
        let userSeconds: TimeInterval
        let systemSeconds: TimeInterval
    }

    private struct RealPixelRollPhaseTimings: Encodable {
        let preflightCleanupSeconds: TimeInterval
        let fixtureCreationSeconds: TimeInterval
        let modelSetupSeconds: TimeInterval
        let previewProcessingSeconds: TimeInterval
        let developProcessingSeconds: TimeInterval
        let fixtureCleanupSeconds: TimeInterval
    }

    private struct RealPixelFixture {
        let label: String
        let url: URL
        let sourceKind: FrameSource
        let width: Int
        let height: Int
        let dpi: Int?
        let bitDepth: Int
        let isReadable: Bool
    }

    private struct RealPixelRollStressReport: Encodable {
        let mode: String
        let framesProcessed: Int
        let workloadCounts: [String: Int]
        let fixturePixelCounts: [String: Int]
        let actualPixelFiles: Bool
        let fixtureFilesReadable: Bool
        let outputsReadable: Bool
        let outputLongEdgeMax: Int
        let proxyLongEdgeLimit: Int
        let developedResidentCount: Int
        let developedResidentLimit: Int
        let cleanedRawResidentCount: Int
        let cleanedRawResidentLimit: Int
        let selectedFramePreserved: Bool
        let stateRoundtripsExactly: Bool
        let stateBleedDetected: Bool
        let elapsedSeconds: TimeInterval
        let averageSecondsPerFrame: TimeInterval
        let phaseTimings: RealPixelRollPhaseTimings
        let startMaxRSSBytes: Int64
        let endMaxRSSBytes: Int64
        let cpuUserSeconds: TimeInterval
        let cpuSystemSeconds: TimeInterval
        let gpuMetricsStatus: String
        let gpuMetricsUnavailableReason: String
        let preflightRemovedTempFiles: Int
        let removedTempFilesAfterRun: Int
        let temporaryFilesCleanedUp: Bool
    }
}

private enum FrameCacheManagerTestsSupport {
    static func makeTransform(index: Int) -> ImageTransform {
        let rotations: [ImageRotation] = [.deg0, .deg90, .deg180, .deg270]
        return ImageTransform(
            rotation: rotations[index % rotations.count],
            flipHorizontal: index.isMultiple(of: 2),
            flipVertical: index.isMultiple(of: 3),
            cropRect: SIMD4<Double>(0.01, 0.02, 0.90, 0.86),
            straightenAngle: Double(index % 9) - 4.0,
            cropAspect: index.isMultiple(of: 4) ? 1.5 : nil
        )
    }

    static func makeDefectEdit(index: Int) -> DefectEditItem {
        DefectEditItem(
            edit: .region(mask: .raw(Data([255, 255, 255, 255])), roi: CGRect(x: 0, y: 0, width: 1, height: 1), width: 1, height: 1),
            strength: index.isMultiple(of: 2) ? 0.75 : 1.0,
            title: "dust layer \(index)",
            summary: "dust 1",
            preview: [],
            baseSize: CGSize(width: 1, height: 1)
        )
    }
}
