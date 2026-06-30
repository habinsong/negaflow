import CoreImage
import Metal

// 모든 ICE 검출·복원이 공유하는 CIContext.
//
// CIContext 생성은 Metal 파이프라인 초기화를 동반해 매우 비싸다(Apple 권장: 한 번
// 만들어 재사용). 기존엔 detect/repair 가 `context: CIContext = CIContext(...)` 를
// default 인자로 갖고 있어, 스트로크가 청크로 쪼개질 때마다 새 컨텍스트를 만들었다
// (브러시 한 번에 수~수십 개). 이게 결함 제거가 수 초씩 걸린 주원인이다.
//
// CIContext 와 CIImage 는 immutable·thread-safe 라 여러 백그라운드 스레드가 같은
// 컨텍스트로 동시에 렌더해도 안전하다.
public enum ICEContext {
    private static let device = MTLCreateSystemDefaultDevice()

    /// 검출용. 다운스케일·대비 계산을 선형 도메인에서 한다(기존 동작 유지).
    public static let detect = make(CGColorSpace.linearSRGB)

    /// 복원·패치 렌더용. sRGB 감마 도메인.
    public static let render = make(CGColorSpace.sRGB)

    /// raw(16bit linear) 도메인 복원·평탄화용. raw 스캔에 직접 ICE를 적용할 때 정밀도와
    /// 색공간을 보존한다.
    public static let renderLinear = make(CGColorSpace.linearSRGB)

    private static func make(_ space: CFString) -> CIContext {
        let options: [CIContextOption: Any] = [
            .workingColorSpace: CGColorSpace(name: space) as Any,
            .cacheIntermediates: false,
        ]
        if let device { return CIContext(mtlDevice: device, options: options) }
        return CIContext(options: options)
    }
}
