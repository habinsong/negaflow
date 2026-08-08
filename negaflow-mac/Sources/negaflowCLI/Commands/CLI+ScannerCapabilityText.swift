import ScannerKit

extension CLI {
    func printCapabilityText(_ value: ScannerCLICapabilitySnapshot) {
        print("resolutions     : \(value.resolutionsDPI)")
        print("modes           : \(value.modes)")
        print("bitDepths       : \(value.bitDepths)")
        print("sourceModes     : \(value.sourceModes ?? [])")
        print("transparencyMode: \(value.transparencyModes ?? [])")
        print("preview         : \(value.supportsPreview)")
        print("transparency    : \(value.supportsTransparency)")
        print("infrared        : \(value.supportsInfrared)")
        print("multiExposure   : \(value.supportsMultiExposure)")
        print("scanArea        : \(value.supportsScanArea)")
        print("lampWarmup      : \(value.supportsLampWarmupStatus)")
        print("brightnessRange : \(String(describing: value.brightnessRange))")
        print("contrastRange   : \(String(describing: value.contrastRange))")
        print("exposureRange   : \(String(describing: value.hardwareExposureRange))")
        print("minScanArea     : \(value.minScanArea.widthMM)×\(value.minScanArea.heightMM) \(value.scanAreaUnit)")
        print("maxScanArea     : \(value.maxScanArea.widthMM)×\(value.maxScanArea.heightMM) \(value.scanAreaUnit)")
        print("outputFormats   : \(value.outputFormats)")
        print("estimatedSpeeds : \(value.estimatedScanSpeeds)")
        print("disabledReasons : \(value.disabledReasons ?? [:])")
    }
}
