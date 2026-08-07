# 전체 로드맵과 진행률

기준일: 2026-08-07
기준 로드맵: `windows_docs/99-plan/migration-roadmap.md`의 M0~M18

## 현재 숫자

- 전체 M0~M18 제품 로드맵: **약 20%**
- 기반 구간 M0~M3: **약 52%**
- 제한형 TIFF 사전 검사 세부 작업: **약 94%**

이 수치는 일정이나 개발 시간의 5%가 아닙니다. 각 milestone의 정의된 산출물과 종료 조건을
동일 가중치로 놓고, 현재 확보한 증거의 비율을 보수적으로 추정한 값입니다. UI와 실제 장치 검증이
뒤에 많이 남아 있으므로 작은 기반 코드가 완성됐다는 이유로 전체 진행률을 크게 잡지 않습니다.

## milestone별 상태

| 단계 | 추정 | 현재 증거 | 주요 미완료 |
|---|---:|---|---|
| M0 제품 기준선 | 35% | exact commit, bootstrap manifest, delta, 일부 asset hash, canonical Film Emulation Core Image artifact | 전체 surface/stage manifest, 권리 결정, 나머지 macOS 기준 artifact |
| M1 저장소·빌드·CI | 68% | 별도 build root, x64/ARM64 native·managed·WinUI graph, dual-RID lock, C ABI, CLI, VS 18.8.2와 Windows App SDK C# component, 고정 SDK/vcpkg, static CRT | shader/packaging, CI, 실제 ARM64 run |
| M2 적합성·CPU scalar | 35% | pixel contract, exposure/matrix, 네거티브 반전, 기본 톤·4-band curve, 고정 64표본 DR/R/G/B point curve, 8-band HSL Color Mixer, 3구간 Color Grading, R/G/B Primary Calibration, 11종 RGB33 Film Emulation 색상→11행 acutance route, macOS golden과 bounded percentile 측정 | 전체 kernel inventory, forced dispatch, 나머지 공간·통계·결함·변환 golden |
| M3 이미지 I/O·색·영속성 | 70% | 동일 read-only stream의 bounded TIFF probe+WIC 16-bit decode, TIFF 6 조기 비트폭 LZW 의미 검사와 Deflate 격리, sink 기반 row streaming, ICC row transform→linear working, whole/stream exact parity 15개, 이미지 SHA 기본-off/opt-in CNG, 검증된 PNG16/TIFF16 게시, transport/signal과 legacy 강도를 보존하는 catalog route projection , SQLite 영속성·단일 작성자 세션·5만 frame 성능 | 독립 Deflate 검증, tile/fuzz, backup 세대·pending restore·defect sidecar |
| M4 CLI end-to-end | 72% | 한 장 decode→color→수동 Dmin develop→tone·Primary Calibration→명시적 film-scan Film Look→sRGB16 TIFF/PNG 검증 게시, 실제 identity/활성 TIFF 차이, macOS golden·cross-platform envelope, source 관찰, 단계별 report, SHA 기본-off, source/profile/intensity catalog projection , 실제 DB 저장과 projection→C ABI 연결 | 고급 color recipe 전체 입력, 나머지 runtime pixel diff manifest |
| M5 GPU/WARP | 0% | 문서만 존재 | D3D11/Direct2D/WARP FP32 vertical slice |
| M6 전체 Develop graph | 18% | post-pipeline DR/R/G/B point curve→8-band HSL Color Mixer→3구간 Color Grading→R/G/B Primary Calibration→명시적 film-scan 11종 RGB33 색상→bounded acutance 순서를 CLI 출력까지 통합, source/profile/intensity recipe projection | 실제 DB 저장·재로드와 render snapshot 연결, digital film 전체 그래프, local·defect 등 전체 stage와 측정 |
| M7 대형 이미지 | 6% | WIC row sink, chunk ICC transform, 단조 progress/cancel, full decoded source 제거와 exact parity | 최종 working streaming, tile, byte reservation, cache, TDR |
| M8 ABI·WinUI shell/canvas | 45% | C ABI가 develop/export/preview/limits를 운반, 셸 시작 시 catalog open, 시험되는 스레딩 정책, 최대화 localized 셸 | GPU canvas, handles/events, lifetime·activation 전체 경로 |
| M9~M14 제품 surface | 8% | Library 목록, 파일 picker import, Develop의 필름 base·노출, Export가 실제 동작 | 미리보기 렌더, base picker, 취소·진행률, Defects, Print, Settings 기능 |
| M15 scanner host | 0% | 문서만 존재 | protocol host와 격리 |
| M16 qualification | 0% | 문서만 존재 | 실제 CPU/GPU/ARM64/display matrix |
| M17 배포·컴플라이언스 | 0% | 설치 선언 초안만 존재 | MSIX/installer, signing, update, SBOM |
| M18 Beta/RC/Stable | 0% | 없음 | release gate 전체 |

계산은 M0 35, M1 68, M2 35, M3 70, M4 72, M6 18, M7 6, M8 45, M9~M14 각각 8, 나머지 0을 19개
milestone의 100점 만점에 대입한 약 20.9%입니다. 표시는 보수적으로 정수 20%이며, 숫자는 구현
증거가 추가될 때만 올립니다.

2026-08-07 에 올라간 것과 그 근거:

- **M3 56 → 70.** SQLite 영속성, 단일 작성자 세션, 5만 frame 성능 측정.
  `verification/2026-08-07-sqlite-catalog-store.md`. 남은 것은 backup 세대·pending restore·
  defect sidecar·독립 Deflate 검증·tile/fuzz 입니다.
- **M4 50 → 72.** projection 이 실제 DB 에 저장되고 C ABI 로 연결됐습니다. 남은 것은 고급
  color recipe 전체 입력과 runtime pixel diff manifest 입니다.
- **M6 14 → 18.** 실제 DB 저장·재로드가 붙었습니다. digital film 전체 그래프와 나머지 stage 는
  그대로 남아 있습니다.
- **M8 18 → 45.** C ABI 가 develop/export/preview/limits 를 실어 나르고, 셸이 시작할 때
  카탈로그를 열며, 스레딩 정책이 시험됩니다. GPU canvas 와 전체 lifetime/activation 은 미착수.
- **M9~M14 2 → 8.** Library 목록, import, Develop 의 필름 base·노출, Export 가 실제로 돕니다.
  `verification/2026-08-07-vertical-slice.md`. 나머지 제품 표면은 그대로입니다.

M5(GPU), M15(scanner host), M16(qualification), M17(배포·서명), M18(release gate)은 **여전히
0%** 입니다. 남은 80% 의 대부분이 여기와 M9~M14 에 있고, 이쪽이 검증이 어렵고 되돌리기 비싼
구간입니다.

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
26. 두 macOS hosted run에서 12,912개 Film Emulation numeric value의 exact 반복성을 확인하고 canonical
    Core Image artifact를 고정했습니다. 색상 platform envelope와 11행 caller-owned scratch의 acutance를
    분리 구현해 x64 Debug/Release 32/32, ARM64 Debug/Release 교차 빌드로 검증했습니다.
27. source 종류를 추정하지 않는 native Film Look route를 만들고 film scan의 RGB33 색상→acutance 순서를
    수동 호출과 bit-exact로 비교했습니다. cube 재사용, 낮은 강도, identity, 부족한 workspace 조기 거부와
    미완성 digital graph의 fail-closed를 검증해 x64 Debug/Release 33/33과 ARM64 전체 교차 빌드를 통과했습니다.
28. 명시적 source/profile/intensity CLI parsing과 bounded workspace 소유를 분리하고, 진단·PNG16·TIFF16에서
    Primary Calibration 뒤 Film Look을 실행했습니다. 같은 tone의 identity/활성 TIFF가 달라지는지, report 단계
    순서, I/O 전 digital-source 거부와 SHA 기본-off를 검증해 x64 Debug/Release 37/37과 ARM64 전체 교차
    빌드를 통과했습니다.
29. catalog의 `scanner`/`imported` transport와 film/digital signal을 분리하고, legacy marker와 missing
    intensity `1.0`, 새 기본 `0.5`를 고정한 관리 코드 projection을 만들었습니다. unknown field 보존,
    invalid 조합 fail-closed와 12개 profile round trip을 x64 Debug/Release 각각 163 assertion으로 실행하고
    ARM64 Debug/Release managed solution을 교차 빌드했습니다.

## 다음 완료 조건

가까운 순서대로 다음을 닫습니다.

1. 새 catalog route projection을 import frame 작성자, 실제 SQLite payload와 C ABI render snapshot에
   연결하고, 앱 restart 뒤에도 source 종류와 stage 순서가 바뀌지 않는지 검증합니다.
2. cube 경계·fractional alpha golden을 확대하고 caller-owned cube/scratch cache·취소 계약을 고정합니다.
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
