# Windows판 호환성 매트릭스

기준일: 2026-08-04  
연결 결정: [decision-register.md](decision-register.md)

이 문서는 “지원한다”라는 한 단어가 OS, CPU, GPU, 스캐너, 파일 포맷, UI 기능을 뒤섞지
않도록 제품 지원 범위를 축별로 분해한다. 표의 `지원`은 구현 완료 선언이 아니라 Windows판이
완성되었을 때 만족해야 할 목표 계약이다. 실기 검증 전 항목은 명시적으로 `후보` 또는
`검증 필요`로 남긴다.

## 상태 정의

| 상태 | 의미 |
|---|---|
| 필수 | v1 출시 게이트다. 빠지면 동등한 Windows판으로 보지 않는다 |
| 조건부 | 사용자 수요 또는 스파이크 결과에 따라 v1 범위를 확정한다 |
| 선택 | 없어도 전체 기능은 동작하며, 성능 또는 유통 편의만 개선한다 |
| 제외 | v1에서 의도적으로 제공하지 않는다 |
| 장치 의존 | 앱만으로 보장할 수 없고 드라이버·하드웨어 실측이 필요하다 |

## 운영체제

| 대상 | 상태 | 빌드·실행 계약 | 검증 |
|---|---|---|---|
| Windows 11 24H2, build 26100 | 조건부 API 하한 후보 | x64·ARM64 네이티브. 고객 지원 여부와 분리 | 2026-10-13 Home/Pro 지원 종료 전후 정책을 별도 기록 |
| Stable 시점에 지원 중인 일반 Windows 11 release | 필수 | 최신 안정 SDK로 빌드하되 런타임 API 가드는 승인된 하한에 맞춤 | Insider가 아닌 정식 채널, clean VM과 실제 PC |
| Windows 11 26H1 신형 장치 | 조건부 | 기존 24H2/25H2의 일반 in-place 후속으로 가정하지 않음 | 해당 신형 ARM64/x64 hardware가 지원 범위일 때 |
| Windows 10 22H2 | 제외 후보 | Windows App SDK 자체 최소와 제품 최소는 별개 | 시장 요구 확인 전 테스트 비용을 만들지 않음 |
| Windows Server | 제외 | GUI·색관리·스캐너 사용자 환경을 제품 대상으로 삼지 않음 | CLI CI 호스트로 쓰더라도 제품 지원으로 표기하지 않음 |

Windows App SDK가 기술적으로 Windows 10 version 1809까지 내려간다는 사실은 제품 지원
선언이 아니다. Negaflow는 디스플레이 색 관리, GPU 드라이버, 프린트, 스캐너까지 함께
검증해야 하므로 최소 OS는 별도 제품 결정으로 유지한다. 최소 API OS, CI image, hardware-lab
tested OS, 신규 설치 지원 OS와 기존 설치 grace period를 같은 값으로 뭉치지 않는다.

## CPU와 프로세스 아키텍처

| 실행 대상 | 상태 | 요구사항 | 금지 |
|---|---|---|---|
| Intel x64 | 필수 | scalar + 안전한 기본 ISA + 런타임 AVX2/FMA 경로 | AVX2를 프로세스 전체 최소 ISA로 만들지 않음 |
| AMD x64 | 필수 | Intel과 같은 x64 바이너리·동일 결과 | 벤더 문자열로 알고리즘 선택 금지 |
| Qualcomm 등 ARM64 | 필수 | 순수 ARM64 앱·엔진·CLI·의존성 | x64 에뮬레이션을 출시 성능 기준으로 쓰지 않음 |
| x86 앱 본체 | 제외 | 없음 | 32비트 주소 공간으로 대형 스캔 처리 금지 |
| ARM64EC 앱 본체 | 제외 | in-process x64 DLL이 없으므로 필요 없음 | ARM64EC를 ARM64 지원의 지름길로 사용 금지 |
| x86 스캐너 플러그인 | 장치 의존 | 별도 프로세스, 제한된 계약, 앱 소유 경로 출력 | 본체에 32비트 DLL 로드 금지 |
| x64 스캐너 플러그인 | 장치 의존 | x64 본체·ARM64 Windows의 에뮬레이션에서 각각 검증 | 에뮬레이션 성공을 드라이버 지원 증거로 간주 금지 |
| ARM64 스캐너 플러그인 | 장치 의존 | ARM64 사용자 모드 코드와 ARM64 호환 장치 드라이버 | x86/x64 드라이버를 ARM64 드라이버로 오인 금지 |

### CPU 결과 계약

- scalar 구현이 수치 기준선이다.
- SIMD 경로는 scalar와 동일한 입출력 범위, 경계 처리, NaN/Inf 정책을 갖는다.
- 디스패치는 CPUID·OS context 지원을 함께 확인한다.
- 사용자가 결과 파일을 보았을 때 CPU 모델 때문에 픽셀이나 메타데이터가 달라지면 안 된다.
- 성능 기준은 전원 연결 고성능 데스크톱만이 아니라 ARM64 노트북과 저전력 x64도 포함한다.

## GPU와 그래픽 백엔드

v1 기준선은 `D3D11 feature level 11_0 + Shader Model 5.0 + Direct2D 1.1+`다.

| 어댑터군 | 상태 | 반드시 확인할 것 | 허용되는 차이 |
|---|---|---|---|
| Intel UHD/Iris Xe | 필수 | iGPU 메모리 압박, 공유 메모리, 하이브리드 GPU | 처리 시간·전력만 |
| Intel Arc | 필수 | discrete 메모리, 드라이버 업데이트, HDR/SDR | 처리 시간만 |
| AMD Radeon iGPU | 필수 | UMA 예산, 노트북 절전 상태 | 처리 시간·전력만 |
| AMD Radeon dGPU | 필수 | 장치 제거, 다중 모니터, HDR | 처리 시간만 |
| NVIDIA GeForce/RTX | 필수 | Optimus, 장치 선택, 스튜디오/게임 드라이버 | 처리 시간만 |
| Qualcomm Adreno | 필수 | ARM64 네이티브, WARP 전환, 공유 메모리 | 처리 시간·전력만 |
| Microsoft WARP | 필수 폴백 | 모든 필수 셰이더·포맷·효과 그래프 | 느린 것은 허용, 기능 누락은 불허 |
| 원격 데스크톱·VM GPU | 조건부 | 어댑터가 바뀌는 세션, WARP 재생성 | 가속을 보장하지 않음 |
| CUDA | 선택 후보 | NVIDIA에서 end-to-end 순이득과 동등성 | 기능 차이는 불허 |
| D3D12 tier | 선택 후보 | D3D11 고유 병목이 계측으로 확인될 때 | 기능 차이는 불허 |

### GPU 기능 기준

| 기능 | D3D11/WARP | CPU | CUDA/D3D12 후보 |
|---|---|---|---|
| 포인트와이즈 현상·색 변환 | 필수 | 필수 | 선택 |
| 리사이즈·샘플링 | 필수 | 필수 | 선택 |
| 히스토그램·통계 | 필수 또는 결정적 CPU | 필수 | 선택 |
| 결함 검출·복원 | 단계별 필수 | 필수 | 선택 |
| 캔버스 합성 | 필수 | WARP로 충족 | 해당 없음 |
| export 렌더 | 필수 | 필수 | 선택 |
| print 렌더 | 필수 | 필수 | 선택 |

`필수 또는 결정적 CPU`는 GPU에서 통계를 만들 수 없다는 뜻이 아니다. 벤더별 원자 연산 순서나
부동소수 리덕션 때문에 자동 보정 결과가 허용 오차를 넘으면, 그 작은 측정 단계만 CPU로
고정하고 전체 픽셀 파이프라인은 GPU에 유지한다는 뜻이다.

## 메모리 등급

고정된 “최소 RAM” 숫자는 실측 전 선언하지 않는다. 대신 동작 등급을 정의한다.

| 등급 | 예시 환경 | 필수 동작 |
|---|---|---|
| 제한 | 8GB RAM, UMA GPU | 단일 대형 이미지 편집, 타일 eviction, 저해상도 프리뷰, export 직렬화 |
| 일반 | 16GB RAM, iGPU 또는 4~8GB VRAM | Library·Develop 일반 흐름과 background thumbnail |
| 고성능 | 32GB+ RAM, 8GB+ VRAM | 여러 대형 이미지, 비교·survey, 병렬 export |

모든 등급에서 해상도·JPEG 품질·DPI·ICC 정확도를 자동으로 낮추면 안 된다. 제한 환경에서는
동시성, 캐시, 프리뷰 해상도를 조절하되 최종 export/print 품질은 유지한다.

## 입력 이미지 포맷

현재 macOS 구현의 실제 디코드·메타데이터 계약을 테스트 벡터로 고정한 뒤 Windows 지원을
확정한다. 아래는 목표 분류이며 라이브러리를 이미 채택했다는 뜻이 아니다.

| 포맷군 | 상태 | 기본 후보 | 주요 검증 |
|---|---|---|---|
| TIFF/BigTIFF | 필수 | libtiff + ICC/EXIF 파서 | 8/16-bit, RGB/gray, alpha, orientation, strips/tiles, 압축 |
| JPEG | 필수 | WIC 또는 libjpeg-turbo | ICC 분할 APP2, EXIF orientation, CMYK 거부/변환 정책 |
| PNG | 필수 | WIC | 8/16-bit, embedded ICC, alpha |
| HEIF/HEIC | 조건부 | WIC codec capability | 코덱 설치 유무를 기능으로 오인하지 않음 |
| DNG/카메라 RAW | 필수 parity, 품질 gate | LibRaw 0.22.2+ 후보 | 선택 라이선스, 카메라별 회귀, Apple RAW 대비 WB·색·하이라이트, embedded preview와 원본 구분 |
| 스캐너 산출물 | 필수 | 플러그인이 앱 지정 파일에 기록 | manifest와 실제 파일 hash·크기·pixel contract |

코덱이 OS에 설치되어 있다는 사실만으로 Negaflow가 그 포맷을 지원한다고 표시하지 않는다.
입력 probe, decode, ICC, orientation, bit depth, 오류 복구를 모두 통과한 조합만 지원 목록에 넣는다.

## 출력과 인쇄

| 기능 | 상태 | 품질 계약 |
|---|---|---|
| JPEG export | 필수 | 요청 품질, 색공간, ICC, orientation·메타데이터 정책 보존 |
| PNG export | 필수 | 비손실, bit depth와 alpha 정책 명시 |
| TIFF export | 필수 | 8/16-bit, BigTIFF 전환, 압축, ICC |
| 원본 크기·사용자 크기 | 필수 | resize 알고리즘과 DPI 메타데이터를 분리 |
| Quick Export | 필수 | 일반 export와 동일 렌더·품질 경계 |
| batch export | 필수 | 충돌 없는 이름, 원자적 파일 확정, 취소·재개 가능한 진행 상태 |
| contact sheet | 필수 | 페이지 geometry·ICC·text overlay 동등성 |
| Windows print pipeline | 필수 | 프린터 capability, page ticket, color-management ownership 명시 |
| HDR export | 조건부 | 현재 macOS 기준선에 실제 제품 계약이 있을 때만 |

## 디스플레이와 색 관리

| 환경 | 상태 | 검증 |
|---|---|---|
| SDR 단일 모니터 | 필수 | ICC v2/v4, 100%/125%/150%/200% DPI |
| 서로 다른 ICC의 다중 모니터 | 필수 | 창 이동 중 profile 갱신, 캐시 무효화 |
| SDR + HDR 혼합 | 조건부 필수 후보 | Advanced Color 상태 변경, scRGB/SDR white level |
| 원격 데스크톱 | 조건부 | profile·adapter 변경 후 안전 폴백 |
| 사용자 지정 프린터 ICC | 필수 | soft proof와 실제 출력 transform 분리 |

색관리 정확성은 모니터 모델명 추정으로 주장하지 않는다. 실제 ICC, 렌더링 의도, black-point
정책과 출력 측정을 기록한다. 측정하지 않은 프린터·용지를 “정확”하다고 표시하지 않는다.

## 스캐너 플러그인

| 경로 | 상태 | 라이선스·프로세스 경계 | 장치 지원 선언 |
|---|---|---|---|
| TWAIN DSM 64-bit | 우선 후보 | 별도 플러그인 프로세스 | 실제 data source + 장치 매트릭스 통과 시 |
| TWAIN DSM 32-bit | 조건부 | x86 플러그인 프로세스만 | 실제 32-bit data source 검증 시 |
| WIA | 후보 | 별도 플러그인 프로세스 | 해당 장치 capability와 필름 기능 실측 시 |
| 벤더 SDK | 조건부 | 플러그인별 라이선스 검토 | 재배포권·비트니스·장치 실측 시 |
| SANE | 조건부 별도 배포 | GPL 플러그인 프로세스·별도 저장소 | backend 공식 목록 + 실제 enumerate/scan 증거 |
| demo/mock | 개발 전용 | 명시적 opt-in | 실제 하드웨어 지원으로 표시 금지 |

USB 장치가 보이는 것, 드라이버가 설치된 것, 플러그인이 enumerate하는 것, 요청 ROI가 실제로
적용된 것은 각각 다른 증거다. 지원 표에는 마지막 단계까지 통과한 조합만 올린다.

## UI/UX 기능 등급

UI 99.9% 동등성은 픽셀 단위 복제가 아니라 같은 제품 상태와 결과에 도달하는 네이티브 Windows
경험을 뜻한다.

| 표면 | 상태 | 동등성 범위 |
|---|---|---|
| Library grid/compare/survey | 필수 | 선택, 정렬, 폴더, 검색, 가상 copy, empty/error/recovery |
| Develop | 필수 | 모든 조정, 자동 보정 opt-in, undo/redo, version, before/after |
| Canvas | 필수 | zoom/pan/fit, crop·mask·overlay, color-managed render |
| Defects | 필수 | recipe, brush/selection, 자동 검출, 비파괴 cache |
| Scan | 필수 인터페이스 | capability-driven UI, preview, job 상태, manifest |
| Export | 필수 | 일반/Quick Export, preset, naming, progress, cancel, 오류 |
| Print | 필수 | single/contact sheet, layout, printer/page setup, output |
| Settings | 필수 | 8개 탭, persistence, reset·validation, shortcuts |
| Help/legal/recovery | 필수 | 오프라인 도움, 라이선스, catalog·source recovery |

세부 acceptance는 [../08-ui/parity-contract.md](../08-ui/parity-contract.md)에서 관리한다.

## 언어·접근성·입력

| 항목 | 상태 | 계약 |
|---|---|---|
| 시스템 언어 | 필수 | 첫 실행 기본, 명시적 앱 언어 우선 |
| English, 한국어, 日本語, 简体中文, Français, Deutsch | 필수 | 현재 macOS 지원 언어와 키·placeholder 동등성 |
| 키보드 | 필수 | 전체 기능 탐색, Windows modifier로 자연스럽게 재매핑 |
| 마우스·정밀 터치패드 | 필수 | zoom/pan/selection/scroll |
| 터치 | 조건부 | 데스크톱 기능을 깨뜨리지 않는 기본 조작 |
| Narrator·UI Automation | 필수 | 이름·역할·상태·값·관계·live region |
| 고대비·텍스트 배율 | 필수 | 시스템 테마와 200% 텍스트에서 기능 손실 없음 |
| RTL | 조건부 | 현재 지원 언어에는 없으나 레이아웃 파손 방지 |

## 지원 선언에 필요한 증거

다음 중 하나라도 빠지면 표의 `필수`는 아직 구현 목표일 뿐 출시 지원이 아니다.

1. 해당 아키텍처의 Release 설치·실행·제거 결과
2. 실제 픽셀 골든과 허용 오차 보고서
3. 실제 GPU 또는 WARP 장치 정보와 드라이버 버전
4. 최소·일반·고성능 데이터셋 성능 결과
5. UI surface별 상태 전이·접근성 자동화와 수동 QA
6. 스캐너는 장치·드라이버·plugin build·requested/applied ROI 증거
7. export/print는 산출물 hash가 아니라 decoded-pixel·ICC·metadata 검증
8. 실패·취소·재시작·device removal·저장공간 부족 경로

## 공식 참고

- [Windows App SDK release channels](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-channels)
- [Windows App SDK deployment overview](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/deploy-overview)
- [Add Arm support to your Windows app](https://learn.microsoft.com/en-us/windows/arm/add-arm-support)
- [Windows on Arm FAQ](https://learn.microsoft.com/en-us/windows/arm/faq)
- [Direct3D hardware feature levels](https://learn.microsoft.com/en-us/windows/win32/direct3d12/hardware-feature-levels)
- [WARP device](https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-devices-create-warp)
