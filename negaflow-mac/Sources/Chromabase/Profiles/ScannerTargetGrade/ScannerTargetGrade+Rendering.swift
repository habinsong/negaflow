import CoreImage
import Foundation

extension ScannerTargetGrade {
    // MARK: 스캐너 렌더링 모델 — 장면과 무관한 고정 변환
    //
    // 랩 스캐너는 네거티브를 밀도로 읽은 뒤 회색 밸런스·농도를 프레임마다 맞추고(오토셋업),
    // 고정 계조 곡선과 색 변환으로 출력을 만든다(Frontier 350, IS&T PICS 1999 / Kodak US6233069).
    // negaflow 에서 프레임별 밸런스는 반전(장면 범위 측정)과 우측 패널의 자동 레벨·색상·톤·WB 가
    // 맡는다. 타깃은 그 뒤의 고정 렌더링만 재현한다 — 장면을 읽지 않으므로 같은 화소는 어느 사진에
    // 있든 같은 값이 되고, 타깃 전환은 파라미터 교체뿐이다.
    //
    // 화소 하나의 계산(작업공간 선형 sRGB, MAIN 반전 출력 기준):
    //   1. 휘도 Y 와 스탑 y = log2(Y / 0.18), 채널 색비 d = log2(rgb) − log2(Y).
    //   2. 색비 크로스토크(행 합 1): 스캐너 색 변환의 hue 결합.
    //   3. 밝기별 R·B 색비 오프셋(스탑): 회색 축의 크로스오버.
    //   4. 휘도 톤 곡선 T(y) → 출력 sRGB 코드, 밝기별 색비 게인 g(y) 로 채도를 싣는다.
    //   5. 휘도를 지킨 채 색비를 되돌리고, 색역을 넘으면 같은 휘도에서 채도만 줄인다.
    // 곡선은 모두 단조 3차(PCHIP) 보간이라 knot 에서 꺾이지 않는다.
    //
    // 값의 근거는 rendering(for:) 의 각 표 주석에 있다.

    /// 톤 knot 위치(18% 회색 기준 스탑).
    static let renderingToneStops: [Double] = [-8, -6, -4, -3, -2, -1, 0, 1, 1.5, 2, 2.5]
    /// 색비 게인 knot 위치(스탑).
    static let renderingChromaStops: [Double] = [-5, -2, 0, 2]
    /// 회색 축 오프셋 knot 위치(스탑).
    static let renderingBalanceStops: [Double] = [-4, -1, 2]
    /// 포지티브(슬라이드)는 직접 디지털화라 네거티브 렌더링을 절반만 싣는다(실측 없음).
    static let renderingPositiveStrength = 0.5

    struct Rendering: Equatable, Sendable {
        /// renderingToneStops 위치의 출력 sRGB 코드(회색의 휘도).
        var tone: [Double]
        /// renderingChromaStops 위치의 log 색비 게인(1 = 입력 채도 유지).
        var chromaGain: [Double]
        /// 색비 크로스토크 (R←G, R←B, G←R, G←B, B←R, B←G).
        var crosstalk: [Double]
        /// renderingBalanceStops 위치의 R·B 색비 오프셋(스탑, G 기준).
        var redBalance: [Double]
        var blueBalance: [Double]
    }

    /// 단조 3차 Hermite(PCHIP). 내부 기울기는 가중 조화평균, 양끝은 할선 기울기이고 범위 밖은
    /// 끝 기울기로 직선 연장한다. 적합 스크립트·Metal 커널·Windows 판이 모두 이 정의를 쓴다.
    struct RenderingCurve: Equatable, Sendable {
        let xs: [Double]
        let ys: [Double]
        let ms: [Double]

        init(xs: [Double], ys: [Double]) {
            precondition(xs.count == ys.count && xs.count >= 2)
            let n = xs.count
            var h = [Double](repeating: 0, count: n - 1)
            var d = [Double](repeating: 0, count: n - 1)
            for i in 0..<(n - 1) {
                h[i] = xs[i + 1] - xs[i]
                d[i] = (ys[i + 1] - ys[i]) / h[i]
            }
            var m = [Double](repeating: 0, count: n)
            for i in 1..<(n - 1) where d[i - 1] * d[i] > 0 {
                let w1 = 2 * h[i] + h[i - 1]
                let w2 = h[i] + 2 * h[i - 1]
                m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
            }
            m[0] = d[0]
            m[n - 1] = d[n - 2]
            self.xs = xs
            self.ys = ys
            self.ms = m
        }

        func value(at x: Double) -> Double {
            let n = xs.count
            if x < xs[0] { return ys[0] + ms[0] * (x - xs[0]) }
            if x > xs[n - 1] { return ys[n - 1] + ms[n - 1] * (x - xs[n - 1]) }
            var i = 0
            while i < n - 2 && x > xs[i + 1] { i += 1 }
            let h = xs[i + 1] - xs[i]
            let t = (x - xs[i]) / h
            let t2 = t * t
            let t3 = t2 * t
            return (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h * ms[i]
                + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h * ms[i + 1]
        }
    }

    struct RenderingCurves: Sendable {
        let tone: RenderingCurve
        let chromaGain: RenderingCurve
        let red: RenderingCurve
        let blue: RenderingCurve
        let crosstalk: [Double]

        init(_ rendering: Rendering) {
            tone = RenderingCurve(xs: renderingToneStops, ys: rendering.tone)
            chromaGain = RenderingCurve(xs: renderingChromaStops, ys: rendering.chromaGain)
            red = RenderingCurve(xs: renderingBalanceStops, ys: rendering.redBalance)
            blue = RenderingCurve(xs: renderingBalanceStops, ys: rendering.blueBalance)
            crosstalk = rendering.crosstalk
        }
    }

    private static let renderingLuma = SIMD3<Double>(0.2126, 0.7152, 0.0722)

    /// CPU 참조 구현. Metal 커널과 같은 식이며 테스트가 두 결과를 대조한다.
    static func renderLinear(_ rgb: SIMD3<Double>,
                             curves: RenderingCurves,
                             monochrome: Bool) -> SIMD3<Double> {
        let x = SIMD3(max(rgb.x, 1e-5), max(rgb.y, 1e-5), max(rgb.z, 1e-5))
        let lumaY = max((x * renderingLuma).sum(), 1e-5)
        let stops = log2(lumaY / NegativeInversion.midGrayLinear)
        let logY = log2(lumaY)
        let d = SIMD3(log2(x.x) - logY, log2(x.y) - logY, log2(x.z) - logY)
        let k = curves.crosstalk
        var mixed = SIMD3(
            d.x + k[0] * (d.y - d.x) + k[1] * (d.z - d.x),
            d.y + k[2] * (d.x - d.y) + k[3] * (d.z - d.y),
            d.z + k[4] * (d.x - d.z) + k[5] * (d.y - d.z)
        )
        // 색 쪽 곡선은 knot 범위 밖에서 평평하다(직선 연장하면 깊은 섀도에서 실측과 반대로 간다).
        // 톤 곡선만 끝 기울기로 연장해 검정·흰색에 이어지게 둔다.
        if !monochrome {
            let balanceStops = clamp(stops, renderingBalanceStops[0], renderingBalanceStops[2])
            mixed.x += curves.red.value(at: balanceStops)
            mixed.z += curves.blue.value(at: balanceStops)
        }
        let chromaStops = clamp(stops, renderingChromaStops[0], renderingChromaStops[3])
        let gain = clamp(curves.chromaGain.value(at: chromaStops), 0.0, 2.0)
        let outY = srgbDecode(clamp(curves.tone.value(at: stops), 0.0, 1.0))
        let ratio = SIMD3(exp2(gain * mixed.x), exp2(gain * mixed.y), exp2(gain * mixed.z))
        var out = ratio * (outY / max((ratio * renderingLuma).sum(), 1e-6))
        let peak = max(out.x, max(out.y, out.z))
        if peak > 1.0 {
            let t = clamp((1.0 - outY) / max(peak - outY, 1e-9), 0.0, 1.0)
            out = SIMD3(repeating: outY) + (out - SIMD3(repeating: outY)) * t
        }
        return SIMD3(max(out.x, 0), max(out.y, 0), max(out.z, 0))
    }

    /// 렌더링을 Metal 커널로 화소마다 계산한다. 커널은 표 값만 받으므로 타깃이 바뀌어도 다시
    /// 컴파일하거나 표를 만들지 않는다.
    static func applyRendering(to image: CIImage,
                               rendering: Rendering,
                               monochrome: Bool,
                               strength: Double) -> CIImage {
        guard let kernel = ChromabaseMetalKernels.colorKernel(named: "scannerRendering") else {
            return image
        }
        let curves = RenderingCurves(rendering)
        let extent = image.extent
        return kernel.apply(extent: extent, arguments: [image] + renderingKernelArguments(
            curves, monochrome: monochrome, strength: strength
        ))?.cropped(to: extent) ?? image
    }

    static func renderingKernelArguments(_ c: RenderingCurves,
                                         monochrome: Bool,
                                         strength: Double) -> [CIVector] {
        func v(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> CIVector {
            CIVector(x: CGFloat(a), y: CGFloat(b), z: CGFloat(c), w: CGFloat(d))
        }
        let t = c.tone, g = c.chromaGain, k = c.crosstalk, r = c.red, b = c.blue
        return [
            v(t.ys[0], t.ys[1], t.ys[2], t.ys[3]),
            v(t.ys[4], t.ys[5], t.ys[6], t.ys[7]),
            v(t.ys[8], t.ys[9], t.ys[10], 0),
            v(t.ms[0], t.ms[1], t.ms[2], t.ms[3]),
            v(t.ms[4], t.ms[5], t.ms[6], t.ms[7]),
            v(t.ms[8], t.ms[9], t.ms[10], 0),
            v(g.ys[0], g.ys[1], g.ys[2], g.ys[3]),
            v(g.ms[0], g.ms[1], g.ms[2], g.ms[3]),
            v(k[0], k[1], k[2], k[3]),
            v(k[4], k[5], strength, monochrome ? 1 : 0),
            v(r.ys[0], r.ys[1], r.ys[2], r.ms[0]),
            v(r.ms[1], r.ms[2], b.ys[0], b.ys[1]),
            v(b.ys[2], b.ms[0], b.ms[1], b.ms[2]),
        ]
    }
}
