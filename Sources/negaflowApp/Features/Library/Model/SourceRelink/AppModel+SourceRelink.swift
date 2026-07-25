import AppKit
import Foundation
import ImageIO

extension AppModel {
    func isSourceAvailable(_ frame: ScanFrame) -> Bool {
        _ = sourceAvailabilityRevision
        return librarySourceAvailability(for: frame) == .online
    }

    func isLibraryFolderAvailable(_ folder: LibraryFolder) -> Bool {
        _ = sourceAvailabilityRevision
        return libraryFolderAvailabilityCache[folder.id] ?? false
    }

    var offlineSourceCount: Int {
        _ = sourceAvailabilityRevision
        return frames.count { librarySourceAvailability(for: $0) == .offline }
    }

    func refreshSourceAvailability() {
        rebuildLibrarySourceAvailabilitySnapshot()
        rebuildLibraryFolderAvailabilitySnapshot()
        advanceSourceAvailabilityRevision()
        invalidateLibraryQueryContext()
    }

    func presentRelinkPanel(for frame: ScanFrame) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.prompt = text(AppLocalizedPhrase.locateOriginal)
        panel.message = text(
            AppLocalizedPhrase.locateSourcePanelMessageFormat,
            frame.rawScanURL.path
        )
        panel.allowedContentTypes = Self.importContentTypes
        let parent = frame.rawScanURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parent.path) {
            panel.directoryURL = parent
        }
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        guard let plan = SourceRelinkPlanner.filePlan(
            oldSourceURL: frame.rawScanURL,
            newSourceURL: selected,
            isReadable: Self.isReadableRelinkTarget
        ) else {
            statusMessage = text(AppLocalizedPhrase.sourceRelinkInvalid)
            return
        }
        let outcome = applySourceRelink(plan)
        statusMessage = outcome.frameCount > 0
            ? text(AppLocalizedPhrase.sourceRelinkedFormat, outcome.frameCount)
            : text(AppLocalizedPhrase.sourceRelinkInvalid)
    }

    func presentRelinkFolderPanel(_ folder: LibraryFolder) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.resolvesAliases = true
        panel.prompt = text(AppLocalizedPhrase.locateMissingFolder)
        panel.message = text(
            AppLocalizedPhrase.locateFolderPanelMessageFormat,
            folder.url.path
        )
        let parent = folder.url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parent.path) {
            panel.directoryURL = parent
        }
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        let plan = SourceRelinkPlanner.folderPlan(
            oldFolderURL: folder.url,
            newFolderURL: selected,
            sourceURLs: frames.map(\.rawScanURL),
            isReadable: Self.isReadableRelinkTarget
        )
        let outcome = applySourceRelink(plan)
        refreshLibrary(relinkedSourceCount: outcome.sourceCount)
    }

    /// 등록 폴더에서 새 파일을 추가하고, bookmark로 이동이 확인된 기존 원본을 다시 연결한다.
    /// 누락 원본은 사용자의 명시적 제거 전까지 절대 카탈로그에서 삭제하지 않는다.
    func refreshLibrary() {
        refreshLibrary(relinkedSourceCount: recoverMovedSourcesFromBookmarks())
    }

    private func refreshLibrary(relinkedSourceCount: Int) {
        var importedCount = 0
        for folder in libraryFolders where Self.isDirectory(folder.url) {
            let candidates = Self.importableImageFiles(in: folder.url)
            let filtered = Self.filterDuplicateImports(
                candidates,
                existingSourceURLs: frames.map(\.rawScanURL)
            )
            guard !filtered.urls.isEmpty else { continue }
            let group = FrameStorageNaming.sanitizeComponent(folder.url.lastPathComponent)
            importImages(
                urls: filtered.urls,
                groupName: group.isEmpty ? FrameStorageNaming.defaultImportGroup : group
            )
            importedCount += filtered.urls.count
        }
        refreshSourceAvailability()
        statusMessage = text(
            AppLocalizedPhrase.libraryRefreshStatusFormat,
            importedCount,
            relinkedSourceCount,
            offlineSourceCount
        )
    }

    @discardableResult
    func applySourceRelink(
        _ plan: SourceRelinkPlan,
        reprocess: Bool = true
    ) -> (frameCount: Int, sourceCount: Int) {
        struct Candidate {
            let url: URL
            let metadata: SourceMetadataSnapshot
        }
        var requestedMappings: [String: URL] = [:]
        for mapping in plan.mappings {
            requestedMappings[mapping.oldSourceURL.standardizedFileURL.path] =
                mapping.newSourceURL.standardizedFileURL
        }
        var mappings: [String: Candidate] = [:]
        for (oldPath, newURL) in requestedMappings {
            guard Self.isReadableRelinkTarget(newURL) else { continue }
            let metadata = SourceMetadataReader.read(from: newURL)
            let family = frames.filter {
                $0.rawScanURL.standardizedFileURL.path == oldPath
            }
            guard !family.isEmpty,
                  family.allSatisfy({ Self.isCompatibleRelinkMetadata(metadata, with: $0) }) else {
                continue
            }
            mappings[oldPath] = Candidate(url: newURL, metadata: metadata)
        }
        var affectedFrames: [ScanFrame] = []
        var appliedMappings: [String: Candidate] = [:]
        for (oldPath, candidate) in mappings.sorted(by: { $0.key < $1.key }) {
            let family = frames.filter {
                $0.rawScanURL.standardizedFileURL.path == oldPath
            }
            // 경로를 바꾸기 전에 family 전체의 source binding을 끊어 이전 cleaned-raw
            // 증명이 새 원본에 재사용되지 않게 한다.
            guard invalidateDefectRecipeSourceBindingsForRelink(family) else { continue }

            for frame in family {
                prepareForSourceRelink(frame)
                let infraredURL = SourceRelinkPlanner.relocatedCompanionURL(
                    frame.infraredScanURL,
                    using: plan,
                    fileExists: { FileManager.default.fileExists(atPath: $0.path) }
                )
                frame.updateSourceLocation(
                    rawURL: candidate.url,
                    infraredURL: infraredURL,
                    // 이미 저장된 snapshot은 원본을 가져온 당시의 immutable facts다. legacy frame만
                    // 명시적 재연결 시 검증에 사용한 동일 snapshot으로 보강한다.
                    sourceMetadata: frame.sourceMetadata ?? candidate.metadata
                )
                affectedFrames.append(frame)
            }
            appliedMappings[oldPath] = candidate
        }

        updateRegisteredFolder(
            for: plan,
            allMappingsApplied: appliedMappings.count == requestedMappings.count
        )
        registerLibraryFolders(for: appliedMappings.values.map(\.url))
        refreshSourceAvailability()
        scheduleLibrarySave()

        if reprocess {
            for frame in affectedFrames {
                if frame.defectEdits.isEmpty {
                    Task { await developFrame(frame, preserveThumbnail: true) }
                } else {
                    rebuildCleanedRaw(frame)
                }
            }
        }
        return (affectedFrames.count, appliedMappings.count)
    }

    private func prepareForSourceRelink(_ frame: ScanFrame) {
        frame.developRevision += 1
        frame.transformRevision += 1
        frame.defectDetectRevision += 1
        frame.cleanRawRevision += 1
        frame.transformTask?.cancel()
        frame.defectDetectTask?.cancel()
        frame.cleanRawTask?.cancel()
        frame.cleanRawTask = nil
        frame.cleanedRawPersistTask?.cancel()
        frame.cleanedRawPersistTask = nil
        frame.isRemovingDefects = false
        cancelInfraredClean(frame)
        cancelRegionDefect(frame)
        if let cached = frame.cleanedRawDiskURL,
           diskStorage.cleanedRawKnownDirectories.contains(where: {
               CleanedRawCacheFile.isOwnedCacheURL(cached, frameID: frame.id, directory: $0)
           }) {
            try? FileManager.default.removeItem(at: cached)
        }
        CleanedRawCacheFile.removeAll(
            for: frame.id,
            additionalDirectories: diskStorage.cleanedRawKnownDirectories
        )
        frame.cleanedRawImage = nil
        frame.cleanedRawMemoryIdentity = nil
        frame.cleanedRawAppliedStamps = []
        frame.cleanedRawDiskURL = nil
        frame.cleanedRawDiskIdentity = nil
        frame.cleanedRawEditCount = 0
        frame.cleanedRawPreviousImage = nil
        frame.cleanedRawPreviousEditCount = -1
        frame.cleanedRawPreviousIdentity = nil
        frame.stripDefectPatchCaches()
        frameCacheManager.removeCleanedRawResident(frame)
        evictDevelopBuffers(frame)
        frame.cachedBaseKey = nil
        frame.cachedBase = nil
        frame.baseRGB = nil
        frame.hasDevelopedOnce = false
    }

    private func recoverMovedSourcesFromBookmarks() -> Int {
        var mappingsByOldPath: [String: SourceRelinkPlan.Mapping] = [:]
        for frame in frames where !frame.isSourceAvailable {
            let location = SourceBookmark.resolve(
                frame.rawScanBookmarkData,
                fallbackURL: frame.rawScanURL
            )
            guard FileManager.default.fileExists(atPath: location.url.path),
                  location.url.standardizedFileURL.path != frame.rawScanURL.standardizedFileURL.path,
                  Self.isReadableRelinkTarget(location.url) else { continue }
            mappingsByOldPath[frame.rawScanURL.standardizedFileURL.path] = .init(
                oldSourceURL: frame.rawScanURL,
                newSourceURL: location.url
            )
        }
        guard !mappingsByOldPath.isEmpty else { return 0 }
        let plan = SourceRelinkPlan(
            mappings: mappingsByOldPath.values.sorted {
                $0.oldSourceURL.path.localizedStandardCompare($1.oldSourceURL.path) == .orderedAscending
            }
        )
        return applySourceRelink(plan).sourceCount
    }

    private func updateRegisteredFolder(
        for plan: SourceRelinkPlan,
        allMappingsApplied: Bool
    ) {
        guard let oldFolderURL = plan.oldFolderURL,
              let newFolderURL = plan.newFolderURL else { return }
        let oldPath = LibraryPresentation.normalizedFolderPath(oldFolderURL)
        if plan.isComplete,
           allMappingsApplied,
           let index = libraryFolders.firstIndex(where: {
               LibraryPresentation.normalizedFolderPath($0.url) == oldPath
           }) {
            let previous = libraryFolders[index]
            libraryFolders[index] = LibraryFolder(
                id: previous.id,
                url: newFolderURL,
                addedAt: previous.addedAt
            )
        } else {
            registerLibraryFolder(newFolderURL)
        }
    }

    private static func isReadableRelinkTarget(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true,
              (values.fileSize ?? 0) > 0,
              isSupportedImport(url) else { return false }
        return CGImageSourceCreateWithURL(url as CFURL, nil) != nil
    }

    private static func isCompatibleRelinkMetadata(
        _ metadata: SourceMetadataSnapshot,
        with frame: ScanFrame
    ) -> Bool {
        guard metadata.fileTypeIdentifier != nil,
              let width = metadata.pixelWidth,
              let height = metadata.pixelHeight,
              width > 0,
              height > 0,
              metadata.imageCount.map({ $0 > metadata.imageIndex }) ?? false else {
            return false
        }

        if let existing = frame.sourceMetadata {
            guard equalWhenKnown(existing.fileTypeIdentifier, metadata.fileTypeIdentifier),
                  equalWhenKnown(existing.fileSizeBytes, metadata.fileSizeBytes),
                  equalWhenKnown(existing.imageCount, metadata.imageCount),
                  existing.imageIndex == metadata.imageIndex,
                  equalWhenKnown(existing.pixelWidth, metadata.pixelWidth),
                  equalWhenKnown(existing.pixelHeight, metadata.pixelHeight),
                  equalWhenKnown(
                    existing.bitsPerColorSample,
                    metadata.bitsPerColorSample
                  ) else {
                return false
            }
        }

        guard equalWhenKnown(frame.sourcePixelWidth, metadata.pixelWidth),
              equalWhenKnown(frame.sourcePixelHeight, metadata.pixelHeight),
              equalWhenKnown(frame.sourceBitDepth, metadata.bitsPerColorSample) else {
            return false
        }
        if frame.sourceKind == .importedFile,
           !equalWhenKnown(frame.sourceResolutionDPI, metadata.resolutionDPI) {
            return false
        }
        return true
    }

    private static func equalWhenKnown<T: Equatable>(_ lhs: T?, _ rhs: T?) -> Bool {
        guard let lhs, let rhs else { return true }
        return lhs == rhs
    }
}
