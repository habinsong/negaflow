# 라이브러리 보존 아카이브

[문서 홈](../README.md)

카탈로그 백업은 앱 상태를 복구하기 위한 용도여서 원본 사진 파일은 제외합니다. 두 플랫폼 모두 `.negaflowarchive` 확장자를 사용하지만, macOS와 Windows의 패키지 형식과 구성은 서로 다릅니다.

> [!WARNING]
> 아카이브 생성이 실패해도 원본이나 타사 XMP, 실행 중인 카탈로그와 기존 아카이브는 그대로 보존합니다.

## macOS 아카이브 (BagIt 폴더)

macOS의 `.negaflowarchive`는 [RFC 8493 BagIt](https://www.rfc-editor.org/rfc/rfc8493.html) 폴더 구조를 따르며 카탈로그와 참조 사진을 함께 보관합니다.

| 포함 항목 | 제외 항목 |
|---|---|
| 이식 가능한 카탈로그 JSON | 실행 중인 SQLite 파일 |
| 참조하는 원본과 남은 IR 원본 | 썸네일과 미리보기 |
| GrainMend 결함 recipe | 다시 만들 수 있는 GrainMend 캐시 |
| 가상 사본과 공유 원본의 연결 | 내보낸 파일 |

내용 파일과 태그 파일의 SHA-256 매니페스트(`manifest-sha256.txt`, `tagmanifest-sha256.txt`)를 따로 작성해 둡니다. `negaflow-archive.json`이 프레임 ID와 저장된 파일 ID를 연결하므로, 한 원본의 가상 사본은 저장본 한 개를 함께 참조합니다.

이미 파일이나 폴더가 있는 대상 경로는 덮어쓰지 않고 막습니다. 임시 폴더는 아래 조건을 모두 통과한 뒤에만 최종 경로로 옮겨집니다.

1. 현재 앱이 카탈로그를 안전하게 읽을 수 있습니다.
2. 원본과 IR 입력이 일반 파일이고 복사 전후의 크기와 수정 시각이 그대로 유지됩니다.
3. 필요한 GrainMend 결함 recipe가 빠짐없이 열립니다.
4. SHA-256 해시(`manifest-sha256.txt`, `tagmanifest-sha256.txt`), 바이트 수, 파일 목록, `Payload-Oxum`이 일치합니다.
5. 프레임과 원본, IR 파일, GrainMend recipe의 연결이 카탈로그와 어긋나지 않습니다.

실패하면 만들다 만 임시 폴더만 지웁니다.

## Windows 아카이브 (ZIP 파일)

Windows의 `.negaflowarchive`는 카탈로그와 결함 상태를 압축한 ZIP 파일이며, 원본 사진 파일은 아카이브 밖의 원래 위치에 그대로 남습니다.

| 포함 항목 | 제외 항목 |
|---|---|
| `library.sqlite` | 원본 사진 파일과 IR 원본 |
| `defects/*` 결함 recipe | 썸네일이나 미리보기, 다시 만들 수 있는 캐시 |
| `archive.json`(항목별 바이트 수와 SHA-256 해시) | 내보낸 파일 |

Windows는 먼저 임시 파일에 아카이브를 만들고 검증이 끝나면 대상 파일과 교체합니다. 생성이 실패하면 임시 파일만 지우고 기존 아카이브는 그대로 지킵니다.

## 제약과 보존 범위

macOS와 Windows의 `.negaflowarchive`는 패키지 형식과 카탈로그 스키마가 서로 달라서 각 운영체제끼리만 옮길 수 있습니다. 이때 원본 파일 형식은 장기 호환용 변환 없이 그대로 남으며, PREMIS 이벤트나 에이전트 기록, 권장 형식으로 변환하는 기능은 v1 범위에서 빠집니다.

아카이브 파일 한 개만 믿고 장기 보관하기는 어려우므로 사본을 서로 다른 매체와 장소에 나누어 보관하고 해시를 주기적으로 다시 확인하세요.

출처:

- [RFC 8493: The BagIt File Packaging Format](https://www.rfc-editor.org/rfc/rfc8493.html)
- [Library of Congress PREMIS](https://www.loc.gov/standards/premis/)
- [Library of Congress Recommended Formats Statement](https://www.loc.gov/preservation/resources/rfs/)
