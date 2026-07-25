import Foundation
import CoreGraphics
import CoreImage
import Chromabase

// 결함 제거 편집 한 단위. 브러시 결함 제거(스트로크 그룹)와 가이드 영역 결함 제거(렌더된 마스크)를 하나의
// 순서 있는 히스토리(defectEdits)로 통합한다 — cleaned raw = 원본 raw + defectEdits 순차 적용.
//
// 이 통합이 핵심: 과거에는 브러시가 "원본 raw + strokes"로 cleaned raw를 재계산하고 가이드는
// 현재 cleaned raw에 직접 덮어써서, 한쪽을 rebuild(⌘Z/clear/증분 불가)하면 다른 쪽 결과가
// 사라졌다. 이제 두 편집이 같은 리스트에 순서대로 쌓이고 재빌드 시 전부 재적용되므로 서로
// 되살아나지 않는다.
//
// 메모리: region 은 무거운 DefectLabelField(라벨맵 + 컴포넌트 픽셀) 대신 zlib 가능한 렌더 마스크만
// 보관한다. 대부분이 0인 ROI 마스크를 원시 RGBA로 프레임마다 붙잡지 않는다.
enum DefectEdit {
    /// 브러시 스트로크 그룹(변형 전 raw 정규좌표).
    case brush([DefectStroke])
    /// 가이드 영역 결함 제거 결과: 렌더된 결함 마스크(RGBA8, 흰색=제거) + raw(y-up) 픽셀 ROI.
    case region(mask: DefectCompressedData, roi: CGRect, width: Int, height: Int)
    /// 하드웨어 IR 채널 검출 결과: 결함 주변만 담은 클러스터 마스크 목록(메모리 절약 —
    /// 풀프레임 마스크 대신 결함 bbox 타일만 보관). 복원은 region 과 동일한 SoftwareDefectRemoval.repair.
    case infrared(clusters: [InfraredDefectRemoval.Cluster])
    /// 복제 도장 스트로크 그룹(변형 전 raw 정규좌표 + 소스 오프셋). 검출 없이 소스 픽셀을 복제한다.
    case clone([CloneStampStroke])
}

/// 마스크 오버레이 표시용 컴포넌트(base 정규 점, y-down). Region 편집이 검출 미리보기를
/// 다운샘플해 보관한다 — 원본 라벨맵 없이도 레이어 마스크를 다시 그릴 수 있다.
struct DefectMaskPreviewComponent {
    let classification: DefectClass
    let confidence: Double
    let points: [CGPoint]
}

/// 강도 1.0으로 계산된 복원 결과 패치(레이어의 실제 변경 영역만). 강도 s 적용 = 원본과의
/// 상수 알파 블렌드(블렌드는 마스크에 선형이라 내부 마스크×s 와 동일) — 강도 조절이 heal/검출
/// 재계산 없이 패치 합성만으로 끝난다.
struct DefectPatch {
    let rect: CGRect     // raw 픽셀(y-up, integral)
    let image: CGImage   // rect 크기의 강도 1.0 결과(RGBA16 linear)

    /// working 위에 강도 s 로 합성한 CIImage 를 돌려준다. s=1 이면 패치 그대로 얹는다.
    /// 블렌드는 CIMix(image·s + background·(1−s), working space 산술)로 한다 — CIBlendWithMask 의
    /// 상수색 마스크는 색공간 변환을 타서 s 가 왜곡되고(0.5→0.214), CIColorMatrix 수동 합산은
    /// premultiply 재적용으로 k² 감쇠가 생긴다. CIMix 는 정확히 선형이라 즉시 경로(캐시 패치
    /// 합성) = 전체 재계산이 성립한다.
    func composited(over working: CIImage, strength: Double, colorSpace: CGColorSpace) -> CIImage {
        let patchCI = CIImage(cgImage: image, options: [.colorSpace: colorSpace])
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
        guard strength < 0.999 else { return patchCI.composited(over: working) }
        let blended = CIFilter(name: "CIMix", parameters: [
            kCIInputImageKey: patchCI.cropped(to: rect),
            kCIInputBackgroundImageKey: working.cropped(to: rect),
            "inputAmount": max(0, strength),
        ])?.outputImage?.cropped(to: rect) ?? patchCI
        return blended.composited(over: working)
    }
}

/// Defect Layer 한 항목(v2). 원본 픽셀을 직접 바꾸는 게 아니라 "복원 레이어"처럼 다룬다:
/// 켜고 끄기(단일 결함 되돌리기 = before/after), 강도(복원 블렌드 비율), 삭제가 가능하고
/// cleaned raw 는 켜진 항목만 순서대로 재적용해 만들어진다.
struct DefectEditItem: Identifiable {
    // 사이드카 복원 시 저장된 id 를 그대로 쓴다(undo 스택/마스크 표시가 id 로 레이어를 찾으므로).
    var id: UUID = UUID()
    let edit: DefectEdit
    var enabled: Bool = true
    /// 복원 블렌드 강도(0~1). 1 = 완전 대체, 낮추면 원본과 섞는다.
    var strength: Double = 1.0
    /// 레이어 이름("브러시 3획", "영역 12개").
    let title: String
    /// 분류/confidence 요약("먼지 7 · 가로 스크래치 2 · 평균 확신 82%").
    let summary: String
    /// 마스크 오버레이 점(region 전용, base 정규). 브러시는 스트로크 자체로 그린다.
    let preview: [DefectMaskPreviewComponent]
    /// preview/스트로크 좌표 변환에 쓰는 raw 픽셀 크기(회전/크롭 정합).
    let baseSize: CGSize?
    /// 강도 1.0 결과 패치 캐시(런타임 전용). 이 레이어가 계산될 때의 베이스(앞선 레이어들의 결과)
    /// 기준이라, 앞선 레이어가 바뀌면 호출측이 무효화한다. 강도/켜기 변경 시 재계산 없이 합성만 한다.
    var cachedPatches: [DefectPatch]?

    var isBrush: Bool {
        if case .brush = edit { return true }
        return false
    }

    var brushStrokes: [DefectStroke] {
        if case .brush(let strokes) = edit { return strokes }
        return []
    }

    var isClone: Bool {
        if case .clone = edit { return true }
        return false
    }

    var cloneStrokes: [CloneStampStroke] {
        if case .clone(let strokes) = edit { return strokes }
        return []
    }

    /// 합성 결과에 영향을 주는 상태의 값 스탬프. 마스크/스트로크는 항목 id 로 대변된다
    /// (세션 안에서 불변) — 커밋된 cleaned raw 베이스의 유효성 판정에 쓴다.
    var appliedStamp: DefectAppliedStamp {
        DefectAppliedStamp(id: id, enabled: enabled, strengthBits: strength.bitPattern)
    }
}

/// cleanedRawImage 가 담은 편집 한 항목의 합성 상태 지문.
struct DefectAppliedStamp: Equatable {
    let id: UUID
    let enabled: Bool
    let strengthBits: UInt64
}

extension DefectClass {
    /// UI 표시 이름.
    var displayName: String {
        displayName(language: .system)
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .dust: return AppLocalization.text(AppLocalizedPhrase.defectDust, language: language)
        case .pinhole: return AppLocalization.text(AppLocalizedPhrase.defectPinhole, language: language)
        case .scratchHorizontal: return AppLocalization.text(AppLocalizedPhrase.defectScratchHorizontal, language: language)
        case .scratchVertical: return AppLocalization.text(AppLocalizedPhrase.defectScratchVertical, language: language)
        case .scratchDiagonal: return AppLocalization.text(AppLocalizedPhrase.defectScratchDiagonal, language: language)
        case .emulsionDamage: return AppLocalization.text(AppLocalizedPhrase.defectEmulsionDamage, language: language)
        case .microSpeck: return AppLocalization.text(AppLocalizedPhrase.defectMicroSpeck, language: language)
        }
    }
}
