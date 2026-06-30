# negaflow 디자인 시스템

## 1. 제품 분위기

negaflow는 사진이 중심이고 조작부는 뒤로 물러나는 macOS 네이티브 필름 현상실입니다. Lightroom, Apple Photos, Image Capture 계열의 작업 밀도를 참고하되, 대시보드나 마케팅 페이지처럼 보이는 장식은 쓰지 않습니다.

핵심 원칙은 세 가지입니다.

- 기본 현상 타겟은 언제나 `main`입니다.
- 자동 보정은 사용자가 선택했을 때만 켭니다. 기본은 수동 선택과 명시적 값 유지입니다.
- UI는 Apple 시스템 소재와 Liquid Glass API를 우선 사용하고, 가짜 블러/그라데이션 장식으로 대체하지 않습니다.

작업 화면은 Lightroom과 Capture One 같은 전문 현상 앱의 밀도와 정렬감을 기준으로 합니다. 기능은 실제 작업 순서대로 묶고, 탭·접이식 섹션·분할 버튼으로 나눠 한 번에 보이는 표면을 단순하게 유지합니다. 좌우 폭이 들쭉날쭉한 행, 임의 간격, 장식 카드 남발, AI SaaS식 홍보 화면 구성은 금지합니다.

## 2. 색상

| 역할 | 토큰 | 사용 |
|---|---|---|
| 기본 표면 | `surface.canvas` | 중앙 캔버스, 사진 주변 작업 영역 |
| 보조 표면 | `surface.material` | 사이드바, 인스펙터, 도구 표면 |
| 기본 텍스트 | `text.primary` | `Color.primary` |
| 보조 텍스트 | `text.secondary` | `Color.secondary` |
| 동작 강조 | `accent.action` | 선택, 확정, 활성 조작 |
| 경고 | `status.warning` | 스캐너 대기와 주의 상태 |
| 오류 | `status.error` | 실패, 취소, 파괴적 동작 |

장식용 강조색과 넓은 컬러 그라데이션은 사용하지 않습니다. 상태와 상호작용은 macOS 시스템 색상, SF Symbols, 소재 차이로 구분합니다.

## 3. 타이포그래피

| 단계 | SwiftUI 스타일 | 용도 |
|---|---|---|
| 창 제목 | `.headline` | 앱 이름, 핵심 작업 제목 |
| 섹션 | `.subheadline.weight(.semibold)` | Scan, Base, 현상 섹션 헤더 |
| 본문 | `.body` | 선택지와 설명 |
| 보조 | `.caption` | 제어 레이블 |
| 메타데이터 | `.caption2.monospacedDigit()` | 프레임 번호, 값, DPI |

SF 계열 시스템 글꼴만 사용합니다. 수치와 프레임 번호는 고정폭 숫자로 흔들림 없이 정렬합니다.

## 4. 레이아웃

기본 단위는 4pt입니다. 인라인 간격은 8pt, 제어 묶음은 12pt, 패널 내부 여백은 14-16pt를 사용합니다.

작업 공간은 아래 구조를 유지합니다.

- 상단: 장치 선택, 진행 상태, appearance 모드, Demo 전환, 진단
- 좌측: Capture One식 tool-tab rail과 Library, Versions, Presets, Output 패널로 롤 관리와 비파괴 버전 작업을 분리
- 중앙: 사진 캔버스와 상태 바
- 하단 프레임 스트립: 롤의 프레임 선택, 최신 프레임은 오른쪽
- 우측: Histogram, Base, 도구, Tone, Color, Detail 순서의 현상 인스펙터

긴 기능 목록을 한 화면에 나열하지 않습니다. 사용 빈도와 작업 순서에 맞춰 접이식 섹션과 분할 버튼을 사용합니다.

좌측 탭에는 스캔, 롤 상태, Virtual Copy, History, Snapshot, Copy/Paste, User Preset, Export처럼 프레임 관리와 버전/출력 흐름에 가까운 기능을 둡니다. 우측 인스펙터에는 현재 선택 프레임의 현상 품질을 직접 바꾸는 조작만 둡니다.

인스펙터 행은 레이블, Picker, Toggle, Slider의 기준선을 맞춥니다. 동일한 성격의 컨트롤은 같은 폭과 같은 간격을 유지하고, 새 기능은 가장 가까운 작업 묶음 안에 배치합니다. 별도 패널은 기능이 독립적인 워크플로일 때만 추가합니다.

## 5. 구성요소

### Base 섹션

- 기본 Base 모드는 앱의 현재 동작을 유지합니다.
- Film 모드에서 필름 Dmin/Dmax를 선택할 수 있습니다.
- Scanner Profile은 기본적으로 `nil`이며 수동 선택입니다.
- `Auto Match`를 사용자가 켠 경우에만 선택한 Film과 같은 필름 키의 NORITSU/SP-3000 프로파일을 적용합니다.
- Roll WB 동기화는 Base와 색온도 보정 흐름에 속하므로 Base 섹션 안에 정렬합니다.
- `Sync Roll WB`는 수동 명령이고, `Auto Sync`는 기본 off이며 사용자가 켠 경우에만 나머지 프레임을 따라가게 합니다.

### 도구 스트립

- 크롭, 회전, 좌우 반전, 상하 반전, 초기화를 SF Symbols 아이콘 버튼으로 제공합니다.
- 현재 프레임의 transform과 다음 스캔에 적용될 orientation을 분리해서 표시합니다.

### Virtual Copy

- Virtual Copy는 좌측 `Versions` 탭의 맨 위 compact control row로 둡니다.
- 사용자가 `Virtual Copy`를 누른 경우에만 별도 비파괴 프레임을 만들고 자동 생성하지 않습니다.
- 원본 raw 파일은 중복하지 않고 copy 프레임이 같은 raw를 공유합니다.
- copy 프레임은 독립된 Film, Base, Scanner Profile, Look, Tone, Color, Detail, geometry, History, Snapshot 상태를 가집니다.
- 프레임 스트립에서는 copy 여부를 짧은 고정폭 메타데이터로만 표시하고 별도 설명 패널을 만들지 않습니다.

### 중앙 캔버스 보기 모드

- 사진 캔버스가 편집의 중심이며, 보기 전환은 사진 위에 작게 떠 있는 컨트롤로 제공합니다.
- Raw, Developed, 좌우 Before/After, 상하 Before/After를 한 묶음으로 유지합니다.
- `\` 단축키는 Developed와 마지막 Raw/Before-After 보기 사이를 오가며, 별도 설명 패널을 만들지 않습니다.
- 비교 라벨과 분할선은 사진 판독을 방해하지 않을 정도로 작게 두고, 별도 카드나 설명 패널을 만들지 않습니다.

### 현상 섹션

- Basic Tone, Tone Curve, Color, Calibration, Detail & Effects 순서로 유지합니다.
- 각 섹션은 펼침/접힘 상태와 섹션별 초기화를 제공합니다.
- 처리 중에는 충돌 가능한 조작을 비활성화합니다.
- 현상 슬라이더는 클릭 또는 Tab으로 선택한 항목만 키보드 미세 조정 대상으로 삼습니다.
- 방향키는 0.01 단위, Shift+방향키는 0.10 단위로 조정하고 각 슬라이더의 범위를 넘지 않습니다.
- 키보드 포커스는 얇은 시스템 accent outline으로만 표시하고 별도 설명 카드나 큰 안내 문구를 만들지 않습니다.

### Developer Debug

- 현상 파이프라인 디버그는 기본 off입니다.
- 우측 인스펙터의 현상 섹션 아래에 접이식 `Developer Debug` 섹션으로만 둡니다.
- `Pipeline Overlay`를 켠 경우에만 캔버스가 선택한 단계 이미지를 보여줍니다.
- 단계 선택은 `After Inversion`, `After AutoLevels`, `After PrintBase`, `Final Tone`으로 제한합니다.
- `dmin`과 `dmaxNorm`은 작은 고정폭 메타데이터 줄로만 보여주고 별도 카드나 설명 패널을 만들지 않습니다.

### 현상 설정 전송

- Copy/Paste Settings는 좌측 `Presets` 탭에 작게 고정합니다.
- 복사/붙여넣기는 명시적 버튼으로만 동작하며 자동 적용하지 않습니다.
- 버튼은 같은 폭의 아이콘+텍스트 컨트롤로 정렬하고, 복사된 원본 프레임은 한 줄 메타데이터로만 표시합니다.
- 부분 선택 붙여넣기는 `Paste Scope` 메뉴에서 Base, Tone, Color, Detail을 수동 선택하게 하며 기본값은 기존 전체 붙여넣기입니다.
- Snapshot과 A/B 비교는 좌측 `Versions` 탭의 compact 행으로 두고 현상 인스펙터를 복잡하게 만들지 않습니다.

### 현상 히스토리

- History는 좌측 `Versions` 탭에서 Virtual Copy 아래, Snapshot 위에 compact control row로 둡니다.
- 기본은 자동 기록이 아니라 사용자가 `Record`를 누른 시점만 저장하는 수동 기록입니다.
- `Apply`는 선택한 History 상태로 현재 프레임만 되돌리고 해당 프레임만 다시 현상합니다.
- History 항목은 Film, Base, Scanner Profile, Look, Tone, Color, Detail, geometry를 보존합니다.
- 저장 개수와 수동 기록 여부는 작은 고정폭 메타데이터 줄로만 표시합니다.

### 사용자 프리셋

- User Presets는 좌측 `Presets` 탭에서 Copy/Paste 아래 compact control row로 둡니다.
- 저장과 적용은 명시적 버튼으로만 동작하며 자동 적용하지 않습니다.
- 프리셋은 Film, Base, Scanner Profile, Look, Tone, Color, Detail 값을 저장하고 crop/rotation/flip은 저장하지 않습니다.
- 선택 메뉴와 Delete 아이콘은 한 줄에 두고, Save/Apply는 같은 폭의 두 버튼으로 정렬합니다.
- 저장 개수와 geometry 보존 여부는 작은 고정폭 메타데이터 줄로만 표시합니다.

### 히스토그램

- 히스토그램은 우측 인스펙터 최상단에 유지해 현상 조작 전후의 톤과 채널 상태를 즉시 확인하게 합니다.
- Luma 면적을 바탕으로 두고 R/G/B 채널 라인을 같은 스케일 위에 겹쳐, 색 채널 불균형을 과장 없이 읽게 합니다.
- 클리핑 표시는 작은 수치/채널 배지로만 제공하고 별도 경고 카드나 설명 패널을 만들지 않습니다.

### Export

- Export는 좌측 `Output` 탭에 Format, Sidecar, 내보내기 버튼만 간결하게 둡니다.
- `Sidecar JSON + XMP 저장`은 기본 off이며, 사용자가 켠 경우에만 `.negaflow.json`과 `.xmp`를 함께 저장합니다.
- `.negaflow.json`은 Negaflow의 canonical 비파괴 sidecar이고, `.xmp`는 다른 현상 도구와 워크플로를 잇는 호환용 subset입니다.
- XMP 저장은 background 자동 동기화가 아니라 명시적 export 동작의 일부여야 합니다.

### 프레임 스트립

- 프레임은 롤 단위 작업의 중심입니다.
- 최신 프레임이 오른쪽에 쌓이는 하단 필름스트립을 사용합니다.
- 프레임별 현상 상태, raw/developed 상태, 필름 타입을 한눈에 읽을 수 있어야 합니다.

### Appearance

- 상단 바에는 `System`, `Dark`, `Light` 세그먼트 토글을 둡니다.
- `System`은 macOS 시스템 설정을 따르고, `Dark`와 `Light`는 앱 창의 `preferredColorScheme`만 고정합니다.
- 모드 선택은 `UserDefaults`에 보존하되 스캔, 현상, export 상태와 분리합니다.

## 6. 모션과 상호작용

마이크로 상호작용과 섹션 전환은 180ms 안팎의 `.snappy` 애니메이션을 사용합니다. 드래그, 크롭, 스캔, 현상 중에는 진행 상태를 숨기지 않습니다.

macOS 26 이상에서는 여러 glass 요소를 `GlassEffectContainer` 안에 묶고, 상호작용 가능한 컨트롤에만 interactive glass를 씁니다. 이전 macOS에서는 `regularMaterial` 기반 fallback을 둡니다.

## 7. 깊이와 표면

깊이는 macOS 소재 기반의 톤 차이로 만듭니다. 두꺼운 카드 테두리, 무거운 그림자, 장식성 블러, AI SaaS식 보라/파랑 배경은 사용하지 않습니다.
