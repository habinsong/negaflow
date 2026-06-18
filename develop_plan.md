아래 계획서는 Negaflow 앱 / Chromabase 색감 엔진 기준으로 바로 프로젝트 문서에 넣을 수 있게 길게 잡았습니다.

먼저 조사 근거를 짧게 정리하면 이렇습니다. Apple의 ImageCaptureCore는 연결된 카메라와 스캐너를 발견하고, 스캐너에서 overview scan과 scan을 수행할 수 있는 macOS 프레임워크입니다. ICScannerDevice는 스캐너 객체이고, Apple 문서에서는 복잡한 스캔 파라미터와 저장 처리를 감싸는 ICScannerDeviceView 사용도 안내합니다.   Plustek OpticFilm 8100은 35mm 필름/슬라이드 전용, 7200dpi급 스캐너로 공식 설명되어 있고, SANE 지원 목록에는 OpticFilm 8100이 Complete 상태로 900/1800/3600/7200dpi 지원으로 올라와 있습니다.   8200i 계열은 Plustek 공식 설명상 내장 적외선 채널, 7200dpi, 48bit output, HDRi RAW 쪽 설명이 있고, HDRi는 적외선 채널을 포함한 64bit color HDRi 또는 32bit grey HDRi로 설명됩니다.   8300i SE는 Plustek 지원 페이지에 macOS 설치 파일과 2025-12-19 날짜의 설치 정보가 보이므로 최신 macOS 쪽 지원 흐름이 이어지는 모델로 보는 게 타당합니다.   또한 VueScan 쪽은 8300i가 Windows/macOS 호환이지만 macOS/Windows에서는 Plustek 드라이버 설치가 필요하다고 설명합니다. 이는 Negaflow가 macOS에서 “완전 독립 USB 드라이버”가 아니라, 현실적으로 Apple/Plustek/SANE 계층을 활용하는 단일 앱으로 가야 함을 보여줍니다.  

Negaflow 개발 계획서

0. 문서 개요

프로젝트명

Negaflow

색감 엔진명

Chromabase

플랫폼

macOS 단독 지원

핵심 장비

Plustek OpticFilm 계열 필름 스캐너

1차 검증 장비

Plustek OpticFilm 8200i

호환 목표 장비

Plustek OpticFilm 8100
Plustek OpticFilm 8200i
Plustek OpticFilm 8300i
기타 OpticFilm 구형 모델은 Experimental로 분리

⸻

1. 프로젝트 정의

Negaflow는 Plustek OpticFilm 계열 필름 스캐너를 macOS에서 직접 제어하고, 프리뷰 스캔부터 본스캔, 네거티브 반전, 현대식 색감 시뮬레이션, JPEG/TIFF 출력까지 하나의 앱에서 끝내는 macOS 네이티브 필름 스캔/현상 프로그램이다.

기존 필름 스캔 프로그램은 기능이 많지만 복잡하고 오래된 워크플로에 가깝다. Negaflow는 필름 스캔을 “스캐너 유틸리티”가 아니라 “현대식 디지털 현상실”로 재해석한다.

핵심 가치는 다음과 같다.

1. Plustek OpticFilm 직접 제어
2. macOS 네이티브 UX
3. 스캔과 색현상을 한 앱에서 통합
4. 네거티브 필름의 오렌지 마스크 제거와 안정적인 반전
5. 현대 카메라 JPEG 시뮬레이션에 가까운 즉시 사용 가능한 색감
6. 복잡한 SilverFast/VueScan식 설정 축소
7. 필름 긱에게는 충분한 제어권, 일반 사용자에게는 단순한 결과물 제공

⸻

2. 제품 한 줄 정의

Negaflow is a macOS-native film scanning and developing app for Plustek OpticFilm scanners, powered by the Chromabase color engine.

한국어 정의:

Negaflow는 Plustek OpticFilm 스캐너를 직접 제어하고, 네거티브 반전부터 현대적인 필름 룩 출력까지 한 앱에서 끝내는 macOS 네이티브 필름 스캔/현상 앱이다.

⸻

3. 왜 필요한가

3.1 기존 프로그램의 문제

SilverFast

장점:

* Plustek 번들 스캔 워크플로에서 사실상 표준에 가까움
* HDRi, iSRD, Multi-Exposure, IT8 등 고급 기능 존재
* 필름 스캐너 제어 측면에서 강함

문제:

* UI/UX가 현대 macOS 앱답지 않음
* 설정 항목이 많고 초보자가 접근하기 어려움
* 스캔 이후 색감이 바로 “요즘 JPEG”처럼 나오지 않음
* 사용자가 원하는 룩을 얻으려면 반복 튜닝이 필요함

VueScan

장점:

* 스캐너 호환성이 넓음
* 오래된 장비를 살리는 데 강함
* 실용적이고 안정적인 편

문제:

* UI가 도구 중심이고 현대적인 현상 앱 느낌이 약함
* 색감이 사용자의 최종 룩으로 바로 이어지기 어려움
* “필름 스캔 → 현대식 JPEG 출력”이라는 감성적 목표와 거리가 있음

Negative Lab Pro

장점:

* 네거티브 색변환 품질과 워크플로가 강함
* 카메라 스캔 사용자에게 인기가 있음

문제:

* Lightroom 의존성이 있음
* Plustek 직접 제어 앱이 아님
* 스캔부터 출력까지 단일 앱으로 끝나지 않음

3.2 Negaflow의 포지션

Negaflow는 다음 시장 틈새를 겨냥한다.

* Plustek OpticFilm을 이미 가지고 있음
* SilverFast/VueScan은 너무 올드하거나 복잡하다고 느낌
* Lightroom 기반 워크플로는 무겁다고 느낌
* 필름을 스캔한 뒤 바로 쓸 수 있는 예쁜 색감을 원함
* macOS 네이티브 앱다운 정돈된 UI를 원함
* 필름 보정의 핵심은 알고 있지만, 매번 수동으로 색을 맞추기는 귀찮음

즉, Negaflow는 “스캐너 프로그램”이라기보다 “Plustek 전용 현대식 필름 현상실”에 가깝다.

⸻

4. 제품 철학

4.1 오래된 복원이 아니라 현대적인 현상

Negaflow는 오래된 필름을 복원하는 앱이 아니다.
Negaflow는 오늘 촬영한 필름을 오늘의 디지털 감각으로 완성하는 앱이다.

핵심 문장:

“Scan film. Shape color. Export clean.”

4.2 복잡한 기능보다 좋은 기본값

스캐너 앱은 보통 기능이 많아질수록 사용성이 떨어진다. Negaflow는 반대로 간다.

기본값은 매우 강하게 잡는다.

* 3600dpi 기본
* 16bit RGB 기본
* Color Negative 기본
* Auto Base 기본
* Neutral 기본 룩
* JPEG 95% 기본 출력
* 원본 Raw TIFF 자동 보관 옵션

4.3 사용자는 SANE, TWAIN, ICA를 몰라도 된다

내부적으로 어떤 백엔드를 사용하든 사용자는 보지 않는다.

사용자는 다음만 본다.

* Scanner detected
* Preview
* Scan
* Develop
* Export

내부 엔진은 추상화한다.

⸻

5. 지원 모델 정책

5.1 지원 등급

Verified

실제 개발자가 직접 테스트한 모델.

초기 Verified 모델:

* Plustek OpticFilm 8200i

Compatible Target

공식 드라이버, macOS 지원, 유사 계열, 기존 백엔드 지원 정보를 기반으로 호환 목표에 넣지만, 개발자가 직접 검증하지 않은 모델.

초기 Compatible Target:

* Plustek OpticFilm 8100
* Plustek OpticFilm 8300i

Experimental

장치 감지와 일부 기능은 가능할 수 있으나 기능 보장을 하지 않는 모델.

예상 Experimental:

* OpticFilm 7200i
* OpticFilm 7300
* OpticFilm 7400
* OpticFilm 7500i
* OpticFilm 7600i
* OpticFilm 9000i

5.2 모델별 기능 가정

OpticFilm 8100

* RGB 스캔 가능 목표
* 7200dpi 가능 목표
* 16bit RGB 가능 목표
* IR 채널 없음
* 먼지 제거는 소프트웨어 기반만 가능

OpticFilm 8200i

* 1차 기준 모델
* RGB 스캔
* 16bit RGB
* 7200dpi
* IR 채널 실험
* 2차에서 IR 기반 먼지 제거 가능

OpticFilm 8300i

* Compatible Target
* RGB 스캔 가능 목표
* IR 채널 가능 목표
* 8200i와 유사한 UX 제공 목표
* 실제 지원 여부는 사용자 리포트와 장치 Capability 감지로 확정

5.3 지원 방식

모델명을 하드코딩해서 기능을 강제로 켜지 않는다.

나쁜 방식:

if model == “8200i” then enable IR

좋은 방식:

장치 Capability를 읽는다.
IR 모드가 있으면 IR 기능을 표시한다.
16bit depth가 있으면 16bit 옵션을 표시한다.
7200dpi가 있으면 7200dpi를 표시한다.
Transparency unit이 있으면 Film Scan을 활성화한다.

이 방식이어야 8300i와 구형 모델을 확장할 수 있다.

⸻

6. 기술 전략

6.1 전체 구조

Negaflow는 겉으로는 하나의 macOS 앱이지만 내부는 다음 계층으로 나뉜다.

1. macOS Native App
2. ScannerKit
3. Scanner Backend
4. Scan Buffer
5. Chromabase Color Engine
6. Look System
7. Export Engine
8. Library / Session System
9. Diagnostics / Report System

구조:

Negaflow.app
→ SwiftUI / AppKit UI
→ ScannerKit
→ ImageCaptureCore Backend
→ SANE Backend
→ Mock Backend
→ Raw Scan Buffer
→ Chromabase
→ Export Engine

6.2 Primary Backend: ImageCaptureCore

macOS 단독 앱이므로 1순위는 Apple의 ImageCaptureCore다.

목표:

* macOS 기본 프레임워크로 스캐너 감지
* ICDeviceBrowser로 장치 검색
* ICScannerDevice로 스캐너 접근
* Overview scan 실행
* 본스캔 실행
* 스캔 결과 파일 또는 이미지 버퍼 획득
* 가능한 경우 해상도, 영역, 컬러 모드 제어

장점:

* macOS 네이티브
* Swift/AppKit 연동이 자연스러움
* 사용자 설치 부담이 적음
* Apple 생태계에 맞는 구조

위험:

* 필름 스캐너의 세부 옵션을 충분히 열어주지 않을 수 있음
* 16bit RGB 획득이 제한될 수 있음
* IR 채널 접근이 어려울 수 있음
* Plustek 드라이버 상태에 의존할 수 있음

따라서 ImageCaptureCore는 반드시 실제 8200i로 검증해야 한다.

6.3 Fallback Backend: SANE / scanimage

ImageCaptureCore로 원하는 수준의 직접 제어가 안 될 경우 SANE 기반 fallback을 사용한다.

SANE는 사용자가 보는 기능이 아니라 앱 내부 스캐너 제어 엔진이다.

초기 구현은 SANE 라이브러리 FFI가 아니라 scanimage CLI wrapper로 시작한다.

이유:

* vibe coding에 적합
* 빠르게 장치 인식과 스캔 테스트 가능
* scanimage -L로 장치 감지 가능
* scanimage -A로 장치 옵션 덤프 가능
* 기능 검증 후 나중에 라이브러리 직접 연동으로 바꿀 수 있음

초기 명령 흐름:

scanimage -L
scanimage -A -d 
scanimage –resolution 3600 –mode Color –depth 16 –format=tiff > scan.tiff

실제 옵션명은 장치와 백엔드에 따라 다르므로 Negaflow는 SANE 옵션을 직접 고정하지 않고 Capability Parser를 둔다.

6.4 Future Backend: TWAIN / ICA Bridge

TWAIN은 장기적으로 고려한다.

다만 macOS 단독 MVP에서는 우선순위를 낮춘다.

이유:

* 제조사 UI가 튀어나올 수 있음
* Negaflow 자체 UI 흐름이 깨질 수 있음
* 16bit/IR/투과 유닛 제어가 제한될 수 있음
* macOS에서는 ImageCaptureCore와 SANE 검증이 우선

TWAIN은 Windows 확장 또는 제조사 드라이버 의존 fallback을 고려할 때 다시 검토한다.

⸻

7. ScannerKit 설계

7.1 역할

ScannerKit은 스캐너 제어 추상화 계층이다.

UI는 ImageCaptureCore인지 SANE인지 몰라야 한다.
UI는 ScannerKit에게만 요청한다.

ScannerKit의 핵심 API:

* detectScanners()
* connect(scannerID)
* disconnect()
* getCapabilities(scannerID)
* startPreviewScan(options)
* startFullScan(options)
* cancelScan()
* getScanProgress()
* getLastError()
* exportScannerReport()

7.2 ScannerDescriptor

스캐너 정보 모델:

* id
* displayName
* vendor
* model
* backendType
* connectionType
* usbVendorID
* usbProductID
* serialNumber
* verifiedStatus
* firmwareVersion
* driverVersion

예시:

ScannerDescriptor
id: plustek-8200i-usb-001
displayName: Plustek OpticFilm 8200i
vendor: Plustek
model: OpticFilm 8200i
backendType: ImageCaptureCore
connectionType: USB
verifiedStatus: Verified

7.3 ScannerCapabilities

장치가 지원하는 기능:

* supportedResolutions
* supportedModes
* supportedBitDepths
* supportsPreview
* supportsTransparency
* supportsInfrared
* supportsMultiExposure
* supportsScanArea
* supportsLampWarmupStatus
* maxScanArea
* minScanArea
* scanAreaUnit
* outputFormats
* estimatedScanSpeeds

예시:

supportedResolutions: 900, 1800, 3600, 7200
supportedModes: Color, Gray, Lineart, Infrared
supportedBitDepths: 8, 16
supportsInfrared: true
supportsTransparency: true
supportsScanArea: true

7.4 ScanOptions

스캔 요청 모델:

* scannerID
* resolution
* bitDepth
* colorMode
* filmType
* scanArea
* infraredEnabled
* multiExposureEnabled
* outputRawTIFF
* temporaryOutputURL

filmType:

* Color Negative
* Color Positive
* Black & White Negative
* Black & White Positive

resolution:

* Preview
* 900
* 1800
* 3600
* 7200

7.5 ScanResult

스캔 결과:

* rawFileURL
* previewImage
* width
* height
* resolution
* bitDepth
* colorSpace
* hasInfraredChannel
* infraredFileURL
* scanDuration
* backendUsed
* warnings

⸻

8. Chromabase 색감 엔진 설계

8.1 Chromabase의 역할

Chromabase는 Negaflow의 핵심 가치다.

스캐너 제어가 성공해도 색감이 별로면 Negaflow는 실패한다.
Chromabase는 필름 스캔 원본을 현대적인 결과물로 바꾸는 색현상 엔진이다.

주요 기능:

* 16bit linear scan input 처리
* Film base color estimation
* Orange mask removal
* Negative inversion
* Auto exposure
* Auto white balance
* Density mapping
* Highlight roll-off
* Shadow shaping
* Color separation
* Look preset 적용
* Grain / sharpness / halation
* JPEG/TIFF export용 출력 변환

8.2 입력

초기 입력 포맷:

* 16bit RGB TIFF
* 8bit RGB TIFF
* PNG/JPEG 테스트 입력
* 향후 DNG/RAW 확장
* 향후 RGBi 64bit 입력

8.3 내부 처리 색공간

MVP에서는 복잡한 ICC 관리보다 안정적인 내부 파이프라인을 우선한다.

초기 권장:

* 입력: scanner RGB 또는 untagged RGB
* 내부 처리: linear floating point RGB
* 작업 범위: 32bit float
* 표시: Display P3 또는 sRGB preview
* 출력: sRGB JPEG, 16bit TIFF 옵션

장기적으로:

* scanner profile
* IT8 calibration profile
* ICC-based transform
* Display P3 export
* ProPhoto-like wide gamut internal processing

8.4 컬러 네거티브 처리 순서

컬러 네거티브 파이프라인:

1. Load Scan
2. Normalize 16bit input
3. Detect border / film base candidate
4. Estimate film base color
5. Remove orange mask
6. Invert density
7. Channel balance
8. Auto exposure
9. Black / white point soft clipping
10. Density curve
11. Highlight roll-off
12. Color matrix / LUT
13. Look preset
14. Grain / sharpening / optional halation
15. Output transform
16. Export

8.5 Film Base Estimation

네거티브 반전의 핵심은 필름 베이스 추정이다.

자동 방식:

* 프리뷰 이미지 가장자리에서 프레임 밖 필름 베이스 후보 탐색
* 사용자 crop 바깥 영역에서 orange mask 샘플링
* 너무 어둡거나 너무 밝은 영역 제외
* RGB 채널 중앙값 기반 추정
* 이상치 제거

수동 방식:

* 사용자가 film base 영역을 스포이드로 클릭
* 해당 지점 주변 n x n 픽셀 평균
* Manual Base로 저장

UI:

Base

* Auto
* Pick Border
* Pick Base
* Reset

8.6 Negative Inversion

단순 1 - RGB 반전은 금지한다.

권장 접근:

* 스캔 값은 투과광 기준이므로 density-like transform을 고려
* 채널별 film base normalization
* 로그 또는 감마 보정 기반 반전 테스트
* inversion 이후 채널 균형 조정
* 하이라이트와 섀도우 클리핑을 부드럽게 처리

초기 MVP에서는 다음 2개 알고리즘을 비교한다.

Algorithm A: Simple normalized invert
Algorithm B: Density-based invert

사용자가 보기에 좋은 쪽을 기본값으로 채택한다.

8.7 Tone Model

Chromabase의 룩은 단순 대비/채도 프리셋이 아니다.
필름 스캔에서 중요한 것은 density, roll-off, black softness다.

톤 파라미터:

* Exposure
* Density
* Contrast
* Highlight Roll-off
* Black Softness
* Midtone Lift
* Shadow Weight
* White Point
* Black Point

기본 UI에는 다음만 노출한다.

* Exposure
* Density
* Highlight
* Shadow

고급 UI에는 다음을 추가한다.

* Highlight Roll-off
* Black Softness
* Midtone
* White Point
* Black Point

8.8 Color Model

색 파라미터:

* Temperature
* Tint
* Color Depth
* Saturation
* Channel Balance
* Skin Bias
* Cyan/Red Separation
* Green/Magenta Correction
* Blue/Yellow Balance

기본 UI:

* Warmth
* Tint
* Color Depth

고급 UI:

* Red Balance
* Green Balance
* Blue Balance
* Cyan Control
* Skin Bias

8.9 Look Preset System

초기 프리셋:

1. Neutral
2. Rich Neutral
3. Soft Print
4. Clear Chrome
5. Warm Lab
6. Deep Slide

Neutral

목표:

* 기록성
* 정확한 색
* 과한 대비 없음
* 다른 보정을 위한 기본 출발점

특성:

* 낮은 색 왜곡
* 부드러운 톤 커브
* 약한 sharpening
* grain off 기본

Rich Neutral

목표:

* 사용자가 말한 “쫀득쫀득”
* 중간톤 밀도
* 과하지 않은 색 농도
* 필름 인화 느낌

특성:

* Density 증가
* Color Depth 증가
* Black Softness 유지
* Highlight Roll-off 부드럽게
* Warmth 약간

Soft Print

목표:

* Portra 계열 인화 느낌에 가까운 부드러운 톤
* 인물/일상 스냅에 적합

특성:

* 낮은 대비
* 부드러운 하이라이트
* 채도 절제
* 피부톤 보호
* 입자 약하게

Clear Chrome

목표:

* Classic Chrome류의 낮은 채도, 선명한 중간톤
* 도시/여행/스냅에 적합

특성:

* 채도 낮춤
* 블루/그린 정리
* 미드톤 대비 증가
* 블랙은 너무 막지 않음

Warm Lab

목표:

* 일본 현상소 JPEG 느낌
* 따뜻하고 부드러운 기본 출력

특성:

* Warmth 증가
* Highlight roll-off
* Shadow soft
* Color Depth 중간

Deep Slide

목표:

* 슬라이드 필름 느낌의 높은 밀도와 선명한 색
* 풍경/간판/야간 빛에 적합

특성:

* Contrast 증가
* Color Depth 증가
* Black 깊게
* Highlight 보호
* Grain 낮음

8.10 Preset File Format

프리셋은 JSON 기반으로 저장한다.

예시:

{
“name”: “Rich Neutral”,
“version”: 1,
“filmTypes”: [“color_negative”],
“tone”: {
“exposure”: 0.0,
“density”: 0.22,
“contrast”: 0.12,
“highlightRollOff”: 0.35,
“blackSoftness”: 0.18
},
“color”: {
“warmth”: 0.05,
“tint”: 0.0,
“colorDepth”: 0.18,
“saturation”: 0.06
},
“texture”: {
“grain”: 0.08,
“sharpness”: 0.12,
“halation”: 0.03
}
}

8.11 Non-destructive Editing

Negaflow는 스캔 원본을 보존한다.

각 프레임마다 sidecar JSON을 저장한다.

sidecar 내용:

* scanner model
* backend used
* scan resolution
* bit depth
* film type
* crop
* base sample
* Chromabase preset
* manual adjustments
* export history
* app version
* engine version

⸻

9. UI/UX 설계

9.1 디자인 방향

Negaflow는 SilverFast처럼 보이면 안 된다.
macOS 네이티브 앱처럼 보여야 한다.

디자인 키워드:

* Native
* Quiet
* Precise
* Filmic
* Dense
* Clean
* No SaaS smell
* No AI dashboard smell
* No fake futuristic look

9.2 화면 구조

MVP 화면은 3개다.

1. Scan
2. Develop
3. Export

또는 하나의 메인 윈도우에서 3영역 구성:

좌측: Roll / Frames
중앙: Preview Canvas
우측: Scan & Develop Controls
하단: Status / Histogram / Before After

9.3 Scan 화면

상단

* Scanner selector
* Connection status
* Diagnostics button

예시:

Plustek OpticFilm 8200i
Verified
USB Connected

Scan Controls

* Film Type
    * Color Negative
    * Slide
    * B&W Negative
    * B&W Positive
* Resolution
    * Preview
    * 1800
    * 3600
    * 7200
* Bit Depth
    * 8bit
    * 16bit
* Scan Mode
    * RGB
    * RGB + IR
* Buttons
    * Preview
    * Scan
    * Cancel

9.4 Preview Canvas

기능:

* 스캔 미리보기 표시
* 수동 crop
* rotate
* flip
* zoom
* before/after
* safe area 표시

초기에는 자동 프레임 인식 금지.
수동 crop이 더 현실적이고 정확하다.

9.5 Develop 패널

Base

* Auto
* Pick Border
* Pick Film Base
* Reset

Look

* Neutral
* Rich Neutral
* Soft Print
* Clear Chrome
* Warm Lab
* Deep Slide

Tone

* Exposure
* Density
* Highlight
* Shadow

Color

* Warmth
* Tint
* Color Depth

Texture

* Grain
* Sharpness
* Halation

9.6 Export 화면

출력:

* JPEG
* TIFF 16bit
* Raw Scan TIFF
* Sidecar JSON
* Contact Sheet JPEG

옵션:

* File naming
* Export folder
* Include metadata
* Export selected frame
* Export all scanned frames

9.7 상태 표시

Plustek 고해상도 스캔은 시간이 걸리므로 상태 표시가 매우 중요하다.

상태 문구:

* Connecting scanner
* Warming lamp
* Ready
* Preview scanning
* Waiting for film holder
* Scanning RGB
* Scanning IR
* Processing negative
* Rendering look
* Exporting
* Complete
* Scanner busy
* Scanner disconnected
* Backend fallback active

⸻

10. Diagnostics 설계

10.1 왜 필요한가

사용자는 8200i만 테스트 가능하다.
8100/8300i까지 지원하려면 장치 리포트 기능이 필수다.

10.2 Scanner Diagnostics 화면

표시 항목:

* Scanner name
* Backend
* USB Vendor ID
* USB Product ID
* Driver version
* Connection status
* Supported resolutions
* Supported color modes
* Supported bit depths
* IR support
* Transparency support
* Scan area range
* Last error

10.3 Export Scanner Report

JSON 파일로 내보낸다.

내용:

{
“app”: “Negaflow”,
“appVersion”: “0.1.0”,
“scanner”: {
“name”: “Plustek OpticFilm 8300i”,
“vendor”: “Plustek”,
“model”: “OpticFilm 8300i”,
“usbVendorID”: “0x07b3”,
“usbProductID”: “unknown”
},
“backend”: {
“type”: “ImageCaptureCore”,
“available”: true
},
“capabilities”: {
“resolutions”: [900, 1800, 3600, 7200],
“modes”: [“Color”, “Gray”, “Infrared”],
“bitDepths”: [8, 16],
“supportsInfrared”: true,
“supportsTransparency”: true
},
“testResults”: {
“previewScan”: “success”,
“fullScan3600”: “not_tested”,
“infraredScan”: “not_tested”
}
}

이 기능 덕분에 직접 보유하지 않은 모델도 사용자 리포트 기반으로 지원을 확장할 수 있다.

⸻

11. 저장 구조

11.1 프로젝트 단위

Negaflow는 한 번의 작업을 Session으로 관리한다.

예:

2026-06-13_Portra400_LeicaM6
2026-06-14_FujiC200_Tokyo
2026-06-15_TestRoll_8200i

11.2 폴더 구조

Negaflow Library

* Sessions
    * 2026-06-13_TestRoll
        * Raw
        * Develop
        * Exports
        * Sidecars
        * Thumbnails
        * Reports

11.3 파일 네이밍

기본:

YYYYMMDD_RollName_FrameNumber

예:

20260613_TestRoll_001_raw.tiff
20260613_TestRoll_001_develop.json
20260613_TestRoll_001_rich-neutral.jpg
20260613_TestRoll_001_neutral_16bit.tiff

⸻

12. 개발 스택

12.1 앱

* Swift
* SwiftUI
* AppKit
* ImageCaptureCore
* Core Image
* Metal optional
* ImageIO

12.2 스캐너 백엔드

1차:

* ImageCaptureCore

Fallback:

* SANE / scanimage wrapper
* Homebrew sane-backends 기반 개발 테스트
* 추후 앱 번들 포함 여부 검토

12.3 색감 엔진

MVP 빠른 구현:

* Swift + Core Image 중심
* 복잡한 알고리즘은 초기 Python 프로토타입으로 검증 가능

장기 구현:

* Swift 또는 Rust core
* 32bit float pipeline
* LUT system
* LCMS 기반 ICC 처리
* Metal 가속

12.4 이미지 처리 라이브러리 후보

* Core Image
* ImageIO
* Accelerate
* Metal Performance Shaders
* libtiff
* LittleCMS
* OpenImageIO 후보
* Rust image crate 후보

MVP에서는 의존성을 줄인다.

⸻

13. 개발 단계

Phase 0. 기술 검증

목표:

8200i가 macOS에서 어떤 경로로 제어 가능한지 확인한다.

작업:

1. ImageCaptureCore 샘플 앱 작성
2. ICDeviceBrowser로 8200i 탐지
3. Overview scan 테스트
4. Full scan 테스트
5. 해상도 제어 테스트
6. 16bit 출력 확인
7. scan area 제어 확인
8. IR 채널 접근 가능성 확인
9. SANE 설치 후 scanimage -L 테스트
10. scanimage -A 옵션 덤프
11. 3600dpi 16bit scan 테스트
12. 7200dpi 16bit scan 테스트

성공 기준:

* 적어도 한 경로로 8200i 직접 스캔 성공
* 16bit RGB TIFF 획득
* SwiftUI 앱에서 스캔 결과 표시 가능

실패 시 대응:

* ImageCaptureCore 제어 부족 → SANE fallback 우선
* SANE macOS 문제 → Plustek driver + ImageCaptureCore 범위 재검토
* IR 접근 불가 → IR은 2차 이후로 연기

Phase 1. 스캐너 MVP

목표:

Negaflow 앱에서 8200i를 직접 스캔한다.

기능:

* 스캐너 감지
* 연결 상태 표시
* 프리뷰 스캔
* 수동 crop
* 3600dpi 본스캔
* 16bit RGB TIFF 저장
* 스캔 진행 상태 표시
* cancel scan
* error handling

성공 기준:

* 앱에서 Preview 버튼 클릭
* 프리뷰 표시
* crop 지정
* Scan 클릭
* Raw TIFF 생성
* 앱에서 Raw TIFF 표시

Phase 2. Chromabase MVP

목표:

스캔된 컬러 네거티브를 보기 좋은 이미지로 반전한다.

기능:

* TIFF load
* Auto film base estimation
* Manual base picker
* Negative inversion
* Auto exposure
* Auto white balance
* Neutral preset
* Rich Neutral preset
* JPEG export
* 16bit TIFF export

성공 기준:

* SilverFast 기본 출력과 비교했을 때 사용자가 더 자주 쓰고 싶은 결과물이 나와야 함
* 최소 5장 이상 샘플에서 색이 크게 무너지지 않아야 함
* 수동 base picker로 실패 케이스를 복구할 수 있어야 함

Phase 3. 앱 통합

목표:

스캔과 색현상을 하나의 UX로 연결한다.

기능:

* Scan → Develop 자동 이동
* Before/After
* Look preset
* Tone sliders
* Color sliders
* Export
* Sidecar 저장
* Session 저장

성공 기준:

* 한 컷을 꽂고 스캔해서 최종 JPEG까지 앱 안에서 완료
* 사용자가 SilverFast/VueScan을 열지 않아도 됨
* Raw TIFF와 최종 결과물이 함께 저장됨

Phase 4. Compatibility Layer

목표:

8100/8300i 대응 구조를 만든다.

기능:

* Capability parser
* Scanner Report Export
* Compatible / Experimental 상태 표시
* IR 없는 모델 UI 자동 비활성
* 알 수 없는 Plustek 모델도 report 추출 가능

성공 기준:

* 8100/8300i 사용자가 리포트를 보내면 기능 판단 가능
* 앱이 미지원 모델에서 무작정 죽지 않음
* 기능이 없는 옵션은 UI에서 자동 숨김/비활성 처리

Phase 5. IR Experimental

목표:

8200i의 IR 채널 캡처 가능성을 검증한다.

기능:

* RGB + IR scan
* IR channel save
* IR preview
* dust mask prototype
* dust mask overlay

MVP에서는 자동 먼지 제거 완성은 하지 않는다.

성공 기준:

* IR 채널을 이미지로 확인 가능
* 먼지/스크래치가 IR에서 구분되는지 확인
* 이후 inpainting 알고리즘 개발 가능성 판단

Phase 6. Beta

목표:

실사용 가능한 베타 앱으로 만든다.

기능:

* 세션 관리
* batch export
* contact sheet
* preference
* crash report
* scanner diagnostics
* update guide
* sample profiles
* keyboard shortcuts

성공 기준:

* 하루에 한 롤 정도를 Negaflow로 처리할 수 있음
* 앱이 중간에 스캐너 오류를 만나도 복구 가능
* 결과물 색감이 일관됨

⸻

14. MVP 범위

14.1 포함

* macOS 전용 앱
* Plustek 8200i Verified
* 스캐너 감지
* 프리뷰 스캔
* 수동 crop
* 3600dpi / 7200dpi 선택
* 16bit RGB scan
* Raw TIFF 저장
* 컬러 네거티브 반전
* 슬라이드 기본 처리
* 흑백 네거티브 기본 처리
* Neutral / Rich Neutral / Soft Print / Clear Chrome
* JPEG export
* 16bit TIFF export
* sidecar JSON
* Scanner Diagnostics
* Scanner Report Export

14.2 제외

* App Store 배포
* Windows/Linux 지원
* 모든 Plustek 모델 Verified 선언
* 완전 자동 프레임 분할
* 전체 롤 자동 스캔
* 완성형 IR 먼지 제거
* SilverFast HDRi 완전 호환
* IT8 캘리브레이션 완성
* Multi-Exposure 완성
* AI 자동 보정
* 클라우드 기능
* 계정/로그인
* 구독 결제
* 라이브러리 기반 대규모 DAM 기능

⸻

15. 성공 기준

15.1 기술 성공 기준

* 8200i에서 직접 프리뷰 스캔 성공
* 8200i에서 직접 본스캔 성공
* 3600dpi 16bit RGB TIFF 생성 성공
* 앱 내부에서 TIFF 프리뷰 표시
* Chromabase로 컬러 네거티브 반전 성공
* JPEG/TIFF export 성공
* 스캐너 연결 오류 처리 가능
* Scanner Report Export 가능

15.2 사용자 경험 성공 기준

* 사용자가 SilverFast 없이 한 컷을 스캔하고 결과물을 얻을 수 있음
* 기본 Neutral 결과가 무난해야 함
* Rich Neutral 결과가 “쫀득한” 인상을 줘야 함
* UI가 복잡한 스캐너 유틸처럼 보이면 실패
* 색 조절 슬라이더가 너무 많으면 실패
* 첫 사용자가 10분 안에 첫 결과물을 얻어야 함

15.3 품질 성공 기준

* 하이라이트가 쉽게 날아가지 않아야 함
* 섀도우가 막히지 않아야 함
* 오렌지 마스크 제거가 안정적이어야 함
* 흰 벽/하늘/피부톤에서 색 틀어짐이 과하면 실패
* 채도만 올린 싸구려 룩이면 실패
* 결과물이 SilverFast 기본값보다 매력적이어야 함

⸻

16. 리스크 분석

16.1 ImageCaptureCore 제어 한계

가장 큰 리스크다.

8200i가 macOS Image Capture에서 보이더라도 Negaflow가 원하는 16bit/IR/해상도/scan area 제어를 모두 할 수 있다는 보장은 없다.

대응:

* Phase 0에서 즉시 검증
* 실패 시 SANE fallback
* ImageCaptureCore는 Preview 전용, SANE은 Full Scan 전용 혼합 구조도 고려

16.2 SANE 배포 문제

SANE은 개발 테스트에는 좋지만 macOS 앱 배포에 포함하기 까다로울 수 있다.

대응:

* 초기 개발자 빌드는 Homebrew dependency 허용
* Beta 전에는 번들링 가능성 검토
* 사용자가 직접 SANE를 설치해야 하는 구조는 최종 제품에서 피한다
* fallback backend로만 사용한다

16.3 Plustek 드라이버 충돌

SilverFast, Plustek 드라이버, ImageCaptureCore, SANE/libusb가 동시에 장치를 잡으려 할 수 있다.

대응:

* 앱 실행 시 SilverFast/VueScan 종료 안내
* 스캐너 점유 상태 감지
* USB 재연결 안내
* Diagnostics에 backend error 표시

16.4 8300i 미검증

8300i를 직접 테스트할 수 없으므로 지원을 보장하면 안 된다.

대응:

* Compatible Target로 표기
* Scanner Report Export 제공
* 사용자 리포트 기반으로 지원 확장
* 기능은 Capability 기반으로 표시

16.5 색감 품질

기술적으로 스캔이 되어도 색감이 별로면 앱 가치는 낮다.

대응:

* Chromabase를 별도 엔진으로 분리
* 샘플 세트를 계속 축적
* Neutral의 안정성을 최우선으로 함
* Rich Neutral은 과하게 만들지 않음
* 사용자가 직접 쓸 결과물을 기준으로 튜닝

⸻

17. Repository 구조

negaflow/
README.md
docs/
PRODUCT_SPEC.md
DEVELOPMENT_PLAN.md
SCANNER_BACKEND.md
CHROMABASE_ENGINE.md
DEVICE_SUPPORT.md
UI_GUIDE.md
TEST_PLAN.md
app/
Negaflow/
NegaflowApp.swift
Views/
ViewModels/
Resources/
core/
ScannerKit/
ScannerBackend.swift
ImageCaptureBackend.swift
SANEBackend.swift
MockScannerBackend.swift
ScannerCapabilities.swift
ScannerReport.swift
Chromabase/
ChromabaseEngine.swift
NegativeInversion.swift
FilmBaseEstimator.swift
ToneMapper.swift
LookPreset.swift
ExportEngine.swift
presets/
neutral.json
rich-neutral.json
soft-print.json
clear-chrome.json
warm-lab.json
deep-slide.json
samples/
README.md
tests/
ScannerKitTests/
ChromabaseTests/
IntegrationTests/

⸻

18. 문서 체계

README.md

짧게 제품 소개.

포함:

* Negaflow 소개
* 지원 스캐너 상태
* MVP 기능
* 개발 상태
* 설치/실행
* 주의사항

PRODUCT_SPEC.md

제품 철학과 UX 정의.

DEVELOPMENT_PLAN.md

이 문서.

SCANNER_BACKEND.md

ImageCaptureCore, SANE, TWAIN 전략 정리.

CHROMABASE_ENGINE.md

색감 엔진 설계.

DEVICE_SUPPORT.md

모델별 지원 상태와 테스트 결과.

TEST_PLAN.md

8200i 검증 절차, 샘플 이미지, 색감 비교 기준.

⸻

19. 초기 README 초안

Negaflow

Negaflow is a macOS-native film scanning and developing app for Plustek OpticFilm scanners.

It directly controls the scanner, captures high-bit-depth film scans, converts negatives through the Chromabase color engine, and exports clean modern JPEG/TIFF results without forcing users through a legacy scanning workflow.

Status

Early development.

Verified scanner

* Plustek OpticFilm 8200i

Compatible targets

* Plustek OpticFilm 8100
* Plustek OpticFilm 8300i

Core features

* Direct scanner control
* Preview scan
* Manual crop
* 16-bit RGB scan
* Color negative conversion
* Modern film looks
* Raw TIFF archive
* JPEG/TIFF export
* Scanner diagnostics
* Scanner report export

Color engine

Powered by Chromabase.

Initial looks:

* Neutral
* Rich Neutral
* Soft Print
* Clear Chrome
* Warm Lab
* Deep Slide

⸻

20. 개발 우선순위

최우선

1. 8200i 직접 인식
2. Preview scan
3. Full scan
4. 16bit RGB TIFF
5. Chromabase Neutral
6. Chromabase Rich Neutral
7. JPEG export

그다음

1. Scanner Diagnostics
2. sidecar JSON
3. 7200dpi
4. 8100/8300i Capability 대응
5. IR capture experimental
6. Batch export

나중

1. IR dust removal
2. Multi-Exposure
3. IT8 calibration
4. Automatic frame detection
5. Full roll workflow
6. App notarization / public beta
7. App Store 여부 검토

⸻

21. 개발자가 절대 하지 말아야 할 것

1. 처음부터 SilverFast 전체 대체를 목표로 삼지 않는다.
2. 처음부터 모든 Plustek 모델 지원을 보장하지 않는다.
3. 처음부터 IR 먼지 제거를 완성하려 하지 않는다.
4. 처음부터 자동 프레임 분할을 넣지 않는다.
5. 처음부터 색공간/ICC/IT8을 완벽하게 만들려 하지 않는다.
6. SwiftUI 화면보다 색감 엔진을 가볍게 보지 않는다.
7. UI를 AI SaaS 대시보드처럼 만들지 않는다.
8. 스캐너 백엔드와 색감 엔진을 섞지 않는다.
9. 사용자가 SANE, TWAIN, ICA 같은 용어를 보게 만들지 않는다.
10. 기능을 많이 넣는 대신 좋은 기본값을 망치지 않는다.

⸻

22. 최종 MVP 문장

Negaflow MVP는 Plustek OpticFilm 8200i를 직접 제어해 16bit RGB 필름 스캔을 수행하고, Chromabase 색감 엔진으로 컬러 네거티브를 안정적으로 반전한 뒤, Neutral/Rich Neutral 룩으로 바로 공유 가능한 JPEG/TIFF를 출력하는 macOS 네이티브 앱이다.

8100과 8300i는 1차부터 구조상 대응하되, Verified가 아니라 Compatible Target으로 둔다. 실제 기능은 장치 Capability 감지와 Scanner Report 기반으로 확장한다.

Negaflow의 성공은 스캐너 제어보다 색감에서 결정된다.
Chromabase가 SilverFast 기본값보다 더 쓰고 싶은 결과물을 만들어야 한다.
그게 이 프로젝트의 핵심이다.

추가로, 위 계획서에서 가장 중요한 판단은 ImageCaptureCore 먼저, SANE fallback입니다. Apple 공식 프레임워크가 스캐너 탐지와 스캔 수행을 지원하므로 macOS 단독 앱의 1순위는 ImageCaptureCore가 맞습니다. 다만 Plustek 필름 스캐너의 IR/16bit/투과 유닛 제어가 충분히 열릴지는 8200i 실기 검증 전에는 확정할 수 없어서, SANE/scanimage를 fallback으로 두는 구조가 안전합니다.  

8100/8200/8300을 모두 욕심내는 건 가능하지만, 문서상 표현은 반드시 Verified / Compatible Target / Experimental로 나눠야 합니다. 8200i는 사용자 테스트가 가능하니 Verified, 8100은 공식 제품 설명과 SANE 지원 목록 근거가 있으니 Compatible Target, 8300i는 최신 macOS 설치 정보와 VueScan 호환 설명이 있으나 직접 테스트가 없으니 Compatible Target이 맞습니다.  