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
    let sources: [PrintPackageExportSource]
    let composition: PrintCompositionSettings
    let package: PrintPackageSettings
    let artifactLayout: PrintPackageArtifactLayout
    let format: ExportFormat
    let options: ExportOptions
    let printerOutputProfile: ICCOutputProfileSnapshot?
    let appVersion: String

    init(
        sources: [PrintPackageExportSource],
        composition: PrintCompositionSettings,
        package: PrintPackageSettings,
        artifactLayout: PrintPackageArtifactLayout,
        format: ExportFormat,
        options: ExportOptions,
        printerOutputProfile: ICCOutputProfileSnapshot? = nil,
        appVersion: String
    ) {
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
        .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
    ])

    static func write(
        _ request: PrintPackageExportRequest,
        journalDirectory: URL = ExportArtifactCommitJournal.defaultDirectoryURL(),
        beforePublish: () throws -> Void = {}
    ) throws -> PrintPackageExportResult {
        let fileManager = FileManager.default
        guard request.format != .rawScanTIFF,
              let printerOutputProfile = request.printerOutputProfile,
              printerOutputProfile.validatedColorSpace() != nil,
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
                package: request.package
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
            var renderSources: [PrintPackageRenderSource] = []
            renderSources.reserveCapacity(globalSourceIndices.count)

            for globalSourceIndex in globalSourceIndices {
                let source = request.sources[globalSourceIndex]
                let sourceCopyURL = stagingDirectory.appendingPathComponent(
                    ".negaflow-source-\(pageIndex)-\(globalSourceIndex)"
                        + (source.snapshot.rawScanURL.pathExtension.isEmpty
                            ? ""
                            : ".\(source.snapshot.rawScanURL.pathExtension)")
                )
                let prepared = try ExportDevelopedFrameRenderer.prepare(
                    source.snapshot,
                    stagedSourceURL: sourceCopyURL,
                    fileManager: fileManager
                )
                guard aspectMatches(prepared.developedImage.extent.size, source.layoutSize) else {
                    throw ChromabaseError.writeFailed("print package source geometry changed")
                }
                let sourceItems = page.items.filter { $0.sourceIndex == globalSourceIndex }
                let raster = try rasterizedSource(
                    prepared.developedImage,
                    items: sourceItems,
                    dpi: request.composition.dpi,
                    format: request.format
                )
                try ExportDevelopedFrameRenderer.verifySourceIdentity(
                    source.snapshot,
                    stagedSourceURL: sourceCopyURL
                )
                if let base = prepared.base { estimatedBases[globalSourceIndex] = base }
                try? fileManager.removeItem(at: sourceCopyURL)
                renderSources.append(PrintPackageRenderSource(
                    image: raster,
                    caption: source.caption
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
                        cropMarkSegments: page.cropMarkSegments
                    ),
                    dpi: request.composition.dpi
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

        for source in request.sources {
            guard try RenderManifest.sourceIdentity(for: source.snapshot.rawScanURL)
                    == source.snapshot.sourceIdentity else {
                throw ChromabaseError.loadFailed("print package source identity changed")
            }
        }
        let outputIdentities = try validateStagedPages(
            stagedURLs,
            expectedOutputProfileSHA256: printerOutputProfile.profileSHA256,
            fileManager: fileManager
        )
        try beforePublish()
        for source in request.sources {
            guard try RenderManifest.sourceIdentity(for: source.snapshot.rawScanURL)
                    == source.snapshot.sourceIdentity else {
                throw ChromabaseError.loadFailed("print package source identity changed")
            }
        }
        guard try validateStagedPages(
            stagedURLs,
            expectedOutputProfileSHA256: printerOutputProfile.profileSHA256,
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

    private static func rasterizedSource(
        _ image: CIImage,
        items: [PrintPackageItemLayout],
        dpi: Int,
        format: ExportFormat
    ) throws -> CIImage {
        let normalized = normalize(image)
        let sourceSize = normalized.extent.size
        let plan = try sourceRasterPlan(
            sourceSize: sourceSize,
            items: items,
            dpi: dpi,
            capsAtSourceResolution: true
        )
        let scaled: CIImage
        if plan.scale < 0.999 {
            scaled = normalized
                .applyingFilter("CILanczosScaleTransform", parameters: [
                    kCIInputScaleKey: plan.scale,
                    kCIInputAspectRatioKey: 1,
                ])
                .cropped(to: CGRect(origin: .zero, size: plan.outputSize))
        } else {
            scaled = normalized
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        let pixelFormat: CIFormat = format == .tiff16 ? .RGBAh : .RGBA8
        guard let cgImage = renderContext.createCGImage(
            scaled,
            from: scaled.extent,
            format: pixelFormat,
            colorSpace: colorSpace
        ) else {
            throw ChromabaseError.writeFailed("print package source rasterization failed")
        }
        return CIImage(cgImage: cgImage, options: [.colorSpace: colorSpace])
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
            let orientedSize = item.quarterTurns == 0
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

    private static func validateStagedPages(
        _ urls: [URL],
        expectedOutputProfileSHA256: String,
        fileManager: FileManager
    ) throws -> [RenderManifest.SourceIdentity] {
        try urls.map { url in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize > 0,
                  ICCOutputProfileSnapshot.embeddedProfileSHA256(at: url)
                    == expectedOutputProfileSHA256 else {
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

    private static func normalize(_ image: CIImage) -> CIImage {
        image.extent.origin == .zero
            ? image
            : image.transformed(by: CGAffineTransform(
                translationX: -image.extent.minX,
                y: -image.extent.minY
            ))
    }

    private static func validSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}
