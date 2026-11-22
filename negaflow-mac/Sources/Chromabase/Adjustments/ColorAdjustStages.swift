import Foundation
import CoreImage

// MARK: - 고급 색 조정 단계 (Color Mixer / Color Grading / Calibration / Point Curves)

public enum ColorMixerStage {
    /// `perceptual` 은 사용자 슬라이더(선형 입력을 sRGB 인코딩 값에서 계산)다. 필름 룩 프리셋은
    /// 이미 감마로 바꾼 값을 넘기므로 false 로 부른다. 윈도우 `ColorMixerParameters::perceptual`.
    public static func apply(to image: CIImage, mixer: ColorMixer, perceptual: Bool = true) -> CIImage {
        guard !mixer.isIdentity,
              let kernel = ChromabaseMetalKernels.colorKernel(named: "colorMixerHSL") else { return image }
        func v4(_ a: [Double], _ base: Int) -> CIVector {
            CIVector(x: CGFloat(a[base]), y: CGFloat(a[base + 1]),
                     z: CGFloat(a[base + 2]), w: CGFloat(a[base + 3]))
        }
        return kernel.apply(extent: image.extent, arguments: [
            image,
            v4(mixer.hue, 0), v4(mixer.hue, 4),
            v4(mixer.saturation, 0), v4(mixer.saturation, 4),
            v4(mixer.luminance, 0), v4(mixer.luminance, 4),
            perceptual ? Float(1) : Float(0),
        ])?.cropped(to: image.extent) ?? image
    }
}

public enum ColorGradingStage {
    /// `perceptual` 은 사용자 슬라이더다. 필름 룩 프리셋은 false 로 부른다(윈도우
    /// `ColorGradingParameters::perceptual`).
    public static func apply(to image: CIImage, grading: ColorGrading, perceptual: Bool = true) -> CIImage {
        guard !grading.isIdentity,
              let kernel = ChromabaseMetalKernels.colorKernel(named: "colorGrade") else { return image }
        func region(_ r: ColorGradeRegion) -> CIVector {
            let rgb = hsv2rgb(hue: r.hue / 360.0, s: 1, v: 1)
            let sat = r.saturation
            return CIVector(x: CGFloat(rgb.0 * sat), y: CGFloat(rgb.1 * sat),
                            z: CGFloat(rgb.2 * sat), w: CGFloat(r.luminance))
        }
        return kernel.apply(extent: image.extent, arguments: [
            image,
            region(grading.shadows),
            region(grading.midtones),
            region(grading.highlights),
            CIVector(x: CGFloat(grading.blending), y: CGFloat(grading.balance)),
            perceptual ? Float(1) : Float(0),
        ])?.cropped(to: image.extent) ?? image
    }
}

public enum CalibrationStage {
    /// `perceptual` 은 사용자 슬라이더다(선형 입력을 sRGB 인코딩 값에서 계산). 필름 룩 프리셋은
    /// 이미 감마로 바꾼 값을 넘기므로 false 로 부른다. 윈도우 `PrimaryCalibration::perceptual`.
    public static func apply(to image: CIImage, calibration c: CalibrationAdjust, perceptual: Bool = true) -> CIImage {
        guard !c.isIdentity,
              let kernel = ChromabaseMetalKernels.colorKernel(named: "calibrationPrimaries") else { return image }
        return kernel.apply(extent: image.extent, arguments: [
            image,
            CIVector(x: CGFloat(c.redHue), y: CGFloat(c.greenHue), z: CGFloat(c.blueHue)),
            CIVector(x: CGFloat(c.redSat), y: CGFloat(c.greenSat), z: CGFloat(c.blueSat)),
            perceptual ? Float(1) : Float(0),
        ])?.cropped(to: image.extent) ?? image
    }
}

// MARK: 포인트 톤 커브 (DR/R/G/B) — per-channel LUT → CIColorCube (sRGB 감마 공간 적용)

public enum PointCurveStage {
    public static func apply(to image: CIImage, curves: PointCurves) -> CIImage {
        guard !curves.isIdentity else { return image }
        let dim = 64
        let rgbLUT = CurveLUT.build(curves.rgb, size: dim)
        // 채널 커브를 rgb 커브 뒤에 합성: composed_c[i] = chCurve_c( rgbCurve(i) ).
        let composedR = compose(rgbLUT, CurveLUT.build(curves.red, size: dim))
        let composedG = compose(rgbLUT, CurveLUT.build(curves.green, size: dim))
        let composedB = compose(rgbLUT, CurveLUT.build(curves.blue, size: dim))
        var cube = [Float](repeating: 0, count: dim * dim * dim * 4)
        var offset = 0
        for bz in 0..<dim {
            for gy in 0..<dim {
                for rx in 0..<dim {
                    cube[offset]     = composedR[rx]
                    cube[offset + 1] = composedG[gy]
                    cube[offset + 2] = composedB[bz]
                    cube[offset + 3] = 1
                    offset += 4
                }
            }
        }
        let data = Data(bytes: cube, count: cube.count * MemoryLayout<Float>.size)
        let graded = image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": dim,
            "inputCubeData": data,
            "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ]).cropped(to: image.extent)
        // 큐브는 [0,1] 밖 값을 잘라 낸다. 그 몫을 다시 더해 광색역·1.0 넘는 값을 지킨다(윈도우
        // `apply_point_curves` 와 같은 식).
        guard let restore = ChromabaseMetalKernels.colorKernel(named: "restoreOutOfRange") else { return graded }
        return restore.apply(extent: image.extent, arguments: [image, graded])?.cropped(to: image.extent) ?? graded
    }

    /// outer(inner(i)) — inner LUT 출력 위치에서 outer LUT 를 **선형 보간**한다.
    /// 가장 가까운 칸으로 반올림하던 앞 판은 마스터 커브만 건드려도 값이 1/63 단위로 계단져
    /// 기울기가 0~2 로 들쭉날쭉했다(±2 레벨 띠). 채널 커브가 항등이면 이제 오차가 없다.
    /// 윈도우 `compose_luts` 와 같은 식이다.
    static func compose(_ inner: [Float], _ outer: [Float]) -> [Float] {
        let last = outer.count - 1
        return inner.map { v in
            let position = min(max(v, 0), 1) * Float(last)
            let lower = min(Int(position), last)
            let upper = min(lower + 1, last)
            let fraction = position - Float(lower)
            return outer[lower] + (outer[upper] - outer[lower]) * fraction
        }
    }
}

// MARK: 커브 LUT 빌더 (단조 3차 Hermite 보간)

public enum CurveLUT {
    /// 제어점에서 size개 샘플 LUT[0..1] 생성. 점이 없거나 직선이면 항등.
    public static func build(_ points: [CurvePoint], size: Int) -> [Float] {
        var lut = [Float](repeating: 0, count: size)
        let pts = normalized(points)
        guard pts.count >= 2 else {
            for i in 0..<size { lut[i] = Float(i) / Float(size - 1) }
            return lut
        }
        let xs = pts.map { $0.x }
        let ys = pts.map { $0.y }
        let m = monotoneTangents(xs: xs, ys: ys)
        for i in 0..<size {
            let x = Double(i) / Double(size - 1)
            lut[i] = Float(min(max(evaluate(x, xs: xs, ys: ys, m: m), 0), 1))
        }
        return lut
    }

    /// 끝점(0,*)/(1,*) 보강 + x 정렬.
    private static func normalized(_ points: [CurvePoint]) -> [CurvePoint] {
        var pts = points.sorted { $0.x < $1.x }
        if pts.isEmpty { return [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)] }
        if pts.first!.x > 1e-6 { pts.insert(CurvePoint(x: 0, y: pts.first!.y), at: 0) }
        if pts.last!.x < 1 - 1e-6 { pts.append(CurvePoint(x: 1, y: pts.last!.y)) }
        return pts
    }

    /// Fritsch–Carlson 단조 접선.
    private static func monotoneTangents(xs: [Double], ys: [Double]) -> [Double] {
        let n = xs.count
        var delta = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let dx = max(xs[i + 1] - xs[i], 1e-9)
            delta[i] = (ys[i + 1] - ys[i]) / dx
        }
        var m = [Double](repeating: 0, count: n)
        m[0] = delta[0]
        m[n - 1] = delta[n - 2]
        for i in 1..<(n - 1) { m[i] = (delta[i - 1] + delta[i]) * 0.5 }
        for i in 0..<(n - 1) {
            if abs(delta[i]) < 1e-12 { m[i] = 0; m[i + 1] = 0; continue }
            let a = m[i] / delta[i], b = m[i + 1] / delta[i]
            let hyp = a * a + b * b
            if hyp > 9 {
                let t = 3 / sqrt(hyp)
                m[i] = t * a * delta[i]
                m[i + 1] = t * b * delta[i]
            }
        }
        return m
    }

    private static func evaluate(_ x: Double, xs: [Double], ys: [Double], m: [Double]) -> Double {
        if x <= xs[0] { return ys[0] }
        if x >= xs[xs.count - 1] { return ys[ys.count - 1] }
        var i = 0
        while i < xs.count - 1 && x > xs[i + 1] { i += 1 }
        let h = max(xs[i + 1] - xs[i], 1e-9)
        let t = (x - xs[i]) / h
        let t2 = t * t, t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        return h00 * ys[i] + h10 * h * m[i] + h01 * ys[i + 1] + h11 * h * m[i + 1]
    }
}

// MARK: HSV→RGB (Swift, Color Grading 틴트 색 계산용)

func hsv2rgb(hue h: Double, s: Double, v: Double) -> (Double, Double, Double) {
    if s <= 1e-6 { return (v, v, v) }
    let hh = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
    let i = Int(hh)
    let f = hh - Double(i)
    let p = v * (1 - s)
    let q = v * (1 - s * f)
    let t = v * (1 - s * (1 - f))
    switch i % 6 {
    case 0: return (v, t, p)
    case 1: return (q, v, p)
    case 2: return (p, v, t)
    case 3: return (p, q, v)
    case 4: return (t, p, v)
    default: return (v, p, q)
    }
}
