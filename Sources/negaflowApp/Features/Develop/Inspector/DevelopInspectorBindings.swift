import SwiftUI
import Chromabase

enum DevelopInspectorBindings {
    @MainActor
    static func noiseReductionEnabled(frame: ScanFrame, onChange: @escaping () -> Void) -> Binding<Bool> {
        Binding(
            get: { frame.params.noiseReduction > 1e-3 },
            set: { on in
                frame.updateParams { $0.noiseReduction = on ? 0.7 : 0 }
                onChange()
            }
        )
    }

    @MainActor
    static func debugOverlayEnabled(frame: ScanFrame, onEnable: @escaping () -> Void) -> Binding<Bool> {
        Binding(
            get: { frame.debugOverlayEnabled },
            set: { isOn in
                frame.debugOverlayEnabled = isOn
                if isOn { onEnable() }
            }
        )
    }

    @MainActor
    static func debugOverlayStage(frame: ScanFrame) -> Binding<DevelopDebugStage> {
        Binding(
            get: { frame.debugOverlayStage },
            set: { frame.debugOverlayStage = $0 }
        )
    }

    @MainActor
    static func tone(
        frame: ScanFrame,
        keyPath: WritableKeyPath<DevelopParameters, Double>,
        onChange: @escaping () -> Void
    ) -> Binding<Double> {
        Binding(
            get: { frame.params[keyPath: keyPath] },
            set: { value in
                frame.updateParams { $0[keyPath: keyPath] = value }
                onChange()
            }
        )
    }

    @MainActor
    static func batchWhiteBalance(
        frame: ScanFrame,
        keyPath: WritableKeyPath<DevelopParameters, Double>,
        onChange: @escaping () -> Void,
        onSync: @escaping () -> Void
    ) -> Binding<Double> {
        Binding(
            get: { frame.params[keyPath: keyPath] },
            set: { value in
                frame.updateParams { $0[keyPath: keyPath] = value }
                onChange()
                onSync()
            }
        )
    }

    @MainActor
    static func pointCurves(frame: ScanFrame) -> Binding<PointCurves> {
        Binding(get: { frame.params.pointCurves }, set: { value in frame.updateParams { $0.pointCurves = value } })
    }

    @MainActor
    static func colorMixer(frame: ScanFrame) -> Binding<ColorMixer> {
        Binding(get: { frame.params.colorMixer }, set: { value in frame.updateParams { $0.colorMixer = value } })
    }

    @MainActor
    static func colorGrading(frame: ScanFrame) -> Binding<ColorGrading> {
        Binding(get: { frame.params.colorGrading }, set: { value in frame.updateParams { $0.colorGrading = value } })
    }

    @MainActor
    static func bwToning(frame: ScanFrame) -> Binding<BWToning> {
        Binding(get: { frame.params.bwToning }, set: { value in frame.updateParams { $0.bwToning = value } })
    }

    @MainActor
    static func calibration(
        frame: ScanFrame,
        keyPath: WritableKeyPath<CalibrationAdjust, Double>,
        onChange: @escaping () -> Void
    ) -> Binding<Double> {
        Binding(
            get: { frame.params.calibration[keyPath: keyPath] },
            set: { value in
                frame.updateParams { $0.calibration[keyPath: keyPath] = value }
                onChange()
            }
        )
    }

    @MainActor
    static func baseMode(
        frame: ScanFrame,
        autoMatchScannerProfile: Binding<Bool>,
        scannerProfiles: [ScannerProfile],
        setModelScannerProfileID: @escaping (String?) -> Void,
        onChange: @escaping () -> Void,
        onSync: @escaping () -> Void
    ) -> Binding<DevelopParameters.BaseMode> {
        Binding(
            get: { frame.params.baseEstimationMode },
            set: { mode in
                frame.updateParams { params in
                    params.baseEstimationMode = mode
                    if mode == .manual, params.manualBaseRGB == nil {
                        params.manualBaseRGB = frame.baseRGB ?? SIMD3(0.90, 0.65, 0.45)
                    }
                    if mode != .preset {
                        autoMatchScannerProfile.wrappedValue = false
                    } else if autoMatchScannerProfile.wrappedValue {
                        params.scannerProfileID = DevelopInspectorProfileMatcher.autoMatchedScannerProfileID(
                            frame: frame,
                            profiles: scannerProfiles,
                            filmStockDminID: params.filmStockDminID
                        )
                        setModelScannerProfileID(params.scannerProfileID)
                    }
                }
                onChange()
                onSync()
            }
        )
    }

    @MainActor
    static func filmStockDminID(
        frame: ScanFrame,
        autoMatchScannerProfile: Bool,
        scannerProfiles: [ScannerProfile],
        setModelScannerProfileID: @escaping (String?) -> Void,
        onChange: @escaping () -> Void,
        onSync: @escaping () -> Void
    ) -> Binding<String?> {
        Binding(
            get: { frame.params.filmStockDminID },
            set: { id in
                frame.updateParams { params in
                    params.filmStockDminID = id
                    if id == nil { params.baseEstimationMode = .auto }
                    if autoMatchScannerProfile {
                        params.scannerProfileID = DevelopInspectorProfileMatcher.autoMatchedScannerProfileID(
                            frame: frame,
                            profiles: scannerProfiles,
                            filmStockDminID: id
                        )
                        setModelScannerProfileID(params.scannerProfileID)
                    }
                }
                onChange()
                onSync()
            }
        )
    }

    @MainActor
    static func lightSourceProfileID(
        frame: ScanFrame,
        onChange: @escaping () -> Void
    ) -> Binding<String?> {
        Binding(
            get: { frame.params.lightSourceProfileID },
            set: { id in
                frame.updateParams { $0.lightSourceProfileID = id }
                onChange()
            }
        )
    }

    @MainActor
    static func autoCorrection(
        frame: ScanFrame,
        keyPath: WritableKeyPath<DevelopParameters, Bool>,
        onChange: @escaping () -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { frame.params[keyPath: keyPath] },
            set: { on in
                frame.updateParams { $0[keyPath: keyPath] = on }
                onChange()
            }
        )
    }

    @MainActor
    static func scannerProfileID(
        frame: ScanFrame,
        setModelScannerProfileID: @escaping (String?) -> Void,
        onChange: @escaping () -> Void,
        onSync: @escaping () -> Void
    ) -> Binding<String?> {
        Binding(
            get: { frame.params.scannerProfileID },
            set: { id in
                setModelScannerProfileID(id)
                frame.updateParams { $0.scannerProfileID = id }
                onChange()
                onSync()
            }
        )
    }

    @MainActor
    static func manualBase(
        frame: ScanFrame,
        channel: Int,
        onChange: @escaping () -> Void,
        onSync: @escaping () -> Void
    ) -> Binding<Double> {
        Binding(
            get: {
                let rgb = frame.params.manualBaseRGB ?? frame.baseRGB ?? SIMD3(0.90, 0.65, 0.45)
                switch channel {
                case 0: return rgb.x
                case 1: return rgb.y
                default: return rgb.z
                }
            },
            set: { value in
                var rgb = frame.params.manualBaseRGB ?? frame.baseRGB ?? SIMD3(0.90, 0.65, 0.45)
                let clamped = min(max(value, 0), 1)
                switch channel {
                case 0: rgb.x = clamped
                case 1: rgb.y = clamped
                default: rgb.z = clamped
                }
                frame.updateParams {
                    $0.manualBaseRGB = rgb
                    $0.baseEstimationMode = .manual
                }
                onChange()
                onSync()
            }
        )
    }
}
