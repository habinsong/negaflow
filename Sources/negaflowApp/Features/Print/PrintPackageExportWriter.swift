import Chromabase
import CoreGraphics
import CoreImage
import Foundation

struct PrintPackageExportSource: @unchecked Sendable {
    let snapshot: ExportFrameSnapshot
    let layoutSize: CGSize
    let caption: String?
}

struct PrintPackageExportRequest: @unchecked Sendable {
    /// 시트 방향 통일 — 미리보기와 같은 배치를 내보내기 위해 그대로 전달한다.
    let forcedQuarterTurns: [Int]?
    let sources: [PrintPackageExportSource]
    let composition: PrintCompositionSettings
    let package: PrintPackageSettings
    let artifactLayout: PrintPackageArtifactLayout
    let format: ExportFormat
    let options: ExportOptions
    let printerOutputProfile: ICCOutputProfileSnapshot?
    let appVersion: String

    init(
        forcedQuarterTurns: [Int]? = nil,
        sources: [PrintPackageExportSource],
        composition: PrintCompositionSettings,
        package: PrintPackageSettings,
        artifactLayout: PrintPackageArtifactLayout,
        format: ExportFormat,
        options: ExportOptions,
        printerOutputProfile: ICCOutputProfileSnapshot? = nil,
        appVersion: String
    ) {
        self.forcedQuarterTurns = forcedQuarterTurns
        self.sources = sources
        self.composition = composition
        self.package = package
        self.artifactLayout = artifactLayout
        self.format = format
        self.options = options
        self.printerOutputProfile = printerOutputProfile
        self.appVersion = appVersion
    }
}

struct PrintPackageExportResult: Sendable {
    let transactionID: UUID
    let outputURLs: [URL]
    let outputIdentities: [RenderManifest.SourceIdentity]
    let contributorPageIndices: [Int: [Int]]
    let estimatedBases: [Int: FilmBase]
}

enum PrintPackageExportWriter {
    static let maximumPageSourceRasterBytes: UInt64 = 512 * 1_024 * 1_024

    private static let renderContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
    ])

    static func write(
        _ request: PrintPackageExportRequest,
        journalDirectory: URL = ExportArtifactCommitJournal.defaultDirectoryURL(),
        beforePublish: () throws -> Void = {}
    ) throws -> PrintPackageExportResult {
        let fileManager = FileManager.default
        let printerOutputProfile: ICCOutputProfileSnapshot?
        if let requestedProfile = request.printerOutputProfile {
            guard requestedProfile.validatedColorSpace() != nil else {
                throw ChromabaseError.writeFailed("invalid print package output profile")
            }
            printerOutputProfile = requestedProfile
        } else {
            printerOutputProfile = nil
        }
        let deliveryProfileData = request.options.colorSpace.cgColorSpace.copyICCData() as Data?
        guard let expectedOutputProfileSHA256 = printerOutputProfile?.profileSHA256
                ?? deliveryProfileData.map(ICCOutputProfileSnapshot.sha256),
              request.format != .rawScanTIFF,
              request.composition.isValid,
              request.composition.perforationStyle == .none,
              request.package.isValid,
              !request.sources.isEmpty,
              request.sources.allSatisfy({ validSize($0.layoutSize) }),
              let expectedPageCount = PrintPackageLayout.expectedPageCount(
                sourceCount: request.sources.count,
                package: request.package
              ),
              expectedPageCount == request.artifactLayout.outputURLs.count,
              let pages = PrintPackageLayout.make(
                sourceSizes: request.sources.map(\.layoutSize),
                composition: request.composition,
                package: request.package,
                forcedQuarterTurns: request.forcedQuarterTurns
              ),
              pages.count == expectedPageCount else {
            throw ChromabaseError.writeFailed("invalid print package export request")
        }
        let protectedSources = request.sources.map { $0.snapshot.rawScanURL }
        guard request.artifactLayout.isAvailable(
            protectedSources: protectedSources,
            reservedPaths: [],
            fileManager: fileManager
        ) else {
            throw ChromabaseError.writeFailed("print package destination is unavailable")
        }

        let outputFolder = request.artifactLayout.outputURLs[0].deletingLastPathComponent()
        let transactionID = UUID()
        let stagingDirectory = outputFolder.appendingPathComponent(
            ".negaflow-export-\(transactionID.uuidString).tmp",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
        try ExportArtifactCommitJournal.beginPreparation(
            transactionID: transactionID,
            stagingDirectory: stagingDirectory,
            in: journalDirectory,
            fileManager: fileManager
        )
        defer {
            ExportArtifactCommitJournal.cancelPreparation(
                transactionID: transactionID,
                in: journalDirectory,
                fileManager: fileManager
            )
        }
        let stagedURLs = request.artifactLayout.staged(in: stagingDirectory)
        var estimatedBases: [Int: FilmBase] = [:]
        var contributorPages: [Int: [Int]] = [:]

        for (pageIndex, page) in pages.enumerated() {
            let globalSourceIndices = Array(Set(page.items.map(\.sourceIndex))).sorted()
            guard !globalSourceIndices.isEmpty else {
                throw ChromabaseError.writeFailed("print package page has no contributors")
            }
            guard let estimatedRasterBytes = estimatedPageSourceRasterByteCount(
                sourceSizes: request.sources.map(\.layoutSize),
                layout: page,
                dpi: request.composition.dpi,
                format: request.format
            ), estimatedRasterBytes <= maximumPageSourceRasterBytes else {
                throw ChromabaseError.writeFailed(
                    "print package page exceeds the safe raster memory budget"
                )
            }
            let localIndexByGlobal = Dictionary(
                uniqueKeysWithValues: globalSourceIndices.enumerated().map { ($0.element, $0.offset) }
            )
            // 한 페이지의 source 는 서로 독립이다. 순서대로 한 장씩 현상하면 시트에 올린
            // 장수만큼 시간이 그대로 늘어나므로, 메모리를 감당할 만큼만 동시에 준비한다.
            let preparedSources = try prepareSources(
                globalSourceIndices,
                request: request,
                page: page
            )
            var renderSources: [PrintPackageRenderSource] = []
            renderSources.reserveCapacity(globalSourceIndices.count)
            for (offset, globalSourceIndex) in globalSourceIndices.enumerated() {
                let prepared = preparedSources[offset]
                if let base = prepared.base { estimatedBases[globalSourceIndex] = base }
                renderSources.append(PrintPackageRenderSource(
                    image: prepared.raster,
                    caption: request.sources[globalSourceIndex].caption
                ))
                contributorPages[globalSourceIndex, default: []].append(pageIndex)
            }

            let remappedItems = page.items.compactMap { item -> PrintPackageItemLayout? in
                guard let localSourceIndex = localIndexByGlobal[item.sourceIndex] else { return nil }
                return PrintPackageItemLayout(
                    sourceIndex: localSourceIndex,
                    cellRectPoints: item.cellRectPoints,
                    destinationRectPoints: item.destinationRectPoints,
                    sourceUnitCropRect: item.sourceUnitCropRect,
                    quarterTurns: item.quarterTurns,
                    captionRectPoints: item.captionRectPoints,
                    zIndex: item.zIndex
                )
            }
            guard remappedItems.count == page.items.count,
                  let renderedPage = PrintPackageRenderer.renderPage(
                    sources: renderSources,
                    layout: PrintPackagePageLayout(
                        pageIndex: page.pageIndex,
                        canvasSizePoints: page.canvasSizePoints,
                        contentRectPoints: page.contentRectPoints,
                        items: remappedItems,
                        cropMarkSegments: page.cropMarkSegments,
                        textItems: page.textItems
                    ),
                    dpi: request.composition.dpi,
                    paperColor: paperColor(for: request.package),
                    foregroundColor: request.package.contactSheetBackground
                        .prefersLightForeground
                        ? CIColor(red: 1, green: 1, blue: 1, alpha: 1)
                        : CIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1),
                    captionFontName: request.package.captionFontName,
                    captionAlignment: request.package.captionAlignment
                  ) else {
                throw ChromabaseError.writeFailed("print package page render failed")
            }
            let metadata = ExportMeta(
                resolutionDPI: request.composition.dpi,
                software: "negaflow \(request.appVersion)",
                metadataPolicy: .minimal
            )
            try ExportEngine.write(
                renderedPage,
                to: stagedURLs[pageIndex],
                format: request.format,
                using: renderContext,
                metadata: metadata,
                options: request.options,
                outputProfile: printerOutputProfile
            )
        }

        try verifyOriginalSources(request.sources)
        let outputIdentities = try validateStagedPages(
            stagedURLs,
            expectedOutputProfileSHA256: expectedOutputProfileSHA256,
            requiresExactOutputProfile: printerOutputProfile != nil,
            fileManager: fileManager
        )
        try beforePublish()
        try verifyOriginalSources(request.sources)
        guard try validateStagedPages(
            stagedURLs,
            expectedOutputProfileSHA256: expectedOutputProfileSHA256,
            requiresExactOutputProfile: printerOutputProfile != nil,
            fileManager: fileManager
        ) == outputIdentities else {
            throw ChromabaseError.writeFailed(
                "print package page changed after profile verification"
            )
        }

        try ExportArtifactCommitJournal.promotePreparation(
            transactionID: transactionID,
            stagingDirectory: stagingDirectory,
            stagedURLs: stagedURLs,
            finalURLs: request.artifactLayout.outputURLs,
            in: journalDirectory,
            fileManager: fileManager
        )
        try? ExportArtifactCommitJournal.completePreparation(
            transactionID: transactionID,
            in: journalDirectory,
            fileManager: fileManager
        )
        do {
            for (stagedURL, finalURL) in zip(stagedURLs, request.artifactLayout.outputURLs) {
                try ExportArtifactCommitJournal.publish(
                    transactionID: transactionID,
                    stagedURL: stagedURL,
                    finalURL: finalURL,
                    in: journalDirectory,
                    fileManager: fileManager
                )
            }
            guard ExportArtifactCommitJournal.cleanupOwnedStaging(
                transactionID: transactionID,
                in: journalDirectory,
                fileManager: fileManager
            ) else {
                throw ChromabaseError.writeFailed("print package staging cleanup failed")
            }
        } catch {
            ExportArtifactCommitJournal.cancelUncommitted(
                transactionID: transactionID,
                in: journalDirectory,
                fileManager: fileManager
            )
            throw error
        }

        return PrintPackageExportResult(
            transactionID: transactionID,
            outputURLs: request.artifactLayout.outputURLs,
            outputIdentities: outputIdentities,
            contributorPageIndices: contributorPages,
            estimatedBases: estimatedBases
        )
    }

    static func estimatedPageSourceRasterByteCount(
        sourceSizes: [CGSize],
        layout: PrintPackagePageLayout,
        dpi: Int,
        format: ExportFormat
    ) -> UInt64? {
        guard (72...600).contains(dpi),
              !sourceSizes.isEmpty,
              sourceSizes.allSatisfy(validSize) else { return nil }
        var total: UInt64 = 0
        for sourceIndex in Set(layout.items.map(\.sourceIndex)).sorted() {
            guard sourceSizes.indices.contains(sourceIndex),
                  let plan = try? sourceRasterPlan(
                    sourceSize: sourceSizes[sourceIndex],
                    items: layout.items.filter { $0.sourceIndex == sourceIndex },
                    dpi: dpi,
                    capsAtSourceResolution: false
                  ), let bytes = rasterByteCount(
                    size: plan.outputSize,
                    bytesPerPixel: format == .tiff16 ? 8 : 4
                  ), total <= UInt64.max - bytes else { return nil }
            total += bytes
        }
        return total
    }

    private struct SourceRasterPlan {
        let scale: CGFloat
        let outputSize: CGSize
    }

    /// 용지 색은 모든 인화 레이아웃에 적용된다 — 미리보기와 같은 종이 위에 합성한다.
    private static func paperColor(for package: PrintPackageSettings) -> CIColor {
        switch package.contactSheetBackground {
        case .black: CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        case .gray: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        case .white: CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
    }

    private struct PreparedPageSource: @unchecked Sendable {
        let raster: CIImage
        let base: FilmBase?
    }

    /// 동시에 띄울 source 개수. 코어를 다 쓰면 풀해상도 현상 여러 장이 한꺼번에 메모리에
    /// 올라가므로 절반만 쓴다.
    private static var sourcePreparationWidth: Int {
        max(2, min(4, ProcessInfo.processInfo.activeProcessorCount / 2))
    }

    /// 동시 실행 결과를 순서대로 모으는 상자. 잠금으로만 접근한다.
    private final class PreparedSourceStore: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [Result<PreparedPageSource, Error>?]

        init(count: Int) {
            results = [Result<PreparedPageSource, Error>?](repeating: nil, count: count)
        }

        func store(_ result: Result<PreparedPageSource, Error>, at index: Int) {
            lock.lock()
            results[index] = result
            lock.unlock()
        }

        func ordered() throws -> [PreparedPageSource] {
            lock.lock()
            let snapshot = results
            lock.unlock()
            return try snapshot.map { result in
                guard let result else {
                    throw ChromabaseError.writeFailed("print package source preparation failed")
                }
                return try result.get()
            }
        }
    }

    private static func prepareSources(
        _ globalSourceIndices: [Int],
        request: PrintPackageExportRequest,
        page: PrintPackagePageLayout
    ) throws -> [PreparedPageSource] {
        let store = PreparedSourceStore(count: globalSourceIndices.count)
        for chunkStart in stride(from: 0, to: globalSourceIndices.count, by: sourcePreparationWidth) {
            let chunk = chunkStart..<min(chunkStart + sourcePreparationWidth, globalSourceIndices.count)
            DispatchQueue.concurrentPerform(iterations: chunk.count) { offset in
                let slot = chunk.lowerBound + offset
                store.store(
                    Result {
                        try autoreleasepool {
                            try prepareSource(
                                globalSourceIndices[slot],
                                request: request,
                                page: page
                            )
                        }
                    },
                    at: slot
                )
            }
        }
        return try store.ordered()
    }

    private static func prepareSource(
        _ globalSourceIndex: Int,
        request: PrintPackageExportRequest,
        page: PrintPackagePageLayout
    ) throws -> PreparedPageSource {
        let source = request.sources[globalSourceIndex]
        // 이 source 가 이 페이지에서 실제로 차지하는 픽셀만 계산한다. 콘택트 시트 한 칸이
        // 3cm 라면 6000px 원본을 그대로 현상할 이유가 없다.
        let sourceItems = page.items.filter { $0.sourceIndex == globalSourceIndex }
        let rasterPlan = try sourceRasterPlan(
            sourceSize: source.layoutSize,
            items: sourceItems,
            dpi: request.composition.dpi,
            capsAtSourceResolution: true
        )
        guard let proxyLongEdge = ExportDevelopedFrameRenderer.proxyInputLongEdge(
            outputLongEdge: max(rasterPlan.outputSize.width, rasterPlan.outputSize.height),
            imageTransform: source.snapshot.params.imageTransform,
            sourcePixelSize: source.snapshot.sourcePixelSize
        ) else {
            throw ChromabaseError.writeFailed("invalid print package raster dimensions")
        }
        let prepared = try ExportDevelopedFrameRenderer.prepareForPrintComposite(
            source.snapshot,
            proxyLongEdge: proxyLongEdge
        )
        guard aspectMatches(prepared.developedImage.extent.size, source.layoutSize) else {
            throw ChromabaseError.writeFailed("print package source geometry changed")
        }
        // 여기서 CGImage 중간 래스터를 만들지 않는다. source graph를 page graph에 그대로
        // 연결하면 Core Image가 crop/scale/develop을 한 번의 최종 page render로 합친다.
        return PreparedPageSource(raster: prepared.developedImage, base: prepared.base)
    }

    private static func verifyOriginalSources(
        _ sources: [PrintPackageExportSource]
    ) throws {
        var verifiedPaths = Set<String>()
        for source in sources {
            let path = source.snapshot.rawScanURL.standardizedFileURL.path
            guard verifiedPaths.insert(path).inserted else { continue }
            try ExportDevelopedFrameRenderer.verifyOriginalSourceIdentity(source.snapshot)
        }
    }

    private static func sourceRasterPlan(
        sourceSize: CGSize,
        items: [PrintPackageItemLayout],
        dpi: Int,
        capsAtSourceResolution: Bool
    ) throws -> SourceRasterPlan {
        guard validSize(sourceSize), !items.isEmpty, (72...600).contains(dpi) else {
            throw ChromabaseError.writeFailed("invalid print package raster input")
        }
        let pixelsPerPoint = CGFloat(dpi) / 72
        var requiredScale: CGFloat = 0
        for item in items {
            let orientedSize = item.quarterTurns % 2 == 0
                ? sourceSize
                : CGSize(width: sourceSize.height, height: sourceSize.width)
            let crop = item.sourceUnitCropRect
            let requiredWidth = item.destinationRectPoints.width * pixelsPerPoint / crop.width
            let requiredHeight = item.destinationRectPoints.height * pixelsPerPoint / crop.height
            requiredScale = max(
                requiredScale,
                requiredWidth / orientedSize.width,
                requiredHeight / orientedSize.height
            )
        }
        guard requiredScale.isFinite, requiredScale > 0 else {
            throw ChromabaseError.writeFailed("invalid print package raster scale")
        }
        let requestedScale = requiredScale * 1.02
        let scale: CGFloat
        if capsAtSourceResolution {
            scale = requestedScale < 0.999 ? requestedScale : 1
        } else {
            scale = requestedScale
        }
        let outputSize = scale == 1
            ? sourceSize
            : CGSize(
                width: max(1, (sourceSize.width * scale).rounded()),
                height: max(1, (sourceSize.height * scale).rounded())
            )
        guard validSize(outputSize) else {
            throw ChromabaseError.writeFailed("invalid print package raster dimensions")
        }
        return SourceRasterPlan(scale: scale, outputSize: outputSize)
    }

    private static func rasterByteCount(size: CGSize, bytesPerPixel: UInt64) -> UInt64? {
        guard validSize(size),
              bytesPerPixel > 0,
              size.width <= CGFloat(UInt64.max),
              size.height <= CGFloat(UInt64.max) else { return nil }
        let width = UInt64(size.width.rounded(.up))
        let height = UInt64(size.height.rounded(.up))
        guard width > 0,
              height > 0,
              width <= UInt64.max / height else { return nil }
        let pixels = width * height
        guard pixels <= UInt64.max / bytesPerPixel else { return nil }
        return pixels * bytesPerPixel
    }

    /// 프린터 ICC 를 지정한 경우에는 그 프로파일이 **그대로** 박혔는지 바이트로 확인한다(랩에
    /// 넘기는 파일이라 대체되면 안 된다). 배포 색공간만 쓰는 경우에는 ImageIO 가 같은 색공간을
    /// 다른 바이트의 동등한 프로파일로 심을 수 있으므로(예: PNG + Adobe RGB), 프로파일이
    /// 박혀 있는지만 확인한다. 예전에는 이 차이 때문에 정상 파일이 "invalid staged print
    /// package page" 로 거부됐다.
    private static func validateStagedPages(
        _ urls: [URL],
        expectedOutputProfileSHA256: String,
        requiresExactOutputProfile: Bool,
        fileManager: FileManager
    ) throws -> [RenderManifest.SourceIdentity] {
        try urls.map { url in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            let embeddedSHA256 = ICCOutputProfileSnapshot.embeddedProfileSHA256(at: url)
            let profileIsAcceptable = requiresExactOutputProfile
                ? embeddedSHA256 == expectedOutputProfileSHA256
                : embeddedSHA256 != nil
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize > 0,
                  profileIsAcceptable else {
                throw ChromabaseError.writeFailed("invalid staged print package page")
            }
            return try RenderManifest.sourceIdentity(for: url)
        }
    }

    private static func aspectMatches(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        guard validSize(lhs), validSize(rhs) else { return false }
        let leftAspect = lhs.width / lhs.height
        let rightAspect = rhs.width / rhs.height
        return abs(leftAspect - rightAspect) / rightAspect <= 0.01
    }

    private static func validSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}
