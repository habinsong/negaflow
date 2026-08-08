import Chromabase

extension AppModel {
    var exportJPEGQuality: Double {
        get { exportSettingsStore.exportJPEGQuality }
        set { exportSettingsStore.exportJPEGQuality = min(max(newValue, 0), 1) }
    }

    var quickExportJPEGQuality: Double {
        get { exportSettingsStore.quickExportJPEGQuality }
        set { exportSettingsStore.quickExportJPEGQuality = min(max(newValue, 0), 1) }
    }

    var exportTIFFCompression: ExportTIFFCompression {
        get { exportSettingsStore.exportTIFFCompression }
        set { exportSettingsStore.exportTIFFCompression = newValue }
    }

    var exportTIFFBitDepth: ExportBitDepth {
        get { exportSettingsStore.exportTIFFBitDepth }
        set { exportSettingsStore.exportTIFFBitDepth = newValue }
    }

    var exportPNGBitDepth: ExportBitDepth {
        get { exportSettingsStore.exportPNGBitDepth }
        set { exportSettingsStore.exportPNGBitDepth = newValue }
    }

    var quickExportPNGBitDepth: ExportBitDepth {
        get { exportSettingsStore.quickExportPNGBitDepth }
        set { exportSettingsStore.quickExportPNGBitDepth = newValue }
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
