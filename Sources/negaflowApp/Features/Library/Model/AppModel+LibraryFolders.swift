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
            importFolders(urls: folders)
        }
        if !files.isEmpty {
            importImages(urls: files)
        }
    }

    func importFolders(urls: [URL]) {
        guard allowsLibraryMutation else { return }
        var importedImageCount = 0
        var emptyFolderCount = 0

        for url in urls {
            registerLibraryFolder(url)
            let files = Self.importableImageFiles(in: url)
            if files.isEmpty {
                emptyFolderCount += 1
            } else {
                importedImageCount += files.count
                // 폴더 가져오기는 디스크 저장(썸네일/내보내기)의 출처 폴더명으로 원본 폴더명을 쓴다.
                let group = FrameStorageNaming.sanitizeComponent(url.lastPathComponent)
                importImages(
                    urls: files,
                    groupName: group.isEmpty ? FrameStorageNaming.defaultImportGroup : group
                )
            }
        }

        if importedImageCount > 0 {
            statusMessage = text(AppLocalizedPhrase.folderImportCompleteFormat, importedImageCount, urls.count)
        } else if emptyFolderCount > 0 {
            statusMessage = text(AppLocalizedPhrase.folderImportCompleteEmptyFormat, emptyFolderCount)
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

    func registerLibraryFolders(for urls: [URL]) {
        let folders = Set(urls.map { $0.deletingLastPathComponent().standardizedFileURL })
        for folder in folders.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
            registerLibraryFolder(folder)
        }
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

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    static func importableImageFiles(in folder: URL) -> [URL] {
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
