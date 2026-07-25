import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    func loadCapabilities() async {
        resetFlatbedPreviewState()
        let requestID = UUID()
        capabilityRequestID = requestID
        guard let id = effectiveScannerID, let b = backend else {
            capabilities = nil
            selectedHardwareScanArea = nil
            capabilityRequestID = nil
            return
        }
        capabilities = nil
        let backendID = ObjectIdentifier(b)
        let loadedCapabilities: ScannerCapabilities
        do {
            loadedCapabilities = try await b.getCapabilities(scannerID: id)
        } catch {
            guard capabilityRequestID == requestID else { return }
            guard effectiveScannerID == id,
                  let currentBackend = backend,
                  ObjectIdentifier(currentBackend) == backendID else {
                capabilityRequestID = nil
                return
            }
            capabilityRequestID = nil
            capabilities = nil
            selectedHardwareScanArea = nil
            statusMessage = text(AppLocalizedPhrase.capabilityUnavailable)
            return
        }
        guard capabilityRequestID == requestID else { return }
        guard effectiveScannerID == id,
              let currentBackend = backend,
              ObjectIdentifier(currentBackend) == backendID else {
            capabilityRequestID = nil
            return
        }
        capabilityRequestID = nil
        capabilities = loadedCapabilities
        clampScannerChoices()
        clampScannerHardwareAdjustments()
        clampHardwareScanAreaSelection()
        clampScanFrameFormatSelection()
        multiExposureEnabled = false
        if capabilities?.supportsInfrared != true {
            infraredEnabled = false
        }
    }

    private func clampScannerHardwareAdjustments() {
        scannerBrightness = capabilities?.brightnessRange?.clamped(scannerBrightness) ?? 0
        scannerContrast = capabilities?.contrastRange?.clamped(scannerContrast) ?? 0
    }

    var hardwareScanAreaBounds: PhysicalScanAreaBounds? {
        capabilities?.physicalScanAreaBounds
    }

    func updateHardwareScanArea(_ requested: ScanArea) {
        selectedHardwareScanArea = capabilities?.clampedPhysicalScanArea(requested)
    }

    func resetHardwareScanArea() {
        selectedHardwareScanArea = hardwareScanAreaBounds?.maximum
    }

    func resolvedHardwareScanArea(for capabilities: ScannerCapabilities) -> ScanArea? {
        guard let bounds = capabilities.physicalScanAreaBounds else { return nil }
        return capabilities.clampedPhysicalScanArea(selectedHardwareScanArea ?? bounds.maximum)
    }

    private func clampHardwareScanAreaSelection() {
        guard let capabilities, let bounds = capabilities.physicalScanAreaBounds else {
            selectedHardwareScanArea = nil
            return
        }
        selectedHardwareScanArea = capabilities.clampedPhysicalScanArea(
            selectedHardwareScanArea ?? bounds.maximum
        )
    }

    private func clampScannerChoices() {
        guard let capabilities else { return }
        let resolutions = capabilities.supportedResolutions
            .filter { $0.dpi > 0 }
            .sorted()
        if !resolutions.contains(resolutionChoice) {
            resolutionChoice = resolutions.contains(.r3600) ? .r3600 : (resolutions.first ?? resolutionChoice)
        }
        if !capabilities.supportedBitDepths.contains(bitDepthChoice) {
            bitDepthChoice = capabilities.supportedBitDepths.contains(.sixteen)
                ? .sixteen
                : (capabilities.supportedBitDepths.first ?? bitDepthChoice)
        }
        let modes = capabilities.supportedModes.filter { $0 == .color || $0 == .gray }
        if !modes.contains(colorModeChoice) {
            colorModeChoice = modes.contains(.color) ? .color : (modes.first ?? colorModeChoice)
        }
    }

    func scannerHardwareAdjustment(_ value: Double, range: ScannerOptionRange?) -> Double? {
        guard let range else { return nil }
        return range.clamped(value)
    }


}
