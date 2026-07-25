import Foundation

// 미세 입자(현상 찌꺼기·건조 얼룩·유분·미세 먼지) 검출 — 기존 dust/scratch 검출과 독립된 추가 패스.
//
// 기존 검출은 "작고 빽빽한 것 = 그레인"(grainFieldDrops)을 안전 공리로 삼으므로 밀집 미세 입자를
// 원리적으로 못 잡는다. 이 패스는 밀도 대신 물리 판별축을 쓴다:
//  1) 채널 동시성 — 컬러 필름 그레인은 염료층별 독립(chromatic)이지만, 유제 표면 이물은 세 채널을
//     같은 위치·같은 극성으로 동시에 가린다. 채널별 dark top-hat 의 min(AND) 결합은 채널당 그레인
//     오탐률 p 를 동시성 ~p³ 로 붕괴시킨다.
//  2) 극성 — 이물은 투과광을 가려 raw 네거티브에서 어둡다(dark top-hat 만 본다). 밝은 미세 점
//     (유제 구멍)은 기존 pinhole 경로가 맡는다.
//  3) 강건 잡음 바닥 — boxMean 통계는 밀집 입자가 서로를 잡음으로 세는 자기억제를 만든다
//     (기존 micro 경로가 밀집 입자를 놓친 원인). 그리드 셀 분위수(입자 픽셀 점유율 수 % 에
//     강건)로 그레인 수준만 추적한다.
//
// 안전 퓨즈: 후보 픽셀 비율이 상한을 넘으면 패스 전체를 버린다 — 흑백 필름(은염 그레인은 3채널
// 동시 응답)처럼 판별축이 무너지는 입력에서 대량 오탐 대신 무해하게 무력화된다.
// 기존 검출 임계·게이트는 일절 건드리지 않는다(순수 추가 패스 — 토글 off 면 코드가 돌지 않는다).
enum DefectSpeckDetector {
    /// dark top-hat SE 반지름. 1 은 폭 1~3px, 3 은 ~7px 입자까지 응답한다(3600dpi 미세 입자 2~6px).
    static let radii = [1, 3]
    /// 강건 잡음 바닥 그리드 셀 한 변(px). 타일 halo(maximumDetectionSupportRadius=80)보다 작아
    /// 타일 경계 통계 차이가 halo 안에서 흡수된다.
    static let cellSize = 32
    /// 셀 내 coherence 분위수. 입자 점유율이 셀의 10% 미만이면 바닥이 오염되지 않는다.
    static let floorQuantile = 0.90
    /// 채널 균형(무채색) 최소 비율(min/max 채널 응답). 광대역 차폐 이물은 세 채널 응답이 비슷하고,
    /// 한 층 위주의 그레인/색 디테일은 비율이 낮다.
    static let minChannelBalance: Float = 0.30
    /// 후보 픽셀 비율 상한 — 초과 시 패스 전체 무효(판별축 붕괴 방어).
    static let maxCandidateFraction = 0.015
    /// 컴포넌트 게이트. 상한을 넘는 이물은 기존 dust/large 경로가 맡는다.
    static let minArea = 2
    static let maxArea = 64
    static let maxAspect = 3.0
    static let minFillRatio = 0.25

    /// coherence 필드에서 채택한 미세 입자 컴포넌트. confidence 는 임계 대비 초과 배율 요약(0~1).
    struct Speck {
        let component: DefectComponentMask.RawComponent
        let confidence: Double
    }

    /// - rgba: 검출 도메인(sRGB 감마) RGBAf 버퍼 — detectLabeled 가 렌더한 것을 그대로 재사용한다.
    /// - valid: DefectContrastField.valid (클리핑 명부/순흑 평탄 제외).
    /// - sensitivity: 기존 dust 민감도 슬라이더(0~1). 임계 완화 폭은 그레인 안전선 안으로 제한.
    static func detect(rgba: [Float], width: Int, height: Int, valid: [Bool],
                       sensitivity: Double) -> [Speck] {
        let n = width * height
        guard n > 0, rgba.count >= n * 4, valid.count >= n else { return [] }
        let s = min(1.0, max(0.0, sensitivity))
        // 절대 바닥(감마 대비)과 강건 SNR 배수. min-결합 coherence 는 단일 채널 top-hat 보다
        // 분포가 훨씬 얇아 기존 micro 임계(0.06/4.5)보다 낮춰도 그레인이 통과하지 못한다.
        let absFloor = Float(0.05 - 0.02 * s)
        let kNoise = Float(4.5 - 1.5 * s)

        var channels = [[Float]](repeating: [Float](repeating: 0, count: n), count: 3)
        for i in 0..<n {
            let o = i * 4
            channels[0][i] = rgba[o]
            channels[1][i] = rgba[o + 1]
            channels[2][i] = rgba[o + 2]
        }

        // 채널 동시성 coherence: 반지름별로 세 채널 dark 응답의 min/max 를 만들고,
        // min(=AND 증거)이 최대인 반지름의 균형 비율을 함께 기록한다.
        // 배경은 closing→opening(작은 어두운 구조를 메우고 작은 밝은 구조를 깎은 국소 배경)이다 —
        // closing 단독을 배경으로 쓰면 밝은 그레인 임펄스가 닫힘 천장을 끌어올려 주변 정상 픽셀
        // 전체에 그레인 진폭만큼의 가짜 dark 응답이 생기고(coherence 바닥 상승), 실제 입자가
        // 상대 임계를 넘지 못한다. 두 연산 모두 SE 보다 큰 구조(피사체 경계/면)는 보존하므로
        // 크기 선택성은 유지된다(경계에서 응답 0).
        var coherence = [Float](repeating: 0, count: n)
        var balance = [Float](repeating: 0, count: n)
        for radius in radii {
            var minResponse = [Float](repeating: .greatestFiniteMagnitude, count: n)
            var maxResponse = [Float](repeating: 0, count: n)
            for c in 0..<3 {
                let closed = DefectMorphology.closing(channels[c], width: width, height: height, radius: radius)
                let background = DefectMorphology.opening(closed, width: width, height: height, radius: radius)
                for i in 0..<n {
                    let d = max(0, background[i] - channels[c][i])
                    if d < minResponse[i] { minResponse[i] = d }
                    if d > maxResponse[i] { maxResponse[i] = d }
                }
            }
            for i in 0..<n where minResponse[i] > coherence[i] {
                coherence[i] = minResponse[i]
                balance[i] = maxResponse[i] > 0 ? minResponse[i] / maxResponse[i] : 0
            }
        }

        // 강건 잡음 바닥: 셀 분위수 → 3×3 셀 평활. 밀집 입자(점유율 수 %)에 오염되지 않고
        // 그레인 coherence 수준만 추적한다.
        let floorField = robustFloor(coherence, width: width, height: height)

        var candidates = [Bool](repeating: false, count: n)
        var candidateCount = 0
        let cellsX = (width + cellSize - 1) / cellSize
        for i in 0..<n where valid[i] {
            let cy = (i / width) / cellSize, cx = (i % width) / cellSize
            let threshold = max(absFloor, kNoise * floorField[cy * cellsX + cx])
            if coherence[i] > threshold, balance[i] >= minChannelBalance {
                candidates[i] = true
                candidateCount += 1
            }
        }
        guard candidateCount > 0,
              Double(candidateCount) <= Double(n) * maxCandidateFraction else { return [] }

        var out: [Speck] = []
        for comp in DefectComponentMask.rawComponents(of: candidates, width: width, height: height) {
            let area = comp.pixels.count
            guard area >= minArea, area <= maxArea else { continue }
            let boxW = comp.maxX - comp.minX + 1, boxH = comp.maxY - comp.minY + 1
            guard Double(area) / Double(boxW * boxH) >= minFillRatio else { continue }
            guard DefectShape.pcaMetrics(comp.pixels, width: width).aspect <= maxAspect else { continue }
            // confidence: 평균 임계 초과 배율(≥1)을 0.25~1 로 요약 — UI 표시용, 게이트 아님.
            var ratioSum = 0.0
            for p in comp.pixels {
                let cy = (p / width) / cellSize, cx = (p % width) / cellSize
                let threshold = max(absFloor, kNoise * floorField[cy * cellsX + cx])
                ratioSum += Double(coherence[p] / max(1e-5, threshold))
            }
            let meanRatio = ratioSum / Double(area)
            let confidence = min(1.0, 0.25 + 0.25 * max(0, meanRatio - 1))
            out.append(Speck(component: comp, confidence: confidence))
        }
        return out
    }

    /// 채택된 미세 입자를 기존 라벨 필드에 추가한다. 기존 검출과 픽셀이 겹치는 입자는 기존 결과
    /// 우선으로 버린다(중복 채택 방지). 입자가 없으면 필드를 그대로 반환한다.
    static func merged(into field: DefectLabelField, specks: [Speck]) -> DefectLabelField {
        guard !specks.isEmpty, field.labels.count == field.width * field.height else { return field }
        var labels = field.labels
        var components = field.components
        var nextID = (components.map(\.id).max() ?? -1) + 1
        for speck in specks {
            let c = speck.component
            guard !c.pixels.contains(where: { labels[$0] >= 0 }) else { continue }
            for p in c.pixels { labels[p] = nextID }
            components.append(DefectComponent(
                id: nextID, kind: .dust, pixels: c.pixels,
                minX: c.minX, minY: c.minY, maxX: c.maxX, maxY: c.maxY,
                classification: .microSpeck, confidence: speck.confidence))
            nextID += 1
        }
        return DefectLabelField(width: field.width, height: field.height,
                             labels: labels, components: components)
    }

    /// 셀 분위수 잡음 바닥(cellsX×cellsY 그리드) + 3×3 셀 박스 평활.
    private static func robustFloor(_ field: [Float], width: Int, height: Int) -> [Float] {
        let cellsX = (width + cellSize - 1) / cellSize
        let cellsY = (height + cellSize - 1) / cellSize
        var grid = [Float](repeating: 0, count: cellsX * cellsY)
        var bucket = [Float]()
        bucket.reserveCapacity(cellSize * cellSize)
        for cy in 0..<cellsY {
            let y0 = cy * cellSize, y1 = min(height, y0 + cellSize)
            for cx in 0..<cellsX {
                let x0 = cx * cellSize, x1 = min(width, x0 + cellSize)
                bucket.removeAll(keepingCapacity: true)
                for y in y0..<y1 {
                    let row = y * width
                    for x in x0..<x1 { bucket.append(field[row + x]) }
                }
                bucket.sort()
                let q = Int(Double(bucket.count - 1) * floorQuantile)
                grid[cy * cellsX + cx] = bucket[q]
            }
        }
        var smoothed = grid
        for cy in 0..<cellsY {
            for cx in 0..<cellsX {
                var sum: Float = 0, count: Float = 0
                for dy in -1...1 {
                    let ny = cy + dy
                    guard ny >= 0, ny < cellsY else { continue }
                    for dx in -1...1 {
                        let nx = cx + dx
                        guard nx >= 0, nx < cellsX else { continue }
                        sum += grid[ny * cellsX + nx]
                        count += 1
                    }
                }
                smoothed[cy * cellsX + cx] = sum / count
            }
        }
        return smoothed
    }
}
