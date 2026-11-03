import Chromabase

extension AppModel {
    @discardableResult
    func configureLibraryFolderDevelopment(
        process: DevelopmentProcess,
        target: DevelopTarget,
        frames requestedFrames: [ScanFrame]
    ) -> [ScanFrame] {
        let newFilmType = process.filmType
        let frames = requestedFrames.filter { ownsFrame($0) && !$0.isPreviewScan }
        return frames.map { frame in
            let compatibleProfileID: String? = frame.params.scannerProfileID.flatMap { profileID in
                guard !target.isScannerEmulation else { return nil }
                return ScannerProfileMatcher.matchingProfiles(
                    target: target,
                    filmType: newFilmType,
                    profiles: scannerProfiles
                ).contains(where: { $0.id == profileID }) ? profileID : nil
            }
            let isDigitalSource = process.isDigitalSource ? true : nil
            frame.filmType = newFilmType
            frame.showDeveloped = true
            frame.updateParams {
                $0.filmType = newFilmType
                $0.isDigitalSource = isDigitalSource
                $0.developTarget = target
                $0.scannerProfileID = compatibleProfileID
            }
            return frame
        }
    }

    @discardableResult
    func applyLibraryFolderDevelopment(
        process: DevelopmentProcess,
        target: DevelopTarget,
        frames requestedFrames: [ScanFrame],
        progress: (@MainActor (LibraryTaskProgress) -> Void)? = nil
    ) -> Task<Void, Never> {
        let frames = requestedFrames.filter { ownsFrame($0) && !$0.isPreviewScan }
        // 사용자가 Apply를 누른 시점에 선택을 먼저 기록한다. 렌더 슬롯을 기다린 뒤 기록하면,
        // 그 사이 Develop에서 더 최근에 고른 프로세스/타깃을 오래된 폴더 작업이 덮어쓴다.
        let configuredFrames = configureLibraryFolderDevelopment(
            process: process,
            target: target,
            frames: frames
        )
        progress?(LibraryTaskProgress(completedCount: 0, totalCount: frames.count))
        let previousTask = sequentialLibraryDevelopmentTask
        let task = Task { [weak self] in
            await previousTask?.value
            guard let self, !Task.isCancelled else { return }

            var nextIndex = 0
            var completedCount = 0
            await withTaskGroup(of: Void.self) { group in
                func enqueueNext() {
                    guard nextIndex < configuredFrames.count else { return }
                    let frame = configuredFrames[nextIndex]
                    nextIndex += 1
                    group.addTask { [weak self, weak frame] in
                        guard let self, let frame, !Task.isCancelled else { return }
                        await self.developLibraryFolderFrame(frame)
                    }
                }

                for _ in 0..<min(
                    self.developController.maxConcurrentDevelopments,
                    configuredFrames.count
                ) {
                    enqueueNext()
                }
                while await group.next() != nil {
                    completedCount += 1
                    progress?(LibraryTaskProgress(
                        completedCount: completedCount,
                        totalCount: frames.count
                    ))
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }
                    enqueueNext()
                }
            }
        }
        sequentialLibraryDevelopmentTask = task
        return task
    }

    private func developLibraryFolderFrame(
        _ frame: ScanFrame
    ) async {
        guard ownsFrame(frame) else { return }
        await waitForExistingDevelopmentToFinish(frame)
        guard !Task.isCancelled, ownsFrame(frame) else { return }
        if let seed = frame.initialThumbnailSeedTask {
            await seed.value
        }
        guard !Task.isCancelled, ownsFrame(frame) else { return }
        await developFrame(
            frame,
            preserveThumbnail: false,
            skipInteractivePreview: true
        )
    }

    @discardableResult
    func developImportedFramesSequentially(_ requestedFrames: [ScanFrame]) -> Task<Void, Never> {
        let frames = requestedFrames.filter { ownsFrame($0) && !$0.isPreviewScan }
        let previousTask = sequentialLibraryDevelopmentTask
        let task = Task { [weak self] in
            await previousTask?.value
            guard let self, !Task.isCancelled else { return }
            for frame in frames {
                guard !Task.isCancelled, self.ownsFrame(frame) else { continue }
                await self.waitForExistingDevelopmentToFinish(frame)
                guard !Task.isCancelled, self.ownsFrame(frame) else { continue }
                await self.developFrameAfterFastPreview(frame)
            }
        }
        sequentialLibraryDevelopmentTask = task
        return task
    }

    /// 복원 때 빠진 현상 썸네일을 채운다. 필름스트립에 보이는 고른 사진 근처부터, 사용자가 사진을
    /// 현상하는 동안에는 비켜 주면서 만든다. 현상 슬롯 하나는 사용자 선택 몫으로 비워 둔다.
    @discardableResult
    func refreshThumbnailsInBackground(_ requestedFrames: [ScanFrame]) -> Task<Void, Never> {
        let order = Dictionary(self.frames.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let anchor = selectedFrameID.flatMap { order[$0] } ?? 0
        let frames = requestedFrames
            .filter { ownsFrame($0) && !$0.isPreviewScan }
            .sorted {
                let left = order[$0.id] ?? .max, right = order[$1.id] ?? .max
                let leftDistance = abs(left - anchor), rightDistance = abs(right - anchor)
                return leftDistance == rightDistance ? left < right : leftDistance < rightDistance
            }
        let previousTask = sequentialLibraryDevelopmentTask
        let task = Task { [weak self] in
            await previousTask?.value
            guard let self else { return }
            let width = max(1, self.developController.maxConcurrentDevelopments - 1)
            for start in stride(from: 0, to: frames.count, by: width) {
                while self.developController.isDevelopingAnyFrame, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard !Task.isCancelled else { return }
                await withTaskGroup(of: Void.self) { group in
                    for frame in frames[start..<min(start + width, frames.count)] {
                        group.addTask { await self.refreshThumbnailOnly(frame) }
                    }
                }
            }
        }
        sequentialLibraryDevelopmentTask = task
        return task
    }

    private func waitForExistingDevelopmentToFinish(_ frame: ScanFrame) async {
        while developController.isDevelopingFrame(frame) {
            guard !Task.isCancelled, ownsFrame(frame) else { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
