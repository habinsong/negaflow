import CoreImage

/// 5 매듭 자연 3차 스플라인 톤 커브(양끝 2차 미분 0)를 **받은 값에 직접** 건다.
///
/// `CIToneCurve` 는 받은 값의 제곱근 위에서 스플라인을 계산하고 결과를 제곱한다. 이미 sRGB 로
/// 인코딩한 값에 걸면 감마가 두 번 걸려 매듭이 설계한 자리(sRGB 59·128·209)가 아니라
/// 13·64·172 에 놓인다. 표시값 도메인에서 설계한 커브는 이 단계를 쓴다. 윈도우
/// `scanner_profile_grade.cpp` 의 `make_tone_curve`·`tone_curve` 와 같은 식이다.
public enum NaturalToneSpline {
    /// 매듭 x(오름차순, 첫째 0·끝 1)와 y 에서 안쪽 매듭의 2차 미분을 구한다. 삼중대각 소거.
    static func secondDerivatives(x: [Double], y: [Double]) -> [Double] {
        precondition(x.count == 5 && y.count == 5)
        let h = (0..<4).map { x[$0 + 1] - x[$0] }
        let rhs = (1...3).map { i in 6 * ((y[i + 1] - y[i]) / h[i] - (y[i] - y[i - 1]) / h[i - 1]) }
        let d1 = 2 * (h[0] + h[1])
        let d2 = 2 * (h[1] + h[2]) - h[1] * h[1] / d1
        let d3 = 2 * (h[2] + h[3]) - h[2] * h[2] / d2
        let m3 = (rhs[2] - (h[2] / d2) * rhs[1] + (h[2] * h[1] / (d2 * d1)) * rhs[0]) / d3
        let m2 = (rhs[1] - h[2] * m3 - (h[1] / d1) * rhs[0]) / d2
        let m1 = (rhs[0] - h[1] * m2) / d1
        return [0, m1, m2, m3, 0]
    }

    /// `x` 는 (0, x1, x2, x3, 1), `y` 는 다섯 매듭의 출력이다. 입력 값 그대로 위에 건다.
    public static func apply(to image: CIImage, x: [Double], y: [Double]) -> CIImage {
        guard x.count == 5, y.count == 5,
              let kernel = ChromabaseMetalKernels.colorKernel(named: "naturalToneSpline5") else {
            return image
        }
        let extent = image.extent
        let m = secondDerivatives(x: x, y: y)
        return kernel.apply(extent: extent, arguments: [
            image,
            CIVector(x: x[1], y: x[2], z: x[3], w: y[0]),
            CIVector(x: y[1], y: y[2], z: y[3], w: y[4]),
            CIVector(x: m[1], y: m[2], z: m[3], w: 0),
        ])?.cropped(to: extent) ?? image
    }
}
