# 대수술: 이미지 가져오기 우선 워크플로우 + SANE 스캐너 플러그인 분리

이 문서는 negaflow의 스캐너 아키텍처와 기본 워크플로우를 바꾼 변경을 설명합니다.

## 무엇이 바뀌었나 (요약)

1. **기본 워크플로우 = 이미지 가져오기 → 현상.** 필름 스캐너 없이 RAW/DNG/TIFF/PNG/JPG/JPEG
   원본(컬러 네거티브 · 컬러 슬라이드 · 흑백 네거티브 · 흑백 슬라이드)을 가져와 바로 현상합니다.
2. **스캐너 = 선택적 외부 플러그인.** SANE 기반 스캐너 인식은 negaflow에서 **완전히 제거**되어
   독립 프로젝트 `negaflow-scanner-sane`(외부 프로세스 플러그인)로 분리됐습니다.
3. **좌측 Library 첫 화면 = 두 진입점(Lightroom식):** ① 이미지 가져오기 ② 스캐너 불러오기.
   두 경로 모두 **동일한 현상 워크플로우**(Develop / Versions / Presets / Film / Output)로 수렴합니다.
4. **상단 툴바:** 항상 노출되는 **이미지 가져오기** 버튼 + (스캐너가 있을 때만) 스캐너 선택/스캔 버튼.
5. **드래그앤드롭:** 창 어디에나 이미지 파일을 다중으로 끌어놓아 연속 가져오기.

## 왜 분리했나 (라이센스)

- Plustek OpticFilm 8200i가 쓰는 SANE `genesys` 백엔드는 **링크 예외 없는 GPL-2.0-or-later**입니다.
- negaflow는 **Apache-2.0**입니다. GPL 코드를 같은 바이너리/주소공간에 결합하면 GPL 의무가
  negaflow로 전파될 수 있습니다.
- 기존 negaflow도 `libsane`를 링크하지 않고 `scanimage`를 **외부 프로세스로만 호출**했지만,
  SANE 관련 코드 자체가 저장소에 있었습니다. 이번에 그 코드를 전부 들어내 별도 GPL 프로젝트로
  옮기고, negaflow는 **별도 프로세스 · CLI 인자 · 파이프 · JSON**으로만 통신합니다.
- 이 방식(프로세스 경계 통신)은 FSF와 법률 분석에서 **파생저작물이 아니라 단순 취합(aggregation)**
  으로 봅니다. SANE의 API/프로토콜 자체는 public domain입니다.
- 출처:
  - SANE License — <http://www.sane-project.org/license.html>
  - GNU GPL FAQ (mere aggregation / exec) — <https://www.gnu.org/licenses/gpl-faq.html>

## 아키텍처: 외부 프로세스 플러그인

negaflow는 스캐너 코드를 내장하지 않습니다. 대신 설치된 플러그인을 발견해 JSON/CLI로 통신합니다.

- **발견 위치:** `~/Library/Application Support/negaflow/Plugins/<id>/manifest.json`
  (테스트/개발용 재정의: 환경변수 `NEGAFLOW_PLUGINS_DIR`).
- **manifest.json:** `schemaVersion, id, name, executable, kind:"scanner", license, homepage`.
- **프로토콜(플러그인 실행파일 stdout JSON):**

  | 커맨드 | 입력 | 출력 |
  | --- | --- | --- |
  | `detect` | — | `{"devices":[{id,displayName,vendor,model,connectionType,verifiedStatus,…}]}` |
  | `capabilities <deviceId>` | — | `{resolutionsDPI,modes,bitDepths,supportsInfrared,…}` |
  | `scan` | 옵션 JSON(stdin) | 진행률 NDJSON `{"type":"progress",…}` … 최종 `{"type":"result",width,height,path,…}` |

- 외부 장치 id는 `plugin:<pluginId>:<플러그인-내부-id>` 로 감싸집니다. negaflow가 플러그인을
  호출할 땐 접두사를 벗겨 전달합니다.

### negaflow 측 핵심 파일 (`Sources/ScannerKit/`)

- `ScannerPluginManifest.swift` — manifest + 와이어 JSON 타입(`PluginDevice`/`PluginCapabilities`/
  `PluginScanOptions`/`PluginScanEvent`).
- `ScannerPluginHost.swift` — `discover()`(플러그인 디렉토리 스캔·manifest 파싱·실행권한 확인).
- `ExternalScannerBackend.swift` — `ScannerBackend` 구현. `Process`로 플러그인을 실행하고 JSON을
  `ScannerDescriptor`/`ScannerCapabilities`/`ScanResult`로 매핑. `backendType = .plugin`.
- `ScanTempFile.swift` — 스캔 임시 파일/이미지 크기 헬퍼(과거 SANEBackend static → SANE 무관).
- `MockScannerBackend.swift` — negaflow 자체 시뮬레이터(GPL 무관). 플러그인 없이도 스캔 경로 데모.

### 앱 측 핵심 파일 (`Sources/negaflowApp/`)

- `AppModel+Import.swift` — 파일 선택(다중)·드래그앤드롭·연속 가져오기. `.importedFile` 프레임 생성.
- `LibrarySourceSection.swift` — 좌측 Library 첫 화면(두 진입점 + 공유 현상 기본값).
- `ScanSection.swift` — `ScannerControlsSection`(스캐너 하드웨어 컨트롤 + 설치/시뮬레이터 안내).
- `ScanFrame.swift` — `FrameSource{ scannerTIFF, importedFile }` 추가(로더 분기용).
- `ContentView.swift` — 소스 인식형 툴바 + 창 전체 드래그앤드롭.
- `DevelopFramePipeline.swift` / `ExportFramePipeline.swift` — 소스별 로더 분기.

## 지원 입력 포맷 (제조사 RAW 전종 + 스캐너 raw)

가져오기는 카메라 제조사 RAW와 스캐너 raw를 폭넓게 받습니다. 단일 출처는
`Chromabase.ImageLoader.rawExtensions` / `standardExtensions` 입니다.

| 제조사 | 확장자 |
| --- | --- |
| Canon | `crw` `cr2` `cr3` |
| Nikon | `nef` `nrw` |
| Sony | `arw` `srf` `sr2` |
| Fujifilm | `raf` |
| Panasonic | `rw2` `raw` |
| Olympus / OM | `orf` |
| Pentax | `pef` |
| Samsung | `srw` |
| Hasselblad | `3fr` `fff` |
| Leica | `rwl` `dng` |
| Phase One | `iiq` · Sigma `x3f` · Epson `erf` · Mamiya `mef` · Leaf `mos` · Kodak `kdc`/`dcr`/`k25` |
| 범용 DNG | `dng` (Apple/Google/Adobe, VueScan/SilverFast raw DNG 포함) |
| 표준 이미지 | `tiff` `tif` `jpeg` `jpg` `png` `heic` `heif` `bmp` |

파일 선택 패널·드래그앤드롭 모두 목록에 없는 신형 RAW라도 macOS(ImageIO/UTType)가
이미지/카메라 RAW로 인식하면 받습니다. 실제 RAW 디코딩은 macOS의 시스템 RAW 지원(Core Image
`CIRAWFilter`)을 따릅니다 — Apple 미지원 기종은 임베디드 프리뷰로 폴백합니다.

## 스캐너 기기·IR 지원 (SANE 플러그인)

플러그인은 **모델명 하드코딩이 아니라 `scanimage -A` 옵션에서 실제 능력을 감지**합니다(§5.3).

- **다중 백엔드 감지.** `scanimage -L`을 백엔드 무관하게 파싱해 genesys(Plustek OpticFilm 7x00i/8x00·"i"
  기종)·epson2/epkowa(Epson Perfection V700/V750/V850 등)·기타 SANE 지원 스캐너를 인식합니다. 표시명은
  실제 벤더+모델, `driverVersion`은 백엔드명. USB 주소 재획득도 백엔드-일반화되어 리셋 후에도 올바른
  장치를 엽니다.
- **소스 자동 감지.** `--source` 문자열을 하드코딩(과거 "Transparency Adapter")하지 않고 장치가 노출하는
  값에서 투과 소스를 고릅니다(Transparency Adapter / Transparency Unit(TPU) / Film …). Epson TPU면
  `--film-type`(Negative/Positive Film)도 필름 종류에 맞춰 설정합니다.
- **IR(적외선) — 능력 기반.** `--source`에 적외선 값(예: "Transparency Adapter Infrared")이나 `--mode`에
  infrared가 노출되는 기기에서만 `supportsInfrared=true`로 감지합니다. 이 경우에만 UI에 **Infrared 토글**이
  나타나고, 켜면 플러그인이 적외선 소스/모드로 스캔합니다(`ScanResult.hasInfraredChannel`).
  - genesys "i" 필름스캐너(7500i/7600i/8200i 등): 적외선 모드/소스를 노출 → IR 가능.
  - OpticFilm 8100 등 비-i 기종: IR 하드웨어 없음 → 토글 미표시.
  - Epson V700/V750/V850(epson2/epkowa): **SANE가 IR 채널을 노출하지 않음** → `supportsInfrared=false`,
    토글 미표시(정확한 동작). TPU/film-type 스캔은 지원.
  - OpticFilm 120/120 Pro/135i: 현재 SANE genesys 지원 목록에 없음 — 사용자의 SANE 빌드가 인식하면
    감지·스캔되지만, SANE가 지원하지 않으면 나타나지 않습니다(하드코딩으로 가짜 지원을 넣지 않음).
- **IR 채널 활용(추후):** IR 스캔 결과는 negaflow의 Software ICE(먼지·스크래치) 검출에 쓰일 수 있으나,
  IR 채널을 자동으로 ICE에 연동하는 것은 후속 과제입니다.

출처: [SANE genesys(8200i·IR 모드)](https://gitlab.com/sane-project/backends) · [sane-epson2(TPU/film-type)](https://manpages.debian.org/trixie/libsane-common/sane-epson2.5.en.html) · [epson2/epkowa IR 미노출(sane-devel)](https://alioth-lists.debian.net/pipermail/sane-devel/2011-January/028119.html)

## 색상 프로필 & 소스별 로더 분기

현상/익스포트의 raw 로딩을 프레임 출처에 따라 분기합니다(`resolveRawInput`).

- `.scannerTIFF`(내장 스캔) → `engine.loadScannerImage`(16bit linear 강제).
- `.importedFile`(가져오기) → `engine.loadImportedImage`(= `ImageLoader.loadImported`), 세부 분기:
  - **카메라 RAW/DNG** → `CIRAWFilter` 데모사이크(제조사 RAW + VueScan/SilverFast raw DNG).
  - **임베디드 ICC 프로필 있음** → 그 프로필로 색관리. **SilverFast HDRi**의 스캐너 디바이스
    프로필(`SFprofT`=투과/포지티브, `SFprofN`=네거티브)과 일반 색관리 이미지(sRGB/AdobeRGB 등)가 여기.
  - **프로필 없는 16bit+** → **linear(gamma 1.0)** 스캐너 raw로 해석. **VueScan raw TIFF**가 여기
    (16bit raw는 gamma 1.0). 이렇게 안 하면 어둡게/틀리게 해석됩니다.
  - 8bit 무프로필 → CGImage 기본 색공간(대개 sRGB).

근거(웹 검증): VueScan raw는 16bit=linear·8bit=gamma2.2, SilverFast HDRi는 linear+스캐너 프로필 임베드.
- SilverFast HDRi RAW — <https://www.silverfast.com/.../hdr-i-raw-data-format-nondestructive-image-archiving/>
- VueScan File Formats — <https://www.hamrick.com/vuescan/html/vuesc24.htm>
- Apple Digital Camera RAW 지원 — <https://support.apple.com/en-us/122870>

> 참고(추후 과제): 발색 튜닝은 스캐너 raw 기준으로 최적화돼 있습니다. 임베디드 프로필/RAW로 색공간은
> 정확히 해석하지만, 소스 특성(감마/색역)이 달라 룩이 완전히 동일하진 않을 수 있습니다.

## 분리된 SANE 플러그인 프로젝트

- 위치: `../negaflow-scanner-sane/` (negaflow git **밖**의 독립 SwiftPM 패키지).
- GitHub: <https://github.com/habinsong/negaflow-scanner-sane>
- 라이센스: **GPL-2.0-or-later** (`LICENSE`).
- 구조: `SANEPluginCore`(SANE 백엔드+모델+TIFF 로더, 테스트 가능 라이브러리) + `negaflow-scanner-sane`
  (JSON/CLI 어댑터 실행파일).
- 설치: `./install.sh` → 릴리스 빌드 후 플러그인 디렉토리에 실행파일 + manifest 복사.
- 요구사항: 런타임에 `scanimage` (`brew install sane-backends`).

## 검증 결과

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (negaflow) — **235 tests, 0 failures**
  (1 skipped, Release 전용 ICE 성능 측정 스킵).
  - 신규 `ScannerKitTests.testDiscoverAndExternalBackendProtocol` — 가짜 플러그인으로 발견 +
    detect/capabilities/scan JSON 매핑 검증.
  - 신규 `ChromabaseTests/ImportedImageLoadTests` — 합성 PNG/16bit TIFF 가져오기 로드+현상,
    제조사 RAW 확장자 분류, **무프로필 16bit→linear(VueScan)**, **임베디드 sRGB 프로필 존중
    (SilverFast/색관리)** 을 수치로 검증(실제 이미지 미사용).
- `bash scripts/run-app.sh build` — **BUILD SUCCEEDED** (xcodebuild, SANE 코드 없이 앱 빌드).
- 플러그인 패키지 — `swift test` **24 SANE tests pass**, `swift build -c release` 성공,
  `negaflow-scanner-sane detect`가 유효 JSON 반환.
- 통합 스모크 — negaflow CLI가 설치된 플러그인을 발견하고 외부 프로세스로 `detect` 호출 →
  `plugin:sane:<id>` 장치가 노출됨(호스트↔플러그인 왕복 확인).

## 남은 리스크

- 앱 GUI는 `scripts/run-app.sh`(xcodebuild)로만 빌드됩니다(SPM CLI 링커의 SwiftUICore 제약 — 기존 제약).
- 플러그인은 컴파일은 scanimage 없이도 되지만, 실제 스캐너 detect/scan은 SANE(`scanimage`) 설치가 필요합니다.
- 가져온 JPG/PNG의 발색 룩은 스캐너 raw 기준 튜닝과 완전히 동일하지 않을 수 있습니다(위 참고).
- GPL 플러그인 배포 시 GNU GPL v2 전문(`COPYING`)을 함께 포함해야 합니다.
