import AppKit
import Chromabase
import CoreGraphics
import Darwin
import XCTest
@testable import negaflowApp

@MainActor
final class FrameCacheManagerTests: XCTestCase {
    func testCleanedRawFIFOEvictsOldestLoadedFrame() {
        let manager = FrameCacheManager(maxResidentCleanedRaw: 2)
        let first = Self.makeFrame(index: 1)
        let second = Self.makeFrame(index: 2)
        let third = Self.makeFrame(index: 3)
        first.cleanedRawImage = Self.makeOnePixelImage()
        second.cleanedRawImage = Self.makeOnePixelImage()
        third.cleanedRawImage = Self.makeOnePixelImage()
        let frames = [first, second, third]

        manager.markCleanedRawResident(first, frames: frames) { $0.cleanedRawImage = nil }
        manager.markCleanedRawResident(second, frames: frames) { $0.cleanedRawImage = nil }
        manager.markCleanedRawResident(third, frames: frames) { $0.cleanedRawImage = nil }

        XCTAssertEqual(manager.residentCleanedRawIDs, [second.id, third.id])
        XCTAssertNil(first.cleanedRawImage)
        XCTAssertNotNil(second.cleanedRawImage)
        XCTAssertNotNil(third.cleanedRawImage)
    }

    func testDevelopedFIFOEvictsOldestNonSelectedFrame() {
        let manager = FrameCacheManager(maxResidentDeveloped: 2)
        let first = Self.makeFrame(index: 1)
        let second = Self.makeFrame(index: 2)
        let third = Self.makeFrame(index: 3)
        let frames = [first, second, third]
        var evictedIDs: [UUID] = []

        manager.markDevelopedResident(first, selectedFrameID: first.id, frames: frames) { evictedIDs.append($0.id) }
        manager.markDevelopedResident(second, selectedFrameID: first.id, frames: frames) { evictedIDs.append($0.id) }
        manager.markDevelopedResident(third, selectedFrameID: first.id, frames: frames) { evictedIDs.append($0.id) }

        XCTAssertEqual(manager.residentDevelopedIDs, [third.id, first.id])
        XCTAssertEqual(evictedIDs, [second.id])
    }

    func testRemoveResidentsDropsFrameIDs() {
        let manager = FrameCacheManager(maxResidentCleanedRaw: 2, maxResidentDeveloped: 2)
        let frame = Self.makeFrame(index: 1)

        manager.markCleanedRawResident(frame, frames: [frame]) { _ in }
        manager.markDevelopedResident(frame, selectedFrameID: frame.id, frames: [frame]) { _ in }
        manager.removeCleanedRawResident(frame)
        manager.removeDevelopedResident(frame)

        XCTAssertTrue(manager.residentCleanedRawIDs.isEmpty)
        XCTAssertTrue(manager.residentDevelopedIDs.isEmpty)
    }

    func testFortyEightFrameRollEvictsOnlyHeavyBuffersAndPreservesPerFrameState() throws {
        let startedAt = Date()
        let startMaxRSSBytes = Self.currentMaxRSSBytes()
        let model = AppModel()
        let frames = (1...48).map { Self.makeFrame(index: $0, workload: Self.workload(for: $0)) }
        let selected = frames[23]
        model.frames = frames
        model.selectedFrameID = selected.id

        for (offset, frame) in frames.enumerated() {
            let index = offset + 1
            let image = Self.makeOnePixelImage()
            let nsImage = Self.makeOnePixelNSImage(image)
            let transform = Self.makeTransform(index: index)

            frame.updateParams {
                $0.exposure = Double(index) / 24.0
                $0.contrast = Double(index % 7) / 10.0
                $0.warmth = Double(index % 5) / 10.0
                $0.tint = -Double(index % 3) / 10.0
                $0.scannerProfileID = "roll-profile-\(index)"
                $0.defectRemoval = index.isMultiple(of: 2) ? 0.45 : 0.2
                $0.noiseReduction = index.isMultiple(of: 3) ? 0.35 : 0.1
                $0.imageTransform = transform
            }
            frame.imageTransform = transform
            frame.setRating(index % 6)
            frame.pickState = index.isMultiple(of: 5) ? .rejected : (index.isMultiple(of: 2) ? .picked : .unflagged)
            frame.defectEdits = [Self.makeDefectEdit(index: index)]
            frame.hasDevelopedOnce = true
            frame.thumbnailImage = nsImage
            frame.developedImage = nsImage
            frame.rawPreviewImage = nsImage
            frame.neutralPreviewImage = nsImage
            frame.mainPreviewImage = nsImage
            frame.rawPreviewTransform = transform
            frame.neutralPreviewTransform = transform
            frame.mainPreviewTransform = transform
            frame.cachedDevelopedBase = image
            frame.cachedRawBase = image
            frame.cachedNeutralBase = image
            frame.cachedMainBase = image
            frame.cachedInteractivePreviewRaw = DevelopFramePreviewRaw(image: image, usesLinearSRGB: false)
            frame.cachedInteractivePreviewRawRevision = frame.cleanRawRevision
            frame.cachedInteractivePreviewRawDimension = 1600
            frame.cachedSettledPreviewRaw = DevelopFramePreviewRaw(image: image, usesLinearSRGB: false)
            frame.cachedSettledPreviewRawRevision = frame.cleanRawRevision
            frame.debugPreviewImages = [.afterInversion: nsImage]
            frame.cleanedRawImage = image
            frame.cleanedRawPreviousImage = image
            frame.cleanedRawPreviousEditCount = index - 1
            frame.cleanedRawEditCount = index

            model.cleanedRawResidentInsert(frame)
            model.markDevelopedResident(frame)
        }

        let developedResidents = Set(model.residentDevelopedIDs)
        let cleanedResidents = Set(model.residentCleanedRawIDs)
        XCTAssertLessThanOrEqual(model.residentDevelopedIDs.count, model.maxResidentDeveloped)
        XCTAssertTrue(developedResidents.contains(selected.id))
        XCTAssertLessThanOrEqual(model.residentCleanedRawIDs.count, model.maxResidentCleanedRaw)

        for (offset, frame) in frames.enumerated() {
            let index = offset + 1
            let workload = Self.workload(for: index)
            let transform = Self.makeTransform(index: index)

            XCTAssertEqual(frame.sourcePixelWidth, workload.width)
            XCTAssertEqual(frame.sourcePixelHeight, workload.height)
            XCTAssertEqual(frame.sourceResolutionDPI, workload.dpi)
            XCTAssertEqual(frame.sourceBitDepth, 16)
            XCTAssertEqual(frame.sourceFrameDisplayName, workload.label)
            XCTAssertEqual(frame.params.exposure, Double(index) / 24.0, accuracy: 0.0001)
            XCTAssertEqual(frame.params.scannerProfileID, "roll-profile-\(index)")
            XCTAssertEqual(frame.params.imageTransform, transform)
            XCTAssertEqual(frame.imageTransform, transform)
            XCTAssertEqual(frame.rating, index % 6)
            XCTAssertEqual(frame.defectEdits.count, 1)
            XCTAssertEqual(frame.defectEdits[0].title, "dust layer \(index)")
            XCTAssertNotNil(frame.thumbnailImage)
            XCTAssertTrue(frame.hasDevelopedOnce)

            if developedResidents.contains(frame.id) {
                XCTAssertNotNil(frame.developedImage)
            } else {
                XCTAssertNil(frame.developedImage)
                XCTAssertNil(frame.rawPreviewImage)
                XCTAssertNil(frame.neutralPreviewImage)
                XCTAssertNil(frame.mainPreviewImage)
                XCTAssertNil(frame.cachedDevelopedBase)
                XCTAssertNil(frame.cachedRawBase)
                XCTAssertNil(frame.cachedNeutralBase)
                XCTAssertNil(frame.cachedMainBase)
                XCTAssertNil(frame.cachedInteractivePreviewRaw)
                XCTAssertNil(frame.cachedSettledPreviewRaw)
                XCTAssertTrue(frame.debugPreviewImages.isEmpty)
            }

            // 디스크 캐시가 없으므로 축출된 cleaned raw 는 RAM 에서 내려간다. 단위 테스트는
            // libraryPersistenceEnabled=false 라 굽지 않으므로 defectEdits 는 그대로 유지된다.
            if cleanedResidents.contains(frame.id) {
                XCTAssertNotNil(frame.cleanedRawImage)
            } else {
                XCTAssertNil(frame.cleanedRawImage)
                XCTAssertNil(frame.cleanedRawPreviousImage)
                XCTAssertEqual(frame.cleanedRawPreviousEditCount, -1)
            }
        }

        let elapsedSeconds = Date().timeIntervalSince(startedAt)
        let endMaxRSSBytes = Self.currentMaxRSSBytes()
        let workloadCounts = Dictionary(grouping: frames, by: { $0.sourceFrameDisplayName ?? "unknown" })
            .mapValues(\.count)
        let developedEvictedCount = frames.filter { !developedResidents.contains($0.id) }.count
        let cleanedRawEvictedCount = frames.filter { !cleanedResidents.contains($0.id) }.count
        let stateRoundtripsExactly = frames.enumerated().allSatisfy { offset, frame in
            let index = offset + 1
            return frame.params.scannerProfileID == "roll-profile-\(index)"
                && frame.params.imageTransform == Self.makeTransform(index: index)
                && frame.imageTransform == Self.makeTransform(index: index)
                && frame.defectEdits.first?.title == "dust layer \(index)"
                && frame.rating == index % 6
                && frame.thumbnailImage != nil
                && frame.hasDevelopedOnce
        }
        let stateBleedDetected = Set(frames.compactMap(\.params.scannerProfileID)).count != frames.count
            || Set(frames.compactMap { $0.defectEdits.first?.title }).count != frames.count

        try Self.writeJSONReportIfRequested(
            RollStressReport(
                framesProcessed: frames.count,
                workloadCounts: workloadCounts,
                developedResidentCount: model.residentDevelopedIDs.count,
                developedResidentLimit: model.maxResidentDeveloped,
                cleanedRawResidentCount: model.residentCleanedRawIDs.count,
                cleanedRawResidentLimit: model.maxResidentCleanedRaw,
                selectedFramePreserved: developedResidents.contains(selected.id),
                developedEvictedCount: developedEvictedCount,
                cleanedRawEvictedCount: cleanedRawEvictedCount,
                outputsReadable: frames.allSatisfy { $0.thumbnailImage != nil && $0.hasDevelopedOnce },
                elapsedSeconds: elapsedSeconds,
                startMaxRSSBytes: startMaxRSSBytes,
                endMaxRSSBytes: endMaxRSSBytes
            ),
            environmentKey: "NEGAFLOW_ROLL_STRESS_REPORT"
        )
        try Self.writeJSONReportIfRequested(
            FrameStateFIFOReport(
                framesProcessed: frames.count,
                distinctScannerProfileIDs: Set(frames.compactMap(\.params.scannerProfileID)).count,
                distinctDefectLayers: Set(frames.compactMap { $0.defectEdits.first?.title }).count,
                stateRoundtripsExactly: stateRoundtripsExactly,
                stateBleedDetected: stateBleedDetected,
                nonResidentDevelopedBuffersEvicted: developedEvictedCount,
                nonResidentCleanedRawBuffersEvicted: cleanedRawEvictedCount,
                elapsedSeconds: elapsedSeconds,
                endMaxRSSBytes: endMaxRSSBytes
            ),
            environmentKey: "NEGAFLOW_FRAME_STATE_REPORT"
        )
    }

    private static func makeFrame(index: Int, workload: FrameWorkload? = nil) -> ScanFrame {
        ScanFrame(
            scanIndex: index,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-cache-test-\(UUID().uuidString).tiff"),
            filmType: .colorNegative,
            sourceKind: workload?.sourceKind ?? .scannerTIFF,
            sourcePixelWidth: workload?.width,
            sourcePixelHeight: workload?.height,
            sourceResolutionDPI: workload?.dpi,
            sourceBitDepth: 16,
            sourceFrameDisplayName: workload?.label
        )
    }

    private static func makeOnePixelImage() -> CGImage {
        let bytes: [UInt8] = [0, 0, 0, 255]
        let data = Data(bytes) as CFData
        let provider = CGDataProvider(data: data)!
        return CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private static func makeOnePixelNSImage(_ image: CGImage) -> NSImage {
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private static func makeTransform(index: Int) -> ImageTransform {
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

    private static func makeDefectEdit(index: Int) -> DefectEditItem {
        DefectEditItem(
            edit: .region(mask: .raw(Data([255, 255, 255, 255])), roi: CGRect(x: 0, y: 0, width: 1, height: 1), width: 1, height: 1),
            strength: index.isMultiple(of: 2) ? 0.75 : 1.0,
            title: "dust layer \(index)",
            summary: "dust 1",
            preview: [],
            baseSize: CGSize(width: 1, height: 1)
        )
    }

    private static func workload(for index: Int) -> FrameWorkload {
        switch index % 4 {
        case 0:
            return FrameWorkload(sourceKind: .importedFile, width: 6000, height: 4000, dpi: nil, label: "digital 24MP")
        case 1:
            return FrameWorkload(sourceKind: .importedFile, width: 8000, height: 6000, dpi: nil, label: "digital 48MP")
        case 2:
            return FrameWorkload(sourceKind: .scannerTIFF, width: 5100, height: 3400, dpi: 3600, label: "scanner 3600DPI")
        default:
            return FrameWorkload(sourceKind: .scannerTIFF, width: 10200, height: 6800, dpi: 7200, label: "scanner 7200DPI")
        }
    }

    private struct FrameWorkload {
        let sourceKind: FrameSource
        let width: Int
        let height: Int
        let dpi: Int?
        let label: String
    }

    private static func currentMaxRSSBytes() -> Int64 {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Int64(usage.ru_maxrss)
    }

    private static func writeJSONReportIfRequested<T: Encodable>(
        _ report: T,
        environmentKey: String
    ) throws {
        guard let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else {
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

    private struct RollStressReport: Encodable {
        let framesProcessed: Int
        let workloadCounts: [String: Int]
        let developedResidentCount: Int
        let developedResidentLimit: Int
        let cleanedRawResidentCount: Int
        let cleanedRawResidentLimit: Int
        let selectedFramePreserved: Bool
        let developedEvictedCount: Int
        let cleanedRawEvictedCount: Int
        let outputsReadable: Bool
        let elapsedSeconds: TimeInterval
        let startMaxRSSBytes: Int64
        let endMaxRSSBytes: Int64
    }

    private struct FrameStateFIFOReport: Encodable {
        let framesProcessed: Int
        let distinctScannerProfileIDs: Int
        let distinctDefectLayers: Int
        let stateRoundtripsExactly: Bool
        let stateBleedDetected: Bool
        let nonResidentDevelopedBuffersEvicted: Int
        let nonResidentCleanedRawBuffersEvicted: Int
        let elapsedSeconds: TimeInterval
        let endMaxRSSBytes: Int64
    }
}
