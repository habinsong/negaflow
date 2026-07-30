import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    /// 같은 UUID가 아니라 현재 FrameStore가 실제로 소유한 객체인지 확인한다.
    func ownsFrame(_ frame: ScanFrame) -> Bool {
        if let indexedFrame = libraryFramesByIDCache[frame.id] {
            return indexedFrame === frame
        }
        return frames.contains(where: { $0 === frame })
    }

    // MARK: 슬라이더 라이브 현상 요청(레이트 throttle)
    //
    // 리딩+트레일링 throttle: 즉시(리딩) 한 번 띄우고, 간격 내 추가 변경은 트레일링으로 모아 ~22fps로
    // 제한한다. 과거처럼 매 틱마다 리비전을 올려 루프가 무제한 렌더하지 않으므로 GPU(IOSurface) 압박이
    // 사라지고 간헐적 블랭크 렌더가 방지된다. 마지막(정착) 호출이 풀해상도 패스까지 마무리한다.
    func requestDevelop(_ frame: ScanFrame) {
        developController.requestDevelop(frame) { [weak self] frame in
            await self?.developFrame(frame)
        }
    }

    func refreshSoftProofPreviewIfNeeded() {
        // 인화 패키지 시트는 썸네일 크기 셀에 여러 장을 늘어놓는 화면이다. 프루프 설정이 바뀔
        // 때마다 선택 전체를 풀해상도로 다시 현상하면 장수만큼 화면이 멈춘다 — 활성 사진만
        // 최신 프루프로 맞추고, 나머지 셀은 이미 만들어 둔 썸네일을 그대로 쓴다.
        var candidates = usesPrintPackageLayout
            ? [actionableFrame].compactMap { $0 }.filter(\.hasDevelopedOnce)
            : actionableSelectedFrames.filter(\.hasDevelopedOnce)
        if candidates.isEmpty, let frame = actionableFrame, frame.hasDevelopedOnce {
            candidates = [frame]
        }
        // 프루프 설정은 이산 변경이며 선택 전체가 같은 프로파일 세대를 보여야 한다. 프레임별
        // 독립 Task를 동시에 띄우면 큰 원본에서 메모리 피크가 겹치고 일부 작업이 탈락할 수 있으므로,
        // 최신 세대의 한 Task를 보관하고 선택 순서대로 렌더한다.
        softProofRefreshTask?.cancel()
        let revision = softProofConfigurationRevision
        softProofRefreshTask = Task { [weak self] in
            guard let self else { return }
            for frame in candidates {
                guard !Task.isCancelled,
                      revision == self.softProofConfigurationRevision else { return }
                guard self.ownsFrame(frame) else { continue }
                await self.developFrame(frame, preserveThumbnail: true)
            }
        }
    }

    func refreshClippingOverlayPreviewIfNeeded() {
        guard let frame = actionableFrame, frame.hasDevelopedOnce else { return }
        requestDevelop(frame)
    }

    // MARK: develop (엔진 호출 — 색감 로직은 그대로)
    // preserveThumbnail=true: 이미 표시 중인 썸네일을 현상 결과로 덮지 않는다. 메모리 복원용
    // 재현상과 포지티브 원본의 최초 현상에 쓰며, 네거티브 최초 현상은 정착 썸네일로 갱신한다.
    func developFrame(
        _ frame: ScanFrame,
        preserveThumbnail: Bool = false,
        skipInteractivePreview: Bool = false,
        selectionBoundFrameID: UUID? = nil
    ) async {
        guard developmentRequestIsCurrent(frame, selectionBoundFrameID: selectionBoundFrameID) else { return }
        // 원본을 읽기 전에 iCloud 사본을 먼저 확보한다. 현상 슬롯을 잡은 뒤 커널 대기에 걸리면
        // 뒤따르는 현상이 전부 멈춘다.
        guard await materializeDevelopSourceIfNeeded(frame) else { return }
        guard developmentRequestIsCurrent(frame, selectionBoundFrameID: selectionBoundFrameID) else { return }
        guard await prepareCleanedRawForConsumption(frame) else { return }
        guard developmentRequestIsCurrent(frame, selectionBoundFrameID: selectionBoundFrameID) else { return }
        // filmType 동기화는 실제로 다를 때만(슬라이더 핫패스에서 불필요한 @Published 발행 방지).
        if frame.params.filmType != frame.filmType {
            frame.updateParams { $0.filmType = frame.filmType }
        }
        frame.developRevision += 1
        // 이미 진행 중이면 리비전만 올리고 종료 — 진행 중 루프가 최신 값으로 재렌더한다(코얼레싱).
        guard developController.beginFrame(frame) else { return }
        guard await developController.acquireDevelopSlot() else {
            developController.endFrame(frame)
            return
        }
        await renderLatestDevelopment(
            for: frame,
            preserveThumbnail: preserveThumbnail,
            skipInteractivePreview: skipInteractivePreview,
            selectionBoundFrameID: selectionBoundFrameID
        )
    }

    func developmentRequestIsCurrent(
        _ frame: ScanFrame,
        selectionBoundFrameID: UUID?
    ) -> Bool {
        guard !Task.isCancelled, ownsFrame(frame) else { return false }
        guard let selectionBoundFrameID else { return true }
        return frame.id == selectionBoundFrameID && selectedFrameID == selectionBoundFrameID
    }

    func developFrameAfterFastPreview(_ frame: ScanFrame) async {
        // 원본 프리뷰 시드(백그라운드 디코드)를 먼저 기다린다. 네거티브는 이 단계에서
        // thumbnailImage 를 비워 두므로 seedFastPreview 가 포지티브 썸네일을 최초로 발행한다.
        if let seed = frame.initialThumbnailSeedTask {
            await seed.value
        }
        await seedFastPreview(frame)
        // 네거티브는 빠른 포지티브 썸네일을 정착 패스의 고품질 결과로 교체한다.
        // 이미 fast preview를 발행했으므로 같은 화면용 패스를 한 번 더 만들지 않는다.
        await developFrame(
            frame,
            preserveThumbnail: !frame.filmType.requiresInversion,
            skipInteractivePreview: true
        )
    }

    /// 썸네일 크기의 가벼운 현상 프리뷰 한 장만 만든다(정착 패스 없음). 인화 시트처럼 작은
    /// 셀에 여러 장을 늘어놓을 때, 장마다 풀해상도 현상을 돌리지 않기 위한 경로다.
    func seedFastPreview(_ frame: ScanFrame) async {
        guard ownsFrame(frame), frame.thumbnailImage == nil else { return }
        guard await materializeDevelopSourceIfNeeded(frame) else { return }
        guard ownsFrame(frame), frame.thumbnailImage == nil else { return }
        guard await developController.acquireDevelopSlot() else { return }
        defer { developController.releaseDevelopSlot() }
        guard ownsFrame(frame), frame.thumbnailImage == nil else { return }
        let baseKey = FilmBaseCacheKey(
            filmType: frame.filmType,
            mode: frame.params.baseEstimationMode,
            manualBaseRGB: frame.params.manualBaseRGB,
            filmStockDminID: frame.params.filmStockDminID,
            lightSourceProfileID: frame.params.lightSourceProfileID
        )
        let snapshot = makeSnapshot(
            for: frame,
            baseKey: baseKey,
            needsRawPreview: false,
            needsNeutralPreview: false,
            needsDebugPreviews: false,
            needsThumbnail: true,
            proxyMaxDimension: DevelopFrameRenderer.fastPreviewMaxDimension
        )
        do {
            let preview = try await Task.detached(priority: .utility) {
                try DevelopFrameRenderer.renderFastPreview(snapshot)
            }.value
            guard ownsFrame(frame), frame.thumbnailImage == nil else { return }
            let thumbnail = preview.thumbnail ?? preview.preview
            frame.thumbnailImage = NSImage(
                cgImage: thumbnail,
                size: NSSize(width: thumbnail.width, height: thumbnail.height)
            )
            frame.thumbnailTransform = snapshot.imageTransform
            persistThumbnail(for: frame, cgImage: thumbnail)
            applyPreviewRawCache(preview, to: frame, maxDimension: snapshot.proxyMaxDimension)
        } catch {
            return
        }
    }

}
