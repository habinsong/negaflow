import Foundation
import CoreGraphics
import ImageIO
import Chromabase

extension ExternalScannerBackend {
    func validLegacyReportedResolution(_ value: Int?, preview: Bool) -> Resolution? {
        guard let value,
              preview ? value == Resolution.preview.dpi : value > 0 else {
            return nil
        }
        return Resolution(value)
    }

    func validatedAppliedOptions(
        _ event: PluginScanEvent,
        requestedWire: PluginScanOptions,
        hostScannerID: String,
        requestID: UUID,
        finalOutputURL: URL,
        preview: Bool
    ) throws -> ScanOptions {
        guard let applied = event.appliedOptions else {
            throw failure(.ioFailure, "plugin protocol v2 appliedOptions 누락")
        }
        guard !applied.deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              applied.deviceID == requestedWire.deviceID else {
            throw failure(.ioFailure, "plugin protocol v2 appliedOptions deviceID 불일치")
        }
        guard applied.resolutionDPI >= 0,
              (preview ? applied.resolutionDPI == 0 : applied.resolutionDPI > 0) else {
            throw failure(.ioFailure, "plugin protocol v2 appliedOptions preview/resolution 불일치")
        }
        guard let bitDepth = BitDepth(rawValue: applied.bitDepth) else {
            throw failure(.ioFailure, "plugin protocol v2 appliedOptions bitDepth가 유효하지 않음")
        }
        guard let colorMode = ColorMode(rawValue: applied.colorMode) else {
            throw failure(.ioFailure, "plugin protocol v2 appliedOptions colorMode가 유효하지 않음")
        }
        guard let filmType = FilmType(rawValue: applied.filmType) else {
            throw failure(.ioFailure, "plugin protocol v2 appliedOptions filmType이 유효하지 않음")
        }
        guard applied.scanArea.originXMM.isFinite,
              applied.scanArea.originYMM.isFinite,
              applied.scanArea.originXMM >= 0,
              applied.scanArea.originYMM >= 0,
              applied.scanArea.widthMM.isFinite,
              applied.scanArea.heightMM.isFinite,
              applied.scanArea.widthMM > 0,
              applied.scanArea.heightMM > 0 else {
            throw failure(.ioFailure, "plugin protocol v2 appliedOptions scanArea가 유효하지 않음")
        }
        guard applied.hardwareExposureTime.map({ $0 > 0 }) ?? true else {
            throw failure(.ioFailure, "plugin protocol v2 appliedOptions hardwareExposureTime이 유효하지 않음")
        }
        guard applied.brightnessAdjustment.map(\.isFinite) ?? true,
              applied.contrastAdjustment.map(\.isFinite) ?? true else {
            throw failure(.ioFailure, "plugin protocol v2 appliedOptions adjustment가 유효하지 않음")
        }
        guard applied.resolutionDPI == requestedWire.resolutionDPI else {
            throw failure(.ioFailure, "plugin protocol v2 requested/appliedOptions resolution 불일치")
        }
        guard applied.bitDepth == requestedWire.bitDepth else {
            throw failure(.ioFailure, "plugin protocol v2 requested/appliedOptions bitDepth 불일치")
        }
        guard applied.colorMode == requestedWire.colorMode else {
            throw failure(.ioFailure, "plugin protocol v2 requested/appliedOptions colorMode 불일치")
        }
        guard applied.filmType == requestedWire.filmType else {
            throw failure(.ioFailure, "plugin protocol v2 requested/appliedOptions filmType 불일치")
        }
        guard requestedWire.scanArea == applied.scanArea else {
            throw failure(.ioFailure, "plugin protocol v2 requested/appliedOptions scanArea 불일치")
        }
        guard applied.infrared == requestedWire.infrared else {
            throw failure(.ioFailure, "plugin protocol v2 requested/appliedOptions infrared 불일치")
        }
        guard applied.multiExposure == requestedWire.multiExposure else {
            throw failure(.ioFailure, "plugin protocol v2 requested/appliedOptions multiExposure 불일치")
        }
        guard applied.hardwareExposureTime == requestedWire.hardwareExposureTime else {
            throw failure(.ioFailure, "plugin protocol v2 requested/appliedOptions hardwareExposureTime 불일치")
        }
        guard applied.brightnessAdjustment == requestedWire.brightnessAdjustment else {
            throw failure(.ioFailure, "plugin protocol v2 requested/appliedOptions brightnessAdjustment 불일치")
        }
        guard applied.contrastAdjustment == requestedWire.contrastAdjustment else {
            throw failure(.ioFailure, "plugin protocol v2 requested/appliedOptions contrastAdjustment 불일치")
        }
        guard requestedWire.outputRawTIFF == applied.outputRawTIFF else {
            throw failure(.ioFailure, "plugin protocol v2 requested/appliedOptions outputRawTIFF 불일치")
        }
        guard event.resolutionDPI == applied.resolutionDPI else {
            throw failure(.ioFailure, "plugin protocol v2 result/appliedOptions resolution 불일치")
        }
        guard event.bitDepth == applied.bitDepth else {
            throw failure(.ioFailure, "plugin protocol v2 result/appliedOptions bitDepth 불일치")
        }
        guard event.hasInfrared == applied.infrared else {
            throw failure(.ioFailure, "plugin protocol v2 result/appliedOptions IR 불일치")
        }

        return ScanOptions(
            requestID: requestID,
            scannerID: hostScannerID,
            resolution: Resolution(applied.resolutionDPI),
            bitDepth: bitDepth,
            colorMode: colorMode,
            filmType: filmType,
            scanArea: applied.scanArea,
            infraredEnabled: applied.infrared,
            multiExposureEnabled: applied.multiExposure,
            hardwareExposureTime: applied.hardwareExposureTime,
            brightnessAdjustment: applied.brightnessAdjustment,
            contrastAdjustment: applied.contrastAdjustment,
            outputRawTIFF: applied.outputRawTIFF,
            temporaryOutputURL: finalOutputURL
        )
    }


}
