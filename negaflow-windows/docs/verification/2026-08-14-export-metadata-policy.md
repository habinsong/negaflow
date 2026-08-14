# 내보내기 메타데이터 정책이 실제 파일에 닿는가

기준일: 2026-08-14

## 무엇을 확인했는가

게시한 파일에 **아무 메타데이터도 들어가지 않던 상태**를 끝냈습니다. macOS 는 스캐너
Make/Model, 소프트웨어 이름, 촬영 일시, 저작자·저작권, 필름 종류를 파일에 적고 정책 네 가지로
무엇을 적을지 가르는데, Windows 는 그중 아무것도 쓰지 않았습니다.

## 어떻게

셸이 쓰는 것과 같은 경로입니다. `ExportSettings.MetadataPolicy` → `ToEncodingOptions` →
`DevelopRequestFactory.Create` → ABI v33 → `write_export_metadata` (WIC
`IWICMetadataQueryWriter`). 입력은 사용자의 실제 스캔 `OpticFilm8100_frame_1.tiff`, 출력은
TIFF16 이고 **정책만** 바꿔 세 번 냈습니다. 나온 파일은 IFD 를 직접 읽어 확인했습니다.

## 결과

| 태그 | minimal | copyrightOnly | all |
| --- | --- | --- | --- |
| Make (271) | `Plustek` | **(없음)** | `Plustek` |
| Model (272) | `OpticFilm 8100` | **(없음)** | `OpticFilm 8100` |
| Software (305) | `Negaflow 1.0` | **(없음)** | `Negaflow 1.0` |
| DateTime (306) | `2026:08:14 12:00:00` | **(없음)** | `2026:08:14 12:00:00` |
| Artist (315) | `habin song` | `habin song` | `habin song` |
| Copyright (33432) | `(c) 2026 habin song` | `(c) 2026 habin song` | `(c) 2026 habin song` |
| Orientation (274) | `1` | `1` | `1` |
| ExifIFD (34665) | 있음 | **(없음)** | 있음 |

읽는 법:

- **`copyrightOnly` 가 실제로 장비를 지웁니다.** 스캐너도 소프트웨어도 날짜도 EXIF 하위 IFD 도
  없고 권리 표시만 남습니다. macOS 와 같은 뜻입니다.
- **Orientation 은 어느 정책에서도 1 입니다.** 기하 변형이 이미 픽셀에 구워져 있으므로, 뷰어가
  한 번 더 돌리면 그림이 뒤집힙니다.
- `minimal` 과 `all` 의 차이는 지금 이 표에 안 보입니다. 차이는 UserComment 의 필름 이름
  하나뿐입니다 — `minimal` 은 `FilmType: …` 만, `all` 은 `FilmStock: …` 까지 적습니다. 필름
  이름은 사용자가 적은 촬영 기록이라 비우기로 한 정책에서는 싣지 않습니다(macOS 와 같음).

## 검증기도 같이 고쳤습니다

TIFF 게시는 IFD 를 다시 읽어 **우리가 쓴 태그만 들어 있는지** 확인하고, 모르는 태그가 하나라도
있으면 게시를 접습니다. 새로 쓰는 일곱 태그(271·272·305·306·315·33432·34665)를 목록에
넣었습니다. 이 목록은 `binary_search` 로 찾으므로 **번호 순서로** 두어야 합니다 — 뒤에 그냥
붙였다가 254(NewSubfileType)를 못 찾아 게시가 통째로 막히는 것을 먼저 겪었습니다.

기존 시험 하나는 "허용 목록이 Make 를 거부한다" 를 검사하고 있었습니다. 이제 Make 는 일부러
쓰는 태그이므로 그 시험의 전제가 바뀌었습니다. **GPS IFD(34853)를 거부하는지**로 바꿨습니다 —
우리가 절대 쓰지 않아야 하는 것이고, 위치가 새어 나가지 않는지를 보는 편이 더 값집니다.

## PNG

PNG 는 EXIF 를 담지 않습니다. WIC 인코더가 질의 작성기를 주지 않으므로 정책을 실어도 **PNG 에는
아무 흔적도 남지 않습니다.** 게시를 막지는 않습니다 — 담을 곳이 없는 것이지 실패가 아닙니다.

## 확인하지 않은 것

- **원본 메타데이터 복사.** macOS 의 `all` 과 `removeLocation` 은 원본 파일의 EXIF·IPTC 를
  옮겨 싣고 `removeLocation` 이 장소 키를 지웁니다. 지금 Windows 는 **앱이 아는 값만** 씁니다.
  그래서 두 정책이 현재는 같은 결과를 냅니다. 원본 복사는 다음 작업입니다.
- macOS 가 같은 설정으로 낸 파일과의 태그 단위 대조. 맥 호스트가 필요합니다.
- JPEG 경로. 코드는 같은 함수를 타지만(`/app1/ifd`) 실파일로 확인하지 않았습니다.
