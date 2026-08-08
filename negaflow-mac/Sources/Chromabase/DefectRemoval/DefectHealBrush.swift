import CoreImage
import Foundation

// MARK: - 브러시 Heal (소스 패치 복제 + 톤 매칭 모델)
//
// 검출 기반 브러시("칠 안에서 결함을 찾아 그 픽셀만 복원")는 실제 필름 그레인 위에서 딜레마가
// 있다: 임계가 그레인 아래면 마스크가 칠 면적을 채워 "통째 밀림"이 되고, 임계를 올리면 희미한
// 결함을 놓친다(롤백 전력). 이 구현은 검출 없이 푼다 — 칠한 영역 전체를 인접한 "실제 이웃
// 픽셀"로 복제하고 밝기/색조만 대상에 맞춘다. 복제된 텍스처는 원본과 같은 그레인·해상도라
// 밀리거나 뿌예질 수가 없다.
//
//  1) 소스 선택: 스트로크와 같은 모양의 변위 패치. 직교 방향 우선(칠을 가로지르는 구조선이
//     자기 자신 위로 매핑돼 보존된다) + 결함 둘레 컨텍스트 SSD 로 같은 텍스처 지역을 고른다.
//  2) 톤 매칭: 복제값 + (대상 저주파 − 소스 저주파) 오프셋 정합. 편미분방정식을 풀지 않고
//     저역 통과 차이만 더한다 — 고주파(그레인·디테일)는 소스 그대로, 저주파(밝기·그라데이션)는
//     대상을 따른다.
//  3) 경계 페더: 마스크를 살짝 블러해 이음선을 없앤다.
//
// 유효한 소스를 못 찾으면 nil — 호출측이 검출 기반 SoftwareDefectRemoval.apply 로 폴백한다.
public enum DefectHealBrush {
    /// - brush: 흰색=칠한 영역(스트로크 래스터). repairExtent 좌표계.
    /// - preferredAngle: 스트로크 주축(도, y-down 픽셀 좌표). nil 이면 컴포넌트 PCA 로 추정.
    /// - strength: 0~1 블렌드(불투명도 의미). 결함 제거량과 함께 텍스처 교체량도 준다.
    public static func heal(to image: CIImage, brush: CIImage, repairExtent: CGRect,
                            preferredAngle: Double?, strength: Double,
                            context: CIContext = DefectContext.render) -> CIImage? {
        guard strength > 1e-3 else { return image }
        let extent = image.extent
        let roi = repairExtent.integral.intersection(extent)
        let width = Int(roi.width.rounded()), height = Int(roi.height.rounded())
        guard width > 4, height > 4 else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let source = image.cropped(to: roi)
        var rgba = [Float](repeating: 0, count: width * height * 4)
        context.render(source, toBitmap: &rgba, rowBytes: width * 4 * MemoryLayout<Float>.size,
                       bounds: roi, format: .RGBAf, colorSpace: colorSpace)
        var maskBytes = [UInt8](repeating: 0, count: width * height * 4)
        context.render(brush.cropped(to: roi), toBitmap: &maskBytes, rowBytes: width * 4,
                       bounds: roi, format: .RGBA8, colorSpace: colorSpace)
        var damaged = [Bool](repeating: false, count: width * height)
        var damagedCount = 0
        for i in 0..<(width * height) where maskBytes[i * 4] > 8 { damaged[i] = true; damagedCount += 1 }
        guard damagedCount > 0 else { return image }

        var healed = rgba
        var healedAll = true
        forEachComponent(damaged, width: width, height: height) { comp, minX, maxX, minY, maxY in
            guard healedAll else { return }
            healedAll = healComponent(comp, minX: minX, maxX: maxX, minY: minY, maxY: maxY,
                                      rgba: rgba, damaged: damaged, width: width, height: height,
                                      preferredAngle: preferredAngle, into: &healed)
        }
        guard healedAll else { return nil }

        let healedImage = CIImage(
            bitmapData: Data(bytes: healed, count: healed.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf, colorSpace: colorSpace
        ).transformed(by: CGAffineTransform(translationX: roi.minX, y: roi.minY))

        // 경계 페더(≈1px) + 강도 스케일. healed 는 마스크 밖=원본이라 페더로 넓어진 링은 no-op 이다.
        let feathered = brush.cropped(to: roi)
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 1.0])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(strength), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: CGFloat(strength), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(strength), w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            .cropped(to: roi)
        let blended = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: healedImage,
            kCIInputBackgroundImageKey: source,
            "inputMaskImage": feathered,
        ])?.outputImage?.cropped(to: roi) ?? source
        guard roi != extent else { return blended.cropped(to: extent) }
        return blended.composited(over: image).cropped(to: extent)
    }

    // MARK: 컴포넌트 heal

    /// 한 스트로크 컴포넌트를 변위 복제 + 저주파 톤 보정으로 채운다. 유효 소스가 없으면 false.
    private static func healComponent(_ comp: [Int], minX: Int, maxX: Int, minY: Int, maxY: Int,
                                      rgba: [Float], damaged: [Bool], width: Int, height: Int,
                                      preferredAngle: Double?, into healed: inout [Float]) -> Bool {
        // 스트로크 축: 주어진 각도(스트로크 주축) 또는 컴포넌트 PCA. 직교 변위가 1순위 —
        // 칠을 가로지르는 구조선(직교 방향으로 이어지는 선)이 자기 자신 위로 매핑돼 보존된다.
        let pca = DefectShape.pcaMetrics(comp, width: width)
        let axis = (preferredAngle ?? pca.angleDegrees) * .pi / 180
        let thickness = max(4.0, pca.thickness)
        let base = Int((thickness + 6).rounded())

        var candidates: [(dx: Int, dy: Int)] = []
        func add(_ angleRad: Double, _ dist: Double) {
            let dx = Int((cos(angleRad) * dist).rounded()), dy = Int((sin(angleRad) * dist).rounded())
            guard dx != 0 || dy != 0 else { return }
            candidates.append((dx, dy)); candidates.append((-dx, -dy))
        }
        let perp = axis + .pi / 2
        for m in [1.4, 2.0, 2.8] { add(perp, Double(base) * m) }        // 직교(구조 보존) 우선
        for m in [1.6, 2.4] { add(axis, Double(base) * m) }             // 축 방향(칠 끝 너머)
        for m in [1.7, 2.5] {                                           // 대각 폴백
            add(perp + .pi / 4, Double(base) * m)
            add(perp - .pi / 4, Double(base) * m)
        }

        // 유효성: 컴포넌트 "전체"가 성한(칠 밖) 소스로 매핑돼야 한다(부분 복제는 이음선을 만든다).
        // 후보 중 컨텍스트 SSD(칠 둘레 성한 픽셀 vs 변위 위치) 최소 = 같은 텍스처/구조 지역.
        let ring = contextRing(damaged, width: width, height: height,
                               minX: minX, maxX: maxX, minY: minY, maxY: maxY)
        var best: (disp: (dx: Int, dy: Int), ssd: Double)?
        for cand in candidates {
            var ok = true
            var i = 0
            while i < comp.count {
                let p = comp[i]
                let y = p / width, x = p - y * width
                let sx = x + cand.dx, sy = y + cand.dy
                if sx < 0 || sy < 0 || sx >= width || sy >= height || damaged[sy * width + sx] {
                    ok = false; break
                }
                i += 1
            }
            guard ok else { continue }
            let ssd = contextSSD(ring, disp: cand, rgba: rgba, damaged: damaged,
                                 width: width, height: height)
            if best == nil || ssd < best!.ssd { best = (cand, ssd) }
        }
        guard let disp = best?.disp else { return false }

        // 저주파 톤: 대상 쪽은 칠을 직교 보간으로 메운 값(경계 연속), 소스 쪽은 원본 —
        // 둘 다 같은 반경 박스 평균. healed = 소스 복제 + (대상 저주파 − 소스 저주파).
        let radius = max(4, min(16, Int((thickness / 2).rounded())))
        var filled = rgba
        for p in comp {
            let y = p / width, x = p - y * width
            guard let f = crossFill(rgba, damaged: damaged, width: width, height: height,
                                    x: x, y: y, axis: axis) else { continue }
            let o = p * 4
            filled[o] = f.r; filled[o + 1] = f.g; filled[o + 2] = f.b
        }
        let low = boxMeanRGB(filled, width: width, height: height, radius: radius)
        for p in comp {
            let y = p / width, x = p - y * width
            let s = (y + disp.dy) * width + (x + disp.dx)
            let o = p * 4, so = s * 4
            healed[o] = clamp01(rgba[so] + low[o] - low[so])
            healed[o + 1] = clamp01(rgba[so + 1] + low[o + 1] - low[so + 1])
            healed[o + 2] = clamp01(rgba[so + 2] + low[o + 2] - low[so + 2])
        }
        return true
    }

    /// 스트로크 직교 방향 양쪽의 성한 픽셀 2점 보간(저주파 경계 연속용). 못 찾으면 축 방향 폴백.
    private static func crossFill(_ rgba: [Float], damaged: [Bool], width: Int, height: Int,
                                  x: Int, y: Int, axis: Double) -> (r: Float, g: Float, b: Float)? {
        let dirs = [axis + .pi / 2, axis]
        for dir in dirs {
            let dx = cos(dir), dy = sin(dir)
            var a: (Float, Float, Float, Int)?
            var b: (Float, Float, Float, Int)?
            for sign in [1.0, -1.0] {
                var step = 1
                while step <= 160 {
                    let sx = x + Int((dx * sign * Double(step)).rounded())
                    let sy = y + Int((dy * sign * Double(step)).rounded())
                    guard sx >= 0, sy >= 0, sx < width, sy < height else { break }
                    let p = sy * width + sx
                    if !damaged[p] {
                        let o = p * 4
                        if sign > 0 { a = (rgba[o], rgba[o + 1], rgba[o + 2], step) }
                        else { b = (rgba[o], rgba[o + 1], rgba[o + 2], step) }
                        break
                    }
                    step += 1
                }
            }
            if let a, let b {
                let t = Float(a.3) / Float(a.3 + b.3)
                return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
            }
            if let one = a ?? b { return (one.0, one.1, one.2) }
        }
        return nil
    }

    /// 칠 둘레(성한) 컨텍스트 표본 — 변위 후보의 외관(SSD) 비교 기준(±96 표본).
    private static func contextRing(_ damaged: [Bool], width: Int, height: Int,
                                    minX: Int, maxX: Int, minY: Int, maxY: Int) -> [Int] {
        var ring: [Int] = []
        let x0 = max(0, minX - 5), x1 = min(width - 1, maxX + 5)
        let y0 = max(0, minY - 5), y1 = min(height - 1, maxY + 5)
        for y in y0...y1 {
            for x in x0...x1 {
                let p = y * width + x
                if !damaged[p] { ring.append(p) }
            }
        }
        guard ring.count > 96 else { return ring }
        let stride = ring.count / 96
        var out: [Int] = []
        var i = 0
        while i < ring.count { out.append(ring[i]); i += stride }
        return out
    }

    private static func contextSSD(_ ring: [Int], disp: (dx: Int, dy: Int),
                                   rgba: [Float], damaged: [Bool], width: Int, height: Int) -> Double {
        guard !ring.isEmpty else { return .greatestFiniteMagnitude }
        var sum = 0.0, count = 0
        for p in ring {
            let y = p / width, x = p - y * width
            let sx = x + disp.dx, sy = y + disp.dy
            guard sx >= 0, sy >= 0, sx < width, sy < height else { continue }
            let q = sy * width + sx
            guard !damaged[q] else { continue }
            let o = p * 4, so = q * 4
            let dr = Double(rgba[o] - rgba[so])
            let dg = Double(rgba[o + 1] - rgba[so + 1])
            let db = Double(rgba[o + 2] - rgba[so + 2])
            sum += dr * dr + dg * dg + db * db
            count += 1
        }
        guard count * 2 >= ring.count else { return .greatestFiniteMagnitude }
        return sum / Double(count)
    }

    private static func boxMeanRGB(_ rgba: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        var channel = [Float](repeating: 0, count: width * height)
        var out = [Float](repeating: 0, count: width * height * 4)
        for c in 0..<3 {
            for i in 0..<(width * height) { channel[i] = rgba[i * 4 + c] }
            let mean = DefectMorphology.boxMean(channel, width: width, height: height, radius: radius)
            for i in 0..<(width * height) { out[i * 4 + c] = mean[i] }
        }
        return out
    }

    private static func clamp01(_ v: Float) -> Float { min(1, max(0, v)) }

    // MARK: connected components (8-이웃)

    private static func forEachComponent(_ damaged: [Bool], width: Int, height: Int,
                                         _ body: (_ comp: [Int], _ minX: Int, _ maxX: Int, _ minY: Int, _ maxY: Int) -> Void) {
        var visited = [Bool](repeating: false, count: width * height)
        var stack = [Int](), comp = [Int]()
        for start in 0..<(width * height) where damaged[start] && !visited[start] {
            stack.removeAll(keepingCapacity: true)
            comp.removeAll(keepingCapacity: true)
            stack.append(start); visited[start] = true
            var minX = width, maxX = 0, minY = height, maxY = 0
            while let pixel = stack.popLast() {
                comp.append(pixel)
                let y = pixel / width, x = pixel - y * width
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
                for ny in max(0, y - 1)...min(height - 1, y + 1) {
                    for nx in max(0, x - 1)...min(width - 1, x + 1) where nx != x || ny != y {
                        let next = ny * width + nx
                        if damaged[next] && !visited[next] { visited[next] = true; stack.append(next) }
                    }
                }
            }
            body(comp, minX, maxX, minY, maxY)
        }
    }
}
