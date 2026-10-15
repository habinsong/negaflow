import Foundation
import CoreImage

// MARK: - ExposureShoulder
//
// 노출 슬라이더의 + 쪽. 반전은 이미 숄더가 들어간 인화 응답(측정 최농부 0.70, 천장 0.90)을
// 내므로, 그 위에 2^EV 만 곱하면 숄더가 다시 펴지고 0.515 EV 만에 1.0 에서 하드 클립된다
// (2026-10-14 실측: +1 EV 에 웨지 상위 6 패치가 255, Highlights −1 로도 229 평탄면).
// Lightroom PV2012 노출이 필름 DlogE 숄더처럼 명부를 소프트 클립하는 것과 같은 계약으로:
//   • 휘도가 확산 화이트(knee) 아래면 정확히 2^EV — 미드그레이는 EV ≤ log2(knee/0.18) ≈ 1.96 까지 정확.
//   • 그 위는 1.0 에 점근하는 지수 숄더 S(u) = 1 − (1−k)·exp(−(u−k)/(1−k)) (knee 에서 C1 연속).
//   • 0 < EV < 헤드룸 E0 에서는 선형과 숄더를 EV/E0 로 섞어 EV 0 의 항등과 연속시킨다.
// 상수는 인화 응답 앵커에서 유도한다: knee = 컬러 확산 화이트, E0 = log2(1 / 필름 타입 화이트).
// 흑백 네거티브는 화이트가 0.85 라 E0 = 0.234 — 같은 knee 를 써야 +1 EV 에서도 숄더 폭이 남는다.
enum ExposureShoulder {
    static let knee = NegativeInversion.colorResponse.whiteOutput

    static func headroomStops(for filmType: FilmType) -> Double {
        log2(1.0 / NegativeInversion.response(for: filmType).whiteOutput)
    }

    static func blend(stops: Double, filmType: FilmType) -> Double {
        min(1.0, max(0.0, stops / headroomStops(for: filmType)))
    }

    /// CPU 참조 — 휘도 하나의 노출 결과(커널과 같은 식). 자동 톤의 순방향 모델이 공유한다.
    static func exposedLuminance(_ y: Double, stops: Double, filmType: FilmType) -> Double {
        let u = y * pow(2.0, stops)
        guard stops > 0, u > knee else { return u }
        let room = 1.0 - knee
        let shoulder = 1.0 - room * exp(-(u - knee) / room)
        return u + (shoulder - u) * blend(stops: stops, filmType: filmType)
    }

    /// exposedLuminance 의 역 — 잰 휘도(숄더에 이미 접힌 값)를 노출 전 휘도로 되돌린다. 숄더는 단조
    /// 증가라 이분법으로 푼다. ÷2^EV 로 되돌리면 한 번 접힌 값을 다시 숄더에 넣어 두 번 접고, 백점을
    /// 낮게 예측해 화이트를 거꾸로 올린다(2026-10-14 Windows 실측: 커브로 247 인 백점을 250 으로).
    static func unexposedLuminance(_ exposed: Double, stops: Double, filmType: FilmType) -> Double {
        var low = exposed / pow(2.0, stops)
        guard stops > 0, exposedLuminance(low, stops: stops, filmType: filmType) < exposed else { return low }
        var high = max(low * 2, 64)
        guard exposedLuminance(high, stops: stops, filmType: filmType) >= exposed else { return high }
        for _ in 0..<60 {
            let middle = 0.5 * (low + high)
            if exposedLuminance(middle, stops: stops, filmType: filmType) < exposed { low = middle } else { high = middle }
        }
        return 0.5 * (low + high)
    }

    /// EV > 0 전용. 커널이 없으면 nil — 호출측이 선형 곱으로 폴백한다.
    static func apply(to image: CIImage, gain: Double, stops: Double, filmType: FilmType) -> CIImage? {
        guard stops > 0,
              let kernel = ChromabaseMetalKernels.colorKernel(named: "exposureShoulder") else { return nil }
        return kernel.apply(extent: image.extent, arguments: [
            image,
            Float(gain),
            Float(knee),
            Float(blend(stops: stops, filmType: filmType)),
        ])?.cropped(to: image.extent)
    }
}
