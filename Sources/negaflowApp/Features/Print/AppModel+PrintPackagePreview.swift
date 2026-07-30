import Chromabase
import Foundation

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
}
