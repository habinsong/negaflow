import Foundation

// MARK: - ScannerBackend protocol (plan §7.1)

/// 모든 스캐너 백엔드가 구현해야 하는 추상 인터페이스.
/// UI는 이 프로토콜에만 의존한다 — ImageCaptureCore/SANE/Mock을 구분하지 않는다 (plan §4.3).
public protocol ScannerBackend: AnyObject {
    var backendType: BackendType { get }

    /// 현재 연결 가능한 스캐너 목록을 반환한다.
    func detectScanners() async throws -> [ScannerDescriptor]

    /// 특정 스캐너의 capability를 조회한다. 모델명이 아닌 장치 능력 기반 (plan §5.3).
    func getCapabilities(scannerID: String) async throws -> ScannerCapabilities

    /// 프리뷰(overview) 스캔. 저해상도 빠른 스캔.
    func startPreviewScan(_ options: ScanOptions,
                          progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> ScanResult

    /// 본스캔. 고해상도 캡처.
    func startFullScan(_ options: ScanOptions,
                      progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> ScanResult

    /// 진행 중인 스캔을 취소한다.
    func cancelScan() async

    /// 마지막 오류를 반환한다.
    func getLastError() -> ScannerError?
}

// MARK: - ScannerRegistry (백엔드 선택)

/// 사용 가능한 백엔드를 우선순위대로 보관하고, 장치를 가장 잘 지원하는 백엔드를 고른다.
///
/// Phase 0 검증 결과에 따른 기본 우선순위:
///   1. SANE (genesys)  — 8200i에서 16bit/7200dpi/투과유닛 전부 검증됨
///   2. ImageCaptureCore — macOS 네이티브지만 8200i 미노출(제조사 ICA 드라이버 없음)
///   3. Mock             — 하드웨어 없는 개발/데모
public final class ScannerRegistry: @unchecked Sendable {
    public private(set) var backends: [ScannerBackend]
    private let queue = DispatchQueue(label: "negaflow.scanner.registry")

    public init(backends: [ScannerBackend]) { self.backends = backends }

    /// 기본 레지스트리. 검증된 SANE을 primary로, Mock은 항상 보험으로 깔아둔다.
    public static func `default`(scanimagePath: String? = nil) -> ScannerRegistry {
        ScannerRegistry(backends: [
            SANEBackend(scanimagePath: scanimagePath),
            MockScannerBackend(),
        ])
    }

    /// 등록된 모든 백엔드에서 장치를 수집한다.
    public func detectAll() async throws -> [(backend: BackendType, devices: [ScannerDescriptor])] {
        var out: [(BackendType, [ScannerDescriptor])] = []
        for b in backends {
            do {
                let devices = try await b.detectScanners()
                out.append((b.backendType, devices))
            } catch {
                // 한 백엔드 실패가 전체를 막지 않게 한다.
                out.append((b.backendType, []))
            }
        }
        return out
    }

    /// 특정 장치 ID를 지원하는 백엔드를 찾는다.
    public func backend(for scannerID: String) -> ScannerBackend? {
        backends.first(where: { $0.backendType == BackendType(fromScannerID: scannerID) })
    }
}

extension BackendType {
    /// scannerID 접두사에서 백엔드 종류를 유추. "sane-...", "ica-...", "mock-..."
    public init(fromScannerID id: String) {
        if id.hasPrefix("sane-")      { self = .sane }
        else if id.hasPrefix("ica-")  { self = .imageCaptureCore }
        else                          { self = .mock }
    }
}
