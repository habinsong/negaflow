import Foundation

// 연결요소 형태 측정(2차 모멘트 PCA) — 게이트(DefectComponentMask)와 분류(DefectClassifier)가 공유한다.
enum DefectShape {
    /// 컴포넌트 픽셀의 2차 모멘트(PCA) → 등가 직사각형 근사. length = 주축 변 길이(√(12λ1)),
    /// thickness = 픽셀수/길이(평균 두께), aspect = length/thickness,
    /// angleDegrees = 주축 방향(0~180, 0=수평). 회전 불변이라 대각선 결함도 동일하게 판정된다.
    static func pcaMetrics(_ comp: [Int], width: Int)
        -> (length: Double, thickness: Double, aspect: Double, angleDegrees: Double) {
        let n = Double(comp.count)
        guard n > 0 else { return (0, 1, 0, 0) }
        var mx = 0.0, my = 0.0
        for p in comp { mx += Double(p % width); my += Double(p / width) }
        mx /= n; my /= n
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in comp {
            let dx = Double(p % width) - mx, dy = Double(p / width) - my
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        sxx /= n; syy /= n; sxy /= n
        let half = (sxx + syy) / 2
        let disc = max(0, half * half - (sxx * syy - sxy * sxy)).squareRoot()
        let l1 = half + disc
        // 길이 L 의 균일 선분은 λ1=(L²-1)/12 → √(12λ1)≈L. +1 로 1px 컴포넌트도 length 1.
        let length = max(1.0, (12 * l1).squareRoot().rounded(.down) + 1)
        let thickness = max(1.0, n / length)
        // 주축 각도: 공분산 고유벡터 방향. 라벨맵은 y-down 이므로 화면 기준 각도와 일치한다.
        var angle = 0.5 * atan2(2 * sxy, sxx - syy) * 180 / .pi
        if angle < 0 { angle += 180 }
        if angle >= 180 { angle -= 180 }
        return (length, thickness, length / thickness, angle)
    }
}
