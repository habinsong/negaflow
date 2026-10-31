import Chromabase
import Foundation

/// 사진을 고른 직후 원본 디코드를 먼저 시작해 둔 것.
///
/// 선택이 바뀌면 SwiftUI 갱신이 메인 스레드를 잡아 선택 현상 작업은 그만큼 늦게 시작한다
/// (실측 175~220ms, 포맷과 무관). 그동안 디코드를 백그라운드에서 먼저 돌리고, 현상 루프가
/// 같은 조건으로 디코드를 만들 때 이것을 이어받는다. 조건이 다르면 이어받지 않고 버린다 —
/// 결과는 원래 경로와 같다. 선택 하나 동안만 살고, 다른 사진을 고르면 취소한다.
final class SelectionDecodeHead: @unchecked Sendable {
    struct SessionKey: Equatable {
        let url: URL
        let inputGamma: InputGammaInterpretation
        let rendering: ImageLoader.RAWRendering
        let applyOrientation: Bool
        let interpretInputGamma: Bool
    }

    let frameID: UUID
    let sessionKey: SessionKey?
    let session: ImagePreviewSession?
    let progressiveURL: URL?
    let firstMaxDimension: CGFloat
    private let lock = NSLock()
    private var active = true
    private var progressive: NativeCameraRAW.ProgressivePreview?

    /// 한 번에 하나만 미리 디코드한다. 빠르게 넘길 때 지나간 사진의 디코드가 쌓이지 않는다.
    private static let queue = DispatchQueue(label: "com.negaflow.selection-decode-head", qos: .userInitiated)

    init(frameID: UUID, sessionKey: SessionKey?, progressiveURL: URL?, firstMaxDimension: CGFloat) {
        self.frameID = frameID
        self.sessionKey = sessionKey
        session = sessionKey.map {
            ImagePreviewSession(url: $0.url, inputGamma: $0.inputGamma, rawRendering: $0.rendering,
                                applyOrientation: $0.applyOrientation, interpretInputGamma: $0.interpretInputGamma)
        }
        self.progressiveURL = progressiveURL
        self.firstMaxDimension = firstMaxDimension
    }

    private var isActive: Bool { lock.withLock { active } }

    func start(sourceURL: URL) {
        Self.queue.async { [self] in
            // iCloud 에서 내려받지 않은 원본을 여기서 열면 다운로드를 기다리며 스레드가 묶인다.
            // 그 경우는 현상 루프가 원래대로 받아 온 뒤 디코드한다.
            guard isActive, !ExportSourceMaterialization.isEvicted(sourceURL) else { return }
            if let progressiveURL {
                let work = NativeCameraRAW.beginProgressivePreview(progressiveURL, firstMaxDimension: firstMaxDimension)
                let keep = lock.withLock { () -> Bool in
                    guard active else { return false }
                    progressive = work
                    return true
                }
                if !keep { work?.cancel() }
            } else if let session {
                // 세션은 원본을 처음 읽을 때 디코드하고 그 결과를 들고 있다. 현상 루프의 같은 호출은
                // 세션 잠금에서 이 디코드를 기다렸다가 그대로 쓴다.
                _ = try? session.preview(maxDimension: firstMaxDimension)
            }
        }
    }

    /// 현상 루프가 같은 조건의 프리뷰 세션을 만들려고 할 때.
    func takeSession(matching key: SessionKey) -> ImagePreviewSession? {
        lock.withLock { active && sessionKey == key ? session : nil }
    }

    /// 현상 루프가 같은 원본·같은 첫 화면 크기로 LibRaw 점진 디코드를 시작하려고 할 때. 아직 시작하지
    /// 않았으면 nil 이고, 이후로는 여기서 시작하지 않는다(현상 루프가 직접 시작한다).
    func takeProgressive(url: URL, firstMaxDimension dimension: CGFloat) -> NativeCameraRAW.ProgressivePreview? {
        lock.withLock {
            guard active, progressiveURL == url, firstMaxDimension == dimension else { return nil }
            active = false
            defer { progressive = nil }
            return progressive
        }
    }

    func cancel() {
        let work = lock.withLock { () -> NativeCameraRAW.ProgressivePreview? in
            active = false
            defer { progressive = nil }
            return progressive
        }
        work?.cancel()
    }
}

extension AppModel {
    /// 선택한 사진이 곧 현상 루프에서 디코드될 조건이면 그 디코드를 지금 시작한다. 조건은 현상 루프의
    /// 프리뷰 세션 생성과 `prepareColdCameraRAWPreview` 의 것과 같다.
    func startSelectionDecodeHead() {
        selectionDecodeHead?.cancel()
        selectionDecodeHead = nil
        guard activeWorkspaceModule == .develop, let frame = selectedFrame,
              frame.isSourceAvailable, librarySourceAvailability(for: frame) != .offline,
              !frame.developedIsSettled, frame.initialThumbnailSeedTask == nil,
              selectedFrameNeedsDevelopment(frame),
              !frame.defectEditsLoadDeferred, !frame.requiresCleanedRawForActiveDefects,
              frame.inputGammaPreviewOverride == nil, frame.inputGammaPreviewSource == nil,
              frame.identityMatchedCleanedRawImage == nil else { return }
        // 이웃 미리 준비가 이 사진을 굳히는 중이면 그 결과를 기다려 쓴다(같은 원본을 두 번 풀지 않는다).
        if neighborCameraRAWPrefetchFrameID == frame.id, !usesCameraNativeDecode(frame) { return }
        let dimension = DevelopFrameRenderer.interactiveProxyDimension(displayTargetPixels: canvasDisplayTargetPixels)
        guard cachedPreviewRaw(for: frame, maxDimension: dimension) == nil,
              cachedSettledPreviewRaw(for: frame) == nil else { return }
        let head: SelectionDecodeHead
        if usesCameraNativeDecode(frame) {
            guard frame.params.inputGamma == .automatic, frame.identityMatchedCleanedRawDiskURL == nil else { return }
            head = SelectionDecodeHead(frameID: frame.id, sessionKey: nil, progressiveURL: frame.rawScanURL,
                                       firstMaxDimension: dimension)
        } else {
            guard let key = selectionPreviewSessionKey(for: frame) else { return }
            head = SelectionDecodeHead(frameID: frame.id, sessionKey: key, progressiveURL: nil,
                                       firstMaxDimension: dimension)
        }
        selectionDecodeHead = head
        head.start(sourceURL: frame.rawScanURL)
    }

    /// 현상 루프가 만드는 프리뷰 세션의 조건. 세션을 공유할 수 없는 원본이면 nil.
    func selectionPreviewSessionKey(for frame: ScanFrame) -> SelectionDecodeHead.SessionKey? {
        let rendering = ImageLoader.RAWRendering.forDigitalSource(frame.params.isDigitalSource, filmType: frame.filmType)
        let cleaned = frame.identityMatchedCleanedRawDiskURL
        let ext = frame.rawScanURL.pathExtension.lowercased()
        guard cleaned != nil || ["tif", "tiff"].contains(ext)
                || (ImageLoader.rawExtensions.contains(ext) && rendering != .cameraNativeNegative) else { return nil }
        return SelectionDecodeHead.SessionKey(
            url: cleaned ?? frame.rawScanURL,
            inputGamma: cleaned == nil ? frame.params.inputGamma : .automatic,
            rendering: rendering,
            applyOrientation: cleaned == nil && frame.sourceKind == .importedFile,
            interpretInputGamma: cleaned == nil)
    }

    func takeSelectionPreviewSession(for frame: ScanFrame, key: SelectionDecodeHead.SessionKey) -> ImagePreviewSession? {
        guard let head = selectionDecodeHead, head.frameID == frame.id else { return nil }
        return head.takeSession(matching: key)
    }

    func takeSelectionProgressivePreview(for frame: ScanFrame, url: URL,
                                         firstMaxDimension: CGFloat) -> NativeCameraRAW.ProgressivePreview? {
        guard let head = selectionDecodeHead, head.frameID == frame.id else { return nil }
        return head.takeProgressive(url: url, firstMaxDimension: firstMaxDimension)
    }

    /// 정착까지 끝났으면 미리 디코드한 원본을 더 붙잡지 않는다.
    func releaseSelectionDecodeHead(for frameID: UUID) {
        guard selectionDecodeHead?.frameID == frameID else { return }
        selectionDecodeHead?.cancel()
        selectionDecodeHead = nil
    }
}
