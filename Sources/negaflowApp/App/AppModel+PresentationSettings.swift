import Chromabase

extension AppModel {
    var appearanceMode: AppAppearanceMode {
        get { presentationPreferencesStore.appearanceMode }
        set { presentationPreferencesStore.appearanceMode = newValue }
    }

    var canvasBackground: CanvasBackground {
        get { presentationPreferencesStore.canvasBackground }
        set { presentationPreferencesStore.canvasBackground = newValue }
    }

    var appLanguage: AppLanguage {
        get { presentationPreferencesStore.appLanguage }
        set { presentationPreferencesStore.appLanguage = newValue }
    }

    var defaultScanRotation: ImageRotation {
        get { presentationPreferencesStore.defaultScanRotation }
        set { presentationPreferencesStore.defaultScanRotation = newValue }
    }

    var developerMode: Bool {
        get { presentationPreferencesStore.developerMode }
        set { presentationPreferencesStore.developerMode = newValue }
    }


    var clippingOverlayEnabled: Bool {
        get { presentationPreferencesStore.clippingOverlayEnabled }
        set {
            guard newValue != presentationPreferencesStore.clippingOverlayEnabled else { return }
            presentationPreferencesStore.clippingOverlayEnabled = newValue
            actionableFrame?.clippingOverlayImage = nil
            actionableFrame?.cachedClippingOverlayBase = nil
            refreshClippingOverlayPreviewIfNeeded()
        }
    }

    func text(_ key: AppLocalizedText) -> String {
        AppLocalization.text(key, language: appLanguage)
    }
}
