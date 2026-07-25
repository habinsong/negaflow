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
        var candidates = actionableSelectedFrames.filter(\.hasDevelopedOnce)
        if candidates.isEmpty, let frame = actionableFrame, frame.hasDevelopedOnce {
            candidates = [frame]
        }
        // DevelopController의 일반 슬라이더 throttle은 단일 trailing task를 사용하므로 여기서
        // 여러 프레임을 연속 requestDevelop하면 중간 프레임이 취소된다. 프루프 설정은 이산 변경이고
        // 인화 패키지의 모든 선택 프레임이 같은 프로파일 세대를 보여야 하므로 각 프레임을 직접 예약한다.
        for frame in candidates {
            Task { [weak self, weak frame] in
                guard let self, let frame else { return }
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
        selectionBoundFrameID: UUID? = nil
    ) async {
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
        await developFrame(frame, preserveThumbnail: !frame.filmType.requiresInversion)
    }

    private func seedFastPreview(_ frame: ScanFrame) async {
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
