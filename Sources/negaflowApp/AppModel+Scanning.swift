import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    // MARK: detection
    func refreshDevices() async {
        isDetecting = true
        defer { isDetecting = false }
        _ = SaneConfigTuner.tune()   // dll.conf 최적화(idempotent)
        saneBackend.invalidateAddressCache()
        let sane = (try? await saneBackend.detectScanners()) ?? []
        devices = sane
        if demoMode {
            selectedDeviceID = Self.mockDeviceID
            await loadCapabilities()
        } else if hasSANE {
            if selectedDeviceID == nil || !saneDevices.contains(where: { $0.id == selectedDeviceID }) {
                selectedDeviceID = saneDevices.first?.id
            }
            await loadCapabilities()
        } else {
            selectedDeviceID = nil
            capabilities = nil
        }
        statusMessage = demoMode ? "Demo 모드" : (hasSANE ? "Ready" : "스캐너 연결 대기 중")
    }

    func toggleDemo(_ on: Bool) {
        demoMode = on
        if on {
            selectedDeviceID = Self.mockDeviceID
            statusMessage = "Demo 모드"
        } else {
            selectedDeviceID = saneDevices.first?.id
            statusMessage = hasSANE ? "Ready" : "스캐너 연결 대기 중"
        }
        Task { await loadCapabilities() }
    }

    func loadCapabilities() async {
        guard let id = effectiveScannerID, let b = backend else { return }
        capabilities = try? await b.getCapabilities(scannerID: id)
        if capabilities?.supportsMultiExposure != true {
            multiExposureEnabled = false
        }
    }

    // MARK: scan (단일 + 배치)
    func runScan(preview: Bool) async {
        await scanFrames(count: 1, preview: preview)
    }

    /// N프레임 연속 스캔. 한 번에 하나만(currentProcess 단일 슬롯).
    /// 배치 진행률 = (frameIndex + frameFraction) / totalFrames 로 리매핑.
    func scanFrames(count: Int, preview: Bool) async {
        guard let id = effectiveScannerID, let backend = backend else {
            statusMessage = "스캐너가 없습니다 — USB를 연결하거나 Demo 모드를 켜세요."
            return
        }
        batchTotal = count
        isScanning = true
        for i in 0..<count {
            batchIndex = i
            var opts: ScanOptions
            if preview {
                opts = ScanOptions.preview(scannerID: id, filmType: filmType)
            } else {
                opts = ScanOptions.strongDefault(scannerID: id)
                opts.resolution = resolutionChoice
                opts.bitDepth = bitDepthChoice
                opts.colorMode = colorModeChoice
                opts.filmType = filmType
                opts.multiExposureEnabled = multiExposureEnabled && (capabilities?.supportsMultiExposure == true)
            }
            opts.temporaryOutputURL = SANEBackend.makeTempURL(prefix: "negaflow_app", suffix: ".tiff")
            scanPhase = preview ? .previewScanning : .scanningRGB
            do {
                let remap: @Sendable (ScanProgress) -> ScanProgress = { p in
                    var q = p
                    if let f = p.fraction {
                        let total = Double(count)
                        q.fraction = (Double(i) + f) / total
                    }
                    return q
                }
                let result = preview
                    ? try await backend.startPreviewScan(opts, progress: { [weak self] p in
                        Task { @MainActor in self?.update(remap(p)) }
                    })
                    : try await backend.startFullScan(opts, progress: { [weak self] p in
                        Task { @MainActor in self?.update(remap(p)) }
                    })
                let frame = ScanFrame(
                    scanIndex: frames.count + 1,
                    rawScanURL: result.rawFileURL,
                    filmType: filmType,
                    initialTransform: nextScanOrientation
                )
                frame.preset = presets.first(where: { $0.id == "neutral" })
                frame.updateParams {
                    $0.filmType = filmType
                    $0.developTarget = developTarget
                    $0.scannerProfileID = scannerProfileID
                }
                frames.append(frame)
                selectedFrameID = frame.id
                statusMessage = "Frame \(frame.scanIndex) 스캔 완료: \(result.width)×\(result.height)"
                // 현상을 await하지 않고 백그라운드로 띄운다 → 스캐너가 현상 동안 유휴하지 않고
                // 다음 프레임 하드웨어 스캔을 곧바로 시작한다(배치 처리량↑). 품질/해상도는 불변.
                // 현상 진행은 프레임 썸네일 스피너 + 하단 processing 상태로 표시된다.
                Task { await developFrame(frame) }
            } catch {
                statusMessage = "Frame \(i+1) 스캔 오류: \(error.localizedDescription)"
                scanPhase = .error
                break
            }
        }
        batchTotal = 0
        batchIndex = 0
        isScanning = false
        if scanPhase != .error {
            scanPhase = .complete
            statusMessage = "\(count)프레임 스캔 완료"
        }
    }

    func cancelScan() async {
        await backend?.cancelScan()
        isScanning = false
        batchTotal = 0
        scanPhase = .idle
        statusMessage = "스캔 취소됨"
    }

    func runDiagnostics() async {
        guard let id = effectiveScannerID, let b = backend else { diagnostics = "활성 스캐너가 없습니다."; return }
        let cap = (try? await b.getCapabilities(scannerID: id)) ?? ScannerCapabilities()
        diagnostics = """
        Scanner   : \(devices.first(where: { $0.backendType == .sane })?.displayName ?? (demoMode ? "Mock" : id))
        Backend   : \(b.backendType.rawValue)
        Resol.    : \(cap.supportedResolutions.map(\.dpi))
        Modes     : \(cap.supportedModes.map(\.rawValue))
        BitDepth  : \(cap.supportedBitDepths.map(\.rawValue))
        IR        : \(cap.supportsInfrared)
        dll tuned : \(SaneConfigTuner.isTuned)
        """
    }

    private func update(_ p: ScanProgress) {
        // 스캔 종료 후 늦게 도착하는 진행 콜백이 완료/취소 상태를 덮어써(역행) 진행률이 어긋나는 것을 막는다.
        guard isScanning else { return }
        let now = Date()
        let nextFraction = p.fraction ?? scanFraction
        let message = p.message.isEmpty ? p.phase.rawValue : p.message
        let phaseChanged = p.phase != lastProgressPhase
        let messageChanged = message != lastProgressMessage
        let fractionMoved = abs(nextFraction - lastProgressFraction) >= 0.015
        let timeElapsed = now.timeIntervalSince(lastProgressUpdateAt) >= 0.20
        guard phaseChanged || messageChanged || fractionMoved || timeElapsed else { return }
        lastProgressUpdateAt = now
        lastProgressFraction = nextFraction
        lastProgressPhase = p.phase
        lastProgressMessage = message
        scanPhase = p.phase
        scanFraction = nextFraction
        statusMessage = message
    }
}
