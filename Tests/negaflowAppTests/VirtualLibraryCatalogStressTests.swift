import AppKit
import Chromabase
import CoreGraphics
import Darwin
import ImageIO
import XCTest
@testable import negaflowApp

@MainActor
final class VirtualLibraryCatalogStressTests: XCTestCase {
    func testTwoThousandFrameVirtualLibraryWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["NEGAFLOW_VIRTUAL_LIBRARY_STRESS"] == "1" else {
            throw XCTSkip(
                "Set NEGAFLOW_VIRTUAL_LIBRARY_STRESS=1 to run the 2,000-frame virtual library stress."
            )
        }

        let keepArtifacts =
            ProcessInfo.processInfo.environment["NEGAFLOW_VIRTUAL_LIBRARY_STRESS_KEEP"] == "1"
        let root = try Self.stressRoot()
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            if !keepArtifacts {
                try? FileManager.default.removeItem(at: root)
            }
        }

        let startedAt = Date()
        let startUsage = Self.currentResourceUsage()
        let fixtureStartedAt = Date()
        let fixtureResult = try await Self.preparePixelFilesOffMainActor(in: root)
        let fixtureSeconds = Date().timeIntervalSince(fixtureStartedAt)

        let configuration = AppLaunchConfiguration(
            uiTestRoot: root,
            importsSyntheticNegative: false,
            enablesDemoScanner: false,
            preparesCorruptCatalog: false,
            createsDropTargetFolder: false,
            developsImportsAutomatically: false
        )
        let model = AppModelFactory.make(configuration: configuration)
        model.transitionLibraryLifecycle(to: .ready)
        model.libraryPersistenceEnabled = true

        let heartbeat = MainActorHeartbeat()
        heartbeat.start()
        try await Task.sleep(for: .milliseconds(60))

        let importStartedAt = Date()
        await model.importFolders(urls: fixtureResult.folders).value
        let importSeconds = Date().timeIntervalSince(importStartedAt)
        let importMaxMainActorGapSeconds = await heartbeat.captureMaximumGap()

        XCTAssertEqual(model.frames.count, Self.totalFrameCount)
        XCTAssertEqual(model.libraryFolders.count, Self.totalFolderCount)
        XCTAssertEqual(Set(model.frames.map { $0.rawScanURL.standardizedFileURL.path }).count, Self.totalFrameCount)
        XCTAssertTrue(model.frames.allSatisfy { FileManager.default.fileExists(atPath: $0.rawScanURL.path) })

        let seedStartedAt = Date()
        let seedTasks = model.frames.compactMap(\.initialThumbnailSeedTask)
        for task in seedTasks {
            await task.value
        }
        let seedSeconds = Date().timeIntervalSince(seedStartedAt)
        let seedMaxMainActorGapSeconds = await heartbeat.captureMaximumGap()
        XCTAssertEqual(seedTasks.count, Self.totalFrameCount)
        XCTAssertTrue(model.frames.allSatisfy { $0.rawPreviewImage != nil })
        XCTAssertTrue(model.frames.allSatisfy {
            guard let image = $0.rawPreviewImage else { return false }
            return max(image.size.width, image.size.height)
                <= DevelopFrameRenderer.thumbnailMaxDimension
        })

        let workloadCounts = Dictionary(
            grouping: model.frames,
            by: { Self.workloadLabel(for: $0.rawScanURL) }
        ).mapValues(\.count)
        for workload in Self.workloads {
            XCTAssertEqual(workloadCounts[workload.label], Self.framesPerWorkload)
            let frames = model.frames.filter {
                Self.workloadLabel(for: $0.rawScanURL) == workload.label
            }
            XCTAssertTrue(frames.allSatisfy {
                $0.sourcePixelWidth == workload.width
                    && $0.sourcePixelHeight == workload.height
                    && $0.sourceResolutionDPI == workload.dpi
            })
        }

        let folderGroups = Dictionary(
            grouping: model.frames,
            by: { $0.rawScanURL.deletingLastPathComponent().standardizedFileURL.path }
        )
        XCTAssertEqual(folderGroups.count, Self.totalFolderCount)
        XCTAssertTrue(folderGroups.values.allSatisfy { $0.count == Self.framesPerFolder })

        for frames in folderGroups.values {
            let preserved = try XCTUnwrap(frames.first)
            preserved.hasDevelopedOnce = true
            preserved.showDeveloped = false
            preserved.updateParams {
                $0.exposure = 0.73
                $0.contrast = -0.21
                $0.developTarget = .rescue
            }
        }

        let folderApplyStartedAt = Date()
        for (index, path) in folderGroups.keys.sorted().enumerated() {
            let frames = folderGroups[path] ?? []
            let combination = Self.randomCombination(index: index)
            _ = model.configureLibraryFolderDevelopment(
                process: combination.process,
                target: combination.target,
                frames: frames
            )
        }
        let folderApplySeconds = Date().timeIntervalSince(folderApplyStartedAt)
        let folderApplyMaxMainActorGapSeconds = await heartbeat.captureMaximumGap()
        XCTAssertEqual(
            model.frames.filter(\.showDeveloped).count,
            Self.totalFrameCount
        )

        let rollStartedAt = Date()
        for path in folderGroups.keys.sorted() {
            let frames = folderGroups[path] ?? []
            let name = URL(fileURLWithPath: path).lastPathComponent
            let roll = try XCTUnwrap(
                model.createPhysicalRoll(name: name, filmType: frames.first?.filmType ?? .colorNegative)
            )
            for frame in frames {
                XCTAssertTrue(model.moveOriginalFrameFamily(containing: frame, toRollID: roll.id))
            }
        }
        let rollSeconds = Date().timeIntervalSince(rollStartedAt)
        let rollMaxMainActorGapSeconds = await heartbeat.captureMaximumGap()
        let physicalRolls = model.rolls.filter { $0.kind == .physical }
        XCTAssertEqual(physicalRolls.count, Self.totalFolderCount)
        XCTAssertTrue(physicalRolls.allSatisfy { $0.frameIDs.count == Self.framesPerFolder })

        let settingsStartedAt = Date()
        var randomFrameIndex = 0
        for (index, roll) in physicalRolls.enumerated() {
            let combination = Self.randomCombination(index: index + Self.totalFolderCount)
            let transform = Self.transform(index: index)
            var params = DevelopParameters()
            params.filmType = combination.process.filmType
            params.isDigitalSource = combination.process.isDigitalSource ? true : nil
            params.developTarget = combination.target
            params.exposure = Double(index % 7) * 0.04
            params.contrast = Double(index % 5) * 0.03
            params.imageTransform = transform
            model.copiedDevelopSettings = DevelopSettingsSnapshot(
                sourceFrameName: "stress-roll-\(index)",
                params: params,
                preset: nil,
                imageTransform: transform
            )
            model.interactionScopeFrameIDs = roll.frameIDs
            model.frameStore.selectedFrameID = roll.frameIDs.first
            model.selectedFrameIDs = Set(roll.frameIDs)
            let first = try XCTUnwrap(
                roll.frameIDs.first.flatMap { id in model.frames.first(where: { $0.id == id }) }
            )
            model.pasteDevelopSettings(to: first)

            // 롤 단위 붙여넣기 경로로 40장씩 하나의 bounded 작업을 예약한 뒤, 작업이
            // MainActor에서 시작되기 전에 각 파일의 프로세스·타깃·편집을 독립 난수로 바꾼다.
            // 따라서 롤/다중 선택 붙여넣기와 2,000장 개별 혼합 현상을 같은 실행에서 검증한다.
            for frameID in roll.frameIDs {
                let frame = try XCTUnwrap(model.frames.first(where: { $0.id == frameID }))
                let randomCombination = Self.randomCombination(
                    index: 10_000 + randomFrameIndex
                )
                let randomTransform = Self.transform(index: randomFrameIndex)
                var randomParams = DevelopParameters()
                randomParams.filmType = randomCombination.process.filmType
                randomParams.isDigitalSource =
                    randomCombination.process.isDigitalSource ? true : nil
                randomParams.developTarget = randomCombination.target
                randomParams.exposure = Double(randomFrameIndex % 7) * 0.04
                randomParams.contrast = Double(randomFrameIndex % 5) * 0.03
                randomParams.imageTransform = randomTransform
                frame.applyDevelopSettingsSnapshot(
                    DevelopSettingsSnapshot(
                        sourceFrameName: "stress-frame-\(randomFrameIndex)",
                        params: randomParams,
                        preset: nil,
                        imageTransform: randomTransform
                    )
                )
                randomFrameIndex += 1
            }
        }
        model.interactionScopeFrameIDs = nil
        model.selectedFrameIDs = []
        model.frameStore.selectedFrameID = nil
        let settingsSeconds = Date().timeIntervalSince(settingsStartedAt)
        let settingsMaxMainActorGapSeconds = await heartbeat.captureMaximumGap()

        XCTAssertTrue(model.frames.allSatisfy {
            $0.params.filmType == $0.filmType
                && $0.params.imageTransform == $0.imageTransform
        })
        let appliedProcesses = Set(model.frames.map {
            DevelopmentProcess(filmType: $0.filmType, isDigitalSource: $0.params.isDigitalSource)
        })
        let appliedTargets = Set(model.frames.map(\.params.developTarget))
        XCTAssertEqual(appliedProcesses, Set(DevelopmentProcess.allCases))
        XCTAssertEqual(appliedTargets, Set(Self.targets))
        let processDistribution = Dictionary(
            grouping: model.frames,
            by: {
                DevelopmentProcess(
                    filmType: $0.filmType,
                    isDigitalSource: $0.params.isDigitalSource
                )
            }
        ).mapValues(\.count)
        let targetDistribution = Dictionary(
            grouping: model.frames,
            by: \.params.developTarget
        ).mapValues(\.count)
        XCTAssertGreaterThan(
            processDistribution[.c41, default: 0],
            Self.totalFrameCount / 2
        )
        XCTAssertTrue(DevelopmentProcess.allCases.allSatisfy {
            processDistribution[$0, default: 0] > 0
        })
        XCTAssertTrue(Self.targets.allSatisfy {
            targetDistribution[$0, default: 0] > 0
        })

        let developmentStartedAt = Date()
        await model.sequentialLibraryDevelopmentTask?.value
        let developmentCompleted = model.frames.allSatisfy(\.hasDevelopedOnce)
        let developmentSeconds = Date().timeIntervalSince(developmentStartedAt)
        let developmentMaxMainActorGapSeconds = await heartbeat.captureMaximumGap()
        XCTAssertTrue(developmentCompleted)
        XCTAssertTrue(model.frames.allSatisfy {
            $0.thumbnailImage != nil && $0.thumbnailTransform == $0.imageTransform
        })
        XCTAssertTrue(model.frames.filter { $0.developedImage != nil }.allSatisfy {
            $0.developedIsSettled && $0.developedPreviewTransform == $0.imageTransform
        })
        XCTAssertLessThanOrEqual(model.residentDevelopedIDs.count, model.maxResidentDeveloped)

        let catalogStartedAt = Date()
        XCTAssertTrue(model.saveLibrary(synchronous: true))
        let catalogSeconds = Date().timeIntervalSince(catalogStartedAt)
        let catalogMaxMainActorGapSeconds = await heartbeat.captureMaximumGap()
        let catalog = try XCTUnwrap(LibraryCatalogFile.loadPrimary(from: model.libraryCatalogURL))
        XCTAssertEqual(catalog.frames.count, Self.totalFrameCount)
        XCTAssertEqual(catalog.folders.count, Self.totalFolderCount)
        XCTAssertEqual(
            Set(catalog.rolls.filter { $0.kind == .physical }.flatMap(\.frameIDs)).count,
            Self.totalFrameCount
        )
        XCTAssertEqual(
            Set(catalog.frames.map(\.params.developTarget)),
            Set(Self.targets)
        )

        heartbeat.stop()
        let endUsage = Self.currentResourceUsage()
        let report = StressReport(
            totalFrames: model.frames.count,
            framesPerWorkload: Self.framesPerWorkload,
            folderCount: folderGroups.count,
            physicalRollCount: physicalRolls.count,
            workloadCounts: workloadCounts,
            processCount: appliedProcesses.count,
            targetCount: appliedTargets.count,
            processDistribution: Dictionary(
                uniqueKeysWithValues: processDistribution.map {
                    ($0.key.displayName, $0.value)
                }
            ),
            targetDistribution: Dictionary(
                uniqueKeysWithValues: targetDistribution.map {
                    ($0.key.rawValue, $0.value)
                }
            ),
            colorNegativeRatio:
                Double(processDistribution[.c41, default: 0])
                / Double(Self.totalFrameCount),
            actualPixelFiles: true,
            uniqueSourcePaths: Set(model.frames.map { $0.rawScanURL.path }).count,
            allThumbnailsReadable: model.frames.allSatisfy { $0.thumbnailImage != nil },
            allDevelopmentsSettled: developmentCompleted,
            catalogRoundTripExact: catalog.frames.count == model.frames.count,
            elapsedSeconds: Date().timeIntervalSince(startedAt),
            fixtureSeconds: fixtureSeconds,
            importSeconds: importSeconds,
            thumbnailSeedSeconds: seedSeconds,
            folderApplySeconds: folderApplySeconds,
            rollAssignmentSeconds: rollSeconds,
            selectedRollSettingsPasteSeconds: settingsSeconds,
            developmentSeconds: developmentSeconds,
            catalogCommitSeconds: catalogSeconds,
            importMaxMainActorGapSeconds: importMaxMainActorGapSeconds,
            thumbnailSeedMaxMainActorGapSeconds: seedMaxMainActorGapSeconds,
            folderApplyMaxMainActorGapSeconds: folderApplyMaxMainActorGapSeconds,
            rollAssignmentMaxMainActorGapSeconds: rollMaxMainActorGapSeconds,
            settingsPasteMaxMainActorGapSeconds: settingsMaxMainActorGapSeconds,
            developmentMaxMainActorGapSeconds: developmentMaxMainActorGapSeconds,
            catalogCommitMaxMainActorGapSeconds: catalogMaxMainActorGapSeconds,
            startMaxRSSBytes: startUsage.maxRSSBytes,
            endMaxRSSBytes: endUsage.maxRSSBytes,
            cpuUserSeconds: max(0, endUsage.userSeconds - startUsage.userSeconds),
            cpuSystemSeconds: max(0, endUsage.systemSeconds - startUsage.systemSeconds),
            artifactRoot: root.path
        )
        try Self.writeReport(report)
    }

    nonisolated private static let framesPerWorkload = 400
    nonisolated private static let foldersPerWorkload = 10
    nonisolated private static let framesPerFolder = framesPerWorkload / foldersPerWorkload
    nonisolated private static let totalFrameCount = workloads.count * framesPerWorkload
    nonisolated private static let totalFolderCount = workloads.count * foldersPerWorkload
    nonisolated private static let targets: [DevelopTarget] = [.main, .noritsu, .sp3000, .f135, .hr]
    nonisolated private static let workloads: [Workload] = [
        Workload(label: "24MP", width: 6_000, height: 4_000, dpi: nil),
        Workload(label: "40MP", width: 7_728, height: 5_152, dpi: nil),
        Workload(label: "60MP", width: 9_504, height: 6_336, dpi: nil),
        Workload(label: "3200DPI", width: 4_535, height: 3_024, dpi: 3_200),
        Workload(label: "4800DPI", width: 6_803, height: 4_535, dpi: 4_800),
    ]

    nonisolated private static func preparePixelFilesOffMainActor(
        in root: URL
    ) async throws -> FixtureResult {
        try await Task.detached(priority: .utility) {
            try preparePixelFiles(in: root)
        }.value
    }

    nonisolated private static func preparePixelFiles(in root: URL) throws -> FixtureResult {
        let sourceRoot = root.appendingPathComponent("Pixel Fixtures", isDirectory: true)
        let libraryRoot = root.appendingPathComponent("Virtual Library", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)

        var folders: [URL] = []
        for workload in workloads {
            let source = sourceRoot.appendingPathComponent("\(workload.label).tiff")
            try makeRGBTIFF(
                width: workload.width,
                height: workload.height,
                dpi: workload.dpi,
                to: source
            )
            guard imageSourceMatches(
                url: source,
                width: workload.width,
                height: workload.height,
                dpi: workload.dpi
            ) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            for folderIndex in 0..<foldersPerWorkload {
                let folder = libraryRoot.appendingPathComponent(
                    String(format: "%@-roll-%02d", workload.label, folderIndex + 1),
                    isDirectory: true
                )
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                folders.append(folder)
                for frameIndex in 0..<framesPerFolder {
                    let destination = folder.appendingPathComponent(
                        String(format: "%@-%02d-%03d.tiff", workload.label, folderIndex + 1, frameIndex + 1)
                    )
                    try FileManager.default.linkItem(at: source, to: destination)
                }
            }
        }
        return FixtureResult(folders: folders)
    }

    nonisolated private static func makeRGBTIFF(
        width: Int,
        height: Int,
        dpi: Int?,
        to url: URL
    ) throws {
        let bytesPerPixel = 3
        let data = Data(count: width * height * bytesPerPixel)
        let provider = CGDataProvider(data: data as CFData)!
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 24,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ), let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.tiff" as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.coderInvalidValue)
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
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    nonisolated private static func imageSourceMatches(
        url: URL,
        width: Int,
        height: Int,
        dpi: Int?
    ) -> Bool {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == width,
           (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == height else {
            return false
        }
        guard let dpi else { return true }
        return (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue == dpi
            && (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.intValue == dpi
    }

    nonisolated private static func workloadLabel(for url: URL) -> String {
        let name = url.deletingLastPathComponent().lastPathComponent
        return workloads.first(where: { name.hasPrefix($0.label) })?.label ?? "unknown"
    }

    nonisolated private static func randomCombination(
        index: Int
    ) -> (process: DevelopmentProcess, target: DevelopTarget) {
        let processSample = Int(stableRandom(UInt64(index) &* 2) % 100)
        let process: DevelopmentProcess = switch processSample {
        case 0..<60: .c41
        case 60..<68: .e6
        case 68..<76: .d76
        case 76..<84: .bwReversal
        case 84..<92: .digitalColor
        default: .digitalBW
        }
        let targetSample = stableRandom(UInt64(index) &* 2 &+ 1)
        return (process, targets[Int(targetSample % UInt64(targets.count))])
    }

    nonisolated private static func stableRandom(_ value: UInt64) -> UInt64 {
        var mixed = value &+ 0x9E37_79B9_7F4A_7C15
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    nonisolated private static func transform(index: Int) -> ImageTransform {
        let rotations: [ImageRotation] = [.deg0, .deg90, .deg180, .deg270]
        return ImageTransform(
            rotation: rotations[index % rotations.count],
            flipHorizontal: index.isMultiple(of: 2),
            flipVertical: index.isMultiple(of: 3),
            cropRect: SIMD4(0.03, 0.04, 0.91, 0.88),
            straightenAngle: Double(index % 9) - 4,
            cropAspect: index.isMultiple(of: 5) ? 1.5 : nil
        )
    }

    nonisolated private static func stressRoot() throws -> URL {
        if let raw = ProcessInfo.processInfo.environment["NEGAFLOW_VIRTUAL_LIBRARY_STRESS_ROOT"],
           raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(
            "negaflow-virtual-library-stress-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    nonisolated private static func writeReport(_ report: StressReport) throws {
        guard let path = ProcessInfo.processInfo.environment["NEGAFLOW_VIRTUAL_LIBRARY_STRESS_REPORT"],
              !path.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url, options: .atomic)
    }

    nonisolated private static func currentResourceUsage() -> ResourceUsage {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return ResourceUsage(
            maxRSSBytes: Int64(usage.ru_maxrss),
            userSeconds: seconds(usage.ru_utime),
            systemSeconds: seconds(usage.ru_stime)
        )
    }

    nonisolated private static func seconds(_ value: timeval) -> TimeInterval {
        TimeInterval(value.tv_sec) + TimeInterval(value.tv_usec) / 1_000_000
    }

    private struct FixtureResult: Sendable {
        let folders: [URL]
    }

    private struct Workload: Sendable {
        let label: String
        let width: Int
        let height: Int
        let dpi: Int?
    }

    private struct ResourceUsage: Sendable {
        let maxRSSBytes: Int64
        let userSeconds: TimeInterval
        let systemSeconds: TimeInterval
    }

    private struct StressReport: Encodable {
        let totalFrames: Int
        let framesPerWorkload: Int
        let folderCount: Int
        let physicalRollCount: Int
        let workloadCounts: [String: Int]
        let processCount: Int
        let targetCount: Int
        let processDistribution: [String: Int]
        let targetDistribution: [String: Int]
        let colorNegativeRatio: Double
        let actualPixelFiles: Bool
        let uniqueSourcePaths: Int
        let allThumbnailsReadable: Bool
        let allDevelopmentsSettled: Bool
        let catalogRoundTripExact: Bool
        let elapsedSeconds: TimeInterval
        let fixtureSeconds: TimeInterval
        let importSeconds: TimeInterval
        let thumbnailSeedSeconds: TimeInterval
        let folderApplySeconds: TimeInterval
        let rollAssignmentSeconds: TimeInterval
        let selectedRollSettingsPasteSeconds: TimeInterval
        let developmentSeconds: TimeInterval
        let catalogCommitSeconds: TimeInterval
        let importMaxMainActorGapSeconds: TimeInterval
        let thumbnailSeedMaxMainActorGapSeconds: TimeInterval
        let folderApplyMaxMainActorGapSeconds: TimeInterval
        let rollAssignmentMaxMainActorGapSeconds: TimeInterval
        let settingsPasteMaxMainActorGapSeconds: TimeInterval
        let developmentMaxMainActorGapSeconds: TimeInterval
        let catalogCommitMaxMainActorGapSeconds: TimeInterval
        let startMaxRSSBytes: Int64
        let endMaxRSSBytes: Int64
        let cpuUserSeconds: TimeInterval
        let cpuSystemSeconds: TimeInterval
        let artifactRoot: String
    }
}

@MainActor
private final class MainActorHeartbeat {
    private var task: Task<Void, Never>?
    private var lastTick = ContinuousClock.now
    private(set) var maximumGapSeconds: TimeInterval = 0

    func start() {
        task?.cancel()
        lastTick = ContinuousClock.now
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
                guard let self, !Task.isCancelled else { return }
                let now = ContinuousClock.now
                maximumGapSeconds = max(
                    maximumGapSeconds,
                    Double(lastTick.duration(to: now).components.attoseconds) / 1e18
                        + Double(lastTick.duration(to: now).components.seconds)
                )
                lastTick = now
            }
        }
    }

    func resetMaximumGap() -> TimeInterval {
        let value = maximumGapSeconds
        maximumGapSeconds = 0
        lastTick = ContinuousClock.now
        return value
    }

    func captureMaximumGap() async -> TimeInterval {
        try? await Task.sleep(for: .milliseconds(30))
        return resetMaximumGap()
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
