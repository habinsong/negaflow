import Foundation
import CoreImage
import simd

// MARK: - ScannerTargetGrade (NORITSU HS-1800 / FUJI SP-3000 타겟)
//
// 두 겹으로 구성된 결정적 스캐너 에뮬레이션이다(장치 정확 복제를 주장하지 않는다):
//   1. 문서 기반 절대 개성(documentedCharacter): 공개 랩/리뷰 문헌으로 방향이 확립된 각 스캐너의
//      고유 톤·중립·스킨·채도 성격을 MAIN 위에 bounded 하게 얹는다. 크기는 특정 컷이 아니라
//      지각 목표(median ΔE)로 합성 테스트에서 보정한다. 이것이 MAIN 대비 시각적 구별의 주 동인이다.
//   2. 실측 상대 차분(scannerSignature): 두 스캐너의 같은 roll-label set에서 분리 가능한 **장비 간
//      상대 스타일**만 대칭 분배해 문서 개성 위에 riding refinement 로 얹는다(pair 없으면 생략).
//
// 과거엔 (2)만 적용해 공유 개성이 절반 차분에서 상쇄돼 MAIN 과 median ΔE<1(지각 불가)이었다.
// (1)은 그 구조적 한계를 문서 근거 에뮬레이션으로 보완한다(측정이라 주장하지 않음).
//
// 근거 경계:
//   • 번들 프로파일과 manifest SHA-256은 입력 통계를 고정한다.
//   • 두 스캐너의 kind/filmKey/source roll-label set이 모두 일치한 group만 비교한다.
//   • 현재 schema에는 frame ID/hash, scanner unit/calibration, 작업자 설정, paired TARGET,
//     독립 holdout이 없다. 따라서 같은 원본 프레임 전체나 절대 색 정확도는 증명되지 않는다.
//
// 상대 시그니처:
//   • tone은 두 출력 percentile 중점을 photometric mid에 재앵커하고 절반 차이를 대칭 분배한다.
//   • neutral/hue/chroma도 pair별 절반 차이/비율만 사용한다. 여러 film pair에서 방향이
//     뒤집히는 성분은 항등으로 돌려 장면·필름 차이를 장치 특성으로 오인하지 않는다.
//   • 측정값은 sRGB 감마 도메인이므로 CIColorCubeWithColorSpace(sRGB)에서 적용한다.
//   • 0...1 측정 cube 밖의 extended working 값은 원본을 유지한다.
//
// 문헌으로 방향이 확립된 **전역 톤 커브·중립축·스킨 hue·대역 채도**는 documentedCharacter 가
// bounded 하게 얹는다(측정 아님, 문서 근거 에뮬레이션). **장치 질감**(NORITSU 기본 샤픈 —
// "끌 수 없다"가 문서화된 시그니처)은 applyDocumentedTexture 가 luminance USM 으로 재현한다
// (2026-07-20 사용자 지시; 정확한 반경/강도 실측이 없어 보수적 수치, 그레인 합성은 하지 않고
// 실제 그레인을 crisp 하게 만드는 실기 메커니즘만 재현). 로컬 대비(장면 적응 톤
// 류)는 여전히 미에뮬레이션. 흑백은 색 성분을 버리고 문서 톤(대비)만 남긴다. 문서 개성은 장치
// 시그니처라 필름 타입 전체(컬러/흑백 × 슬라이드/네거티브)에 같은 방향으로 적용하되, 포지티브는
// 개입이 작아 documentedPositiveScale 로 약하게 얹는다. 실측 상대 차분은 roll-label pair 존재
// 시에만. 실측/문서 톤 전이는 정상 DR 장면 유래이므로 저DR(평탄) 장면에서는 장면 DR 신뢰도
// (NegativeInversion.sceneToneConfidence)로 톤 성분을 identity 쪽으로 게이트한다(노출 과다 방지).
public enum ScannerTargetGrade {}
