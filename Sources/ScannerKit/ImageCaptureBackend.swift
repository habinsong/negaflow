import Foundation
// ImageCaptureCore는 앱 타겟에서만 임포트한다(SPM 라이브러리 타겟에서 ICA 의존성 분리).
// 여기서는 백엔드 인터페이스만 제공하고, 실제 ICA 연동은 NegaflowApp에서 수행한다.

// MARK: - ImageCaptureBackend (plan §6.2 — 골격)
//
// Phase 0 검증 결론:
//   Plustek OpticFilm 8200i는 ICDeviceBrowser에 노출되지 않는다(0 devices).
//   제조사 ICA 드라이버가 없기 때문이다. 따라서 현재 이 백엔드는 비활성 상태로,
//   미래 호환 모델(8300i 등이 ICA에 노출되는 경우)을 대비해 프로토콜만 갖춘다.
//
//   실제 ICA 드라이버가 설치된 환경에서는 NegaflowApp 계층의
//   ImageCaptureBridge가 이 프로토콜을 구현한다.
public protocol ImageCaptureBridge: ScannerBackend {
    /// ICA가 장치를 발견했는지 여부. 앱 시작 시 한 번 검증용.
    func isAvailable() async -> Bool
}

/// ICA 미지원 환경에서 사용하는 비활성 백엔드. detectScanners()는 항상 빈 배열.
public final class InactiveImageCaptureBackend: ImageCaptureBridge, @unchecked Sendable {
    public let backendType: BackendType = .imageCaptureCore
    public init() {}
    public func getLastError() -> ScannerError? { nil }

    public func isAvailable() async -> Bool { false }

    public func detectScanners() async throws -> [ScannerDescriptor] { [] }
    public func getCapabilities(scannerID: String) async throws -> ScannerCapabilities {
        throw ScannerError(.notConnected, "ImageCaptureCore inactive on this device")
    }
    public func startPreviewScan(_ options: ScanOptions,
                                 progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> ScanResult {
        throw ScannerError(.notConnected, "ImageCaptureCore inactive on this device")
    }
    public func startFullScan(_ options: ScanOptions,
                              progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> ScanResult {
        throw ScannerError(.notConnected, "ImageCaptureCore inactive on this device")
    }
    public func cancelScan() async {}
}
