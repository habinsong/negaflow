import AppKit
import Chromabase
import Foundation

enum PrintPackagePreviewResolution {
    static let maximumDimension = DevelopFrameRenderer.interactiveMaxDimension

    static func pixelDimension(of image: NSImage?) -> CGFloat {
        guard let image else { return 0 }
        let representationDimension = image.representations.reduce(CGFloat.zero) { result, representation in
            max(result, CGFloat(max(representation.pixelsWide, representation.pixelsHigh)))
        }
        if representationDimension > 0 {
            return representationDimension
        }
        return max(image.size.width, image.size.height)
    }

    static func requiredDisplayDimension(_ displayTargetPixels: CGFloat) -> CGFloat {
        guard displayTargetPixels.isFinite, displayTargetPixels > 0 else { return 0 }
        return min(displayTargetPixels, maximumDimension)
    }

    static func renderDimension(for displayTargetPixels: CGFloat) -> CGFloat {
        let required = requiredDisplayDimension(displayTargetPixels)
        guard required > 0 else { return 0 }
        let step = DevelopFrameRenderer.interactiveDimensionStep
        let quantized = (required / step).rounded(.up) * step
        return min(
            max(quantized, DevelopFrameRenderer.fastPreviewMaxDimension),
            maximumDimension
        )
    }

    static func needsUpgrade(_ image: NSImage?, displayTargetPixels: CGFloat) -> Bool {
        let required = requiredDisplayDimension(displayTargetPixels)
        return required > 0 && pixelDimension(of: image) + 0.5 < required
    }

    static func bestImage(
        developed: NSImage?,
        packagePreview: NSImage?,
        thumbnail: NSImage?,
        raw: NSImage?
    ) -> NSImage? {
        let positiveCandidates = [developed, packagePreview, thumbnail].compactMap { $0 }
        guard var best = positiveCandidates.first else { return raw }
        var bestDimension = pixelDimension(of: best)
        for candidate in positiveCandidates.dropFirst() {
            let dimension = pixelDimension(of: candidate)
            if dimension > bestDimension {
                best = candidate
                bestDimension = dimension
            }
        }
        return best
    }
}

extension AppModel {
    /// "사진 비율" 용지가 따라갈 가로세로비. 기준은 지금 보고 있는 사진이다.
    var printPaperPhotoAspectRatio: Double? {
        guard let frame = actionableFrame,
              let size = printPackageLayoutSize(for: frame),
              size.width > 0,
              size.height > 0 else { return nil }
        return Double(size.width / size.height)
    }

    /// 인화 화면과 내보내기가 같은 용지를 쓰도록 구성 설정을 한 곳에서 만든다.
    func printCompositionSettings(dpi: Int) -> PrintCompositionSettings {
        printWorkspaceSettingsStore.compositionSettings(
            dpi: dpi,
            photoAspectRatio: printPaperPhotoAspectRatio
        )
    }

    /// 시트 방향 통일이 켜져 있을 때, 사진마다 배치 단계에서 더 돌려야 할 90° 횟수.
    /// 표시 중인 그림은 프레임의 회전이 이미 적용된 상태이므로, 스캔 기본 방향까지의 차이만 돌린다.
    /// 프레임 자체(현상뷰·인화 단일 레이아웃)의 방향은 그대로 둔다.
    func printPackageForcedQuarterTurns(
        for frames: [ScanFrame],
        package: PrintPackageSettings
    ) -> [Int]? {
        guard package.normalizesSourceOrientation else { return nil }
        let target = defaultScanRotation.rawValue
        return frames.map { frame in
            ((target - frame.imageTransform.rotation.rawValue) % 4 + 4) % 4
        }
    }

    /// 지금 화면이 여러 장을 한 시트에 늘어놓는 인화 패키지 레이아웃인가.
    var usesPrintPackageLayout: Bool {
        activeWorkspaceModule == .print
            && printWorkspaceSettingsStore.layoutMode != .singleImage
    }

    /// 인화 패키지(콘택트 시트·픽처 패키지·커스텀) 시트에 올라간 프레임들의 **가벼운** 미리보기를
    /// 채운다.
    ///
    /// 시트의 셀은 작다. 장마다 인터랙티브 + 정착 풀해상도 현상을 돌리면 선택이 조금만 늘어도
    /// 화면이 뚝뚝 끊긴다. 여기서는 보여줄 그림이 아예 없는 프레임만, 썸네일 크기의 프리뷰
    /// 한 장으로 채운다. 이미 썸네일이나 현상 결과가 있으면 그대로 재활용한다.
    @discardableResult
    func preparePrintPackagePreviews(for requestedFrames: [ScanFrame]) -> Task<Void, Never>? {
        let pending = requestedFrames.filter { frame in
            ownsFrame(frame)
                && !frame.isPreviewScan
                && isSourceAvailable(frame)
                && frame.thumbnailImage == nil
                && frame.developedImage == nil
                && frame.rawPreviewImage == nil
        }
        guard !pending.isEmpty else { return nil }

        let previousTask = printPackagePreviewTask
        let task = Task { [weak self] in
            await previousTask?.value
            guard let self, !Task.isCancelled else { return }
            for frame in pending {
                guard !Task.isCancelled, self.ownsFrame(frame) else { continue }
                // 시드가 이미 돌고 있으면 그 결과를 기다린다 — 같은 파일을 두 번 읽지 않는다.
                if let seed = frame.initialThumbnailSeedTask {
                    await seed.value
                }
                guard !Task.isCancelled, self.ownsFrame(frame) else { continue }
                await self.seedFastPreview(frame)
            }
        }
        printPackagePreviewTask = task
        return task
    }

    /// 패키지 셀이 실제로 차지하는 Retina 픽셀보다 현재 래스터가 작을 때만 표시용 프리뷰를
    /// 올린다. 작은 셀은 360px 썸네일을 그대로 사용하고, 큰 셀도 1600px 상한을 둬 선택 전체를
    /// 풀해상도로 현상하던 과거 경로의 지연과 메모리 피크를 되살리지 않는다.
    func preparePrintPackageDisplayPreview(
        for frame: ScanFrame,
        displayTargetPixels: CGFloat
    ) async {
        guard !isPrintPackageExporting,
              ownsFrame(frame),
              !frame.isPreviewScan,
              isSourceAvailable(frame) else { return }
        let currentImage = printPackageDisplayImage(for: frame)
        guard PrintPackagePreviewResolution.needsUpgrade(
            currentImage,
            displayTargetPixels: displayTargetPixels
        ) else { return }
        let targetDimension = PrintPackagePreviewResolution.renderDimension(
            for: displayTargetPixels
        )
        guard targetDimension > 0 else { return }

        if let existingTask = frame.printPackagePreviewTask {
            await existingTask.value
            guard !Task.isCancelled, ownsFrame(frame) else { return }
            let refreshedImage = printPackageDisplayImage(for: frame)
            guard PrintPackagePreviewResolution.needsUpgrade(
                refreshedImage,
                displayTargetPixels: displayTargetPixels
            ) else { return }
        }

        frame.printPackagePreviewGeneration &+= 1
        let generation = frame.printPackagePreviewGeneration
        let developRevision = frame.developRevision
        let cleanRawRevision = frame.cleanRawRevision
        let sourceLocationRevision = frame.sourceLocationRevision
        let transform = frame.imageTransform
        let proofRevision = softProofConfigurationRevision

        let task = Task(priority: .utility) { [weak self, weak frame] in
            guard let self, let frame, !Task.isCancelled,
                  !self.isPrintPackageExporting,
                  self.activeWorkspaceModule == .print,
                  self.ownsFrame(frame) else { return }
            if let seed = frame.initialThumbnailSeedTask {
                await seed.value
            }
            guard !Task.isCancelled,
                  self.ownsFrame(frame),
                  await self.materializeDevelopSourceIfNeeded(frame),
                  await self.prepareCleanedRawForConsumption(frame),
                  !Task.isCancelled,
                  !self.isPrintPackageExporting,
                  self.ownsFrame(frame),
                  await self.developController.acquireDevelopSlot() else { return }
            defer { self.developController.releaseDevelopSlot() }

            let baseKey = FilmBaseCacheKey(
                filmType: frame.filmType,
                mode: frame.params.baseEstimationMode,
                manualBaseRGB: frame.params.manualBaseRGB,
                filmStockDminID: frame.params.filmStockDminID,
                lightSourceProfileID: frame.params.lightSourceProfileID
            )
            let snapshot = self.makeSnapshot(
                for: frame,
                baseKey: baseKey,
                needsRawPreview: false,
                needsNeutralPreview: false,
                needsDebugPreviews: false,
                needsThumbnail: false,
                proxyMaxDimension: targetDimension
            )

            do {
                let renderTask = Task.detached(priority: .utility) {
                    try DevelopFrameRenderer.renderFastPreview(snapshot)
                }
                let result = try await withTaskCancellationHandler {
                    try await renderTask.value
                } onCancel: {
                    renderTask.cancel()
                }
                guard !Task.isCancelled,
                      !self.isPrintPackageExporting,
                      self.activeWorkspaceModule == .print,
                      self.ownsFrame(frame),
                      frame.printPackagePreviewGeneration == generation,
                      frame.developRevision == developRevision,
                      frame.cleanRawRevision == cleanRawRevision,
                      frame.sourceLocationRevision == sourceLocationRevision,
                      frame.imageTransform == transform,
                      self.softProofConfigurationRevision == proofRevision else { return }
                frame.printPackagePreviewImage = NSImage(
                    cgImage: result.preview,
                    size: NSSize(width: result.preview.width, height: result.preview.height)
                )
                frame.printPackagePreviewDevelopRevision = developRevision
                frame.printPackagePreviewCleanRawRevision = cleanRawRevision
                frame.printPackagePreviewSourceLocationRevision = sourceLocationRevision
                frame.printPackagePreviewTransform = transform
                frame.printPackagePreviewSoftProofRevision = proofRevision
                frame.printPackagePreviewTargetDimension = targetDimension
            } catch {
                return
            }
        }
        frame.printPackagePreviewTask = task
        frame.printPackagePreviewTargetDimension = targetDimension
        await task.value
        if frame.printPackagePreviewGeneration == generation {
            frame.printPackagePreviewTask = nil
        }
    }

    func printPackageDisplayImage(for frame: ScanFrame) -> NSImage? {
        PrintPackagePreviewResolution.bestImage(
            developed: frame.developedImage,
            packagePreview: validPrintPackagePreviewImage(for: frame),
            thumbnail: frame.thumbnailImage,
            raw: frame.rawPreviewImage
        )
    }

    func discardPrintPackagePreviews() {
        cancelPrintPackagePreviewTasks()
        for frame in frames {
            frame.printPackagePreviewImage = nil
            frame.printPackagePreviewDevelopRevision = -1
            frame.printPackagePreviewCleanRawRevision = -1
            frame.printPackagePreviewTransform = nil
            frame.printPackagePreviewSoftProofRevision = nil
            frame.printPackagePreviewTargetDimension = 0
        }
    }

    /// 내보내기는 전용 페이지 렌더러만 사용한다. 시작 직전에 표시용 작업을 끊어 원본 준비,
    /// 현상 슬롯과 GPU가 Export/Quick Export와 경쟁하지 않게 하되 완성된 화면 캐시는 유지한다.
    func cancelPrintPackagePreviewTasks() {
        printPackagePreviewTask?.cancel()
        printPackagePreviewTask = nil
        for frame in frames {
            frame.printPackagePreviewTask?.cancel()
            frame.printPackagePreviewGeneration &+= 1
            frame.printPackagePreviewTask = nil
        }
    }

    private func validPrintPackagePreviewImage(for frame: ScanFrame) -> NSImage? {
        guard frame.printPackagePreviewDevelopRevision == frame.developRevision,
              frame.printPackagePreviewCleanRawRevision == frame.cleanRawRevision,
              frame.printPackagePreviewSourceLocationRevision == frame.sourceLocationRevision,
              frame.printPackagePreviewTransform == frame.imageTransform,
              frame.printPackagePreviewSoftProofRevision == softProofConfigurationRevision else {
            return nil
        }
        return frame.printPackagePreviewImage
    }
}
