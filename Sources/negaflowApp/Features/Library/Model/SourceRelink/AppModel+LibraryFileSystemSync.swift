import Foundation

private struct LibraryFileSystemFrameLocation: Sendable {
    let oldURL: URL
    let bookmarkData: Data?
}

private struct LibraryFileSystemRefreshPreparation: Sendable {
    let mappings: [SourceRelinkPlan.Mapping]
    /// 사라졌지만 새 위치를 찾지 못한 원본이 있는지. 있으면 오프라인 표시를 갱신해야 한다.
    let hasMissingSources: Bool

    var isEmpty: Bool { mappings.isEmpty && !hasMissingSources }
}

extension AppModel {
    func updateLibraryFileSystemMonitoring() {
        let uniqueCandidateURLs = Dictionary(
            grouping: libraryFolders.map(\.url)
                + frames.map { $0.rawScanURL.deletingLastPathComponent().standardizedFileURL },
            by: { $0.standardizedFileURL.path }
        )
        .values
        .compactMap(\.first)
        let urls = Dictionary(
            grouping: uniqueCandidateURLs,
            by: { LibraryPresentation.normalizedFolderPath($0) }
        )
        .values
        .compactMap(\.first)
        .filter(Self.isDirectory)
        libraryFileSystemMonitor.update(folderURLs: urls) { [weak self] folderURL in
            Task { @MainActor [weak self] in
                self?.scheduleLibraryFileSystemRefresh(for: folderURL)
            }
        }
    }

    func scheduleLibraryFileSystemRefresh(for folderURL: URL) {
        pendingLibraryFileSystemRefreshPaths.insert(
            LibraryPresentation.normalizedFolderPath(folderURL)
        )
        libraryFileSystemRefreshTask?.cancel()
        libraryFileSystemRefreshTask = Task { [weak self] in
            // iCloud 다운로드처럼 폴더에 쓰기가 쏟아질 때 이벤트마다 확인하지 않도록 넉넉히 모은다.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            let paths = pendingLibraryFileSystemRefreshPaths
            pendingLibraryFileSystemRefreshPaths.removeAll()
            await synchronizeLibraryAfterFileSystemChanges(
                in: paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
            )
        }
    }

    func synchronizeLibraryAfterFileSystemChanges(in changedFolders: [URL]) async {
        guard !changedFolders.isEmpty else { return }
        guard allowsLibraryMutation, !isAcknowledgedLibraryTransactionActive else {
            for folder in changedFolders {
                pendingLibraryFileSystemRefreshPaths.insert(
                    LibraryPresentation.normalizedFolderPath(folder)
                )
            }
            libraryFileSystemRefreshTask?.cancel()
            libraryFileSystemRefreshTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self else { return }
                let paths = pendingLibraryFileSystemRefreshPaths
                pendingLibraryFileSystemRefreshPaths.removeAll()
                await synchronizeLibraryAfterFileSystemChanges(
                    in: paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
                )
            }
            return
        }

        let changedPaths = Set(changedFolders.map {
            LibraryPresentation.normalizedFolderPath($0)
        })
        // 바뀐 폴더에 속한 우리 원본 전부를 후보로 넘긴다. "지금 사라졌는지"는 detached 에서
        // 직접 확인한다 — 캐시된 가용성에 기대면 이동을 한 박자 늦게 알아채고, MainActor 에서
        // 파일을 stat 하면 iCloud 다운로드처럼 폴더 이벤트가 쏟아질 때 UI 가 그대로 멈춘다.
        let locations = Dictionary(
            grouping: frames.filter {
                changedPaths.contains(LibraryPresentation.normalizedFolderPath(
                    $0.rawScanURL.deletingLastPathComponent()
                ))
            },
            by: { $0.rawScanURL.standardizedFileURL.path }
        )
        .values
        .compactMap(\.first)
        .map {
            LibraryFileSystemFrameLocation(
                oldURL: $0.rawScanURL.standardizedFileURL,
                bookmarkData: $0.rawScanBookmarkData
            )
        }
        guard !locations.isEmpty else { return }
        let preparation = await Task.detached(priority: .utility) {
            Self.prepareLibraryFileSystemRefresh(locations: locations)
        }.value
        guard !Task.isCancelled, allowsLibraryMutation else { return }
        // 우리 원본은 그대로인데 폴더만 바뀐 경우(대표적으로 iCloud 가 다른 파일을 내려받는
        // 중)에는 아무 일도 하지 않는다. 여기서 매번 전체 가용성을 다시 재면 다운로드가 끝날
        // 때까지 메인 스레드가 잡힌다.
        guard !preparation.isEmpty else { return }

        var relinkedCount = 0
        for mappings in Dictionary(
            grouping: preparation.mappings,
            by: { LibraryPresentation.normalizedFolderPath(
                $0.oldSourceURL.deletingLastPathComponent()
            ) }
        ).values {
            guard let firstMapping = mappings.first else { continue }
            let oldFolder = firstMapping.oldSourceURL.deletingLastPathComponent()
                .standardizedFileURL
            let oldSourcePaths = Set(frames.compactMap { frame -> String? in
                LibraryPresentation.normalizedFolderPath(
                    frame.rawScanURL.deletingLastPathComponent()
                ) == LibraryPresentation.normalizedFolderPath(oldFolder)
                    ? frame.rawScanURL.standardizedFileURL.path
                    : nil
            })
            let mappedOldPaths = Set(mappings.map {
                $0.oldSourceURL.standardizedFileURL.path
            })
            let newFolders = Set(mappings.map {
                LibraryPresentation.normalizedFolderPath(
                    $0.newSourceURL.deletingLastPathComponent()
                )
            })
            let registeredFolderWasMoved = !Self.isDirectory(oldFolder)
                && oldSourcePaths == mappedOldPaths
                && newFolders.count == 1
                && libraryFolders.contains {
                    LibraryPresentation.normalizedFolderPath($0.url)
                        == LibraryPresentation.normalizedFolderPath(oldFolder)
                }
            let plan = SourceRelinkPlan(
                mappings: mappings,
                oldFolderURL: registeredFolderWasMoved ? oldFolder : nil,
                newFolderURL: registeredFolderWasMoved
                    ? mappings[0].newSourceURL.deletingLastPathComponent()
                    : nil
            )
            relinkedCount += applySourceRelink(plan, reprocess: false).sourceCount
        }

        refreshSourceAvailability()
        updateLibraryFileSystemMonitoring()
        // 감시는 "이미 가져온 원본이 어디로 갔는지"만 따라간다. 폴더에 새로 생긴 파일을
        // 자동으로 가져오지 않는다 — 한 장만 가져온 폴더의 나머지가 통째로 딸려 오던 경로다.
        // 폴더 전체를 원할 때는 폴더 가져오기 또는 라이브러리 새로고침이 명시적 진입점이다.
        guard relinkedCount > 0 || offlineSourceCount > 0 else { return }
        statusMessage = text(
            AppLocalizedPhrase.libraryRefreshStatusFormat,
            0,
            relinkedCount,
            offlineSourceCount
        )
    }

    private nonisolated static func prepareLibraryFileSystemRefresh(
        locations: [LibraryFileSystemFrameLocation]
    ) -> LibraryFileSystemRefreshPreparation {
        var mappings: [SourceRelinkPlan.Mapping] = []
        var hasMissingSources = false
        for location in locations {
            guard !FileManager.default.fileExists(atPath: location.oldURL.path) else { continue }
            hasMissingSources = true
            let resolved = SourceBookmark.resolve(
                location.bookmarkData,
                fallbackURL: location.oldURL
            ).url.standardizedFileURL
            guard resolved != location.oldURL,
                  FileManager.default.fileExists(atPath: resolved.path) else { continue }
            mappings.append(.init(
                oldSourceURL: location.oldURL,
                newSourceURL: resolved
            ))
        }

        return LibraryFileSystemRefreshPreparation(
            mappings: mappings,
            hasMissingSources: hasMissingSources
        )
    }
}
