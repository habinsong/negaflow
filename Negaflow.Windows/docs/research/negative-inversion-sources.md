# 네거티브 반전 근거와 권리 조사

기준일: 2026-08-04

## 구현 provenance

Windows 수동 현상 경로의 수식, 고정 계수와 알고리즘 version은 같은 Apache-2.0 저장소의 macOS
Sources/Chromabase/Film/NegativeInversion.swift와 기존 Windows scalar reference에서 가져왔습니다.
새 orchestration은 직접 작성했으며 Darktable, RawTherapee나 다른 외부 프로젝트의 구현 코드를
복사하거나 번역하지 않았습니다.

저장소의 [LICENSE](../../../LICENSE)와 [NOTICE](../../../NOTICE)는 이 내부 이식의 저작권 및
기여 조건을 계속 적용합니다. 새 runtime dependency나 외부 사진 fixture는 추가하지 않았습니다.

## 기술 근거

- [Apple CIColorKernel](https://developer.apple.com/documentation/coreimage/cicolorkernel)은 macOS
  기준 구현이 pixel 단위 color kernel로 동작한다는 API 경계만 확인하는 데 사용했습니다.
- [Apple CIContext](https://developer.apple.com/documentation/coreimage/cicontext)은 Core Image가
  working color space에서 입력과 출력을 색상 변환한다는 점을 확인하는 데 사용했습니다.
- H&D characteristic curve와 base/fog, toe, straight-line, shoulder 구분은 오래된 감광학
  선행 기술입니다. 현재 수동 경로는 이를 제품별 물리 모델이라고 주장하지 않고 Negaflow의 고정
  generic print response로 취급합니다.

Apple 문서의 예제 코드나 외부 특허의 수식·표·도면은 구현에 복사하지 않았습니다.

## 특허 engineering screen

다음 공개 문서를 기능 범위와 비교했습니다.

- [US4866513A](https://patents.google.com/patent/US4866513A/en): 한 frame의 평균·최대·최소를
  검출해 preset gamma를 자동 선택하는 color-film video 보정입니다. 현재 구현은 장면 통계를
  읽거나 gamma를 자동 선택하지 않습니다.
- [US5500316A](https://patents.google.com/patent/US5500316A/en): electronic scanning을 위해
  contrast를 조정한 color negative film 재료에 관한 문서입니다. 현재 구현은 필름 제조물이나
  emulsion 구성을 만들지 않습니다.
- [US6849366B1](https://patents.google.com/patent/US6849366B1/en): film processing quality
  control용 sensitometric wedge와 제조·측정 절차에 관한 문서입니다. 현재 구현은 control strip,
  processor feedback이나 film 제조를 수행하지 않습니다.

Google Patents는 조사 시점에 각각 Expired - Lifetime 또는 Expired - Fee Related로
표시하지만, 사이트 자체가 상태를 법적 결론으로 보증하지 않는다고 명시합니다. 따라서 이 기록은
기능 중복을 피하기 위한 초기 engineering screen일 뿐 법률 의견이나 freedom-to-operate 보증이
아닙니다. 배포 지역과 최종 제품 기능이 확정되면 별도 검토가 필요합니다.

## 구현에 반영한 경계

- 현재 단계는 명시적 Dmin과 고정 response만 사용하는 generic manual path입니다.
- 자동 노출 분류, frame 통계 기반 gamma 선택과 제조 공정 품질 제어는 구현하지 않았습니다.
- 외부 patent code나 sample payload를 포함하지 않았습니다.
- 현재 네이티브 runtime dependency는 Windows 기본 API뿐입니다.
