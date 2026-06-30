import CoreImage

// MARK: - SamplingContextPool
//
// 작은 비트맵 readback(히스토그램/퍼센타일/메디안 샘플링)용 CIContext 공유 캐시.
//
// 왜 필요한가: `CIContext` 생성은 Metal 디바이스·커맨드큐·중간 버퍼 힙을 할당하는 무거운
// 작업이다. 기존엔 AutoLevels/NeutralBalance/NegativeInversion/ToneMapper/FilmBaseEstimator가
// 매 현상(슬라이더 드래그마다)마다 `CIContext(...)`를 새로 만들었다. 드래그 중 초당 수십 개의
// 컨텍스트가 생성되고 GPU 자원이 즉시 회수되지 않아 메모리가 누적 → 렌더 실패(이미지가 사라지거나
// 직전 프레임이 남음)·오버플로우를 유발했다.
//
// 해결: 작업 색공간(workingColorSpace)별로 컨텍스트를 하나만 만들어 재사용한다. CIContext는
// 스레드 안전하므로 백그라운드 렌더 스레드에서 공유해도 된다(Apple 권장: 생성 비용이 크니 한 번
// 만들어 재사용). 색공간이 다르면 다운스케일 리샘플링 결과(linear vs sRGB 평균)가 달라지므로
// 색공간을 키로 분리해 기존 동작을 정확히 보존한다.
enum SamplingContextPool {
    private static let lock = NSLock()
    private static var cache: [String: CIContext] = [:]

    /// `workingColorSpace == nil` 이면 색 관리 비활성(NSNull)로 만든다(FilmBaseEstimator의
    /// raw 값 직독용). 그 외엔 working/output 모두 해당 색공간으로 설정한다.
    static func context(workingColorSpace cs: CGColorSpace?) -> CIContext {
        let key = (cs?.name as String?) ?? "__unmanaged__"
        lock.lock()
        defer { lock.unlock() }
        if let ctx = cache[key] {
            return ctx
        }
        let options: [CIContextOption: Any]
        if let cs {
            options = [.workingColorSpace: cs, .outputColorSpace: cs]
        } else {
            options = [.workingColorSpace: NSNull()]
        }
        let ctx = CIContext(options: options)
        cache[key] = ctx
        return ctx
    }
}
