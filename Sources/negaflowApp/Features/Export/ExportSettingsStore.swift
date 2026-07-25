import Combine
import Foundation
import Chromabase

@MainActor
final class ExportSettingsStore: ObservableObject {
    private enum Keys {
        static let exportFormat = "export.format"
        static let exportColorSpace = "export.colorSpace"
        static let softProofEnabled = "softProof.enabled"
        static let softProofSimulation = "softProof.simulation"
        static let softProofICCProfileData = "softProof.iccProfileData"
        static let softProofICCProfileName = "softProof.iccProfileName"
        static let printerOutputICCProfileData = "print.outputICCProfileData"
        static let printerOutputICCProfileName = "print.outputICCProfileName"
        static let printerOutputICCProfileMigrationCompleted =
            "print.outputICCProfileMigrationCompleted"
        static let destinationGamutWarningEnabled = "softProof.destinationGamutWarningEnabled"
        static let exportDPI = "export.dpi"
        static let exportLongEdge = "export.longEdge"
        static let exportWriteMainFlatMaster = "export.writeMainFlatMaster"
        static let exportWriteOriginalRaw = "export.writeOriginalRaw"
        static let exportFilenamePrefix = "export.filenamePrefix"
        static let exportNamingTemplate = "export.namingTemplate"
        static let exportSequenceStart = "export.sequenceStart"
        static let exportJPEGQuality = "export.jpegQuality"
        static let exportTIFFCompression = "export.tiffCompression"
        static let exportTIFFBitDepth = "export.tiffBitDepth"
        static let exportPreserveAlpha = "export.preserveAlpha"
        static let exportMetadataPolicy = "export.metadataPolicy"
        static let exportOutputSharpening = "export.outputSharpening"
        static let exportOutputSharpeningMedium = "export.outputSharpeningMedium"
        static let quickExportFormat = "export.quick.format"
        static let quickExportDPI = "export.quick.dpi"
        // 빠른 내보내기 폴더 경로는 DiskStorageStore("disk.quickExportFolder")로 이관됐다.
        // 구키("export.quick.folder")는 DiskStorageStore 가 최초 실행 시 이어받는다.
    }

    private let defaults: UserDefaults

    @Published var exportFormat: ExportFormat = .jpeg {
        didSet { defaults.set(exportFormat.rawValue, forKey: Keys.exportFormat) }
    }
    @Published var exportColorSpace: ExportColorSpace = .sRGB {
        didSet { defaults.set(exportColorSpace.rawValue, forKey: Keys.exportColorSpace) }
    }
    @Published var softProofEnabled: Bool = false {
        didSet { defaults.set(softProofEnabled, forKey: Keys.softProofEnabled) }
    }
    @Published var softProofSimulation: SoftProofSimulation = .profileOnly {
        didSet { defaults.set(softProofSimulation.rawValue, forKey: Keys.softProofSimulation) }
    }
    @Published var softProofICCProfileData: Data? {
        didSet {
            if let softProofICCProfileData {
                defaults.set(softProofICCProfileData, forKey: Keys.softProofICCProfileData)
            } else {
                defaults.removeObject(forKey: Keys.softProofICCProfileData)
            }
        }
    }
    @Published var softProofICCProfileName: String? {
        didSet {
            if let softProofICCProfileName {
                defaults.set(softProofICCProfileName, forKey: Keys.softProofICCProfileName)
            } else {
                defaults.removeObject(forKey: Keys.softProofICCProfileName)
            }
        }
    }
    @Published var printerOutputICCProfileData: Data? {
        didSet {
            if let printerOutputICCProfileData {
                defaults.set(printerOutputICCProfileData, forKey: Keys.printerOutputICCProfileData)
            } else {
                defaults.removeObject(forKey: Keys.printerOutputICCProfileData)
            }
        }
    }
    @Published var printerOutputICCProfileName: String? {
        didSet {
            if let printerOutputICCProfileName {
                defaults.set(printerOutputICCProfileName, forKey: Keys.printerOutputICCProfileName)
            } else {
                defaults.removeObject(forKey: Keys.printerOutputICCProfileName)
            }
        }
    }
    @Published var destinationGamutWarningEnabled: Bool = false {
        didSet {
            defaults.set(destinationGamutWarningEnabled, forKey: Keys.destinationGamutWarningEnabled)
        }
    }
    @Published var exportDPI: Int = 0 {
        didSet { defaults.set(exportDPI, forKey: Keys.exportDPI) }
    }
    @Published var exportLongEdge: Int = 0 {
        didSet { defaults.set(exportLongEdge, forKey: Keys.exportLongEdge) }
    }
    @Published var exportWriteMainFlatMaster: Bool = false {
        didSet { defaults.set(exportWriteMainFlatMaster, forKey: Keys.exportWriteMainFlatMaster) }
    }
    @Published var exportWriteOriginalRaw: Bool = false {
        didSet { defaults.set(exportWriteOriginalRaw, forKey: Keys.exportWriteOriginalRaw) }
    }
    @Published var exportNamingTemplate: String = ExportNamingTemplate.defaultPattern {
        didSet { defaults.set(exportNamingTemplate, forKey: Keys.exportNamingTemplate) }
    }
    @Published var exportSequenceStart: Int = 1 {
        didSet { defaults.set(exportSequenceStart, forKey: Keys.exportSequenceStart) }
    }
    @Published var exportJPEGQuality: Double = 0.95 {
        didSet { defaults.set(exportJPEGQuality, forKey: Keys.exportJPEGQuality) }
    }
    @Published var exportTIFFCompression: ExportTIFFCompression = .none {
        didSet { defaults.set(exportTIFFCompression.rawValue, forKey: Keys.exportTIFFCompression) }
    }
    @Published var exportTIFFBitDepth: ExportTIFFBitDepth = .sixteen {
        didSet { defaults.set(exportTIFFBitDepth.rawValue, forKey: Keys.exportTIFFBitDepth) }
    }
    @Published var exportPreserveAlpha = false {
        didSet { defaults.set(exportPreserveAlpha, forKey: Keys.exportPreserveAlpha) }
    }
    @Published var exportMetadataPolicy: ExportMetadataPolicy = .minimal {
        didSet { defaults.set(exportMetadataPolicy.rawValue, forKey: Keys.exportMetadataPolicy) }
    }
    @Published var exportOutputSharpening: Double = 0 {
        didSet { defaults.set(exportOutputSharpening, forKey: Keys.exportOutputSharpening) }
    }
    @Published var exportOutputSharpeningMedium: OutputSharpeningMedium = .screen {
        didSet { defaults.set(exportOutputSharpeningMedium.rawValue, forKey: Keys.exportOutputSharpeningMedium) }
    }
    @Published var quickExportFormat: ExportFormat = .jpeg {
        didSet { defaults.set(quickExportFormat.rawValue, forKey: Keys.quickExportFormat) }
    }
    @Published var quickExportDPI: Int = 0 {
        didSet { defaults.set(quickExportDPI, forKey: Keys.quickExportDPI) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Keys.exportFormat),
           let value = ExportFormat(rawValue: raw) {
            exportFormat = value
        }
        if let raw = defaults.string(forKey: Keys.exportColorSpace),
           let value = ExportColorSpace(rawValue: raw) {
            exportColorSpace = value
        }
        softProofEnabled = defaults.bool(forKey: Keys.softProofEnabled)
        if let raw = defaults.string(forKey: Keys.softProofSimulation),
           let value = SoftProofSimulation(rawValue: raw) {
            softProofSimulation = value
        }
        if let data = defaults.data(forKey: Keys.softProofICCProfileData),
           SoftProof.rgbOutputColorSpace(fromICCData: data) != nil {
            softProofICCProfileData = data
            softProofICCProfileName = defaults.string(forKey: Keys.softProofICCProfileName)
        } else {
            softProofICCProfileData = nil
            softProofICCProfileName = nil
        }
        let storedPrinterData = defaults.data(forKey: Keys.printerOutputICCProfileData)
        let storedPrinterName = defaults.string(forKey: Keys.printerOutputICCProfileName)
        let shouldMigrateSoftProofProfile = !defaults.bool(
            forKey: Keys.printerOutputICCProfileMigrationCompleted
        )
        let migratedPrinterData = storedPrinterData
            ?? (shouldMigrateSoftProofProfile ? softProofICCProfileData : nil)
        let migratedPrinterName = storedPrinterName
            ?? (shouldMigrateSoftProofProfile ? softProofICCProfileName : nil)
        if let data = migratedPrinterData,
           let profile = ICCOutputProfileSnapshot(
               profileName: migratedPrinterName ?? "Printer ICC",
               iccProfileData: data
           ) {
            printerOutputICCProfileData = profile.iccProfileData
            printerOutputICCProfileName = profile.profileName
        } else {
            printerOutputICCProfileData = nil
            printerOutputICCProfileName = nil
        }
        defaults.set(true, forKey: Keys.printerOutputICCProfileMigrationCompleted)
        destinationGamutWarningEnabled = defaults.bool(
            forKey: Keys.destinationGamutWarningEnabled
        )
        exportDPI = defaults.integer(forKey: Keys.exportDPI)
        exportLongEdge = defaults.integer(forKey: Keys.exportLongEdge)
        exportWriteMainFlatMaster = defaults.bool(forKey: Keys.exportWriteMainFlatMaster)
        exportWriteOriginalRaw = defaults.bool(forKey: Keys.exportWriteOriginalRaw)
        if let pattern = defaults.string(forKey: Keys.exportNamingTemplate),
           ExportNamingTemplate.isValid(pattern) {
            exportNamingTemplate = ExportNamingTemplate.normalized(pattern)
        } else {
            exportNamingTemplate = ExportNamingTemplate.migratedPattern(
                fromLegacyPrefix: defaults.string(forKey: Keys.exportFilenamePrefix) ?? ""
            )
        }
        let storedSequenceStart = defaults.integer(forKey: Keys.exportSequenceStart)
        exportSequenceStart = max(1, storedSequenceStart)
        if defaults.object(forKey: Keys.exportJPEGQuality) != nil {
            let quality = defaults.double(forKey: Keys.exportJPEGQuality)
            exportJPEGQuality = quality.isFinite && (0...1).contains(quality) ? quality : 0.95
        }
        if let raw = defaults.string(forKey: Keys.exportTIFFCompression),
           let value = ExportTIFFCompression(rawValue: raw) {
            exportTIFFCompression = value
        }
        if let value = ExportTIFFBitDepth(rawValue: defaults.integer(forKey: Keys.exportTIFFBitDepth)) {
            exportTIFFBitDepth = value
        }
        exportPreserveAlpha = defaults.bool(forKey: Keys.exportPreserveAlpha)
        if let raw = defaults.string(forKey: Keys.exportMetadataPolicy),
           let value = ExportMetadataPolicy(rawValue: raw) {
            exportMetadataPolicy = value
        }
        if defaults.object(forKey: Keys.exportOutputSharpening) != nil {
            let strength = defaults.double(forKey: Keys.exportOutputSharpening)
            exportOutputSharpening = strength.isFinite && (0...1).contains(strength) ? strength : 0
        }
        if let raw = defaults.string(forKey: Keys.exportOutputSharpeningMedium),
           let value = OutputSharpeningMedium(rawValue: raw) {
            exportOutputSharpeningMedium = value
        }
        if let raw = defaults.string(forKey: Keys.quickExportFormat),
           let value = ExportFormat(rawValue: raw),
           value == .jpeg || value == .png {
            quickExportFormat = value
        }
        quickExportDPI = defaults.integer(forKey: Keys.quickExportDPI)
        if exportFormat == .rawScanTIFF {
            exportLongEdge = 0
            exportTIFFCompression = .none
            exportTIFFBitDepth = .sixteen
            exportPreserveAlpha = false
            exportOutputSharpening = 0
            defaults.set(0, forKey: Keys.exportLongEdge)
            defaults.set(ExportTIFFCompression.none.rawValue, forKey: Keys.exportTIFFCompression)
            defaults.set(ExportTIFFBitDepth.sixteen.rawValue, forKey: Keys.exportTIFFBitDepth)
            defaults.set(false, forKey: Keys.exportPreserveAlpha)
            defaults.set(0, forKey: Keys.exportOutputSharpening)
        }
        if quickExportFormat != .jpeg && quickExportFormat != .png {
            quickExportFormat = .jpeg
            defaults.set(ExportFormat.jpeg.rawValue, forKey: Keys.quickExportFormat)
        }
    }
}
