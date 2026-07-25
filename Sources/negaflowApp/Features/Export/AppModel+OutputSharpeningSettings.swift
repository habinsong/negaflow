import Chromabase

extension AppModel {
    var exportOutputSharpening: Double {
        get { exportSettingsStore.exportOutputSharpening }
        set { exportSettingsStore.exportOutputSharpening = min(max(newValue, 0), 1) }
    }

    var exportOutputSharpeningMedium: OutputSharpeningMedium {
        get { exportSettingsStore.exportOutputSharpeningMedium }
        set { exportSettingsStore.exportOutputSharpeningMedium = newValue }
    }
}
