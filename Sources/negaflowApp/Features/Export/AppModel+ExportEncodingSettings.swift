import Chromabase

extension AppModel {
    var exportJPEGQuality: Double {
        get { exportSettingsStore.exportJPEGQuality }
        set { exportSettingsStore.exportJPEGQuality = min(max(newValue, 0), 1) }
    }

    var exportTIFFCompression: ExportTIFFCompression {
        get { exportSettingsStore.exportTIFFCompression }
        set { exportSettingsStore.exportTIFFCompression = newValue }
    }

    var exportTIFFBitDepth: ExportTIFFBitDepth {
        get { exportSettingsStore.exportTIFFBitDepth }
        set { exportSettingsStore.exportTIFFBitDepth = newValue }
    }

    var exportPreserveAlpha: Bool {
        get { exportSettingsStore.exportPreserveAlpha }
        set { exportSettingsStore.exportPreserveAlpha = newValue }
    }

    var exportMetadataPolicy: ExportMetadataPolicy {
        get { exportSettingsStore.exportMetadataPolicy }
        set { exportSettingsStore.exportMetadataPolicy = newValue }
    }
}
