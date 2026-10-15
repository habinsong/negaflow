import Foundation
import CoreImage
import CoreGraphics

// MARK: - NeutralWhiteBalancePicker (중립 스포이드)
//
// 사용자가 찍은 점이 무채색이 되는 온도·틴트를 푼다. 값은 화이트밸런스 단계의 입력
// (ChromabaseEngine.developWhiteBalanceInputPreview)에서 잰다 — 게인은 그 값에 그대로 곱해지므로
// 역산이 정확하고, 그 뒤의 톤·커브(휘도 기반)는 중립을 중립으로 둔다. 화면 결과에서 재면 커브의
// 가산 밝힘이 채널비를 줄여 한 번에 맞지 않는다.
public enum NeutralWhiteBalancePicker {
    /// 평균 창 반경(긴 변 대비). 그레인 한 알이 아니라 찍은 면의 색을 잰다 — 3600px 프록시에서 ±14px.
    static let radiusFraction = 0.004

    /// 찍은 점(변형 전 정규 좌표, y-down) 주위의 linear 평균. 너무 어둡거나(비율이 잡음) 클리핑에
    /// 가까우면 nil — 자동 화이트밸런스의 중립 후보 조건(NeutralAxisEstimator)과 같다.
    public static func sample(_ image: CIImage, atUnit point: CGPoint) -> SIMD3<Double>? {
        let extent = image.extent.integral
        guard extent.width >= 1, extent.height >= 1, !extent.isInfinite else { return nil }
        let radius = max(2, (radiusFraction * Double(max(extent.width, extent.height))).rounded())
        let cx = extent.minX + min(max(point.x, 0), 1) * extent.width
        let cy = extent.maxY - min(max(point.y, 0), 1) * extent.height
        let window = CGRect(x: cx - radius, y: cy - radius, width: 2 * radius + 1, height: 2 * radius + 1)
            .integral.intersection(extent)
        guard !window.isNull, window.width >= 1, window.height >= 1 else { return nil }
        let w = Int(window.width), h = Int(window.height)
        var bitmap = [Float](repeating: 0, count: w * h * 4)
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        SamplingContextPool.context(workingColorSpace: linear).render(
            image, toBitmap: &bitmap, rowBytes: w * 4 * MemoryLayout<Float>.size,
            bounds: window, format: .RGBAf, colorSpace: linear)
        var sum = SIMD3<Double>(repeating: 0)
        for i in stride(from: 0, to: bitmap.count, by: 4) {
            sum += SIMD3(Double(bitmap[i]), Double(bitmap[i + 1]), Double(bitmap[i + 2]))
        }
        let mean = sum / Double(w * h)
        let floor = NeutralAxisEstimator.minimumChannel
        guard mean.x > floor, mean.y > floor, mean.z > floor,
              0.2126 * mean.x + 0.7152 * mean.y + 0.0722 * mean.z < NeutralAxisEstimator.maximumLuminance
        else { return nil }
        return mean
    }

    /// 화이트밸런스 입력값 c 를 중립으로 만드는 온도·틴트. 온도가 R/B 를, 틴트가 G/√(R·B) 를 맡는다
    /// (틴트는 R/B 를 바꾸지 않는다). 범위(±4)를 넘으면 끝값에서 멈춘다.
    public static func solve(_ reference: SIMD3<Double>) -> (warmth: Double, tint: Double)? {
        guard reference.x > 0, reference.y > 0, reference.z > 0 else { return nil }
        let redBlue = log2(reference.z / reference.x)
        let green = log2((reference.x * reference.z).squareRoot() / reference.y)
        let warmth = WhiteBalanceGains.solve(redBlue, WhiteBalanceGains.warmthRedBlueStops)
        let tint = WhiteBalanceGains.solve(green - WhiteBalanceGains.warmthGreenStops(warmth),
                                           WhiteBalanceGains.tintGreenStops)
        return (warmth, tint)
    }
}
