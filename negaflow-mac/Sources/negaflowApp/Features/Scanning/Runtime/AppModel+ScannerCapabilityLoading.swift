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
            resolutionChoice = Self.preferredScanResolution(
                in: resolutions,
                isFlatbed: capabilities.supportsPositionedScanArea == true
            ) ?? resolutionChoice
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

    /// 필름 스캔 기본 해상도의 목표값. 장치가 이 값을 지원하지 않으면 근사값을 쓴다.
    static let targetScanDPI = Resolution.r3600.dpi

    /// 평판 프리뷰 목표 해상도. 프리뷰는 그 위에서 필름 영역을 잡는 작업면이라 프레임
    /// 경계가 보일 만큼은 되어야 하고, 본 스캔만큼 오래 걸리면 의미가 없다.
    ///
    /// 300dpi면 8×10 유리판이 3000픽셀, 가장 작은 규격인 하프프레임(18 × 24 mm)이
    /// 213 × 283픽셀이라 프레임 검출에 여유가 있다. 검출기는 긴 변 2048픽셀로 줄여
    /// 분석하므로 그 여유분은 검출이 아니라 사람이 눈으로 영역을 잡을 때 쓰인다.
    static let targetFlatbedPreviewDPI = 300

    /// 평판 필름 스캔 기본 해상도의 목표값.
    ///
    /// 평판은 목록에 6400dpi 이상까지 올라오지만 필름에서 실제로 분해되는 해상도는 그보다
    /// 훨씬 낮다. GT-X900 실측에서 렌즈를 홀더용으로 바꾼 것만으로 선명도가 1.76배 달라졌고,
    /// 그 위쪽 값들은 파일만 커진다. 2400dpi 는 35mm 한 컷이 3400×2270픽셀이라 인화에 충분한
    /// 크기이면서, 스캔 시간과 용량이 실용 범위에 남는 지점이다.
    static let targetFlatbedScanDPI = 2400

    /// 목록에 목표값이 없을 때 쓸 필름 스캔 기본 해상도. 오름차순 목록의 첫 값을 쓰면
    /// 50dpi부터 노출하는 기기(epson2 평판: 50|60|…|12800dpi)에서 기본값이 최저 해상도로
    /// 떨어진다.
    static func preferredScanResolution(
        in resolutions: [Resolution],
        isFlatbed: Bool = false
    ) -> Resolution? {
        nearestSupportedResolution(
            to: isFlatbed ? targetFlatbedScanDPI : targetScanDPI,
            in: resolutions
        )
    }

    /// 평판 프리뷰에 쓸 해상도. 장치가 실제로 지원하는 값 중에서만 고른다.
    static func preferredFlatbedPreviewResolution(in resolutions: [Resolution]) -> Resolution? {
        nearestSupportedResolution(to: targetFlatbedPreviewDPI, in: resolutions)
    }

    /// 목표 dpi에 가장 가까운 지원 값. 같은 거리면 큰 쪽을 쓴다.
    static func nearestSupportedResolution(to dpi: Int, in resolutions: [Resolution]) -> Resolution? {
        let usable = resolutions.filter { $0.dpi > 0 }
        if let exact = usable.first(where: { $0.dpi == dpi }) { return exact }
        return usable.min {
            let first = abs($0.dpi - dpi)
            let second = abs($1.dpi - dpi)
            return first != second ? first < second : $0.dpi > $1.dpi
        }
    }

    static func scannerHardwareAdjustment(
        _ value: Double,
        range: ScannerOptionRange?,
        scannerID: String,
        bitDepth: BitDepth
    ) -> Double? {
        guard let range else { return nil }
        let backend = scannerID
            .replacingOccurrences(of: "sane-", with: "")
            .split(separator: ":", maxSplits: 1)
            .first
            .map(String.init)?
            .lowercased()
        if backend == "genesys", bitDepth == .sixteen {
            return nil
        }
        let clamped = range.clamped(value)
        return clamped == 0 ? nil : clamped
    }


}
