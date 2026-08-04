# PNG16 출력·검증·게시 구현

## 책임 경계

이 단계는 현상된 `WorkingImage`를 opaque 16-bit sRGB PNG 한 개로 안전하게 게시합니다.

```text
Film Look까지 끝난 extended-linear-sRGB RGBA32F WorkingImage
  → finite·opaque·크기 검사
  → 최종 경계 clamp + sRGB OETF + packed RGB16
  → 같은 디렉터리의 CREATE_NEW staging에 Microsoft WIC PNG encode
  → flush
  → bounded PNG 구조 검사
  → Microsoft WIC PNG decode로 전체 pixel·ICC exact readback
  → 기존 파일을 대체하지 않는 최종 이름 게시
```

UI, catalog, recipe와 source 파일 수명은 이 모듈이 소유하지 않습니다. 공개 C ABI도 늘리지 않았으며 현재
첫 소비자는 CLI입니다.

## 파일 구성

- `working_to_srgb16.h/.cpp`: working float에서 packed RGB16으로 가는 순수 출력 변환
- `atomic_output_file.h/.cpp`: handle-backed `IStream`, staging flush와 단일 파일 게시
- `png_structure_reader.h/.cpp`: bounded streamed PNG container 검사
- `wic_srgb16_support.h/.cpp`: PNG/TIFF가 공유하는 exact RGB16 frame I/O와 등록 sRGB profile
- `wic_png_export.h/.cpp`: PNG encode, 구조·readback과 게시 orchestration
- `export_developed_image.h/.cpp`: PNG/TIFF가 공유하는 decode·color·develop·tone·Film Look·단계 보고
- `export_developed_png.h/.cpp`: PNG 형식을 고르는 얇은 CLI adapter

## 출력 변환

입력은 양수 폭·높이, 폭 이상의 stride, 정확한 backing pixel 수를 가져야 합니다. 각 RGBA component는
finite여야 하고 alpha는 정확히 1이어야 합니다. alpha를 조용히 버리거나 배경색과 합성하지 않습니다.

RGB는 working 공간에서 음수와 1 초과 값을 유지합니다. 출력 정수로 바꾸는 마지막 순간에만 clamp하고
sRGB OETF를 적용한 뒤 `floor(value × 65535 + 0.5)`로 반올림합니다. clamp된 color component 수를 결과에
기록합니다. 16-bit 출력에는 현재 dither를 적용하지 않습니다.

기본 packed pixel 상한은 512 MiB입니다. 폭·높이·stride·sample byte 수를 checked 64-bit로 계산하고
할당 전에 상한을 적용합니다.

## WIC와 ICC 고정

- encoder: `CLSID_WICPngEncoder`
- decoder: `CLSID_WICPngDecoder`
- pixel format: 정확히 `GUID_WICPixelFormat48bppRGB`
- destination profile: `GetStandardColorSpaceProfileW(LCS_sRGB)`가 가리키는 등록 profile
- PNG color context: `IWICBitmapFrameEncode::SetColorContexts`

encoder와 decoder는 Microsoft vendor로 요청한 뒤 실제 CLSID를 다시 확인합니다. `SetPixelFormat`이 가장
가까운 다른 형식을 돌려주는 WIC 계약을 허용하지 않고 exact format이 아니면 중단합니다. ICC는 크기 상한,
header declared size, `acsp`, RGB data color space와 bounded tag table을 검사한 뒤 사용합니다.

## 게시 순서

1. 절대 목적지의 부재와 부모 디렉터리를 확인합니다.
2. 같은 부모에 추측하기 어려운 이름으로 staging 파일을 `CREATE_NEW` 생성합니다.
3. 파일 handle을 소유하는 작은 `IStream`에 WIC가 씁니다.
4. frame과 encoder를 commit하고 `FlushFileBuffers` 뒤 handle을 닫습니다.
5. 파일 크기 상한, PNG signature, 첫 `IHDR`, 16-bit truecolor, `iCCP`, `IDAT`, 마지막 `IEND`와 chunk
   범위를 검사합니다.
6. 같은 staging 파일을 Microsoft WIC decoder로 열어 치수·format·모든 RGB16 sample·ICC bytes를 exact
   비교합니다.
7. 검증된 byte 수를 기억하고 replace/cross-volume-copy flag 없이 최종 이름으로 옮깁니다.
8. 최종 경로가 일반 disk file이고 byte 수가 같은지 다시 확인합니다.

encode·flush·structure·readback·publish 전 실패는 staging을 best-effort로 지웁니다. 최종 이름으로 옮긴 뒤
검사가 실패하면 이미 외부에 보인 파일을 임의 삭제하지 않고 `published_file_invalid`와 `published=true`를
반환합니다. 목적지가 encode 도중 생긴 경합에서는 목적지를 보존하고 staging만 폐기합니다.

이 순서는 단일 artifact의 같은-volume 이름 게시 경계입니다. 디렉터리 metadata의 전원 장애 내구성,
network filesystem, 여러 파일과 catalog를 묶는 transaction은 보장하지 않습니다.

## 검증 한도

- encoded RGB16 pixel: 기본 512 MiB
- PNG artifact: 기본 2 GiB
- destination ICC: 기본 4 MiB
- readback 묶음: 기본 16 MiB
- PNG chunk 수: 최대 65,536개

readback buffer가 한 행도 담지 못하면 한도를 넘겨 강제 할당하지 않고 실패합니다. PNG parser는 파일 전체를
메모리에 올리지 않으며 각 chunk 길이가 실제 파일 범위 안인지 확인합니다. CRC를 따로 계산하지 않는 대신
후속 WIC decode와 exact pixel/profile 비교가 모두 성공해야 게시합니다.

## CLI

```powershell
.\out\build\native\x64-debug\Debug\negaflow-cli.exe --export-developed-png16 <source> <absolute-destination> 0.72 0.32 0.15 color
```

목적지는 존재하지 않아야 합니다. command는 기존 row-streamed TIFF decode와 scanner color 변환, 수동
Dmin 현상과 tone을 거쳐 PNG16을 만듭니다. 선택한 Film Look은 마지막에
`film_scan <film-emulation> <film-look-intensity>` 세 값을 모두 추가하며 Primary Calibration 뒤, 출력
변환 전에 실행됩니다. 성공 JSON에는 형식·치수·byte 수·ICC 크기·clipping 수·검증 상태와 게시 방식,
Film Look route·workspace·시간을 넣고 경로는 넣지 않습니다. source는 decode 전후 file ID·크기·최종
수정 시각만 관찰하고 단계별 byte·memory·wall/process-CPU time을 보고합니다. CPU는 프로세스 모든
스레드의 user+kernel 합계이고 얻지 못하면 `null`입니다. `source_sha256_mode`와
`artifact_sha256_mode`는 모두 `off`이며 이 command는 SHA-256 함수나 진단용 full-frame fingerprint
scan을 호출하지 않습니다.

## 남은 위험

- packed RGB16과 최종 working float가 모두 전체 프레임 메모리에 존재
- Windows에 등록된 sRGB profile의 machine별 차이
- 독립 decoder와 CRC 비교 부재
- TIFF16은 별도 phase-1 경계로 구현됐지만 DPI·metadata policy variant·resize·sharpen은 미구현
- encode/readback progress와 cooperative cancellation 미구현
- COM apartment가 이미 STA이면 현재 동기 API는 명시적으로 거부하므로 제품 연결은 MTA worker가 필요
- 실제 ARM64 Windows에서의 encode/readback 실행 미검증
