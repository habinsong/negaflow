import CoreImage
import Foundation

// 브러시로 지정된 결함 마스크 안의 픽셀을 주변 구조와 질감으로 복원한다.
enum DefectScratchRepairer {
    struct RepairResult {
        let image: CIImage
        let blendMask: CIImage
    }

    /// isophote 채움 방향 후보(반대 방향 쌍의 대표).
    private static let dirs: [(dx: Int, dy: Int)] = [(1, 0), (0, 1), (1, 1), (1, -1)]
    /// 얇은 결함 전용 확장 후보(v2): 26.6°/63.4° 를 더해 완만한 대각 에지도 끊지 않고 잇는다.
    /// 두꺼운 결함(onion-peel)은 채운 값이 되먹임되므로 확장 방향의 미세 드리프트가 층층이
    /// 누적된다(합성 테스트에서 저주파 패치 잔차 확인) — 원본만 참조하는 얇은 경로에만 쓴다.
    private static let dirsThin: [(dx: Int, dy: Int)] = [
        (1, 0), (0, 1), (1, 1), (1, -1),
        (2, 1), (1, 2), (2, -1), (1, -2),
    ]

    static func repair(image: CIImage, mask: CIImage, extent: CGRect,
                       preferredAngle: Double? = nil,
                       context: CIContext = DefectContext.render) -> CIImage? {
        repairResult(image: image, mask: mask, extent: extent,
                     preferredAngle: preferredAngle, context: context)?.image
    }

    static func repairResult(image: CIImage, mask: CIImage, extent: CGRect,
                             preferredAngle: Double? = nil,
                             context: CIContext = DefectContext.render,
                             preparedMaskData: Data? = nil) -> RepairResult? {
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

        let reusableMaskData = preparedMaskData?.count == width * height * 4 ? preparedMaskData : nil
        var renderedMaskBytes: [UInt8]?
        var damaged = [Bool](repeating: false, count: width * height)
        if let reusableMaskData {
            reusableMaskData.withUnsafeBytes { rawBuffer in
                let bytes = rawBuffer.bindMemory(to: UInt8.self)
                for i in 0..<(width * height) { damaged[i] = bytes[i * 4] > 8 }
            }
        } else {
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            context.render(mask, toBitmap: &bytes, rowBytes: width * 4,
                           bounds: extent, format: .RGBA8, colorSpace: colorSpace)
            for i in 0..<(width * height) { damaged[i] = bytes[i * 4] > 8 }
            renderedMaskBytes = bytes
        }
        var refinedBlendMask: CIImage?
        if crossAngle != nil {
            damaged = refineBroadDamageMask(rgba, damaged: damaged, width: width, height: height)
            if let reusableMaskData {
                refinedBlendMask = blendMask(from: reusableMaskData, retaining: damaged,
                                             width: width, height: height,
                                             extent: extent, colorSpace: colorSpace)
            } else if let renderedMaskBytes {
                refinedBlendMask = blendMask(from: renderedMaskBytes, retaining: damaged,
                                             width: width, height: height,
                                             extent: extent, colorSpace: colorSpace)
            }
        }
        let damagedOrig = damaged   // 질감 소스의 "성함" 판정용(onion-peel 이 damaged 를 지우기 전)

        var repaired = rgba
        var seed: UInt64 = 0x2545_F491_4F6C_DD1D
        forEachComponent(damaged, width: width, height: height) { comp, minX, maxX, minY, maxY in
            let span = max(maxX - minX, maxY - minY) + 1
            let maxStep = min(128, span + 8)
            // 주변 성한 픽셀의 고주파(그레인) 진폭(채널별) — 질감 전사 잔차의 클램프와 폴백 노이즈에 쓴다.
            let sigma = grainSigmaRGB(rgba, damaged: damagedOrig, width: width, height: height,
                                      minX: minX, maxX: maxX, minY: minY, maxY: maxY)
            var filled: [Int] = []   // 실제로 채운 픽셀 — 질감 전사 대상
            filled.reserveCapacity(comp.count)
            let thickness = min(maxX - minX, maxY - minY) + 1
            if thickness <= 3 {
                // 얇은 결함: 원본만 참조하는 2점 isophote 보간으로 교차 구조를 잇는다.
                for pixel in comp {
                    let y = pixel / width
                    let x = pixel - y * width
                    guard let fill = directionalFill(rgba, damaged: damaged, width: width, height: height,
                                                     x: x, y: y, maxStep: maxStep, crossAngle: crossAngle,
                                                     directions: dirsThin)
                        ?? neighborhoodFill(rgba, damaged: damaged, width: width, height: height,
                                            x: x, y: y, radius: 4)
                    else { continue }
                    let offset = pixel * 4
                    repaired[offset] = clamp01(fill.r)
                    repaired[offset + 1] = clamp01(fill.g)
                    repaired[offset + 2] = clamp01(fill.b)
                    filled.append(pixel)
                }
            } else {
                // 두껍거나 굽은 결함: 경계에서 안쪽으로 채우되 원본 마스크를 구조 판정에 유지한다.
                var remaining = comp
                var layer: [Int] = []
                var nextRemaining: [Int] = []
                layer.reserveCapacity(comp.count)
                nextRemaining.reserveCapacity(comp.count)
                while !remaining.isEmpty {
                    layer.removeAll(keepingCapacity: true)
                    for pixel in remaining where hasClearNeighbor(
                        damaged, width: width, height: height, pixel
                    ) {
                        layer.append(pixel)
                    }
                    if layer.isEmpty { layer.append(contentsOf: remaining) }   // 폐곡선 내부 등 고립
                    let before = remaining.count
                    for pixel in layer {
                        let y = pixel / width
                        let x = pixel - y * width
                        guard let fill = directionalFill(rgba, damaged: damaged, structureDamaged: damagedOrig,
                                                         width: width, height: height,
                                                         x: x, y: y, maxStep: maxStep, crossAngle: crossAngle)
                            ?? neighborhoodFill(rgba, damaged: damaged, width: width, height: height,
                                                x: x, y: y, radius: 4)
                        else { continue }
                        let offset = pixel * 4
                        repaired[offset] = clamp01(fill.r)
                        repaired[offset + 1] = clamp01(fill.g)
                        repaired[offset + 2] = clamp01(fill.b)
                        // 채운 값을 반영 → 다음 안쪽 layer가 성한 픽셀로 참조.
                        rgba[offset] = fill.r; rgba[offset + 1] = fill.g; rgba[offset + 2] = fill.b
                        damaged[pixel] = false
                        filled.append(pixel)
                    }
                    nextRemaining.removeAll(keepingCapacity: true)
                    for pixel in remaining where damaged[pixel] { nextRemaining.append(pixel) }
                    if nextRemaining.count == before { break }   // 진전 없음(완전 고립) — 무한루프 방지
                    swap(&remaining, &nextRemaining)
                }
            }
            transferTexture(&repaired, source: rgba, damagedOrig: damagedOrig,
                            width: width, height: height, filled: filled, compCount: comp.count,
                            minX: minX, maxX: maxX, minY: minY, maxY: maxY,
                            crossAngle: crossAngle, sigma: sigma, seed: &seed)
        }

        let out = CIImage(
            bitmapData: Data(bytes: repaired, count: repaired.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf, colorSpace: colorSpace
        )
        let repairedImage = out
            .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
            .cropped(to: extent)
        return RepairResult(image: repairedImage, blendMask: refinedBlendMask ?? mask.cropped(to: extent))
    }

    private static func blendMask(from maskBytes: [UInt8], retaining damaged: [Bool],
                                  width: Int, height: Int, extent: CGRect,
                                  colorSpace: CGColorSpace) -> CIImage {
        var refined = maskBytes
        for pixel in 0..<(width * height) where !damaged[pixel] {
            let offset = pixel * 4
            refined[offset] = 0
            refined[offset + 1] = 0
            refined[offset + 2] = 0
            refined[offset + 3] = 0
        }
        return CIImage(
            bitmapData: Data(refined),
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: colorSpace
        )
        .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
        .cropped(to: extent)
    }

    private static func blendMask(from maskData: Data, retaining damaged: [Bool],
                                  width: Int, height: Int, extent: CGRect,
                                  colorSpace: CGColorSpace) -> CIImage {
        var refined = maskData
        refined.withUnsafeMutableBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            for pixel in 0..<(width * height) where !damaged[pixel] {
                let offset = pixel * 4
                bytes[offset] = 0
                bytes[offset + 1] = 0
                bytes[offset + 2] = 0
                bytes[offset + 3] = 0
            }
        }
        return CIImage(
            bitmapData: refined,
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: colorSpace
        )
        .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
        .cropped(to: extent)
    }

    // MARK: fill

    /// isophote(구조 연속) 방향 보간. 4방향 중 "양쪽 성한 픽셀의 색이 가장 비슷한" 방향을
    /// 고른다 — 그 방향이 구조가 이어지는 방향이라, 에지를 가로질러 뭉개지 않고 따라 잇는다.
    /// 거리 가중이라 늘어남도 없다. (span 은 동률일 때만 약하게 반영해 가까운 쪽을 선호.)
    private static func directionalFill(_ rgba: [Float], damaged: [Bool], structureDamaged: [Bool]? = nil,
                                        width: Int, height: Int,
                                        x: Int, y: Int, maxStep: Int,
                                        crossAngle: Double?,
                                        directions: [(dx: Int, dy: Int)] = dirs) -> (r: Float, g: Float, b: Float)? {
        var best: (r: Float, g: Float, b: Float)?
        var bestScore = Float.greatestFiniteMagnitude
        var bestStructure: (r: Float, g: Float, b: Float)?
        var bestStructureScore = Float.greatestFiniteMagnitude
        var oneSided: (r: Float, g: Float, b: Float)?
        var oneDist = Int.max
        for (dx, dy) in directions {
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
                let t = Float(a.dist) / Float(a.dist + b.dist)   // a→b 사이 픽셀 위치 비율
                let fill = (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
                let structure = min(
                    ridgeSupport(rgba, damaged: damaged, width: width, height: height,
                                 x: a.x, y: a.y, r: a.r, g: a.g, b: a.b, dx: dx, dy: dy),
                    ridgeSupport(rgba, damaged: damaged, width: width, height: height,
                                 x: b.x, y: b.y, r: b.r, g: b.g, b: b.b, dx: dx, dy: dy)
                )
                if structure > 0.18, colorDiff < 0.22 {
                    let structureScore = -structure + 0.002 * Float(a.dist + b.dist) + cross * 0.25
                    if structureScore < bestStructureScore {
                        bestStructureScore = structureScore
                        bestStructure = fill
                    }
                }
                if score < bestScore {
                    bestScore = score
                    best = fill
                }
            } else if let one = a ?? b, one.dist < oneDist {
                oneDist = one.dist
                oneSided = (one.r, one.g, one.b)   // 양쪽을 못 찾을 때만 쓰는 폴백
            }
            guard let structureDamaged else { continue }
            let sa = nearestClear(rgba, damaged: structureDamaged, width: width, height: height,
                                  x: x, y: y, dx: -dx, dy: -dy, maxStep: maxStep)
            let sb = nearestClear(rgba, damaged: structureDamaged, width: width, height: height,
                                  x: x, y: y, dx: dx, dy: dy, maxStep: maxStep)
            guard let sa, let sb else { continue }
            let colorDiff = abs(sa.r - sb.r) + abs(sa.g - sb.g) + abs(sa.b - sb.b)
            let structure = min(
                ridgeSupport(rgba, damaged: structureDamaged, width: width, height: height,
                             x: sa.x, y: sa.y, r: sa.r, g: sa.g, b: sa.b, dx: dx, dy: dy),
                ridgeSupport(rgba, damaged: structureDamaged, width: width, height: height,
                             x: sb.x, y: sb.y, r: sb.r, g: sb.g, b: sb.b, dx: dx, dy: dy)
            )
            if structure > 0.18, colorDiff < 0.22 {
                let t = Float(sa.dist) / Float(sa.dist + sb.dist)
                let fill = (sa.r + (sb.r - sa.r) * t, sa.g + (sb.g - sa.g) * t, sa.b + (sb.b - sa.b) * t)
                let cross = crossPenalty(dx: dx, dy: dy, crossAngle: crossAngle)
                let structureScore = -structure + 0.002 * Float(sa.dist + sb.dist) + cross * 0.25
                if structureScore < bestStructureScore {
                    bestStructureScore = structureScore
                    bestStructure = fill
                }
            }
        }
        if let bestStructure, let best,
           luma(bestStructure) < luma(best) - 0.08 {
            return bestStructure
        }
        return best ?? bestStructure ?? oneSided
    }

    private static func luma(_ color: (r: Float, g: Float, b: Float)) -> Float {
        color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
    }

    private static func refineBroadDamageMask(_ rgba: [Float], damaged: [Bool],
                                              width: Int, height: Int) -> [Bool] {
        var refined = damaged
        forEachComponent(damaged, width: width, height: height) { comp, minX, maxX, minY, maxY in
            let maxSide = max(maxX - minX, maxY - minY) + 1
            let avgThick = Double(comp.count) / Double(max(1, maxSide))
            let boxArea = max(1, (maxX - minX + 1) * (maxY - minY + 1))
            let fillRatio = Double(comp.count) / Double(boxArea)
            guard comp.count > 700, avgThick > 10, fillRatio > 0.25 else { return }
            let values = comp.map { p -> Float in
                let o = p * 4
                return luma((rgba[o], rgba[o + 1], rgba[o + 2]))
            }.sorted()
            guard let median = percentile(values, 0.5) else { return }
            let deviations = values.map { abs($0 - median) }.sorted()
            let mad = percentile(deviations, 0.5) ?? 0
            let threshold = max(Float(0.055), mad * 5.0)
            let growThreshold = max(Float(0.04), min(threshold * 0.75, threshold - 0.015))
            var keep: [Int] = []
            keep.reserveCapacity(comp.count / 8)
            for p in comp {
                let o = p * 4
                let v = luma((rgba[o], rgba[o + 1], rgba[o + 2]))
                if abs(v - median) >= threshold { keep.append(p) }
            }
            guard !keep.isEmpty, keep.count < Int(Double(comp.count) * 0.85) else { return }
            for p in comp { refined[p] = false }
            for p in keep {
                let y = p / width
                let x = p - y * width
                for yy in max(minY, y - 5)...min(maxY, y + 5) {
                    for xx in max(minX, x - 5)...min(maxX, x + 5) {
                        let dx = xx - x, dy = yy - y
                        guard dx * dx + dy * dy <= 25 else { continue }
                        let q = yy * width + xx
                        let o = q * 4
                        let v = luma((rgba[o], rgba[o + 1], rgba[o + 2]))
                        if abs(v - median) >= growThreshold {
                            refined[q] = true
                        }
                    }
                }
            }
        }
        return refined
    }

    private static func percentile(_ sorted: [Float], _ p: Double) -> Float? {
        guard !sorted.isEmpty else { return nil }
        let pos = min(Double(sorted.count - 1), max(0, p * Double(sorted.count - 1)))
        let lo = Int(pos.rounded(.down))
        let hi = Int(pos.rounded(.up))
        if lo == hi { return sorted[lo] }
        let t = Float(pos - Double(lo))
        return sorted[lo] + (sorted[hi] - sorted[lo]) * t
    }

    /// 후보 양끝이 방향을 따라 이어지는 얇은 구조선 위에 있는지 본다. 수평 브러시의 수평 선처럼
    /// cross 방향만으로는 사라지는 구조를 양끝 색 증거로 살리기 위한 tie-breaker다.
    private static func ridgeSupport(_ rgba: [Float], damaged: [Bool], width: Int, height: Int,
                                     x: Int, y: Int, r: Float, g: Float, b: Float,
                                     dx: Int, dy: Int) -> Float {
        let px = -dy, py = dx
        var total: Float = 0
        var count: Float = 0
        for sign in [-1, 1] {
            var side: Float = 0
            var found = false
            for step in 1...3 {
                let sx = x + px * sign * step
                let sy = y + py * sign * step
                guard sx >= 0, sy >= 0, sx < width, sy < height else { continue }
                let p = sy * width + sx
                guard !damaged[p] else { continue }
                let o = p * 4
                let diff = abs(r - rgba[o]) + abs(g - rgba[o + 1]) + abs(b - rgba[o + 2])
                if diff > side { side = diff }
                found = true
            }
            if found {
                total += side
                count += 1
            }
        }
        return count > 0 ? total / count : 0
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
        -> (r: Float, g: Float, b: Float, dist: Int, x: Int, y: Int)? {
        var step = 1
        while step <= maxStep {
            let sx = x + dx * step, sy = y + dy * step
            guard sx >= 0, sy >= 0, sx < width, sy < height else { return nil }
            let p = sy * width + sx
            if !damaged[p] {
                let o = p * 4
                return (rgba[o], rgba[o + 1], rgba[o + 2], step, sx, sy)
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

    static func clamp01(_ v: Float) -> Float { min(1, max(0, v)) }

}
