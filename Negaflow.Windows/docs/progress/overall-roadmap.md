# 전체 로드맵과 진행률

기준일: 2026-08-04
기준 로드맵: `windows_docs/99-plan/migration-roadmap.md`의 M0~M18

## 현재 숫자

- 전체 M0~M18 제품 로드맵: **약 14%**
- 기반 구간 M0~M3: **약 45%**
- 제한형 TIFF 사전 검사 세부 작업: **약 94%**

이 수치는 일정이나 개발 시간의 5%가 아닙니다. 각 milestone의 정의된 산출물과 종료 조건을
동일 가중치로 놓고, 현재 확보한 증거의 비율을 보수적으로 추정한 값입니다. UI와 실제 장치 검증이
뒤에 많이 남아 있으므로 작은 기반 코드가 완성됐다는 이유로 전체 진행률을 크게 잡지 않습니다.

## milestone별 상태

| 단계 | 추정 | 현재 증거 | 주요 미완료 |
|---|---:|---|---|
| M0 제품 기준선 | 35% | exact commit, bootstrap manifest, delta, 일부 asset hash | 전체 surface/stage manifest, 권리 결정, 실제 macOS 기준 artifact |
| M1 저장소·빌드·CI | 68% | 별도 build root, x64/ARM64 native·managed·WinUI graph, dual-RID lock, C ABI, CLI, VS 18.8.2와 Windows App SDK C# component, 고정 SDK/vcpkg, static CRT | shader/packaging, CI, 실제 ARM64 run |
| M2 적합성·CPU scalar | 32% | pixel contract, exposure/matrix, 네거티브 반전, 기본 톤·4-band curve, 고정 64표본 DR/R/G/B point curve, 8-band HSL Color Mixer, 3구간 Color Grading, R/G/B Primary Calibration, standalone 11종 RGB33 Film Emulation 색상, fixed Float32 fixture와 bounded percentile 측정 | 전체 kernel inventory, forced dispatch, 공간·통계·결함·변환, 실제 macOS golden |
| M3 이미지 I/O·색·영속성 | 54% | 동일 read-only stream의 bounded TIFF probe+WIC 16-bit decode, TIFF 6 조기 비트폭 LZW 의미 검사와 Deflate 격리, sink 기반 row streaming, ICC row transform→linear working, whole/stream exact parity 15개, 이미지 SHA 기본-off/opt-in CNG, 검증된 PNG16/TIFF16 단일 파일 게시 | 독립 Deflate 검증, ColorSync parity, tile/fuzz, SQLite, catalog transaction·복구 |
| M4 CLI end-to-end | 44% | 한 장 decode→color→수동 Dmin develop→노출·기본 톤·동적 4-band curve→sRGB16 TIFF/PNG 검증 게시, point curve·Color Mixer·Color Grading·Primary Calibration 버전/적용 report 경계, source 관찰, 단계별 byte·memory·wall/process-CPU report, 진단 전용 stage 통계·versioned fingerprint, SHA 기본-off | 고급 color recipe 입력·저장, 실제 macOS runtime pixel diff·cross-platform 허용오차 manifest |
| M5 GPU/WARP | 0% | 문서만 존재 | D3D11/Direct2D/WARP FP32 vertical slice |
| M6 전체 Develop graph | 8% | post-pipeline DR/R/G/B point curve→8-band HSL Color Mixer→3구간 Color Grading→R/G/B Primary Calibration scalar 순서 통합, 다음 film-scan 분기의 11종 RGB33 색상 subcomponent는 standalone 검증 | Film Emulation acutance·source routing, digital film, local·defect 등 전체 stage와 측정 |
| M7 대형 이미지 | 6% | WIC row sink, chunk ICC transform, 단조 progress/cancel, full decoded source 제거와 exact parity | 최종 working streaming, tile, byte reservation, cache, TDR |
| M8 ABI·WinUI shell/canvas | 18% | C ABI와 C# `LibraryImport` bootstrap, 최대화 localized 셸, caption inset, 표시 설정 저장 | handles/events, GPU canvas, lifetime, activation 전체 경로 |
| M9~M14 제품 surface | 2% | Library/Develop/Print/Settings 계층과 empty/disabled 상태 골격 | 실제 catalog, Develop, Defects, Export, Print와 Settings 기능 |
| M15 scanner host | 0% | 문서만 존재 | protocol host와 격리 |
| M16 qualification | 0% | 문서만 존재 | 실제 CPU/GPU/ARM64/display matrix |
| M17 배포·컴플라이언스 | 0% | 설치 선언 초안만 존재 | MSIX/installer, signing, update, SBOM |
| M18 Beta/RC/Stable | 0% | 없음 | release gate 전체 |

계산은 M0 35, M1 68, M2 32, M3 54, M4 44, M6 8, M7 6, M8 18, M9~M14 각각 2, 나머지 0을 19개
milestone의 100점 만점에 대입한 약 14.6%입니다. 표시는 정수 14%이며, 숫자는 구현
증거가 추가될 때만 올립니다.

## 현재 완료된 작은 루프

1. exact macOS 기준선과 Windows 기술 경계를 고정했습니다.
2. x64/ARM64 네이티브 코어, DLL, CLI, 테스트 골격을 만들었습니다.
3. float32 extended-linear 픽셀과 첫 scalar 수치 계약을 실행 가능하게 만들었습니다.
4. TIFF 디코더 전에 실행되는 읽기 전용 구조 검사와 손상 fixture를 만들었습니다.
5. x64 Debug/Release 실행과 ARM64 Debug/Release 교차 빌드를 분리해 검증했습니다.
6. WIC decode와 Windows ICM 색상 경로로 사용자 TIFF 15개를 working float까지 변환했습니다.
7. static CRT로 별도 VC++ Redistributable DLL 의존성을 제거했습니다.
8. .NET 10 Interop이 x64 native DLL을 실제 로드하고 ABI를 검증하며 ARM64 target으로 교차 빌드됩니다.
9. TIFF preflight와 WIC decode가 경로를 재개방하지 않고 같은 read-only `IStream`을 사용합니다.
10. 정상 합성 LZW를 exact sample로 검증하고, 잘린 압축 segment와 decoded-byte 한도 초과를
    pixel buffer 할당 전에 차단합니다.
11. WIC pixel copy를 선택적 행 묶음으로 나누고 묶음 사이 취소, 단조 진행률과 부분 sample 폐기를
    검증했습니다.
12. WIC row sink와 재사용 ICM transform을 연결해 full decoded source와 full-frame ICC intermediate를
    제거하고 사용자 TIFF 15개의 최종 float exact parity를 확인했습니다.
13. 일반 이미지 SHA-256 기본값을 `끔`으로 고정하고, 명시적으로 켠 경우에만 CNG 순차 경로가 동작하도록
    known-answer와 실제 코퍼스로 검증했습니다.
14. TIFF decode→scanner color→수동 Dmin negative inversion을 연결하고 기존 scalar와 exact 일치 및
    추가 full-frame pixel allocation 0을 검증했습니다.
15. Swift 기준 치수와 6개 언어를 사용하는 WinUI 셸을 x64 전체 작업영역에서 실행하고, 오른쪽 Windows
    caption inset, Settings와 일반 이미지 SHA-256 기본 `끔` 상태를 확인했습니다.
16. 현상된 working float를 16-bit sRGB PNG로 encode하고 구조·전체 pixel·ICC를 readback한 뒤 기존
    파일을 덮어쓰지 않고 같은 디렉터리에서 게시하는 CPU 수직 경로를 검증했습니다.
17. 같은 출력 변환·게시 경계를 재사용해 무압축 RGB16 TIFF를 만들고 단일 IFD 최소 metadata,
    전체 pixel·ICC, source 상태 전후와 단계별 CLI report를 검증했습니다.
18. macOS Float32 수식의 노출·기본 톤·4-band curve를 제자리 scalar로 연결하고 fixed fixture, bounded
    동적 percentile 측정과 TIFF16/PNG16 실제 게시를 검증했습니다.
19. 기본 export에 프로세스 전체 CPU 시간을 추가하고, 별도 개발 진단에서 scanner→working, develop,
    tone의 active RGBA32F 통계와 versioned 비암호 fingerprint를 검증했습니다.
20. TIFF 6.0 조기 비트폭 규칙을 따르는 길이 전용 LZW 의미 검사기를 추가해 WIC 전에 손상 code stream과
    압축 입력 작업량을 차단하고, 독립 검증기가 없는 Deflate는 fail-closed로 격리했습니다.
21. macOS post-pipeline의 첫 DR/R/G/B 포인트 커브를 고정 64표본·무할당 scalar로 연결하고, 제어점
    경계·처리 순서·합성 fixture를 x64에서 실행하고 ARM64로 교차 빌드했습니다.
22. 포인트 커브 뒤 8대역 HSL Color Mixer를 고정 배열·무할당 scalar로 연결하고, 회색 보호·원형 hue
    대역·48개 합성 값을 x64에서 실행하고 ARM64로 교차 빌드했습니다.
23. Color Mixer 뒤 shadows/midtones/highlights Color Grading을 준비값 기반·무할당 scalar로 연결하고,
    identity·세 구간·48개 합성 값을 x64에서 실행하고 ARM64로 교차 빌드했습니다.
24. Color Grading 뒤 R/G/B Primary Calibration을 고정 세 대역·무할당 scalar로 연결하고, identity·회색
    gate·48개 합성 값을 x64에서 실행하고 ARM64로 교차 빌드했습니다.
25. 다음 film-scan source 분기의 11종 profile을 5% intensity·caller-owned RGB33 색상 cube로 격리하고,
    11개 node signature와 48개 합성 값을 x64에서 실행하고 ARM64로 교차 빌드했습니다. acutance와 실제
    source routing은 아직 연결하지 않았습니다.

## 다음 완료 조건

가까운 순서대로 다음을 닫습니다.

1. M4 tone, point curve, Color Mixer, Color Grading, Primary Calibration과 Film Emulation 색상 cube의 실제
   macOS runtime golden·pixel diff를 확보합니다. cube 보간·경계와 fractional alpha를 따로 확인합니다.
2. `CIUnsharpMask`의 impulse/edge golden으로 acutance 수치를 고정한 뒤 digital/film source routing을
   연결합니다.
3. 다음 Develop 후처리 단계를 macOS 실행 순서대로 조사·이식합니다.
4. 독립 Deflate 검증기를 구현하거나 dependency gate를 열 근거를 확보하고, WIC 압축 해제 CPU budget과
   deadline을 검증합니다.
5. 같은 ICC patch에 대한 macOS ColorSync golden과 Windows ICM 수치를 비교합니다.
6. 차이가 허용 범위를 넘을 때만 LittleCMS를 dependency gate에 올립니다.
7. 최종 working buffer와 출력을 downstream row/tile 소비자로 넘기고 전체 process budget을 적용합니다.
8. WinUI 셸의 축소 폭·DPI·High Contrast·keyboard matrix를 검증하고 실제 catalog 연결을 시작합니다.

## 진행률을 올리지 않는 항목

- ARM64 cross-compile만 성공하고 실제 ARM64에서 실행하지 않은 경우
- 코덱이 파일을 열었지만 bit depth, ICC, orientation을 검증하지 않은 경우
- UI mockup만 있고 네이티브 수명·오류·키보드 경로가 없는 경우
- 빌드 artifact가 있으나 clean restore와 재현 가능한 lock이 없는 경우
