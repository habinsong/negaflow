# 렌더 기록

[문서 홈](../README.md)

사이드카의 `renderManifest`는 원본, 편집값, 최종 파일을 SHA-256으로 잇습니다. 파일 경로는 기록하지 않습니다.

> [!IMPORTANT]
> `renderManifest`는 파일과 설정 사이의 해시 관계를 적은 기록입니다. 전자 서명이나 인증서가 없으므로 C2PA Content Credentials가 아닙니다.

## v3에 들어가는 것

- 원본 바이트 수, SHA-256, 알고리즘 이름 `sha-256`
- 실제로 쓴 렌더 입력
- GrainMend 캐시 파일 또는 메모리 입력의 검증 범위
- 현상, GrainMend, 내보내기 설정의 SHA-256
- 스캐너 프로파일의 SHA-256
- 디코더 출처와 Chroma Engine 렌더러 버전
- 최종 파일의 SHA-256, 바이트 수, 픽셀 크기, 형식

인코더가 쓰기를 마치면 ImageIO로 파일을 다시 열어 픽셀 크기를 확인하고 파일 전체의 해시를 구합니다. 사이드카는 그 뒤에 씁니다. v3 검사가 실패하면 결과를 완성된 출력 묶음으로 게시하지 않습니다.

## GrainMend 입력

- `cleanedMemory`: 메모리의 픽셀에는 표준 해시가 없어서 검증 범위를 `sourceAndDevelopRecipe`로 적습니다. GrainMend 편집 기록의 SHA-256은 항상 들어갑니다.
- `cleanedFile`: GrainMend 캐시 파일 전체와 편집 기록을 모두 해시합니다.

v1과 v2 파일도 열립니다. 그때 없던 해시는 나중에 채워 넣지 않습니다.

## C2PA와의 차이

전자 서명, 인증서, 신뢰 사슬, 내장 claim 저장소가 없고 확인할 수 있는 SHA-256 값만 있습니다. C2PA의 hard binding과 처리 이력, PREMIS의 무결성 개념을 참고했습니다.

출처:

- [C2PA Content Credentials 2.2](https://spec.c2pa.org/specifications/specifications/2.2/specs/C2PA_Specification.html)
- [C2PA hard-binding guidance](https://spec.c2pa.org/specifications/specifications/2.4/guidance/Guidance.html)
- [PREMIS preservation metadata](https://www.loc.gov/standards/premis/)
- [Apple Image I/O orientation and image properties](https://developer.apple.com/documentation/imageio/cgimagepropertyorientation)
