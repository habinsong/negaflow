import Foundation
import Chromabase

/// Defect Layer 이름을 만드는 데 필요한 값.
///
/// 문자열을 미리 만들어 저장하면 만들던 시점의 언어가 그대로 굳는다 — 앱 언어를 바꿔도 이미
/// 쌓인 레이어만 예전 언어로 남는다. 그래서 값만 들고 있다가 **표시 시점에** 현재 언어로 만든다.
enum DefectEditLabel: Hashable, Codable {
    case automatic(count: Int)
    case guided(count: Int)
    case brush(strokeCount: Int)
    case clone(diameterPixels: Int)
    case infrared(count: Int)

    func title(language: AppLanguage) -> String {
        switch self {
        case .automatic(let count):
            return AppLocalization.format(
                AppLocalizedPhrase.grainMendAutoEditTitleFormat, language: language, count
            )
        case .guided(let count):
            return AppLocalization.format(
                AppLocalizedPhrase.grainMendGuidedEditTitleFormat, language: language, count
            )
        case .brush(let strokeCount):
            return AppLocalization.format(
                AppLocalizedPhrase.grainMendBrushEditTitleFormat, language: language, strokeCount
            )
        case .clone(let diameterPixels):
            return AppLocalization.format(
                AppLocalizedPhrase.cloneStampEditTitleFormat, language: language, diameterPixels
            )
        case .infrared(let count):
            return AppLocalization.format(
                AppLocalizedPhrase.grainMendIREditTitleFormat, language: language, count
            )
        }
    }
}

/// 레이어 요약도 같은 이유로 값만 들고 있다가 표시 시점에 문자열로 만든다.
enum DefectEditSummary: Hashable, Codable {
    /// 분류별 개수 + 평균 확신(자동/가이드/IR).
    case classBreakdown(DefectClassBreakdown)
    /// 고정 문구(브러시·복제 도장은 분류가 없다).
    case brush
    case clone

    func text(language: AppLanguage) -> String {
        switch self {
        case .classBreakdown(let breakdown):
            return breakdown.summary(language: language)
        case .brush:
            return AppLocalization.text(AppLocalizedPhrase.brushEditSummary, language: language)
        case .clone:
            return AppLocalization.text(AppLocalizedPhrase.cloneStampEditSummary, language: language)
        }
    }
}

/// 분류별 개수 한 항목. Dictionary 는 순서가 없어 표시 순서를 위해 배열로 들고 있는다.
struct DefectClassCount: Hashable, Codable {
    var classification: DefectClass
    var count: Int
}

/// 레이어 요약("먼지 7 · 가로 스크래치 2 · 평균 확신 82%")의 원재료.
struct DefectClassBreakdown: Hashable, Codable {
    /// DefectClass.allCases 순서로 정렬돼 있다.
    var counts: [DefectClassCount]
    var meanConfidence: Double

    init(counts: [DefectClassCount], meanConfidence: Double) {
        self.counts = counts
        self.meanConfidence = meanConfidence
    }

    /// 분류와 확신만 있으면 되므로 검출 경로(RGB/IR)의 타입에 묶이지 않는다.
    init(classifications: [(classification: DefectClass, confidence: Double)]) {
        var totals: [DefectClass: Int] = [:]
        var confidenceSum = 0.0
        for entry in classifications {
            totals[entry.classification, default: 0] += 1
            confidenceSum += entry.confidence
        }
        counts = DefectClass.allCases.compactMap { classification in
            totals[classification].map {
                DefectClassCount(classification: classification, count: $0)
            }
        }
        meanConfidence = classifications.isEmpty
            ? 0
            : confidenceSum / Double(classifications.count)
    }

    init(components: [DefectComponent]) {
        self.init(classifications: components.map { ($0.classification, $0.confidence) })
    }

    init(components: [InfraredDefectRemoval.Component]) {
        self.init(classifications: components.map { ($0.classification, $0.confidence) })
    }

    func summary(language: AppLanguage) -> String {
        let classes = counts
            .map { "\($0.classification.displayName(language: language)) \($0.count)" }
            .joined(separator: " · ")
        return AppLocalization.format(
            AppLocalizedPhrase.confidenceSummaryFormat,
            language: language,
            classes,
            meanConfidence * 100
        )
    }
}
