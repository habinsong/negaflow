import CoreImage
import Foundation

// 브러시로 지정된 결함 마스크 안의 픽셀을 주변에서 복원한다.
//
// 핵심: 각 결함 픽셀을 isophote(등밝기선=구조가 이어지는) 방향으로 보간한다. 4방향 중
// "양쪽 성한 픽셀의 색이 가장 비슷한" 방향을 고르면 그게 구조가 연속인 방향이다 —
// 거기로만 보간하면 에지를 가로질러 뭉개는 "우그러짐"이 사라지고(문헌: diffuse only
// along the isophote direction), 거리 가중이라 한쪽 색을 길게 복사해 생기던 "늘어남"도
// 없다. 단순 평균(blur) 대신 2점 보간이라 경계가 또렷하다.
//
// 복원 품질은 입력 마스크 정확도에도 좌우된다 — 마스크가 결함보다 넓으면 성한 픽셀까지
// 보간된다. 브러시 마스크는 ICEScratchDetector(ridge·양옆균형)가 에지를 배제해 낸다.
enum ICEScratchRepairer {
    private static let dirs: [(dx: Int, dy: Int)] = [(1, 0), (0, 1), (1, 1), (1, -1)]

    static func repair(image: CIImage, mask: CIImage, extent: CGRect,
                       preferredAngle: Double? = nil,
                       context: CIContext = ICEContext.render) -> CIImage? {
        let width = Int(extent.width.rounded())
        let height = Int(extent.height.rounded())
        guard width > 2, height > 2 else { return nil }
        // 스크래치는 그 길이에 수직인 방향으로 메워야 한다(가로 스크래치 → 세로로). 그 방향이
        // 결함을 가로지르는 최단이자, 교차하는 구조선(세로선)을 따라 잇는 방향이다.
        let crossAngle = preferredAngle.map { ($0 + 90).truncatingRemainder(dividingBy: 180) }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var rgba = [Float](repeating: 0, count: width * height * 4)
        context.render(image, toBitmap: &rgba,
                       rowBytes: width * 4 * MemoryLayout<Float>.size,
                       bounds: extent, format: .RGBAf, colorSpace: colorSpace)

        var maskBytes = [UInt8](repeating: 0, count: width * height * 4)
        context.render(mask, toBitmap: &maskBytes, rowBytes: width * 4,
                       bounds: extent, format: .RGBA8, colorSpace: colorSpace)

        var damaged = [Bool](repeating: false, count: width * height)
        for i in 0..<(width * height) { damaged[i] = maskBytes[i * 4] > 8 }

        var repaired = rgba
        var seed: UInt64 = 0x2545_F491_4F6C_DD1D
        forEachComponent(damaged, width: width, height: height) { comp, minX, maxX, minY, maxY in
            let span = max(maxX - minX, maxY - minY) + 1
            let maxStep = min(64, span + 8)
            // 주변 성한 픽셀의 고주파(그레인) 진폭을 추정해, 복원면이 매끈해 "뿌옇게" 보이지
            // 않도록 같은 수준의 질감을 되살린다. 구조(에지)는 3x3 고역통과로 배제한다.
            let sigma = grainSigma(rgba, damaged: damaged, width: width, height: height,
                                   minX: minX, maxX: maxX, minY: minY, maxY: maxY)
            let thickness = min(maxX - minX, maxY - minY) + 1
            if thickness <= 3 {
                // 얇은 결함(긴/얇은 스크래치 포함): 원본만 참조하는 2점 isophote 보간. 결함을
                // 가로지르는 교차 구조선(세로선 등)을 원본 그대로 잇는다 — GOAT 품질 유지.
                for pixel in comp {
                    let y = pixel / width
                    let x = pixel - y * width
                    guard let fill = directionalFill(rgba, damaged: damaged, width: width, height: height,
                                                     x: x, y: y, maxStep: maxStep, crossAngle: crossAngle)
                        ?? neighborhoodFill(rgba, damaged: damaged, width: width, height: height,
                                            x: x, y: y, radius: 4)
                    else { continue }
                    let n = sigma > 0 ? sigma * nextNoise(&seed) : 0   // luma 상관 노이즈(채널 공통)
                    let offset = pixel * 4
                    repaired[offset] = clamp01(fill.r + n)
                    repaired[offset + 1] = clamp01(fill.g + n)
                    repaired[offset + 2] = clamp01(fill.b + n)
                }
            } else {
                // 두껍거나 굽은 결함: onion-peel 전파(경계→안쪽). 채운 값을 다음 안쪽 layer의
                // 입력으로 삼아(Telea FMM 정신), 중앙까지 isophote 방향으로 완전히 메운다 —
                // 평균 블러 폴백 없이 sharp 하게 제거된다.
                var remaining = comp
                while !remaining.isEmpty {
                    var layer = remaining.filter { hasClearNeighbor(damaged, width: width, height: height, $0) }
                    if layer.isEmpty { layer = remaining }   // 폐곡선 내부 등 고립 — 남은 것 일괄 처리
                    let before = remaining.count
                    for pixel in layer {
                        let y = pixel / width
                        let x = pixel - y * width
                        guard let fill = directionalFill(rgba, damaged: damaged, width: width, height: height,
                                                         x: x, y: y, maxStep: maxStep, crossAngle: crossAngle)
                            ?? neighborhoodFill(rgba, damaged: damaged, width: width, height: height,
                                                x: x, y: y, radius: 4)
                        else { continue }
                        let n = sigma > 0 ? sigma * nextNoise(&seed) : 0
                        let offset = pixel * 4
                        repaired[offset] = clamp01(fill.r + n)
                        repaired[offset + 1] = clamp01(fill.g + n)
                        repaired[offset + 2] = clamp01(fill.b + n)
                        // 채운 값(노이즈 제외)을 반영 → 다음 안쪽 layer가 성한 픽셀로 참조.
                        rgba[offset] = fill.r; rgba[offset + 1] = fill.g; rgba[offset + 2] = fill.b
                        damaged[pixel] = false
                    }
                    remaining = remaining.filter { damaged[$0] }
                    if remaining.count == before { break }   // 진전 없음(완전 고립) — 무한루프 방지
                }
            }
        }

        let out = CIImage(
            bitmapData: Data(bytes: repaired, count: repaired.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf, colorSpace: colorSpace
        )
        return out
            .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
            .cropped(to: extent)
    }

    // MARK: fill

    /// isophote(구조 연속) 방향 보간. 4방향 중 "양쪽 성한 픽셀의 색이 가장 비슷한" 방향을
    /// 고른다 — 그 방향이 구조가 이어지는 방향이라, 에지를 가로질러 뭉개지 않고 따라 잇는다.
    /// 거리 가중이라 늘어남도 없다. (span 은 동률일 때만 약하게 반영해 가까운 쪽을 선호.)
    private static func directionalFill(_ rgba: [Float], damaged: [Bool], width: Int, height: Int,
                                        x: Int, y: Int, maxStep: Int,
                                        crossAngle: Double?) -> (r: Float, g: Float, b: Float)? {
        var best: (r: Float, g: Float, b: Float)?
        var bestScore = Float.greatestFiniteMagnitude
        var oneSided: (r: Float, g: Float, b: Float)?
        var oneDist = Int.max
        for (dx, dy) in dirs {
            let a = nearestClear(rgba, damaged: damaged, width: width, height: height,
                                 x: x, y: y, dx: -dx, dy: -dy, maxStep: maxStep)
            let b = nearestClear(rgba, damaged: damaged, width: width, height: height,
                                 x: x, y: y, dx: dx, dy: dy, maxStep: maxStep)
            if let a, let b {
                // 점수(낮을수록 선호): ① 양쪽 색차 ② 비대칭(거리 차) ③ 거리합 ④ 브러시 직교
                // (스크래치를 가로지르는) 방향에서 벗어난 정도. ④가 핵심 — 가로 스크래치는
                // 세로로 메워야 교차 구조선을 끊지 않고, 그레인으로 색차가 커도 올바른
                // 방향을 고른다.
                let colorDiff = abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
                let asymmetry = Float(abs(a.dist - b.dist))
                let cross = crossPenalty(dx: dx, dy: dy, crossAngle: crossAngle)
                let score = colorDiff + 0.02 * asymmetry + 0.004 * Float(a.dist + b.dist) + cross
                if score < bestScore {
                    bestScore = score
                    let t = Float(a.dist) / Float(a.dist + b.dist)   // a→b 사이 픽셀 위치 비율
                    best = (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
                }
            } else if let one = a ?? b, one.dist < oneDist {
                oneDist = one.dist
                oneSided = (one.r, one.g, one.b)   // 양쪽을 못 찾을 때만 쓰는 폴백
            }
        }
        return best ?? oneSided
    }

    /// 채움 방향이 "스크래치를 가로지르는 방향(crossAngle)"에서 벗어난 만큼 점수에 더할 벌점.
    private static func crossPenalty(dx: Int, dy: Int, crossAngle: Double?) -> Float {
        guard let crossAngle else { return 0 }
        var dirAngle = atan2(Double(dy), Double(dx)) * 180 / .pi
        if dirAngle < 0 { dirAngle += 180 }
        let d = abs(dirAngle - crossAngle).truncatingRemainder(dividingBy: 180)
        let diff = min(d, 180 - d)            // 0~90
        return Float(diff / 90) * 0.20        // 직교에서 90° 벗어나면 +0.20
    }

    /// 결함 픽셀의 8-이웃에 성한(복원 완료 포함) 픽셀이 하나라도 있는가 = 이번 onion-peel layer 대상.
    private static func hasClearNeighbor(_ damaged: [Bool], width: Int, height: Int, _ pixel: Int) -> Bool {
        let y = pixel / width, x = pixel - y * width
        for ny in max(0, y - 1)...min(height - 1, y + 1) {
            for nx in max(0, x - 1)...min(width - 1, x + 1) where nx != x || ny != y {
                if !damaged[ny * width + nx] { return true }
            }
        }
        return false
    }

    private static func nearestClear(_ rgba: [Float], damaged: [Bool], width: Int, height: Int,
                                     x: Int, y: Int, dx: Int, dy: Int, maxStep: Int)
        -> (r: Float, g: Float, b: Float, dist: Int)? {
        var step = 1
        while step <= maxStep {
            let sx = x + dx * step, sy = y + dy * step
            guard sx >= 0, sy >= 0, sx < width, sy < height else { return nil }
            let p = sy * width + sx
            if !damaged[p] {
                let o = p * 4
                return (rgba[o], rgba[o + 1], rgba[o + 2], step)
            }
            step += 1
        }
        return nil
    }

    /// 최후의 폴백: 반경 내 성한 픽셀 평균(거대 결함 중앙 등 보간이 닿지 못할 때만).
    private static func neighborhoodFill(_ rgba: [Float], damaged: [Bool], width: Int, height: Int,
                                         x: Int, y: Int, radius: Int) -> (r: Float, g: Float, b: Float)? {
        var r: Float = 0, g: Float = 0, b: Float = 0, count: Float = 0
        for ny in max(0, y - radius)...min(height - 1, y + radius) {
            for nx in max(0, x - radius)...min(width - 1, x + radius) {
                let p = ny * width + nx
                guard !damaged[p] else { continue }
                let o = p * 4
                r += rgba[o]; g += rgba[o + 1]; b += rgba[o + 2]; count += 1
            }
        }
        guard count > 0 else { return nil }
        return (r / count, g / count, b / count)
    }

    // MARK: grain (텍스처 재주입)

    /// 결함 주변(bbox+pad) 성한 픽셀의 고주파 진폭 = 그레인 std 추정. 각 픽셀에서 3x3
    /// 국소 평균을 빼(고역통과) 구조(저주파 에지)를 배제하고, 남은 그레인만 측정한다.
    private static func grainSigma(_ rgba: [Float], damaged: [Bool], width: Int, height: Int,
                                   minX: Int, maxX: Int, minY: Int, maxY: Int) -> Float {
        let pad = 4
        let x0 = max(1, minX - pad), x1 = min(width - 2, maxX + pad)
        let y0 = max(1, minY - pad), y1 = min(height - 2, maxY + pad)
        guard x1 >= x0, y1 >= y0 else { return 0 }
        var sum: Float = 0, count: Float = 0
        for y in y0...y1 {
            for x in x0...x1 {
                let p = y * width + x
                guard !damaged[p] else { continue }
                var localMean: Float = 0, c: Float = 0
                for ny in (y - 1)...(y + 1) {
                    for nx in (x - 1)...(x + 1) {
                        let q = ny * width + nx
                        guard !damaged[q] else { continue }
                        let o = q * 4
                        localMean += 0.2126 * rgba[o] + 0.7152 * rgba[o + 1] + 0.0722 * rgba[o + 2]; c += 1
                    }
                }
                guard c > 0 else { continue }
                localMean /= c
                let o = p * 4
                let luma = 0.2126 * rgba[o] + 0.7152 * rgba[o + 1] + 0.0722 * rgba[o + 2]
                sum += abs(luma - localMean); count += 1
            }
        }
        guard count > 8 else { return 0 }
        // 평균절대편차 → std 환산(가우시안 ≈1.25배). 에지 잔여로 폭주하지 않게 상한.
        return min(0.05, sum / count * 1.25)
    }

    /// 결정적 LCG 기반 [-1,1) 균등 노이즈(재현 가능, 빠름). amplitude ≈ std 가 되도록 보정.
    private static func nextNoise(_ state: inout UInt64) -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return (Float(state >> 40) / Float(1 << 24) * 2 - 1) * 1.23   // 복원면 그레인을 이웃 수준 바로 아래로
    }

    private static func clamp01(_ v: Float) -> Float { min(1, max(0, v)) }

    // MARK: connected components (8-이웃)

    private static func forEachComponent(_ damaged: [Bool], width: Int, height: Int,
                                         _ body: (_ comp: [Int], _ minX: Int, _ maxX: Int, _ minY: Int, _ maxY: Int) -> Void) {
        var visited = [Bool](repeating: false, count: width * height)
        var stack = [Int]()
        var comp = [Int]()
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
