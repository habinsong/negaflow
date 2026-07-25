import Foundation
import CoreGraphics
import ImageIO
import Chromabase

// MARK: - ExternalScannerBackend
//
// 설치된 외부 스캐너 플러그인 하나를 감싸는 백엔드. 플러그인 실행파일을 Process 로 띄워
// JSON/CLI 프로토콜(detect / capabilities / scan)로 통신한다. negaflow 는 이 백엔드만 알고
// 특정 scanner 구현은 전혀 모른다.
public final class ExternalScannerBackend: ScannerBackend, @unchecked Sendable {
    public let backendType: BackendType = .plugin
    public let plugin: InstalledScannerPlugin

    var lastError: ScannerError?
    let processLock = NSLock()
    var currentProcess: Process?
    var currentProcessCancellation: (@Sendable () -> Void)?
    var currentProcessCompletion: ProcessCleanupToken?
    private let capabilityTokenLock = NSLock()
    private var capabilityTokens: [String: String] = [:]
    private let detectedDeviceLock = NSLock()
    private var detectedDevices: [String: ScannerDescriptor] = [:]

    public init(plugin: InstalledScannerPlugin) { self.plugin = plugin }

    public func getLastError() -> ScannerError? { lastError }

    /// 이 백엔드가 소유한 장치 id 인가. 외부 id 는 `plugin:<pluginId>:<내부id>`.
    public func owns(scannerID: String) -> Bool {
        scannerID.hasPrefix(externalPrefix)
    }

    var externalPrefix: String { "plugin:\(plugin.id):" }
    func externalID(_ internalID: String) -> String { externalPrefix + internalID }
    func internalID(_ scannerID: String) -> String {
        scannerID.hasPrefix(externalPrefix)
            ? String(scannerID.dropFirst(externalPrefix.count))
            : scannerID
    }

    // MARK: detect
    public func detectScanners() async throws -> [ScannerDescriptor] {
        try validatePluginCompatibility()
        let out = try await run(args: ["detect"], stdin: nil, onLine: nil)
        guard out.status == 0 else {
            throw failure(.ioFailure, "plugin detect 실패: \(out.stderrText)")
        }
        guard let response = try? JSONDecoder().decode(PluginDetectResponse.self, from: out.stdout) else {
            throw failure(.ioFailure, "plugin detect 응답 파싱 실패")
        }
        var seenDeviceIDs = Set<String>()
        let descriptors = response.devices.compactMap { device -> ScannerDescriptor? in
            let deviceID = externalID(device.id)
            guard seenDeviceIDs.insert(deviceID).inserted else { return nil }
            return ScannerDescriptor(
                id: deviceID,
                displayName: device.displayName,
                vendor: device.vendor,
                model: device.model,
                backendType: .plugin,
                connectionType: ConnectionType(rawValue: device.connectionType ?? "usb") ?? .usb,
                usbVendorID: device.usbVendorID,
                usbProductID: device.usbProductID,
                serialNumber: device.serialNumber,
                verifiedStatus: VerifiedStatus(rawValue: device.verifiedStatus ?? "") ?? .compatibleTarget,
                driverVersion: device.driverVersion ?? plugin.name
            )
        }
        setDetectedDevices(descriptors)
        clearCapabilityTokens()
        return descriptors
    }

    // MARK: capabilities
    public func getCapabilities(scannerID: String) async throws -> ScannerCapabilities {
        try validatePluginCompatibility()
        let internalDeviceID = internalID(scannerID)
        let requestData: Data?
        if let descriptor = detectedDevice(for: scannerID) {
            requestData = try? JSONEncoder().encode(
                PluginCapabilityRequest(
                    deviceID: internalDeviceID,
                    vendor: descriptor.vendor,
                    model: descriptor.model
                )
            )
        } else {
            requestData = nil
        }
        let out = try await run(
            args: ["capabilities", internalDeviceID],
            stdin: requestData,
            onLine: nil
        )
        guard out.status == 0 else {
            throw failure(.ioFailure, "plugin capabilities 실패: \(out.stderrText)")
        }
        guard let caps = try? JSONDecoder().decode(PluginCapabilities.self, from: out.stdout) else {
            throw failure(.ioFailure, "plugin capabilities 응답 파싱 실패")
        }
        setCapabilityToken(
            plugin.manifest.resolvedProtocolVersion == ScannerPluginManifest.streamProtocolVersion
                ? caps.capabilityToken
                : nil,
            for: scannerID
        )
        let decodedScanAreaUnit = caps.scanAreaUnit.flatMap(ScanAreaUnit.init(rawValue:))
        let scanAreaUnit = decodedScanAreaUnit ?? .millimeter
        let supportsScanArea = (caps.supportsScanArea ?? false)
            && (caps.scanAreaUnit == nil || decodedScanAreaUnit != nil)
        let supportsPositionedScanArea = supportsScanArea
            && caps.supportsPositionedScanArea == true
            && caps.scanOriginXRange != nil
            && caps.scanOriginYRange != nil
            && caps.scanWidthRange != nil
            && caps.scanHeightRange != nil
        return ScannerCapabilities(
            supportedResolutions: caps.resolutionsDPI.map { Resolution($0) }.sorted(),
            supportedModes: caps.modes.compactMap { ColorMode(rawValue: $0) },
            supportedBitDepths: caps.bitDepths.compactMap { BitDepth(rawValue: $0) },
            sourceModes: caps.sourceModes ?? [],
            transparencyModes: caps.transparencyModes ?? [],
            supportsPreview: caps.supportsPreview ?? false,
            supportsTransparency: caps.supportsTransparency ?? false,
            supportsInfrared: caps.supportsInfrared ?? false,
            supportsMultiExposure: caps.supportsMultiExposure ?? false,
            supportsScanArea: supportsScanArea,
            supportsPositionedScanArea: supportsPositionedScanArea,
            supportsLampWarmupStatus: false,
            brightnessRange: caps.brightnessRange,
            contrastRange: caps.contrastRange,
            hardwareExposureRange: caps.hardwareExposureRange,
            scanOriginXRange: caps.scanOriginXRange,
            scanOriginYRange: caps.scanOriginYRange,
            scanWidthRange: caps.scanWidthRange,
            scanHeightRange: caps.scanHeightRange,
            disabledReasons: caps.disabledReasons ?? [:],
            maxScanArea: ScanArea(
                originXMM: caps.maxScanAreaOriginXMM ?? 0,
                originYMM: caps.maxScanAreaOriginYMM ?? 0,
                widthMM: caps.maxScanAreaWidthMM ?? 0,
                heightMM: caps.maxScanAreaHeightMM ?? 0
            ),
            minScanArea: ScanArea(
                originXMM: caps.minScanAreaOriginXMM ?? caps.maxScanAreaOriginXMM ?? 0,
                originYMM: caps.minScanAreaOriginYMM ?? caps.maxScanAreaOriginYMM ?? 0,
                widthMM: caps.minScanAreaWidthMM ?? 0,
                heightMM: caps.minScanAreaHeightMM ?? 0
            ),
            scanAreaUnit: scanAreaUnit,
            outputFormats: caps.outputFormats ?? []
        )
    }

    func capabilityToken(for scannerID: String) -> String? {
        capabilityTokenLock.lock()
        defer { capabilityTokenLock.unlock() }
        return capabilityTokens[scannerID]
    }

    private func setCapabilityToken(_ token: String?, for scannerID: String) {
        capabilityTokenLock.lock()
        defer { capabilityTokenLock.unlock() }
        if let token, !token.isEmpty {
            capabilityTokens[scannerID] = token
        } else {
            capabilityTokens.removeValue(forKey: scannerID)
        }
    }

    private func clearCapabilityTokens() {
        capabilityTokenLock.lock()
        defer { capabilityTokenLock.unlock() }
        capabilityTokens.removeAll()
    }

    private func detectedDevice(for scannerID: String) -> ScannerDescriptor? {
        detectedDeviceLock.lock()
        defer { detectedDeviceLock.unlock() }
        return detectedDevices[scannerID]
    }

    private func setDetectedDevices(_ descriptors: [ScannerDescriptor]) {
        detectedDeviceLock.lock()
        defer { detectedDeviceLock.unlock() }
        detectedDevices = Dictionary(
            descriptors.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: scan
    public func startPreviewScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        try await scan(options, preview: true, progress: progress)
    }

    public func startFullScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        try await scan(options, preview: false, progress: progress)
    }


}
