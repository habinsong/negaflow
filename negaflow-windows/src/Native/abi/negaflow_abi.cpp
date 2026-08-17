#include "negaflow_abi.h"

// 공개 C ABI 는 아래 폴더의 번역 단위로 나뉩니다.
//   request/  C 요청 → 파이프라인 요청
//   result/   파이프라인 결과 → C 결과
//   export/   파일 내보내기 진입점
//   preview/  미리보기 진입점
//   run/      실행 상태(취소·진행)가 있는 진입점
//   detect/   GrainMend·적외선·평판 검출
//   probe/    TIFF·표준 이미지 원본 검사
//   proof/    색역·소프트 프루프
//   adjust/   자동 톤
//   support/  레이아웃 고정, 문자 헬퍼, 빌드 신원, 한계값
// 이 파일은 공유 라이브러리의 이름 있는 자리를 유지합니다.
