import Combine
import Foundation
import Chromabase

@MainActor
final class PresentationPreferencesStore: ObservableObject {
    private enum Keys {
        static let appearanceMode = "appearanceMode"
        static let canvasBackground = "canvasBackground"
        static let appLanguage = "appLanguage"
        static let defaultScanRotation = "defaultScanRotation"
        static let developerMode = "developerMode"
        static let clippingOverlayEnabled = "clippingOverlay.enabled"
    }

    private let defaults: UserDefaults

    @Published var appearanceMode: AppAppearanceMode = .system {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode) }
    }

    @Published var canvasBackground: CanvasBackground = .black {
        didSet { defaults.set(canvasBackground.rawValue, forKey: Keys.canvasBackground) }
    }

    @Published var appLanguage: AppLanguage = .system {
        didSet { defaults.set(appLanguage.rawValue, forKey: Keys.appLanguage) }
    }

    // 스캔 원본은 방향 태그 없이 물리적으로 뒤집혀 저장되는 경우가 많아, 방향 미지정 새 스캔에
    // 적용할 기본 회전을 사용자가 고른다. 기본값 = 180°(대상 스캐너 관례).
    @Published var defaultScanRotation: ImageRotation = .deg180 {
        didSet { defaults.set(defaultScanRotation.rawValue, forKey: Keys.defaultScanRotation) }
    }

    @Published var developerMode = false {
        didSet { defaults.set(developerMode, forKey: Keys.developerMode) }
    }

    @Published var clippingOverlayEnabled = false {
        didSet { defaults.set(clippingOverlayEnabled, forKey: Keys.clippingOverlayEnabled) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Keys.appearanceMode),
           let value = AppAppearanceMode(rawValue: raw) {
            appearanceMode = value
        }
        if let raw = defaults.string(forKey: Keys.canvasBackground),
           let value = CanvasBackground(rawValue: raw) {
            canvasBackground = value
        }
        if let raw = defaults.string(forKey: Keys.appLanguage),
           let value = AppLanguage(rawValue: raw) {
            appLanguage = value
        }
        // rawValue 0(deg0)이 유효하므로 미설정과 구분하려 object 존재를 확인한다.
        if let raw = defaults.object(forKey: Keys.defaultScanRotation) as? Int,
           let value = ImageRotation(rawValue: raw) {
            defaultScanRotation = value
        }
        developerMode = defaults.bool(forKey: Keys.developerMode)
        clippingOverlayEnabled = defaults.bool(forKey: Keys.clippingOverlayEnabled)
    }
}
