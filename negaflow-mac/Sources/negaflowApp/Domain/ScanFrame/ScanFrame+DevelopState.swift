import AppKit
import Chromabase

@MainActor
extension ScanFrame {
    func updateParams(_ body: (inout DevelopParameters) -> Void) {
        var next = params
        body(&next)
        params = next
    }

    /// 가져오기/스캔이 neutral preset과 장치·target 기본값을 모두 적용한 뒤, 프레임을 publish하기
    /// 직전에 한 번 호출한다. 생성자 기본값을 ingest 기준점으로 고정하면 자동 초기화 자체가 사용자
    /// 편집으로 오분류되므로 호출 시점을 명시한다.
    func establishLibraryWorkflowBaselineIfNeeded() {
        guard libraryWorkflowTrackingState == nil,
              let recipeSHA256 = currentLibraryDevelopRecipeSHA256() else { return }
        libraryWorkflowTrackingState = .newFrame(currentRecipeSHA256: recipeSHA256)
    }

    func currentLibraryDevelopRecipeSHA256() -> String? {
        let key = LibraryDevelopRecipeFingerprintCacheKey(
            filmType: filmType,
            presetID: preset?.id,
            params: params,
            imageTransform: imageTransform
        )
        if libraryDevelopRecipeFingerprintCacheKey == key {
            return libraryDevelopRecipeFingerprintCacheSHA256
        }
        guard let sha256 = try? LibraryDevelopRecipeFingerprint.sha256(
            filmType: key.filmType,
            presetID: key.presetID,
            params: key.params,
            imageTransform: key.imageTransform
        ) else {
            libraryDevelopRecipeFingerprintCacheKey = nil
            libraryDevelopRecipeFingerprintCacheSHA256 = nil
            return nil
        }
        libraryDevelopRecipeFingerprintCacheKey = key
        libraryDevelopRecipeFingerprintCacheSHA256 = sha256
        return sha256
    }

    func updateTransform(_ body: (inout ImageTransform) -> Void) {
        var next = imageTransform
        body(&next)
        imageTransform = next
    }

    func clearPreviewRawCaches() {
        cachedInteractivePreviewRaw = nil
        cachedInteractivePreviewRawRevision = -1
        cachedInteractivePreviewRawDimension = 0
        cachedSettledPreviewRaw = nil
        cachedSettledPreviewRawRevision = -1
    }

    /// 현상/변형 결과의 픽셀 크기를 레이아웃 기준으로 기록한다.
    /// - authoritative: 정착(풀해상도)·변형 fast-path 결과. 항상 채택한다.
    /// - 비-authoritative(인터랙티브 프록시): 종횡비가 실제로 바뀐 경우(>0.5%)에만 채택해
    ///   반올림 수준의 차이로 레이아웃이 흔들리지 않게 한다.
    func noteDevelopedDisplaySize(_ size: CGSize, authoritative: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        if authoritative || Self.aspectDiffers(displayPixelSize, from: size) {
            displayPixelSize = size
        }
    }

    nonisolated static func aspectDiffers(_ current: CGSize?, from new: CGSize) -> Bool {
        guard let current, current.width > 0, current.height > 0,
              new.width > 0, new.height > 0 else { return true }
        let currentAspect = current.width / current.height
        let newAspect = new.width / new.height
        return abs(currentAspect - newAspect) / newAspect > 0.005
    }
}
