# 렌더 기록

[문서 홈](../README.md)

macOS 내보내기 사이드카에 기록되는 `renderManifest`는 원본과 편집 설정, 최종 출력 파일을 SHA-256 해시로만 연결해 파일 경로를 제외하며, Windows 내보내기 사이드카는 별도의 현상 레시피만 기록합니다.

> [!IMPORTANT]
> `renderManifest`는 파일과 설정의 해시 연결 관계만 기록한 파일이며, 전자 서명이나 인증서를 포함하는 C2PA Content Credentials와는 구별됩니다.

## v3에 들어가는 것

- 원본 바이트 수와 SHA-256, 알고리즘 이름 `sha-256`
- 실제로 사용한 렌더 입력
- GrainMend 캐시 파일 또는 메모리 입력의 검증 범위
- 현상과 GrainMend, 내보내기 설정의 SHA-256
- 스캐너 프로파일의 SHA-256과 프린터 출력 프로파일을 반영했을 때의 `outputProfileSHA256`
- 디코더 출처와 Chroma Engine 렌더러 버전
- 최종 파일의 SHA-256과 바이트 수, 픽셀 크기와 형식

인코더가 기록을 마치면 ImageIO로 파일을 다시 열어 픽셀 크기를 확인하고 파일의 해시를 구한 뒤에 사이드카를 작성하며 v3 검증을 통과한 경우에만 결과를 완성된 출력 파일로 내보냅니다.

## GrainMend 입력

- `cleanedMemory`: 메모리의 픽셀에는 표준 해시가 없어서 검증 범위를 `sourceAndDevelopRecipe`로 기록하고 GrainMend 편집 기록의 SHA-256을 항상 함께 넣습니다.
- `cleanedFile`: GrainMend 캐시 파일과 편집 기록을 모두 해시합니다.

v1과 v2 파일도 그대로 열리며 당시 기록된 해시 항목만 남습니다.

## C2PA와의 차이

전자 서명, 인증서, 신뢰 사슬, 내장 claim 저장소는 포함하지 않고 C2PA의 hard binding과 처리 이력, PREMIS의 무결성 개념을 참고해 검증 가능한 SHA-256 수치만 기록합니다.

출처:

- [C2PA Content Credentials 2.2](https://spec.c2pa.org/specifications/specifications/2.2/specs/C2PA_Specification.html)
- [C2PA hard-binding guidance](https://spec.c2pa.org/specifications/specifications/2.4/guidance/Guidance.html)
- [PREMIS preservation metadata](https://www.loc.gov/standards/premis/)
- [Apple Image I/O orientation and image properties](https://developer.apple.com/documentation/imageio/cgimagepropertyorientation)
