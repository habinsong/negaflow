import Foundation

// 스크래치 후보: 2단계 방향성 매칭 필터.
//
//  1) 짧은 oriented ridge: 각 방향에서 중심선이 양옆보다(부호 일관) 강한가 + 양옆 균형
//     (step edge 기각). 채널 최대값(bright) 위에서 봐 한 채널만 파인 스크래치도 잡는다.
//  2) 방향 적분: ridge 응답을 그 방향으로 길게 평균. 결맞은 스크래치는 보존되고 랜덤
//     그레인은 0으로 평균된다 → SNR≈1의 희미한 긴 선도 노이즈 위로 떠오른다.
//
// 형태(길이/aspect) 판정은 ICEComponentMask 가 맡는다.
enum ICEScratchDetector {
    private static let angleStep = 22.5    // 0~157.5°, 8방향
    private static let shortHalf = 2       // 짧은 ridge 반길이
    private static let sideOffset = 2.0    // 중심선-양옆 거리
    private static let longHalf = 12       // 방향 적분 반길이(라인 누적)

    /// 방향 정렬 허용 오차(도). 브러시 주축과 이 각도 안의 ridge 만 결함으로 본다.
    private static let alignTolerance = 32.0

    /// - region: nil이면 전역. 주어지면 그 영역(브러시) 안에서만 후보를 낸다(공간 제한).
    /// - preferredAngle: 브러시 주축 방향(도, 0~180). 주어지면 그와 정렬된 방향의 ridge 만
    ///   결함으로 본다 — 칠을 가로지르는 정상 구조선(가로 칠 위의 세로선 등)을 보존한다.
    /// - aggressive: true면 브러시 모드(사용자가 위치 보증) — 얇은 스크래치까지 공격적으로 잡는다.
    ///   false(자동·Region)면 보수적으로 결맞은 선만 잡는다. 공간 범위(region)와 독립이다.
    static func candidates(_ field: ICEContrastField, sensitivity: Double, protectDetail: Double,
                           region: [Bool]? = nil, preferredAngle: Double? = nil,
                           aggressive: Bool = false) -> [Bool] {
        let w = field.width, h = field.height, n = w * h
        // 적분 응답에 대한 임계. 방향 적분이 이미 노이즈를 줄이므로 낮게 둘 수 있다.
        // 브러시 모드는 사용자가 위치를 보증했으므로 더 공격적으로(얇은 스크래치까지) 잡는다.
        // 과검출은 grain-only 가드 테스트로 감시한다.
        let absThreshold = Float((aggressive ? 0.020 : 0.034) - sensitivity * (aggressive ? 0.016 : 0.014))
        // 적분 응답의 국소 평균(=방향 텍스처 수준)의 k배 이상이어야 통과. 결맞은 선은
        // 국소 평균을 거의 안 올리지만 텍스처/그레인은 평균과 비슷해 기각된다.
        let kFloor = Float((aggressive ? 2.0 : 4.0) - sensitivity * (aggressive ? 1.0 : 0.8))
        // 양옆 균형: 빡빡할수록 step edge/구조물 경계를 더 강하게 기각.
        let balanceLimit = Float((aggressive ? 0.14 : 0.10) - protectDetail * (aggressive ? 0.03 : 0.04))
        // 짧은 ridge가 실제 선 위(얇게)를 국소화하고, 적분이 결맞음을 검증한다.
        let shortFloor = absThreshold * 0.6
        let bright = field.bright
        let valid = field.valid

        var best = [Float](repeating: 0, count: n)        // 브러시 방향(또는 전체) 적분 최대
        var bestPerp = [Float](repeating: 0, count: n)    // 직교 방향 적분 — 구조선 판별용
        var localRidge = [Float](repeating: 0, count: n)  // 짧은 ridge 최대(국소화)
        var angle = 0.0
        while angle < 180.0 {
            defer { angle += angleStep }
            let rad = angle * .pi / 180.0
            let dx = cos(rad), dy = sin(rad), px = -sin(rad), py = cos(rad)
            let ridge = shortRidgeMap(bright, w: w, h: h, valid: valid,
                                      dx: dx, dy: dy, px: px, py: py, balanceLimit: balanceLimit)
            if let pref = preferredAngle {
                let diff = angularDifference(angle, pref)
                if diff <= alignTolerance {            // 브러시 방향과 정렬
                    for i in 0..<n where ridge[i] > localRidge[i] { localRidge[i] = ridge[i] }
                    integrateAlong(ridge, into: &best, w: w, h: h, valid: valid, dx: dx, dy: dy)
                } else if diff >= 90 - alignTolerance { // 직교
                    integrateAlong(ridge, into: &bestPerp, w: w, h: h, valid: valid, dx: dx, dy: dy)
                }
            } else {
                for i in 0..<n where ridge[i] > localRidge[i] { localRidge[i] = ridge[i] }
                integrateAlong(ridge, into: &best, w: w, h: h, valid: valid, dx: dx, dy: dy)
            }
        }
        let floor = ICEMorphology.boxMean(best, width: w, height: h, radius: 12)
        let directional = preferredAngle != nil

        var cand = [Bool](repeating: false, count: n)
        for i in 0..<n
        where valid[i]
            && (region?[i] ?? true)                  // 브러시 영역 안에서만
            && localRidge[i] > shortFloor            // 실제 선 위(얇게)
            && best[i] > absThreshold                // 결맞은 라인
            && best[i] > kFloor * floor[i]           // 방향 텍스처보다 두드러짐
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

    /// 2단계: ridge 응답을 방향(dx,dy)으로 길게 평균, 각 픽셀의 최대 적분값 갱신.
    private static func integrateAlong(_ ridge: [Float], into best: inout [Float],
                                       w: Int, h: Int, valid: [Bool], dx: Double, dy: Double) {
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                guard valid[i] else { continue }
                var sum: Float = 0, cnt: Float = 0
                for t in -longHalf...longHalf {
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
