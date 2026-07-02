import Foundation

// 스크래치 후보: 2단계 방향성 매칭 필터.
//
//  1) 짧은 oriented ridge: 각 방향에서 중심선이 양옆보다(부호 일관) 강한가 + 양옆 균형
//     (step edge 기각). 채널 최대값(bright) 위에서 봐 한 채널만 파인 스크래치도 잡는다.
//  2) 방향 적분: ridge 응답을 그 방향으로 길게 평균. 결맞은 스크래치는 보존되고 랜덤
//     그레인은 0으로 평균된다 → SNR≈1의 희미한 긴 선도 노이즈 위로 떠오른다.
//
// 8방향은 서로 독립이라 방향별로 병렬 계산 후 max-reduce 한다(출력 동일, 속도만 개선).
// 형태(길이/aspect) 판정은 ICEComponentMask 가 맡는다.
enum ICEScratchDetector {
    private static let angleStep = 22.5    // 0~157.5°, 8방향
    private static let shortHalf = 2       // 짧은 ridge 반길이
    private static let sideOffset = 2.0    // 중심선-양옆 거리
    private static let longHalf = 12       // 방향 적분 반길이(라인 누적)
    private static let curveHalf = 6       // 곡선용 짧은 적분(급곡 결함의 결맞음 보존)

    /// 방향 정렬 허용 오차(도). 브러시 주축과 이 각도 안의 ridge 만 결함으로 본다.
    private static let alignTolerance = 32.0

    /// 방향 적분/ridge 맵(스레숄딩 전 공유 값). strong/weak 게이트가 이 위에서만 달라진다.
    private struct Maps {
        let best: [Float]        // 브러시 방향(또는 전체) 적분 최대
        let bestPerp: [Float]    // 직교 방향 적분(구조선 판별용)
        let localRidge: [Float]  // 짧은 ridge 최대(국소화)
        let floor: [Float]       // best 의 국소 평균(방향 텍스처 수준)
    }

    /// - region: nil이면 전역. 주어지면 그 영역(브러시) 안에서만 후보를 낸다(공간 제한).
    /// - preferredAngle: 브러시 주축 방향(도, 0~180). 주어지면 그와 정렬된 방향의 ridge 만
    ///   결함으로 본다 — 칠을 가로지르는 정상 구조선(가로 칠 위의 세로선 등)을 보존한다.
    /// - aggressive: true면 브러시 모드(사용자가 위치 보증) — 얇은 스크래치까지 공격적으로 잡는다.
    ///   false(자동·Region)면 보수적으로 결맞은 선만 잡는다. 공간 범위(region)와 독립이다.
    static func candidates(_ field: ICEContrastField, sensitivity: Double, protectDetail: Double,
                           region: [Bool]? = nil, preferredAngle: Double? = nil,
                           aggressive: Bool = false) -> [Bool] {
        // 브러시 경로: 단일 스케일(기존 동작 유지).
        let maps = computeMaps(field, protectDetail: protectDetail,
                               preferredAngle: preferredAngle, aggressive: aggressive, multiScale: false)
        return gate(field, maps, sensitivity: sensitivity, protectDetail: protectDetail,
                    region: region, preferredAngle: preferredAngle, aggressive: aggressive, weak: false)
    }

    /// 히스테리시스(이중 임계) 후보. strong 은 기존 보수 게이트, weak 는 **절대 임계만** 완화하고
    /// SNR floor(그레인 안전선)는 strong 과 동일하게 유지한다 — weak 픽셀은 컴포넌트를 새로 만들지
    /// 못하고(호출측이 strong 코어 포함 컴포넌트만 채택), 이미 검출된 결함을 잇는(조각/저대비 gap
    /// 연결) 역할만 한다. 그레인은 strong 코어가 없어 컴포넌트가 생기지 않는다(Canny 이중 임계 정신).
    static func candidatesLeveled(_ field: ICEContrastField, sensitivity: Double, protectDetail: Double,
                                  region: [Bool]? = nil, preferredAngle: Double? = nil,
                                  aggressive: Bool = false) -> (strong: [Bool], weak: [Bool]) {
        // Region 경로: 다중 스케일 적분. 짧은 적분(curveHalf)이 급곡 결함의 결맞음을 보존해 같은
        // 임계에서 곡선 스크래치·불규칙 먼지의 strong 코어를 살린다(a contrario floor 비율은 유지).
        let maps = computeMaps(field, protectDetail: protectDetail,
                               preferredAngle: preferredAngle, aggressive: aggressive, multiScale: true)
        let strong = gate(field, maps, sensitivity: sensitivity, protectDetail: protectDetail,
                          region: region, preferredAngle: preferredAngle, aggressive: aggressive, weak: false)
        let weak = gate(field, maps, sensitivity: sensitivity, protectDetail: protectDetail,
                        region: region, preferredAngle: preferredAngle, aggressive: aggressive, weak: true)
        return (strong, weak)
    }

    /// 공유 맵(best/bestPerp/localRidge/floor) 계산. 8방향을 병렬로 돌리고 max-reduce 한다.
    /// - multiScale: true면 방향 적분을 긴(longHalf)·짧은(curveHalf) 두 스케일로 하고 픽셀별 max 를
    ///   취한다 — 긴 직선 스크래치와 급곡 곡선 결함을 함께 살린다(브러시=false 로 기존 동작 유지).
    private static func computeMaps(_ field: ICEContrastField, protectDetail: Double,
                                    preferredAngle: Double?, aggressive: Bool, multiScale: Bool) -> Maps {
        let w = field.width, h = field.height, n = w * h
        // 양옆 균형: 빡빡할수록 step edge/구조물 경계를 더 강하게 기각.
        let balanceLimit = Float((aggressive ? 0.14 : 0.10) - protectDetail * (aggressive ? 0.03 : 0.04))
        let bright = field.bright
        let valid = field.valid

        var best = [Float](repeating: 0, count: n)
        var bestPerp = [Float](repeating: 0, count: n)
        var localRidge = [Float](repeating: 0, count: n)

        // 각 방향 인덱스 0..7. 방향별 로컬 결과를 락으로 max-merge(merge 는 O(N)·저비용).
        let angles = stride(from: 0.0, to: 180.0, by: angleStep).map { $0 }
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: angles.count) { k in
            let angle = angles[k]
            let rad = angle * .pi / 180.0
            let dx = cos(rad), dy = sin(rad), px = -sin(rad), py = cos(rad)
            let ridge = shortRidgeMap(bright, w: w, h: h, valid: valid,
                                      dx: dx, dy: dy, px: px, py: py, balanceLimit: balanceLimit)
            var integ = [Float](repeating: 0, count: n)
            integrateAlong(ridge, into: &integ, w: w, h: h, valid: valid, dx: dx, dy: dy, half: longHalf)
            if multiScale {
                // 짧은 스케일 적분을 픽셀별 max 로 합친다(곡선 결맞음 보존).
                integrateAlong(ridge, into: &integ, w: w, h: h, valid: valid, dx: dx, dy: dy, half: curveHalf)
            }

            // 역할: 전역(preferredAngle=nil)은 모든 방향이 best/localRidge 에 기여. 브러시 방향이
            // 있으면 정렬 방향만 best/localRidge, 직교 방향만 bestPerp 에 기여한다.
            var role = 0   // 0=best+localRidge, 1=perp, 2=무시
            if let pref = preferredAngle {
                let diff = angularDifference(angle, pref)
                if diff <= alignTolerance { role = 0 }
                else if diff >= 90 - alignTolerance { role = 1 }
                else { role = 2 }
            }
            guard role != 2 else { return }
            lock.lock()
            if role == 0 {
                for i in 0..<n {
                    if ridge[i] > localRidge[i] { localRidge[i] = ridge[i] }
                    if integ[i] > best[i] { best[i] = integ[i] }
                }
            } else {
                for i in 0..<n where integ[i] > bestPerp[i] { bestPerp[i] = integ[i] }
            }
            lock.unlock()
        }
        let floor = ICEMorphology.boxMean(best, width: w, height: h, radius: 12)
        return Maps(best: best, bestPerp: bestPerp, localRidge: localRidge, floor: floor)
    }

    /// 공유 맵에 임계를 적용해 후보 bool 을 낸다. weak=true 면 절대 임계만 완화(SNR floor 는 동일).
    private static func gate(_ field: ICEContrastField, _ maps: Maps,
                             sensitivity: Double, protectDetail: Double,
                             region: [Bool]?, preferredAngle: Double?, aggressive: Bool,
                             weak: Bool) -> [Bool] {
        let n = field.width * field.height
        // 임계(그레인 안전선)는 s≤1 로 clamp — 슬라이더가 1.5 까지 올라가도(형태 게이트 완화용)
        // 임계는 안 낮춘다(실제 필름 그레인 폭발 방지).
        let s = min(1.0, sensitivity)
        // 적분 응답에 대한 임계. 방향 적분이 이미 노이즈를 줄이므로 낮게 둘 수 있다. 단 브러시도
        // 그레인의 적분 잔차(~0.01) 아래로는 못 내려간다 — 하회하면 그레인 위 오검출 줄무늬가
        // 칠 영역에 대량 발생해 복원이 칠을 통째로 재합성한다(전체 블러).
        let absBase = Float((aggressive ? 0.026 : 0.034) - s * (aggressive ? 0.014 : 0.014))
        // weak 는 절대 임계를 절반으로만 낮춘다(조각/저대비 gap 연결용). SNR floor 는 그대로.
        let absThreshold = weak ? absBase * 0.5 : absBase
        // 적분 응답의 국소 평균(=방향 텍스처 수준)의 k배 이상이어야 통과 — 그레인 안전선(불변).
        // 적분(25샘플 평균)으로 분포가 좁아져 있어 k≈1.9(브러시)면 그레인 통과율이 사실상 0이다.
        // 과거 1.1은 국소 평균 바로 위 요동까지 통과시켜 그레인/텍스처 면에서 대량 오검출됐다.
        let kFloor = Float((aggressive ? 2.8 : 4.0) - s * (aggressive ? 1.0 : 0.8))
        let shortFloor = absThreshold * 0.6
        let valid = field.valid
        let directional = preferredAngle != nil
        let best = maps.best, bestPerp = maps.bestPerp, localRidge = maps.localRidge, floor = maps.floor

        var cand = [Bool](repeating: false, count: n)
        for i in 0..<n
        where valid[i]
            && (region?[i] ?? true)                  // 브러시 영역 안에서만
            && localRidge[i] > shortFloor            // 실제 선 위(얇게)
            && best[i] > absThreshold                // 결맞은 라인
            && best[i] > kFloor * floor[i]           // 방향 텍스처보다 두드러짐(그레인 안전선)
            && (!directional || best[i] > bestPerp[i]) {  // 브러시와 정렬된 선만(직교 구조선 배제)
            cand[i] = true
        }
        return cand
    }

    /// 1단계: 한 방향의 짧은 ridge 응답 맵(양극성, 양옆 균형 조건).
    private static func shortRidgeMap(_ src: [Float], w: Int, h: Int, valid: [Bool],
                                      dx: Double, dy: Double, px: Double, py: Double,
                                      balanceLimit: Float) -> [Float] {
        var map = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                guard valid[i] else { continue }
                var c: Float = 0, sp: Float = 0, sn: Float = 0
                let k = Float(2 * shortHalf + 1)
                for t in -shortHalf...shortHalf {
                    let td = Double(t)
                    c += sample(src, w, h, x, y, td * dx, td * dy)
                    sp += sample(src, w, h, x, y, td * dx + sideOffset * px, td * dy + sideOffset * py)
                    sn += sample(src, w, h, x, y, td * dx - sideOffset * px, td * dy - sideOffset * py)
                }
                c /= k; sp /= k; sn /= k
                guard abs(sp - sn) < balanceLimit else { continue }
                map[i] = max(0, max(min(c - sp, c - sn), min(sp - c, sn - c)))
            }
        }
        return map
    }

    /// 2단계: ridge 응답을 방향(dx,dy)으로 반길이 half 만큼 평균, 각 픽셀의 최대 적분값 갱신.
    private static func integrateAlong(_ ridge: [Float], into best: inout [Float],
                                       w: Int, h: Int, valid: [Bool], dx: Double, dy: Double, half: Int) {
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                guard valid[i] else { continue }
                var sum: Float = 0, cnt: Float = 0
                for t in -half...half {
                    let cx = Int((Double(x) + Double(t) * dx).rounded())
                    let cy = Int((Double(y) + Double(t) * dy).rounded())
                    if cx < 0 || cy < 0 || cx >= w || cy >= h { continue }
                    sum += ridge[cy * w + cx]; cnt += 1
                }
                let integ = cnt > 0 ? sum / cnt : 0
                if integ > best[i] { best[i] = integ }
            }
        }
    }

    private static func sample(_ src: [Float], _ w: Int, _ h: Int, _ x: Int, _ y: Int,
                               _ ox: Double, _ oy: Double) -> Float {
        let cx = min(w - 1, max(0, x + Int(ox.rounded())))
        let cy = min(h - 1, max(0, y + Int(oy.rounded())))
        return src[cy * w + cx]
    }

    /// 두 각도(도)의 최소 차이(0~90). 선 방향은 180° 주기이고 좌우 구분이 없으므로.
    private static func angularDifference(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 180)
        return min(d, 180 - d)
    }
}
