import Foundation

// MARK: - GrainMend RGB 결함 분류
//
// 검출된 컴포넌트(dust/scratch 구조 후보)를 물리 결함 종류로 세분화하고, 검출 증거의 세기를
// confidence(0~1)로 요약한다. 임계·SNR 게이트는 검출기가 이미 끝냈다 — 여기서는 채택된
// 컴포넌트의 형태·극성·증거만 읽는 순수 추가 단계라 검출 결과 자체를 바꾸지 않는다.

/// 물리 결함 종류. 검출 kind(dust/scratch)는 구조 게이트용이고, 이 분류는 표시·복원 힌트용이다.
///  - dust: 필름 위 이물(어두운 blob — raw 투과광을 가림).
///  - pinhole: 유제 구멍(작고 둥근 밝은 점 — 빛이 그대로 통과).
///  - scratchHorizontal/Vertical/Diagonal: 주축 방향별 스크래치.
///  - emulsionDamage: 넓고 불규칙한 유제 손상(긁힘 자국·박리 등).
///  - microSpeck: 현상 찌꺼기·유분·미세 먼지(2~7px, 채널 동시성 검출 — DefectSpeckDetector).
public enum DefectClass: String, Sendable, CaseIterable, Codable {
    case dust
    case pinhole
    case scratchHorizontal
    case scratchVertical
    case scratchDiagonal
    case emulsionDamage
    case microSpeck
}

enum DefectClassifier {
    /// 스크래치 주축 각도 → 방향 분류 경계(도). 0±30 수평, 90±30 수직, 그 사이 대각.
    private static let horizontalBand = 30.0
    private static let verticalBand = 30.0

    /// 분류/confidence 를 채운 컴포넌트 목록을 낸다. 라벨맵은 그대로 재사용한다.
    /// - strong: 히스테리시스 strong(core) 픽셀 합집합 — confidence 의 증거 비율.
    /// - pinholeMaxArea: pinhole 로 인정하는 최대 면적(px, 호출측이 물리 크기 법칙으로 환산).
    /// - emulsionMinArea: emulsion damage 로 볼 최소 면적(px).
    static func classify(field: DefectLabelField, contrast: DefectContrastField,
                         strong: [Bool], pinholeMaxArea: Int, emulsionMinArea: Int) -> DefectLabelField {
        guard !field.isEmpty else { return field }
        let classified = field.components.map { comp -> DefectComponent in
            let evidence = componentEvidence(comp, field: field, contrast: contrast, strong: strong)
            let cls = classification(comp, width: field.width, polarity: evidence.polarity,
                                     pinholeMaxArea: pinholeMaxArea, emulsionMinArea: emulsionMinArea)
            return DefectComponent(id: comp.id, kind: comp.kind, pixels: comp.pixels,
                                minX: comp.minX, minY: comp.minY, maxX: comp.maxX, maxY: comp.maxY,
                                classification: cls, confidence: evidence.confidence)
        }
        return DefectLabelField(width: field.width, height: field.height,
                             labels: field.labels, components: classified)
    }

    // MARK: 증거(confidence·극성)

    /// confidence = 검출 증거 요약(0~1). strong 코어 비율(히스테리시스 채택 근거)과
    /// 진폭/국소그레인 SNR 을 섞는다. 임계 통과 컴포넌트의 하한을 0.2 로 두어
    /// "채택되긴 했지만 약한" 결함이 0 에 붙지 않게 한다.
    private static func componentEvidence(_ comp: DefectComponent, field: DefectLabelField,
                                          contrast: DefectContrastField, strong: [Bool])
        -> (confidence: Double, polarity: Double) {
        let w = field.width, h = field.height
        var strongCount = 0
        var mag = 0.0, noise = 0.0, inside = 0.0
        for p in comp.pixels {
            if p >= 0, p < strong.count, strong[p] { strongCount += 1 }
            mag += Double(max(contrast.dustMag[p], contrast.thinMag[p]))
            noise += Double(contrast.noiseScale[p])
            inside += Double(contrast.bright[p])
        }
        let n = Double(max(1, comp.pixels.count))
        let strongFraction = Double(strongCount) / n
        let snr = (mag / n) / max(1e-4, noise / n)
        let confidence = min(1.0, max(0.0, 0.2 + 0.5 * strongFraction + 0.3 * min(1.0, snr / 8.0)))

        // 극성: 컴포넌트 평균 밝기 − 주변 링 평균 밝기(라벨된 픽셀 제외). >0 밝은 결함(pinhole 류).
        let pad = 3
        let x0 = max(0, comp.minX - pad), x1 = min(w - 1, comp.maxX + pad)
        let y0 = max(0, comp.minY - pad), y1 = min(h - 1, comp.maxY + pad)
        var ring = 0.0, ringCount = 0.0
        for y in y0...y1 {
            for x in x0...x1 {
                let p = y * w + x
                guard field.labels.isEmpty || field.labels[p] < 0 else { continue }
                ring += Double(contrast.bright[p]); ringCount += 1
            }
        }
        let polarity = ringCount > 0 ? inside / n - ring / ringCount : 0
        return (confidence, polarity)
    }

    // MARK: 종류 판정

    private static func classification(_ comp: DefectComponent, width: Int, polarity: Double,
                                       pinholeMaxArea: Int, emulsionMinArea: Int) -> DefectClass {
        let pca = DefectShape.pcaMetrics(comp.pixels, width: width)
        switch comp.kind {
        case .scratch:
            // 주축 방향으로 수평/수직/대각을 가른다(다방향 스크래치 문헌의 orientation binning).
            let a = pca.angleDegrees
            if a <= horizontalBand || a >= 180 - horizontalBand { return .scratchHorizontal }
            if abs(a - 90) <= verticalBand { return .scratchVertical }
            return .scratchDiagonal
        case .dust:
            let area = comp.pixels.count
            let boxW = comp.maxX - comp.minX + 1, boxH = comp.maxY - comp.minY + 1
            let fillRatio = Double(area) / Double(max(1, boxW * boxH))
            // pinhole: 작고 둥글고 꽉 찬 "밝은" 점(유제 구멍은 투과광이 그대로 지나간다).
            if polarity > 0.015, area <= pinholeMaxArea, pca.aspect <= 2.5, fillRatio >= 0.4 {
                return .pinhole
            }
            // emulsion damage: 넓거나(면적) 불규칙(낮은 fill)·두꺼운 손상 자국.
            if area >= emulsionMinArea, fillRatio <= 0.5 || pca.thickness >= 8 {
                return .emulsionDamage
            }
            return .dust
        }
    }
}
