# 라이브러리 보존 아카이브

[문서 홈](../README.md)

카탈로그 백업은 앱을 다시 돌리기 위한 것이고 원본 사진은 담지 않습니다. `.negaflowarchive` 아카이브는 이들을 한 패키지에 담습니다.

| 담는 것 | 빼는 것 |
|---|---|
| 이식 가능한 카탈로그 JSON | 실행 중인 SQLite 파일 |
| 참조하는 원본과 남은 IR 원본 | 썸네일과 미리보기 |
| 아직 필요한 GrainMend 편집 기록 | 다시 만들 수 있는 GrainMend 캐시 |
| 가상 사본과 공유 원본의 연결 | 내보낸 파일 |

> [!WARNING]
> 아카이브 생성이 실패해도 기존 아카이브를 덮어쓰지 않습니다. 원본, 타사 XMP, 실행 중인 카탈로그도 건드리지 않습니다.

## 패키지 구조와 검사

패키지는 [RFC 8493 BagIt](https://www.rfc-editor.org/rfc/rfc8493.html)의 폴더 구조를 따릅니다. 내용 파일과 관리 파일의 SHA-256 목록은 따로 씁니다. `negaflow-archive.json`이 프레임 ID와 저장된 파일 ID를 잇습니다. 한 원본의 가상 사본들은 저장본 하나를 함께 씁니다.

임시 폴더는 아래가 모두 통과한 뒤에만 최종 경로로 옮겨집니다.

1. 현재 앱이 카탈로그를 안전하게 읽을 수 있습니다.
2. 원본과 IR 입력이 일반 파일이고 복사하는 동안 크기와 수정 시각이 바뀌지 않습니다.
3. 필요한 GrainMend 기록을 모두 읽을 수 있습니다.
4. SHA-256, 바이트 수, 파일 목록, `Payload-Oxum`이 일치합니다.
5. 프레임과 원본, IR 파일, GrainMend 기록의 연결이 카탈로그와 일치합니다.

실패하면 만들다 만 임시 폴더만 지웁니다. 기존 아카이브는 그대로 남습니다.

## 한계

원본 형식은 그대로 보존하며 장기 호환을 위한 변환은 하지 않습니다. PREMIS 보존 이벤트와 에이전트 기록, 권장 형식으로의 이전은 v1에 포함하지 않습니다.

아카이브 하나는 보존 계획이 아닙니다. 사본을 다른 매체와 다른 장소에 두고 해시를 주기적으로 다시 확인하세요.

출처:

- [RFC 8493: The BagIt File Packaging Format](https://www.rfc-editor.org/rfc/rfc8493.html)
- [Library of Congress PREMIS](https://www.loc.gov/standards/premis/)
- [Library of Congress Recommended Formats Statement](https://www.loc.gov/preservation/resources/rfs/)
