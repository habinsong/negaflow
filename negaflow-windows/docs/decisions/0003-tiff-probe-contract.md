# ADR-0003: 디코더 앞의 제한형 TIFF 사전 검사

상태: 채택
기준일: 2026-08-04

## 문제

WIC와 libtiff는 TIFF 구조를 폭넓게 처리하지만 파일이 주장하는 dimensions, IFD count, metadata length와
strip/tile table을 디코더 호출 전에 제품 예산으로 제한해야 합니다. 손상 파일이 두 디코더를 연속으로
실행시키거나 거대 allocation을 유도해서는 안 됩니다.

## 결정

- 독립적인 최소 probe가 Classic/BigTIFF header와 첫 IFD를 먼저 검사합니다.
- source는 Windows read-only handle로만 열고 write sharing을 허용하지 않습니다.
- 파일 내용에 비례하는 allocation 없이 entry와 segment를 고정 크기로 읽습니다.
- 모든 offset, count, raster, working-memory 계산은 checked 64-bit입니다.
- 외부 tag value와 각 strip/tile의 offset+byte count가 실제 file 범위 안인지 확인합니다.
- multiple IFD는 현재 조용히 첫 페이지만 선택하지 않고 명시 오류로 종료합니다.
- probe 성공은 pixel decode나 지원 layout 승인을 뜻하지 않습니다.
- WIC와 libtiff fallback은 후속 단계에서 별도 allowlist로 연결합니다.

## 대안

WIC만 먼저 호출하는 방식은 설치된 제3자 codec과 디코더 내부 resource 사용을 probe 전에 통제하기
어렵습니다. libtiff만 호출하는 방식은 memory option이 모든 application allocation을 제한하지 않으며,
단순 container 분류에도 dependency를 강제합니다. 따라서 작은 read-only preflight를 먼저 둡니다.

## 결과

원본 불변과 구조 오류 분류를 디코더와 분리할 수 있습니다. 대신 TIFF parser surface가 하나 생기므로
합성 malformed corpus, fuzzing, 공식 규격과의 지속 비교가 필요합니다. 이 probe는 metadata 의미 해석이나
compression decode로 확장하지 않고 작은 경계를 유지합니다.
