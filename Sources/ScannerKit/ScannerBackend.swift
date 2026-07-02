import Foundation

// MARK: - ScannerBackend protocol (plan §7.1)

/// 모든 스캐너 백엔드가 구현해야 하는 추상 인터페이스.
/// UI는 이 프로토콜에만 의존한다. 실제 하드웨어 구현은 외부 플러그인 뒤에 숨긴다.
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
/// 하드웨어 스캐너는 외부 프로세스 플러그인이 담당하고, Mock은 하드웨어 없는 개발/데모 경로를 제공한다.
///   1. 설치된 스캐너 플러그인(ExternalScannerBackend)
///   2. Mock
public final class ScannerRegistry: @unchecked Sendable {
    public private(set) var backends: [ScannerBackend]
    private let queue = DispatchQueue(label: "negaflow.scanner.registry")

    public init(backends: [ScannerBackend]) { self.backends = backends }

    /// 기본 레지스트리. 설치된 스캐너 플러그인을 먼저 등록하고, Mock은 항상 폴백으로 둔다.
    public static func `default`() -> ScannerRegistry {
        let plugins = ScannerPluginHost.discover().map { ExternalScannerBackend(plugin: $0) }
        return ScannerRegistry(backends: plugins + [MockScannerBackend()])
    }

    /// 등록된 모든 백엔드에서 장치를 수집한다.
    ///
    /// 최적화: 백엔드별로 동시에 probe 한다(TaskGroup). 느린 하드웨어 플러그인이 있어도
    /// Mock과 다른 백엔드가 즉시 반환하므로 UI가 빨리 채워진다.
    public func detectAll() async throws -> [(backend: BackendType, devices: [ScannerDescriptor])] {
        let snapshot = backends
        return await withTaskGroup(of: (Int, BackendType, [ScannerDescriptor]).self) { group in
            for (idx, b) in snapshot.enumerated() {
                group.addTask {
                    let devs = (try? await b.detectScanners()) ?? []
                    return (idx, b.backendType, devs)
                }
            }
            var collected: [(Int, BackendType, [ScannerDescriptor])] = []
            for await r in group { collected.append(r) }
            // 원래 backends 순서대로 정렬.
            collected.sort { $0.0 < $1.0 }
            return collected.map { ($0.1, $0.2) }
        }
    }

    /// 특정 장치 ID를 지원하는 백엔드를 찾는다. 플러그인 장치는 소유 플러그인으로 우선 매칭한다.
    public func backend(for scannerID: String) -> ScannerBackend? {
        if let owner = backends
            .compactMap({ $0 as? ExternalScannerBackend })
            .first(where: { $0.owns(scannerID: scannerID) }) {
            return owner
        }
        return backends.first(where: { $0.backendType == BackendType(fromScannerID: scannerID) })
    }
}

extension BackendType {
    /// scannerID 접두사에서 백엔드 종류를 유추. "plugin:...", "ica-...", "mock-..."
    public init(fromScannerID id: String) {
        if id.hasPrefix("plugin:")    { self = .plugin }
        else if id.hasPrefix("sane-") { self = .sane }
        else if id.hasPrefix("ica-")  { self = .imageCaptureCore }
        else                          { self = .mock }
    }
}
