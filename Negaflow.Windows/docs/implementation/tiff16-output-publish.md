# TIFF16 출력·최소 메타데이터 검증·게시 구현

## 책임 경계

이 단계는 수동 현상이 끝난 `WorkingImage`를 최소 메타데이터의 opaque 16-bit sRGB TIFF 한 개로
게시합니다.

```text
source TIFF
  → file ID·크기·최종 수정 시각 관찰
  → bounded probe + row-streamed Microsoft WIC decode
  → scanner ICC/linear-raw → extended-linear-sRGB WorkingImage
  → source 상태 재관찰; 변경 시 출력 전 중단
  → manual Dmin negative develop
  → tone adjustment → Primary Calibration
  → explicit film-scan Film Look: RGB33 color → bounded acutance
  → 최종 경계 clamp + sRGB OETF + packed RGB16
  → 같은 디렉터리 CREATE_NEW staging에 Microsoft WIC TIFF encode
  → flush
  → TIFF 구조 + 첫 IFD allowlist 검사
  → Microsoft WIC decode로 전체 pixel·ICC exact readback
  → 기존 목적지를 대체하지 않는 최종 이름 게시
```

source 파일은 읽기 전용이며 metadata를 출력으로 복사하지 않습니다. UI, catalog, recipe와 여러 artifact를
묶는 transaction은 이 모듈이 소유하지 않습니다. 공개 C ABI도 늘리지 않았으며 첫 소비자는 CLI입니다.

## 파일 구성

- `image_file_observation.h/.cpp`: content를 읽지 않는 source 파일 상태 관찰과 비교
- `wic_srgb16_support.h/.cpp`: PNG/TIFF가 공유하는 COM·WIC factory, 등록 sRGB, exact RGB16 frame I/O
- `tiff_ifd_allowlist.h/.cpp`: bounded Classic TIFF 첫 IFD 최소 tag 검사
- `wic_tiff_export.h/.cpp`: TIFF encode, 구조·metadata·pixel·ICC 검증과 publish orchestration
- `export_developed_image.h/.cpp`: decode·color·develop·tone·Film Look·단계 보고를 공유하는 CLI orchestration
- `export_developed_png.cpp`, `export_developed_tiff.cpp`: 형식만 고르는 얇은 command adapter

PNG와 TIFF의 container 검사·상태 enum·encoder adapter는 분리하고, exact sRGB16 frame I/O와 filesystem
publish만 재사용합니다. 한 객체가 입력, 현상, 출력, CLI 직렬화를 모두 맡지 않습니다.

## TIFF encode 계약

- encoder: `CLSID_WICTiffEncoder`
- decoder: `CLSID_WICTiffDecoder`
- vendor: Microsoft
- pixel format: 정확히 `GUID_WICPixelFormat48bppRGB`
- sample: unsigned 16-bit RGB, opaque, chunky planar
- compression: `TiffCompressionMethod = WICTiffCompressionNone` (`VT_UI1`)
- destination color: Windows 등록 `LCS_sRGB` profile
- container: stripped Classic TIFF, 단일 IFD, orientation 1

`SetPixelFormat`의 반환 GUID가 요청과 다르면 중단합니다. profile은 WIC에 넘기기 전 크기·header·`acsp`·RGB
color space와 bounded tag table을 검사합니다. encode 후에는 preflight 결과가 치수, bit depth, sample
format, compression tag 1, photometric RGB 2, planar 1, orientation 1, strip 수, packed raster byte 수와 ICC
길이에 정확히 맞아야 합니다.

## 최소 metadata 정책

첫 IFD parser는 파일 전체를 메모리에 올리지 않고 header, entry count와 각 12-byte entry를 bounded
offset read로 확인합니다. 최대 128개 tag만 받고 중복 tag를 거부합니다. 구조상 허용하는 tag는 다음과
같습니다.

| 분류 | tag |
|---|---|
| 이미지 구조 | 254, 256, 257, 258, 259, 262, 266, 273, 274, 277, 278, 279 |
| 해상도·배치·sample 구조 | 282, 283, 284, 296, 317, 339 |
| ICC profile | 34675 |

ICC tag 34675는 반드시 있어야 합니다. Make 271을 포함한 descriptive tag, Software, DateTime, Artist,
Copyright, XMP 700, EXIF/GPS/IPTC pointer와 알 수 없는 tag는 모두 거부합니다. bounded TIFF probe가
다음 IFD offset 0을 요구하므로 추가 page에 metadata를 숨기는 형태도 게시되지 않습니다.

이 정책은 source metadata를 골라 전달하는 기능이 아닙니다. WIC가 새 파일을 만들며 생성한 구조 tag만
허용하는 phase-1 `minimal` 정책입니다.

## source 안전과 SHA 정책

CLI는 decode 직전과 decode·scanner color 변환 직후에 source를 다시 열어 다음 값만 비교합니다.

- volume serial과 file index
- file byte 수
- 최종 수정 시각

`FILE_READ_ATTRIBUTES`만 요청하고 image content를 읽거나 hash하지 않습니다. 관찰이 실패하거나 값이
달라지면 develop·output 전에 중단합니다. 이는 cryptographic 동일성 증거가 아니며 읽는 도중의 일반적인
교체·크기·수정 변경을 값싸게 감지하는 안전장치입니다. 공급망과 명시적 진단 SHA-256은 별도 opt-in
경계를 유지합니다.

## 게시와 실패 계약

TIFF adapter는 PNG에서 검증한 `AtomicOutputFile`을 사용합니다. encode·flush·structure·metadata·readback
중 하나라도 실패하면 staging을 best-effort로 폐기합니다. 모든 검증이 끝나야 replace/cross-volume-copy
flag 없이 최종 이름으로 옮깁니다. 목적지가 미리 있거나 작업 중 생기면 기존 목적지를 보존합니다.

게시 후 최종 파일 확인이 실패하면 외부에 보인 파일을 임의 삭제하지 않고
`published_file_invalid`, `published=true`로 사실을 전달합니다. 이 경계는 한 파일의 같은-volume 게시이며
directory fsync, 전원 장애, network filesystem과 catalog transaction을 보장하지 않습니다.

## CLI와 단계 보고

```powershell
.\out\build\native\x64-debug\Debug\negaflow-cli.exe --export-developed-tiff16 <source> <absolute-destination> 0.72 0.32 0.15 color
```

기존 명령은 identity Film Look으로 그대로 동작합니다. 선택한 profile을 적용할 때는 마지막에
`film_scan <film-emulation> <film-look-intensity>` 세 값을 모두 추가합니다. 목적지는 존재하지 않아야
합니다. 성공 JSON은 기존 상위 필드와 함께 다음을 기록합니다.

- source byte 수와 `source_unchanged_during_decode`
- source/artifact SHA mode `off`
- decode+color: WIC pixel format, 변환 여부, frame/row/copy 수, decoded/peak byte, scanner transform
- develop: 적용 Dmin, normalized Dmax, 추가 full-frame byte 0
- Film Look: 명시적 source/profile/intensity, route, color/acutance 적용, bounded workspace byte
- output: artifact/pixel/ICC byte, clipping, strip/IFD/compression, 검증·게시 상태
- 결합된 decode+color, develop, tone, Film Look, output과 전체 wall/process-CPU microseconds

streaming decode와 color 변환, output 변환·encode·검증·게시가 각각 한 API 호출 안에서 결합되어 있으므로
존재하지 않는 세부 시간을 추정해 나누지 않습니다. CPU는 `GetProcessTimes`의 모든 스레드 user+kernel
합계이고 실패하면 `null`입니다. 기본 export는 stage fingerprint를 위해 pixel을 다시 훑지 않으며, 해당
통계는 별도 `--develop-negative-tiff` 진단에만 있습니다. 경로, file ID와 시각 값은 JSON에 넣지 않습니다.

## 기본 한도

- packed RGB16: 512 MiB
- TIFF artifact: 2 GiB
- destination ICC: 4 MiB
- readback buffer: 16 MiB
- 첫 IFD entry: 128개

readback buffer가 한 행도 담지 못하면 더 크게 할당하지 않고 실패합니다. 현재 출력은 Classic TIFF만
허용하므로 2 GiB 초과와 BigTIFF는 별도 설계가 필요합니다.

## 남은 위험

- 최종 working float와 packed RGB16이 동시에 전체 프레임 메모리에 존재
- 같은 Microsoft WIC codec 계열을 사용한 readback이며 독립 decoder 비교가 아님
- Windows 등록 sRGB profile의 machine별 차이
- WIC servicing에 새 정상 구조 tag가 추가되면 fail-closed allowlist가 출력을 거부할 수 있음
- source 관찰은 cryptographic content 동일성 증거가 아님
- DPI/metadata policy variant, compression variant와 cancellation/progress 미구현
- macOS TIFF golden·pixel diff와 실제 ARM64 실행 미검증
