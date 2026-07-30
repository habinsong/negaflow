import AppKit
import Foundation

extension AppModel {
    func presentCreateLibraryFolder(in parentFolder: URL? = nil) {
        guard allowsLibraryMutation else { return }
        let alert = NSAlert()
        alert.messageText = text(AppLocalizedPhrase.newFolder)
        alert.addButton(withTitle: text(AppLocalizedPhrase.create))
        alert.addButton(withTitle: text(AppLocalizedPhrase.cancel))

        let nameField = NSTextField(string: text(AppLocalizedPhrase.untitledFilm))
        nameField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        nameField.selectText(nil)
        alert.accessoryView = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        _ = createLibraryFolder(
            named: nameField.stringValue,
            in: parentFolder ?? defaultLibraryFolderCreationParent()
        )
    }

    func defaultLibraryFolderCreationParent(selectedFolderID: String? = nil) -> URL {
        if let selectedFolderID, !selectedFolderID.isEmpty {
            return URL(fileURLWithPath: selectedFolderID, isDirectory: true)
                .standardizedFileURL
                .deletingLastPathComponent()
        }
        return diskStorage.scansURL
            .appendingPathComponent(
                FrameStorageNaming.dateFolderName(),
                isDirectory: true
            )
            .appendingPathComponent(
                FrameStorageNaming.filmTypeFolderName(scanFilmType),
                isDirectory: true
            )
    }

    @discardableResult
    func createLibraryFolder(named requestedName: String, in parentFolder: URL) -> URL? {
        guard allowsLibraryMutation else { return nil }
        let parent = parentFolder.standardizedFileURL
        let sanitizedName = FrameStorageNaming.sanitizeComponent(requestedName)
        let name = FrameStorageNaming.availableFilmFolderName(
            sanitizedName.isEmpty ? text(AppLocalizedPhrase.untitledFilm) : sanitizedName,
            in: parent
        )
        let folder = parent.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )
        } catch {
            statusMessage = text(AppLocalizedPhrase.folderCreateFailedStatus)
            return nil
        }
        registerLibraryFolder(folder)
        diskStorage.recentCreatedScanFolderPath = folder.path
        statusMessage = text(AppLocalizedPhrase.folderCreatedStatusFormat, folder.lastPathComponent)
        return folder
    }

    func revealLibraryFolderInFinder(_ folder: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([folder.standardizedFileURL])
    }

    func revealSourceFilesInFinder(_ frames: [ScanFrame]) {
        let sourceURLs = Dictionary(
            grouping: frames.map(\.rawScanURL).map(\.standardizedFileURL),
            by: \.path
        )
        .values
        .compactMap(\.first)
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard !sourceURLs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(sourceURLs)
    }

    var recentCreatedScanFolder: URL? {
        guard let folder = diskStorage.recentCreatedScanFolderURL?.standardizedFileURL,
              Self.isDirectory(folder),
              libraryFolders.contains(where: {
                  LibraryPresentation.normalizedFolderPath($0.url)
                      == LibraryPresentation.normalizedFolderPath(folder)
              }) else {
            return nil
        }
        return folder
    }

    func presentImportFolderPanel() {
        guard allowsLibraryMutation else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.resolvesAliases = true
        panel.prompt = text(AppLocalizedPhrase.importFolder)
        panel.message = text(AppLocalizedPhrase.folderImportPanelMessage)
        guard panel.runModal() == .OK else { return }
        importFolders(urls: panel.urls)
    }

    func importURLs(_ urls: [URL]) {
        guard allowsLibraryMutation else { return }
        let folders = urls.filter { Self.isDirectory($0) }
        let files = urls.filter { !Self.isDirectory($0) }
        if !folders.isEmpty {
            let folderTask = importFolders(urls: folders)
            if !files.isEmpty {
                Task { [weak self] in
                    await folderTask.value
                    await self?.importImagesWithProgress(urls: files)
                }
            }
        } else if !files.isEmpty {
            Task { [weak self] in
                await self?.importImagesWithProgress(urls: files)
            }
        }
    }

    @discardableResult
    func importFolders(urls: [URL]) -> Task<Void, Never> {
        guard allowsLibraryMutation else { return Task {} }
        return Task { [weak self] in
            let prepared = await Task.detached(priority: .userInitiated) {
                urls.map { url in
                    let files = Self.importableImageFiles(in: url)
                    return PreparedFolderImport(
                        url: url,
                        files: files
                    )
                }
            }.value
            guard let self, self.allowsLibraryMutation else { return }
            var importedImageCount = 0
            var emptyFolderCount = 0
            var allFiles: [URL] = []
            var groupNamesByIdentity: [String: String] = [:]
            allFiles.reserveCapacity(prepared.reduce(0) { $0 + $1.files.count })
            groupNamesByIdentity.reserveCapacity(allFiles.capacity)

            for item in prepared {
                self.registerLibraryFolder(item.url)
                if item.files.isEmpty {
                    emptyFolderCount += 1
                } else {
                    importedImageCount += item.files.count
                    let group = FrameStorageNaming.sanitizeComponent(item.url.lastPathComponent)
                    let storageGroup = group.isEmpty
                        ? FrameStorageNaming.defaultImportGroup
                        : group
                    allFiles.append(contentsOf: item.files)
                    for file in item.files {
                        groupNamesByIdentity[Self.importIdentity(file)] = storageGroup
                    }
                }
            }
            if !allFiles.isEmpty {
                // 전체 폴더를 한 번에 append해 FrameStore 재색인·observation 갱신·카탈로그 예약을
                // 폴더 수만큼 반복하지 않는다. 파일별 원본 폴더명은 identity 맵이 보존한다.
                await self.importImagesWithProgress(
                    urls: allFiles,
                    groupNamesByIdentity: groupNamesByIdentity
                )
            }

            if importedImageCount > 0 {
                self.statusMessage = self.text(
                    AppLocalizedPhrase.folderImportCompleteFormat,
                    importedImageCount,
                    urls.count
                )
            } else if emptyFolderCount > 0 {
                self.statusMessage = self.text(
                    AppLocalizedPhrase.folderImportCompleteEmptyFormat,
                    emptyFolderCount
                )
            }
        }
    }

    func registerLibraryFolder(_ url: URL) {
        let folderURL = url.standardizedFileURL
        let path = LibraryPresentation.normalizedFolderPath(folderURL)
        guard !libraryFolders.contains(where: { LibraryPresentation.normalizedFolderPath($0.url) == path }) else {
            return
        }
        libraryFolders.append(LibraryFolder(url: folderURL))
        scheduleLibrarySave()
    }

    /// 폴더 등록과 그 폴더에 속한 프레임만 카탈로그에서 제거한다. 실제 폴더/파일은 유지한다.
    func removeLibraryFolder(_ folder: LibraryFolder) {
        guard allowsLibraryMutation else { return }
        let path = LibraryPresentation.normalizedFolderPath(folder.url)
        let framesInFolder = frames.filter {
            LibraryPresentation.normalizedFolderPath(LibraryPresentation.folderURL(for: $0)) == path
        }
        removeFramesFromLibrary(framesInFolder, restoringFoldersOnUndo: [folder])
        libraryFolders.removeAll {
            LibraryPresentation.normalizedFolderPath($0.url) == path
        }
        if diskStorage.recentCreatedScanFolderURL.map({
            LibraryPresentation.normalizedFolderPath($0) == path
        }) == true {
            diskStorage.recentCreatedScanFolderPath = nil
        }
        scheduleLibrarySave()
    }

    /// 명시적으로 등록되지 않고 원본 경로에서 파생된 폴더 행도 동일하게 라이브러리에서
    /// 제거한다. 해당 경로의 프레임만 카탈로그에서 제거하며 실제 폴더와 원본 파일은 유지한다.
    func removeLibraryFolderSection(_ section: LibraryFolderSection) {
        if let folder = section.folder {
            removeLibraryFolder(folder)
            return
        }
        guard allowsLibraryMutation else { return }
        let path = LibraryPresentation.normalizedFolderPath(
            URL(fileURLWithPath: section.id, isDirectory: true)
        )
        let framesInFolder = frames.filter {
            LibraryPresentation.normalizedFolderPath(LibraryPresentation.folderURL(for: $0)) == path
        }
        removeFramesFromLibrary(framesInFolder)
    }

    nonisolated static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    nonisolated static func importableImageFiles(in folder: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.filter { url in
            let values = try? url.resourceValues(forKeys: keys)
            return values?.isRegularFile == true && values?.isHidden != true && isSupportedImport(url)
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

private struct PreparedFolderImport: Sendable {
    let url: URL
    let files: [URL]
}
