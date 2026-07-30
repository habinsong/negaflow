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

    var developsImportsAutomatically: Bool {
        get { presentationPreferencesStore.developsImportsAutomatically }
        set { presentationPreferencesStore.developsImportsAutomatically = newValue }
    }

    /// GrainMend 미세 입자 검출의 시작값(자동). 이미 열려 있는 프레임의 체크 상태는 건드리지 않는다.
    var defaultAutoDefectMicroSpecks: Bool {
        get { presentationPreferencesStore.defaultAutoDefectMicroSpecks }
        set { presentationPreferencesStore.defaultAutoDefectMicroSpecks = newValue }
    }

    /// 같은 시작값의 가이드 쪽. 자동과 별개로 기억한다.
    var defaultGuidedDefectMicroSpecks: Bool {
        get { presentationPreferencesStore.defaultGuidedDefectMicroSpecks }
        set { presentationPreferencesStore.defaultGuidedDefectMicroSpecks = newValue }
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
