# 장기 유지보수와 두 플랫폼의 동등성 운영

> 상태: Windows 구현 전 설계 기준  
> 기준일: 2026-08-04  
> 적용 범위: Negaflow macOS 제품, 향후 Windows 제품, 스캐너 플러그인, 공통 데이터 자산, 빌드·배포·검증 체계

## 0. 결론

Negaflow의 장기 유지보수 문제는 소스 코드를 두 운영체제에서 공유하지 않는 데 있지 않다. 진짜 위험은 다음 네 가지가 서로 다른 속도로 변하면서도 하나의 `앱 버전`으로 뭉뚱그려지는 것이다.

1. 사용자가 보는 제품 동작과 UI/UX
2. 현상 파이프라인의 수치 의미와 파일 포맷
3. 플랫폼별 네이티브 구현과 런타임
4. 스캐너 플러그인과 외부 드라이버 생태계

따라서 유지보수 체계는 다음 원칙으로 고정한다.

- macOS와 Windows는 **네이티브 구현을 독립적으로 유지**한다.
- 두 구현의 공통 기준은 공유 소스 코드가 아니라 **버전이 고정된 제품 사양, 데이터 자산, 기준 manifest, 적합성 시험**이다.
- 움직이는 `main`이나 마케팅 버전을 Windows 포팅 기준으로 삼지 않는다.
- 모든 릴리스는 정확한 소스 커밋, 자산 해시, 스키마, 셰이더, 도구 체인, 시험 corpus를 묶은 **재현 가능한 기준선**을 가진다.
- 앱 버전, 데이터 스키마, 알고리즘 버전, 네이티브 ABI, 스캐너 프로토콜, 자산 번들 버전을 서로 분리한다.
- 플랫폼 차이는 숨기지 않고 **의도된 차이, 임시 차이, 결함**으로 분류한다.
- 골든 결과는 편의를 위해 갱신하지 않는다. 의미 변경의 근거와 양쪽 플랫폼 검증이 있어야 승격한다.
- Windows 코어 앱은 스캐너 플러그인 없이도 완전한 가져오기·현상·내보내기 제품으로 유지한다.
- 배포 파일 롤백과 사용자 데이터 롤백을 같은 동작으로 취급하지 않는다.

이 문서는 구체적인 라이브러리의 현재 최신 버전을 영구 규칙으로 고정하지 않는다. 버전 숫자는 기준일의 조사 스냅샷이고, 실제 출시 시점에는 지원 수명과 회귀 결과를 다시 확인한다.

---

## 1. 유지보수에서 지켜야 할 제품 불변식

### 1.1 결과 불변식

- 같은 원본, 같은 recipe, 같은 색 관리 조건, 같은 알고리즘 버전이면 두 플랫폼은 정의된 허용 오차 안에서 같은 결과를 낸다.
- 미리보기와 내보내기는 품질을 낮춘 별도 알고리즘이 아니라 동일한 현상 의미를 공유한다.
- 미리보기의 축소 해상도, 타일 순서, 비동기 실행 때문에 recipe 의미가 달라지지 않는다.
- GPU 제조사, CPU 제조사, x64/ARM64에 따라 사용자가 선택한 조정값의 의미가 바뀌지 않는다.
- GPU 경로가 실패하면 완전한 CPU 경로로 재실행하거나 명시적으로 실패한다. 부분 처리 결과를 성공으로 반환하지 않는다.
- 원본 파일은 불변이며 catalog, sidecar, thumbnail, cleaned-raw cache와 구분한다.
- 필요한 비파괴 결과를 재구성할 수 없으면 원본을 대신 내보내지 않고 실패를 표시한다.

### 1.2 UI/UX 불변식

- Windows 버전은 WinUI 3의 네이티브 입력·포커스·접근성·창 동작을 사용한다.
- macOS 화면을 픽셀 단위로 복제하는 대신 정보 위계, 작업 순서, 기능 노출 조건, 조정 의미를 동등하게 유지한다.
- 새 기능은 Library, Develop, Scan, Export 중 어느 흐름에 들어가는지 먼저 결정한다.
- 스캐너 관련 UI는 플러그인이 보고한 capability만 노출한다.
- 지원하지 않는 기능을 모델명 추측이나 비활성 가짜 컨트롤로 암시하지 않는다.
- 빈 상태, 오류 상태, 취소 상태, 장치 분리 상태도 제품 동등성의 일부로 시험한다.

### 1.3 플러그인·라이선스 불변식

- SANE, TWAIN DSM 또는 배포 조건을 별도로 검토해야 하는 스캐너 구성 요소는 코어 앱에 정적으로 링크하지 않는다.
- 플러그인은 별도 프로세스와 기존 방향의 JSON 메시지 계약으로 격리한다.
- 플러그인의 설치, 서명, 라이선스 고지, SBOM, 업데이트, 제거 수명은 코어 앱과 분리한다.
- 플러그인이 없거나 손상되어도 코어 앱이 시작되고 기존 사진 작업을 수행할 수 있어야 한다.
- USB 발견은 스캔 지원, IR 지원, 필름 홀더 포맷 지원의 증거가 아니다.

---

## 2. 하나의 버전 번호로 관리하면 안 되는 이유

`2.1.0` 같은 제품 버전 하나만 기록하면 다음 질문에 답할 수 없다.

- 이 릴리스가 어떤 현상 알고리즘 의미를 사용했는가?
- 오래된 catalog를 읽고 다시 저장했을 때 되돌릴 수 있는가?
- 스캐너 플러그인 프로토콜 몇 버전까지 호환되는가?
- GPU 셰이더가 어느 컴파일러와 옵션으로 만들어졌는가?
- 같은 이름의 scanner profile이 실제로 같은 바이트인가?
- Windows x64와 ARM64 설치 파일이 같은 소스와 자산으로 빌드됐는가?
- macOS에서 수정된 tone curve가 Windows에도 반영됐는가?

따라서 다음 버전 축을 독립적으로 기록한다.

| 버전 축 | 의미 | 변경 예시 | 호환성 판단 주체 |
|---|---|---|---|
| 제품 마케팅 버전 | 사용자에게 보이는 릴리스 | `1.3.0` | 릴리스 정책 |
| 빌드 식별자 | 정확한 산출물 재현 | 커밋, CI run, timestamp | 빌드 시스템 |
| 제품 사양 버전 | 두 플랫폼이 따라야 할 동작 | 조정 범위, UI 흐름 | 제품 결정 기록 |
| catalog 스키마 | 라이브러리 DB 구조 | 새 테이블·열 | 저장소 계층 |
| sidecar 스키마 | 외부 metadata 구조 | 필드 추가 | parser/migrator |
| recipe 스키마 | 현상 파라미터 구조 | 새 조정값 | 현상 엔진 |
| 알고리즘 버전 | 같은 recipe의 수치 의미 | grain, blur, curve 변경 | 현상 엔진 |
| native ABI | C#/C++ 경계와 구조체 레이아웃 | 함수·구조체 변경 | interop 계층 |
| 스캐너 프로토콜 | 앱↔외부 프로세스 계약 | command/capability 추가 | plugin host |
| 플러그인 패키지 | 공급자별 구현 릴리스 | WIA/TWAIN backend 수정 | plugin updater |
| 자산 번들 | preset/profile/LUT 집합 | profile 재측정 | asset pipeline |
| 셰이더 팩 | HLSL/DXIL 집합 | kernel 변경 | GPU 엔진 |
| update feed | 업데이트 메타데이터 계약 | 서명 key rotation | updater |
| 적합성 corpus | fixture와 기대값 집합 | 신규 edge case | QA/CI |

제품 마케팅 버전이 같아도 위 버전들이 같다는 뜻은 아니다. 반대로 catalog 스키마가 그대로인 내부 성능 개선은 마케팅 major 변경을 요구하지 않을 수 있다.

---

## 3. 기준선 manifest

### 3.1 목적

Windows v1의 목표를 `macOS v1.x` 또는 `main`으로 적는 것은 불충분하다. 태그는 이동하지 않더라도 태그가 참조한 자산, 외부 도구, 생성 결과가 빠지면 재현할 수 없다.

각 제품 기준선은 기계가 읽을 수 있는 하나의 manifest와 사람이 읽는 변경 설명을 함께 가진다. 파일명과 저장 위치는 Windows 저장소가 생길 때 결정하되, 논리 구조는 다음을 포함한다.

### 3.2 필수 식별자

```json
{
  "baselineFormat": 1,
  "productSpecVersion": "...",
  "macos": {
    "repository": "...",
    "commit": "full-commit-id",
    "dirty": false
  },
  "windows": {
    "repository": "...",
    "commit": "full-commit-id",
    "dirty": false
  },
  "schemas": {
    "catalog": 0,
    "sidecar": 0,
    "recipe": 0,
    "algorithm": 0,
    "nativeAbi": 0,
    "scannerProtocol": 0
  },
  "assets": {},
  "shaders": {},
  "toolchains": {},
  "conformance": {},
  "knownDifferences": []
}
```

이 예시는 계약 필드의 방향을 보여 주기 위한 설계 예시이며 현재 저장소에 존재하는 production manifest가 아니다.

### 3.3 자산 항목

각 자산 집합은 최소한 다음을 기록한다.

- 논리적 이름
- 자산 번들 버전
- 원본 위치와 정확한 소스 커밋
- 생성 도구 버전과 입력 버전
- 파일 목록 또는 canonical manifest 해시
- 각 파일의 cryptographic hash
- 라이선스와 provenance 레코드 위치
- 사람이 검토한 변경 사유

대상은 다음을 포함한다.

- film preset
- scanner profile
- camera/profile LUT
- 기본 export preset
- localization source
- test fixture와 expectation
- icon/font 등 제품 자산
- 플러그인별 device definition

Windows가 macOS 폴더를 수동으로 복사해 정본으로 삼지 않는다. 장기적으로는 플랫폼 중립적인 canonical asset source 또는 검증된 생성 산출물을 두 플랫폼이 소비한다. 전환 전에는 macOS 저장소가 임시 정본일 수 있지만, **정확한 커밋과 해시를 고정한 read-only 입력**으로만 사용한다.

### 3.4 셰이더 항목

- HLSL 소스 해시
- entry point와 profile
- DXC 정확한 버전
- 컴파일 옵션
- debug/release 구분
- 생성된 DXIL 해시
- reflection/리소스 binding manifest
- CPU reference 알고리즘 버전
- 승인한 numeric tolerance

DXC나 최적화 옵션을 바꾸는 것은 단순 빌드 도구 업데이트가 아니다. 부동소수점 결과와 드라이버 코드 생성에 영향을 줄 수 있으므로 전체 적합성 시험 대상이다.

### 3.5 도구 체인 항목

- Visual Studio/Build Tools servicing baseline
- MSVC toolset
- Windows SDK
- Windows App SDK stable release
- .NET SDK/runtime
- CMake와 Ninja
- vcpkg repository commit 또는 registry baseline
- NuGet lock 상태와 lock file hash
- WiX Toolset
- signing/timestamp 정책 버전
- 각 도구를 설치한 공식 채널

`latest`는 manifest 값이 될 수 없다. 자동 업데이트 정책을 사용하더라도 실제 릴리스 산출물은 해석 가능한 정확한 버전을 기록한다.

### 3.6 적합성 항목

- corpus 버전
- expectation 버전
- tolerance 정책 버전
- macOS 기준 결과 생성 build ID
- Windows CPU scalar 결과 build ID
- WARP 결과 build ID
- 물리 GPU/CPU/OS matrix 결과 링크
- 실패 면제와 만료일

### 3.7 알려진 차이 항목

차이는 자유 형식 메모가 아니라 다음 필드를 가진 레코드로 관리한다.

- 고유 ID
- 발견 날짜
- 영역
- 사용자에게 보이는 영향
- 분류: `intentional`, `temporary`, `defect`
- 허용한 이유
- 영향을 받는 플랫폼·아키텍처·장치
- 검출 시험
- 담당자
- 만료 또는 재검토 날짜
- 해결 릴리스

만료된 면제가 있는 build는 Stable 승격을 막는다.

---

## 4. 두 개의 개발선과 하나의 승격 절차

macOS 제품은 Windows 포팅 중에도 계속 발전한다. Windows가 움직이는 `main`을 매일 따라가면 포팅 완료 조건이 사라진다. 반대로 기준선을 한 번 고정하고 영원히 무시하면 출시 시점부터 낡는다.

따라서 다음 두 개발선을 명시한다.

### 4.1 제품 개발선

- macOS의 실제 제품 개발을 계속한다.
- 새 기능과 동작 변경은 평소의 제품 검증을 거친다.
- Windows에 영향을 줄 수 있는 변경에는 delta record를 만든다.
- 사양 변경과 macOS 구현 변경을 구분한다.

### 4.2 Windows 포팅 기준선

- 시작 시 exact commit과 자산 해시를 고정한다.
- 포팅 완료까지 기능 집합을 임의로 늘리지 않는다.
- 보안, 데이터 손실, 중대한 제품 결함 수정은 예외적으로 즉시 흡수한다.
- 그 외 변경은 delta backlog에 두고 다음 동기화 창에서 평가한다.

### 4.3 변경 승격 순서

모든 교차 플랫폼 변경은 다음 상태를 통과한다.

1. `observed` — macOS 또는 공통 사양의 변화가 발견됨
2. `classified` — 제품, UI, 수치, 데이터, 성능, 보안, 플랫폼 전용으로 분류
3. `spec-approved` — 두 플랫폼에서 기대하는 동작과 허용 차이가 결정됨
4. `macos-implemented` — 해당되는 macOS 구현과 시험 완료
5. `windows-implemented` — 해당되는 Windows 구현과 시험 완료
6. `conformance-passed` — 공통 적합성 및 플랫폼 matrix 통과
7. `release-approved` — 문서·배포·복구 준비 완료
8. `released` — 실제 채널 산출물과 manifest 기록

다음 상태도 허용하지만 사유와 재검토 날짜가 필요하다.

- `deferred`
- `platform-not-applicable`
- `rejected`
- `blocked-hardware`
- `blocked-license`

`macos-implemented`를 곧바로 `spec-approved`로 간주하지 않는다. 구현 실수 또는 플랫폼 편의가 제품 사양으로 굳어지는 것을 막기 위해서다.

---

## 5. Delta ledger

단순한 `반영/미반영` 체크박스로는 충분하지 않다. 각 delta는 다음을 기록한다.

| 필드 | 설명 |
|---|---|
| ID | 변경되지 않는 고유 ID |
| 발견 근거 | macOS 커밋, issue, incident, 연구 문서 |
| 기준선 전·후 | 영향을 받는 baseline |
| 분류 | 제품/UI/수치/데이터/보안/성능/스캐너/배포 |
| 사용자 영향 | 보이는 결과와 workflow 변화 |
| 데이터 영향 | schema/migration/rollback 영향 |
| 수치 영향 | 결과 차이와 tolerance 필요 여부 |
| 장치 영향 | CPU/GPU/scanner/OS 범위 |
| 플랫폼 상태 | macOS/Windows 각각의 구현·시험 상태 |
| 증거 | 시험 run, screenshot, numeric report, hardware log |
| 릴리스 | 최초 포함 버전과 channel |
| 소유자 | 결정·구현·QA 책임 |
| 만료일 | 임시 면제의 재검토 시점 |

### 5.1 자동 생성과 사람 판단

자동화할 수 있는 항목:

- 마지막 baseline 이후 바뀐 파일 목록
- resource bundle hash 차이
- schema 상수 차이
- shader manifest 차이
- 공개 API/ABI signature 차이
- conformance expectation 차이

사람이 판단해야 하는 항목:

- 변경이 제품 사양인지 구현 수정인지
- UI/UX 동등성을 깨는지
- 골든 갱신이 정당한지
- 사용자가 알아야 할 릴리스 노트인지
- 이전 recipe를 새 알고리즘으로 재해석할지

자동 diff가 비어 있다고 동작이 같다는 뜻은 아니다. 컴파일러, 드라이버, OS, 색 관리 런타임 변화도 기준선에 들어가야 한다.

---

## 6. 정본의 계층

### 6.1 가장 높은 정본

1. 명시적으로 승인된 제품 불변식
2. 버전이 붙은 공통 제품 사양
3. 데이터와 파일 포맷 계약
4. 적합성 fixture·expectation·tolerance
5. 플랫폼별 구현

구현이 사양과 다르면 구현이 자동으로 정본이 되지 않는다. 차이를 조사해 사양 또는 구현 중 하나를 명시적으로 수정한다.

### 6.2 플랫폼 중립 자산

다음은 가능한 한 하나의 canonical source에서 생성한다.

- scanner profile의 수치 데이터
- film preset과 기본값
- recipe 필드 정의
- localization source string ID와 의미
- 합성 fixture 정의
- 지원 format 식별자
- scanner protocol schema

플랫폼별 포맷 변환은 생성 단계다. `.strings`와 `.resw`를 각각 손으로 편집해 두 정본을 만들지 않는다.

### 6.3 플랫폼별로 독립 유지할 것

- SwiftUI/AppKit와 WinUI 3 화면 구현
- Core Image/Metal과 D3D11/Direct2D/C++ 엔진 구현
- macOS와 Windows의 파일 선택·보안·창 수명
- ColorSync와 WCS/ICC 연동
- Image Capture/SANE plugin과 WIA/TWAIN plugin
- notarization과 Authenticode/MSI 배포

동등성은 이 코드를 합치는 데서 나오지 않고, 같은 사양과 시험을 통과시키는 데서 나온다.

---

## 7. 호환성 정책

### 7.1 읽기와 쓰기 원칙

- 최신 앱은 지원 범위 안의 오래된 catalog/sidecar/recipe를 읽는다.
- 쓰기는 현재 스키마로만 한다.
- migration 전에는 사용자 복구가 가능한 backup을 만든다.
- migration은 중단·전원 손실 후 재시도 가능한 단계로 설계한다.
- 알 수 없는 미래 버전은 오래된 앱이 억지로 읽지 않고 명확히 거부한다.
- 알 수 없는 필드를 보존할 수 있는 포맷은 왕복 보존 여부를 계약에 적는다.
- 읽었다는 사실만으로 원본 URL, third-party XMP, source image를 다시 쓰지 않는다.

### 7.2 호환성 표

각 릴리스는 최소한 다음 표를 게시한다.

| 소비자 | 입력 버전 | 결과 |
|---|---|---|
| 현재 앱 | 현재 catalog | 완전 지원 |
| 현재 앱 | 지원 범위 내 과거 catalog | migration 후 지원 |
| 현재 앱 | 미래 catalog | fail closed |
| 과거 앱 | 현재 catalog | 지원하지 않음 또는 read-only 복구 경로 |
| 현재 코어 | 과거 plugin protocol | 정해진 compatibility window 내 지원 |
| 현재 코어 | 미래 plugin protocol | handshake에서 거부 |
| 현재 plugin | 과거 코어 protocol | plugin manifest에 명시 |

### 7.3 알고리즘과 recipe

recipe schema와 알고리즘 버전을 분리한다. 같은 필드 집합이라도 다음 변경은 알고리즘 버전 변경이 될 수 있다.

- blur edge mode
- grain noise 생성 방식과 seed
- grain 크기의 픽셀/물리 단위 해석
- curve 보간법
- 색공간 또는 transfer function
- reduce 순서
- clipping 위치
- 결함 검출 threshold 의미

기존 사진은 기본적으로 저장 당시 알고리즘 의미를 재현한다. 새 알고리즘으로 자동 재해석하려면 사용자 가치, 시각 변화, export 재현성, downgrade를 별도로 결정한다.

---

## 8. 적합성 시험 운영

### 8.1 시험 계층

| 계층 | 검증 대상 | 대표 판정 |
|---|---|---|
| 계약 | schema, enum, 기본값, capability | exact |
| 결정적 수치 | curve, matrix, 좌표, 경계 | exact 또는 매우 작은 오차 |
| CPU scalar | 모든 현상 단계의 기준 구현 | reference |
| CPU SIMD | x64/ARM64 최적화 | scalar 대비 오차 |
| WARP | GPU 셰이더의 재현 가능한 hosted 경로 | CPU 대비 오차 |
| 물리 GPU | Intel/NVIDIA/AMD/Qualcomm | vendor/driver matrix |
| 전체 workflow | import/scan→develop→export | 상태·파일·픽셀 |
| UI/UX | keyboard, focus, accessibility, layout | 실제 앱 관찰 |
| 장치 | scanner capability와 실물 ROI | 실기기 증거 |

WARP는 실제 GPU 드라이버 호환성 증거가 아니다. 물리 GPU 시험은 WARP 시험을 대체하지도 않는다. 둘의 실패 의미가 다르므로 함께 유지한다.

### 8.2 fixture 관리

- 합성 fixture를 우선한다.
- 실사진이 필요하면 재배포·CI 사용이 허용된 corpus만 넣는다.
- 사용자 라이브러리와 개인 사진을 fixture로 복사하지 않는다.
- profile 검증용 측정 파일은 장치, 타깃, 측정 조건, 권리 정보를 기록한다.
- scanner raw fixture는 장치 모델명만 아니라 장치 식별 정보, backend, mode, bit depth, resolution, ROI를 기록한다.
- 랜덤 효과는 명시적 seed와 절대 이미지 좌표를 사용한다.
- 타일 크기나 처리 순서에 따라 fixture 결과가 바뀌지 않아야 한다.

### 8.3 허용 오차 구조

하나의 전역 `epsilon`을 쓰지 않는다.

- 단계별 absolute/relative tolerance
- 채널별 허용 범위
- 최대 오차
- 평균 또는 percentile 오차
- 실패 픽셀 비율
- 구조적 결과의 decision tolerance
- 색 차이가 필요한 경우 명시한 색공간과 ΔE 방식

허용 오차는 현재 구현이 통과하도록 사후 확대하지 않는다. 각 값은 알고리즘 특성, 정밀도, 사용자 인지 영향에 근거한다.

### 8.4 골든 갱신 규칙

골든 변경 PR은 다음을 포함해야 한다.

1. 변경한 제품 사양 또는 결함 설명
2. 전·후 수치 요약
3. 대표 이미지의 전·후 시각 비교
4. macOS 결과
5. Windows CPU scalar 결과
6. Windows WARP 결과
7. 요구되는 물리 GPU 결과
8. 기존 catalog/recipe 재현 영향
9. tolerance 변경 여부와 이유
10. 승인자

`--update-goldens`를 실행한 결과 전체를 검토 없이 커밋하는 흐름은 금지한다.

---

## 9. 의존성과 도구 체인 유지보수

### 9.1 기본 정책

- production build는 stable/supported channel만 사용한다.
- preview/experimental은 별도 실험 branch와 CI에서만 평가한다.
- version range만 두고 릴리스 때 해석하게 하지 않는다.
- source package와 실제 binary 산출물의 hash를 기록한다.
- 직접 의존성과 전이 의존성을 모두 SBOM에 기록한다.
- 업데이트는 한 번에 한 축을 바꾸고 before/after 적합성을 비교한다.
- 보안 패치가 긴급해도 결과 차이, 설치, 복구를 생략하지 않는다.

### 9.2 .NET

2026-08-04 조사 스냅샷에서 .NET 10은 active LTS이며 공식 지원 종료는 2028-11-14로 표시된다. 공식 정책은 LTS가 3년 지원되고, 지원을 받으려면 해당 release line의 최신 patch 수준을 유지하도록 요구한다.

운영 규칙:

- Windows 앱의 기준 runtime은 선택한 LTS major와 정확한 SDK patch로 고정한다.
- 월별 patch를 자동 production 승격하지 않는다.
- patch 후보 build에서 UI, interop, trimming/self-contained packaging, crash dump, startup 성능을 검증한다.
- 지원 종료 180일 전까지 다음 LTS migration 결과를 확보한다.
- 지원 종료 90일 전에는 남은 blocker가 없는 release candidate를 만든다.
- manifest에는 `10`이 아니라 실제 SDK/runtime 버전과 설치 유형을 기록한다.

여기서 `.NET 10`은 기준일의 후보이지 영구 고정 사양이 아니다. Windows 구현 착수일과 첫 출시일에 지원 상태를 다시 확인한다.

### 9.3 Windows App SDK

Windows App SDK는 Stable, Preview, Experimental channel을 제공하며 production은 Stable만 사용한다. 공식 release servicing 표는 branch별 end-of-servicing 날짜가 짧을 수 있으므로, 앱 개발 완료 때까지 한 버전을 무기한 고정하는 전략은 안전하지 않다.

운영 규칙:

- 제품 기준선에는 major/minor/patch와 runtime 배포 방식을 함께 기록한다.
- self-contained 배포라도 SDK branch 자체의 보안·호환성 수명은 추적한다.
- end-of-servicing 180/90/30일 알림을 둔다.
- 새 Stable branch는 먼저 Beta에서 창 수명, XAML, 입력, 접근성, dispatcher, WebView 사용 여부, packaging을 검증한다.
- Preview/Experimental API에 production UX를 의존하지 않는다.
- branch migration은 UI visual regression과 실제 ARM64 실행을 포함한다.

2026-08-04의 공식 표에 표시된 구체 버전은 조사 시점 스냅샷일 뿐이다. 릴리스 전에 [Windows App SDK release channels](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-channels)와 [downloads](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads)를 다시 확인한다.

### 9.4 Windows와 지원 OS

`minimum OS`와 `Microsoft가 현재 servicing하는 OS`를 분리한다.

- minimum OS: 앱이 기술적으로 시작할 수 있는 최저 feature update
- tested OS: CI와 실기기에서 검증한 build/edition
- supported OS: 고객 지원과 결함 수정을 제공하는 범위
- current OS: Microsoft가 현재 보안 servicing하는 범위

2026-08-04 조사 기준으로 Windows 11 24H2는 Home/Pro 계열에서 2026-10-13, Enterprise/Education에서 2027-10-12에 end of updates로 표시된다. Windows 11은 Home/Pro 계열 24개월, Enterprise/Education 계열 36개월의 feature update servicing을 갖는다. 따라서 기존 설계의 `Windows 11 24H2`를 영구적인 단일 지원 기준으로 남기면 첫 출시 시점에 이미 일부 edition이 지원 종료 상태일 수 있다.

운영 규칙:

- 24H2가 API 기준선으로 유지될 수 있는지와 고객 지원 대상인지 별도로 결정한다.
- 일반 소비자용 제품이라면 Home/Pro end-of-servicing 전에 다음 일반 배포 feature update를 검증한다.
- 26H1은 공식 release information상 2026년 신형 장치용이며 기존 24H2/25H2 장치의 일반 in-place feature update가 아니므로, 자동으로 일반 기준선으로 삼지 않는다.
- LTSC를 일반 소비자 지원 기간을 늘리는 수단으로 간주하지 않는다.
- OS matrix는 x64와 ARM64, 최소 지원 build와 최신 누적 update를 포함한다.
- Microsoft 지원 종료 후에도 기술적으로 실행된다는 이유만으로 지원한다고 표현하지 않는다.

출시 승인 시 [Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)과 edition별 lifecycle을 다시 확인한다.

### 9.5 Visual Studio, MSVC, Windows SDK

Visual Studio/Build Tools, MSVC, Windows SDK는 하나의 뭉치가 아니다. 각각의 정확한 버전을 기록한다.

- 빌드 agent image 이름만 기록하지 않는다.
- CI 시작 시 resolved compiler, linker, SDK, CMake 버전을 artifact로 남긴다.
- Current 또는 유효한 servicing baseline을 선택한다.
- 지원이 끝난 LTSC를 재현성이라는 이유로 계속 production에 사용하지 않는다.
- compiler patch도 codegen·floating-point·PDB·sanitizer·linker 변화가 있을 수 있으므로 적합성 시험을 실행한다.
- Windows SDK 갱신 시 API availability와 minimum OS 선언을 함께 검토한다.
- x64 compiler 성공을 ARM64 compiler 성공으로 간주하지 않는다.

Visual Studio 공식 정책은 Community가 Current Channel 최신 servicing release만 지원되고, Enterprise/Professional/Build Tools는 제공되는 servicing channel 정책을 따른다고 설명한다. 팀이 실제 보유한 edition과 라이선스에 맞는 채널을 선택해야 한다.

### 9.6 vcpkg

vcpkg는 manifest mode를 사용하고 `builtin-baseline` 또는 명시한 registry baseline을 고정한다. 공식 문서상 versioning과 custom registries는 manifest mode에서 사용한다.

- `vcpkg.json`의 느슨한 dependency 이름만으로 재현성을 주장하지 않는다.
- vcpkg repository/registry commit을 기록한다.
- 필요한 경우 최소 버전과 `overrides`를 사용하되 이유를 남긴다.
- baseline 갱신 diff에 전이 의존성, feature, license, triplet 결과를 포함한다.
- x64-windows와 arm64-windows를 독립적으로 resolve·build·검증한다.
- custom triplet 또는 overlay port는 upstream과의 차이, owner, 제거 조건을 기록한다.
- binary cache artifact는 입력 manifest/baseline/triplet/toolchain과 결합한 key를 사용한다.
- 오래된 cache가 새 baseline 결과로 오인되지 않도록 provenance를 남긴다.

### 9.7 NuGet

- direct/transitive dependency를 lock file에 고정한다.
- CI와 release build는 locked mode로 해석한다.
- lock file 변경을 source change로 검토한다.
- Windows App SDK와 .NET runtime package의 호환 범위를 확인한다.
- 패키지 서명·source·license를 dependency inventory에 연결한다.
- restore source를 명시하고 예기치 않은 public/private feed 혼합을 막는다.

### 9.8 SBOM과 provenance

각 architecture의 release artifact는 별도 SBOM을 가진다.

- SPDX 등 선택한 형식과 버전을 고정한다.
- C++ 정적 라이브러리, NuGet, runtime, installer payload, plugin을 포함한다.
- 소스 저장소, 버전, license expression, package hash를 기록한다.
- 코어 앱 SBOM과 플러그인 SBOM을 분리하되 release manifest에서 연결한다.
- 생성 도구 자체도 pin하고 실행 버전을 기록한다.
- SBOM 생성 성공만으로 라이선스 준수 완료라고 판단하지 않는다.

Microsoft의 `sbom-tool`은 후보 생성 도구가 될 수 있지만, 도입 전 CMake/vcpkg/NuGet/WiX payload 포착 범위를 실제 산출물로 검증한다. 자세한 라이선스 결정은 [../13-build-and-deps/third-party-licenses.md](../13-build-and-deps/third-party-licenses.md)에서 관리한다.

---

## 10. GPU와 드라이버 유지보수

### 10.1 범용성 우선순위

1. CPU scalar reference
2. x64/ARM64 CPU 최적화
3. D3D11/Direct2D 공통 GPU 경로
4. WARP hosted 검증·fallback
5. 측정으로 정당화된 선택적 vendor 경로
6. NVIDIA 전용 CUDA는 가장 마지막의 선택적 가속 후보

CUDA availability가 제품 기능 availability를 결정해서는 안 된다. CUDA 경로가 추가되더라도 같은 recipe, 같은 edge behavior, 같은 color pipeline, 같은 failure semantics를 가져야 한다.

### 10.2 드라이버 matrix

각 Stable 릴리스는 최소 다음 축을 기록한다.

- Intel x64 integrated GPU
- Intel x64 discrete GPU가 제품 대상이면 별도
- AMD x64 integrated/discrete 대표
- NVIDIA x64 대표
- Qualcomm ARM64 GPU 대표
- Microsoft WARP
- GPU 비활성 CPU-only
- 각 장치의 adapter ID, driver version, OS build

한 제조사의 한 세대에서 통과한 결과를 같은 제조사 전체로 일반화하지 않는다.

### 10.3 드라이버 업데이트 triage

드라이버 회귀가 접수되면 다음 순서로 판별한다.

1. 같은 파일·recipe·app build 재현
2. GPU 경로와 CPU reference 비교
3. WARP와 비교
4. 이전 driver와 현재 driver 비교
5. debug layer/ETW/crash artifact 수집
6. adapter/driver 범위 축소
7. shader 또는 API 계약 위반인지 조사
8. quarantine, CPU fallback, app hotfix 중 선택

### 10.4 알려진 문제 정책

- 장치 차단은 모델명 문자열이 아니라 안정적인 adapter/driver 조건을 사용한다.
- remote blocklist가 필요하면 서명된 정책, 만료, offline behavior, privacy 범위를 먼저 설계한다.
- 전체 GPU를 영구 비활성화하지 않고 문제가 난 kernel/driver 범위를 최소화한다.
- quarantine은 telemetry 없이도 사용자 support bundle에서 설명 가능해야 한다.
- blocklist는 문제의 근본 수정 후 제거되는 임시 안전장치다.

---

## 11. 스캐너 플러그인의 독립 수명

### 11.1 릴리스 분리

다음은 각각 독립 버전을 가진다.

- Negaflow Windows 코어 앱
- WIA 플러그인
- TWAIN x64 플러그인
- TWAIN x86 adapter/bridge가 필요한 경우 해당 구성 요소
- 향후 제조사 SDK 플러그인

코어 앱 업데이트가 사용자가 별도로 설치한 GPL 또는 third-party scanner plugin을 묵시적으로 덮어쓰지 않는다.

### 11.2 프로토콜 compatibility window

handshake는 최소 다음을 교환한다.

- protocol major/minor
- plugin package ID와 version
- process architecture
- supported commands
- capability schema version
- optional feature flags
- max message/artifact constraints
- cancellation 지원

규칙:

- major 불일치는 명확히 거부한다.
- minor 확장은 feature negotiation으로 처리한다.
- 알 수 없는 command/field의 처리 정책을 schema에 정의한다.
- capability가 없으면 UI를 숨기거나 지원하지 않음을 명확히 표시한다.
- timeout·취소·pipe cleanup·process termination을 release gate로 시험한다.

### 11.3 장치 matrix 유지

지원 표는 다음 네 수준을 구분한다.

1. USB/OS에서 장치가 보임
2. backend가 장치를 열고 capability를 보고함
3. 자동화된 virtual/fixture 계약 통과
4. 지정한 필름 홀더와 ROI로 실물 스캔 검증

`지원` 표시는 필요한 수준을 충족한 장치에만 붙인다. IR, multi-frame, exposure, bit depth, transparency unit은 각각 별도 증거가 필요하다.

### 11.4 라이선스와 보안

- 플러그인별 소스·binary·license notice를 독립 추적한다.
- 코어와 플러그인 간 파일 전달 경로를 검증한다.
- plugin executable과 manifest 서명을 검증한다.
- untrusted stdout/stderr와 JSON 크기를 제한한다.
- 임시 scan artifact의 owner, cleanup, crash recovery를 시험한다.
- vendor driver license가 재배포를 허용하는지 별도로 확인한다.

자세한 경계는 [../10-scanner/plugin-architecture.md](../10-scanner/plugin-architecture.md), [../10-scanner/protocol-contract.md](../10-scanner/protocol-contract.md), [../10-scanner/plugin-security-and-lifecycle.md](../10-scanner/plugin-security-and-lifecycle.md)를 따른다.

---

## 12. 데이터 migration과 rollback

### 12.1 배포 rollback과 데이터 rollback 분리

- 앱 binary rollback: 이전 서명된 설치 파일로 돌아감
- 설정 rollback: 앱 설정의 이전 snapshot 복구
- catalog recovery: backup 또는 journal을 이용한 명시적 복구
- recipe migration reversal: 변환이 가역적이라고 증명된 경우에만 수행
- source file: rollback 대상이 아니라 불변 원본

업데이트 실패 때문에 앱 binary가 이전 버전으로 돌아갔다고 해서 새 버전이 이미 migration한 catalog를 이전 앱이 안전하게 열 수 있는 것은 아니다.

### 12.2 migration release gate

- 과거 지원 버전별 fixture catalog
- 큰 catalog와 긴 경로
- 중복/누락 source
- 읽기 전용 위치
- 디스크 부족
- migration 중 강제 종료
- 재시작 후 재개 또는 안전 rollback
- backup 검증
- ARM64와 x64 결과
- downgrade 시 사용자 메시지

### 12.3 데이터 보존 기간

- 자동 backup 보존 개수와 용량 한도를 제품 정책으로 정한다.
- cache는 재생성 가능 여부에 따라 삭제 우선순위를 정한다.
- source와 app-owned derivative를 경로 이름만으로 구분하지 않는다.
- catalog 손상 또는 부재를 빈 catalog로 해석해 orphan을 삭제하지 않는다.
- support bundle은 원본 사진을 기본 포함하지 않는다.

---

## 13. 릴리스 채널과 승격

### 13.1 채널

| 채널 | 대상 | 허용 조건 |
|---|---|---|
| Development | 내부 개발 | 진단 도구와 미완료 migration 허용, 사용자 데이터와 분리 |
| Beta | 명시적 참여자 | 서명, 업데이트 복구, known issues, telemetry/privacy 결정 완료 |
| Stable | 일반 사용자 | 모든 필수 gate, architecture parity, 지원 수명 충족 |

Preview Windows SDK나 실험 GPU 경로는 앱 Stable 채널에 섞지 않는다. 기능 자체의 experiment flag와 배포 채널을 구분한다.

### 13.2 Architecture parity

x64와 ARM64가 같은 날짜에 같은 마케팅 버전을 가질 수 있으려면 다음이 같아야 한다.

- 제품 사양
- 자산 번들
- recipe와 catalog 호환성
- 기능 목록
- update feed 정책
- release note

성능 수치와 일부 장치 지원은 다를 수 있지만 알려진 차이로 기록한다. ARM64 artifact가 늦으면 x64와 같은 버전을 가졌다고 가장하지 않고 channel/availability를 명시한다.

### 13.3 Stable 승격 gate

- exact clean commits
- baseline manifest 완성
- dependency lock과 SBOM
- x64/ARM64 release build
- signature와 timestamp 검증
- installer clean install/update/repair/uninstall
- CPU scalar/SIMD/WARP 적합성
- 물리 GPU matrix
- catalog migration/recovery
- 실제 WinUI 3 주요 workflow QA
- 접근성·키보드·고 DPI·다중 모니터
- 스캐너 plugin 없는 상태
- 지원을 주장하는 실제 scanner matrix
- update feed와 rollback rehearsal
- release note와 known differences

---

## 14. 보안 취약점 대응

### 14.1 입력

- OS와 Microsoft runtime security advisory
- NuGet/vcpkg/upstream advisory
- scanner vendor driver 공지
- code-signing certificate 상태
- crash/support report
- dependency scanning
- 연구자 또는 사용자 제보

### 14.2 triage

CVSS 숫자만으로 patch 우선순위를 정하지 않는다.

- Negaflow가 취약 코드를 실제로 포함하는가?
- 공격자가 접근 가능한 입력 경로인가?
- 사진, ICC, TIFF/RAW, plugin JSON, installer/update metadata 중 어디인가?
- sandbox 밖 파일 쓰기 또는 code execution이 가능한가?
- 플러그인 프로세스 경계가 영향을 제한하는가?
- x64/ARM64 중 어느 artifact가 영향받는가?
- mitigation이 있는가?
- 사용자 데이터 기밀성·무결성·가용성 영향은 무엇인가?

### 14.3 대응 단계

1. 영향받는 exact artifact와 dependency 식별
2. exploitability 확인
3. 배포 중지 또는 feed 차단 필요성 결정
4. 최소 patch와 dependency update
5. 보안 재현 시험과 전체 회귀
6. 새 SBOM·manifest·서명 산출
7. 채널 승격
8. 필요 시 사용자 안내와 취약 artifact 철회
9. root cause와 재발 방지 기록

고정된 시간 SLA는 운영 인력과 배포 체계가 정해진 뒤 별도 정책으로 승인한다. 이 문서에서 근거 없이 숫자를 약속하지 않는다.

---

## 15. 관측성과 support bundle

### 15.1 기본 원칙

- 진단은 opt-in 또는 명확한 privacy 정책을 따른다.
- 사진 픽셀, 파일명, 전체 경로, 개인 catalog 내용을 기본 수집하지 않는다.
- crash dump와 GPU/driver 정보의 민감도를 문서화한다.
- 사용자에게 생성되는 support bundle의 내용을 미리 보여 준다.
- 수집하지 않은 데이터가 있는 것처럼 원격 진단 능력을 주장하지 않는다.

### 15.2 support bundle 권장 항목

- 앱·빌드·baseline 식별자
- OS edition/build/architecture
- CPU architecture와 feature tier
- GPU adapter ID, driver, 선택된 경로, fallback 이유
- Windows App SDK/.NET runtime
- asset/shader pack 버전
- catalog/recipe schema 버전만, 내용 제외
- scanner plugin ID/version/protocol/capability summary
- 최근 bounded structured logs
- crash/hang artifact에 대한 사용자 선택
- installer/update transaction 상태

### 15.3 로그 안정성

- 이벤트 이름과 필드에도 schema version을 둔다.
- 자유 형식 로그 파싱에 운영 판단을 의존하지 않는다.
- path와 사용자 문자열을 redaction한다.
- 반복 오류로 디스크가 차지 않게 크기와 보존 기간을 제한한다.
- 로그가 꺼져 있어도 사용자에게 유용한 오류 메시지를 제공한다.

---

## 16. 성능 회귀 예산

성능 목표는 `빠르다`가 아니라 장치 tier, fixture, 작업, 측정 방식이 있는 숫자로 관리한다.

### 16.1 핵심 지표

- 앱 cold/warm start
- library 첫 표시와 scroll
- 사진 첫 decode
- Develop 첫 유효 preview
- 조정 입력부터 화면 반영까지 latency
- 100% zoom pan/frame pacing
- peak working set와 GPU memory
- single export와 batch throughput
- first-file preparation 시간
- progress 최초 갱신 시간
- scanner discovery/preview/full scan
- update install/rollback 시간

### 16.2 비교 규칙

- 동일한 fixture와 장치 전원 정책
- warm-up 포함 여부 명시
- median과 tail percentile
- CPU/GPU/driver/OS/build 기록
- UI 응답성과 총 처리량을 분리
- 품질, DPI, ICC, 출력 해상도를 낮춰 얻은 속도는 같은 지표로 비교하지 않음
- compiler/runtime update 전후를 별도 run으로 보존

### 16.3 gate

- 작은 변동은 trend로 관찰한다.
- 승인 임계값을 넘는 회귀는 원인·사용자 영향·예외 만료일이 없으면 Stable을 막는다.
- 평균 개선이 tail 악화를 숨기지 않게 한다.
- x64 개선이 ARM64 회귀를 상쇄하지 않는다.
- 한 GPU vendor 개선이 다른 vendor 결함을 상쇄하지 않는다.

구체 도구와 측정은 [../12-performance/profiling-tools.md](../12-performance/profiling-tools.md), CI matrix는 [../12-performance/ci-and-testing.md](../12-performance/ci-and-testing.md)를 따른다.

---

## 17. 문서 자체의 유지보수

### 17.1 문서 metadata

시간에 민감한 문서는 다음을 가진다.

- 상태: 결정/후보/조사/폐기
- 기준일
- 적용 baseline
- owner
- 다음 검토일
- 공식 근거 링크
- 코드 근거 경로와 commit

현재 `windows_docs/`는 구현 전 설계 자료이므로 존재하지 않는 Windows 파일을 현재 구현처럼 표현하지 않는다. 예시 경로와 제안 API는 `proposed`임을 표시한다.

### 17.2 자동 점검

- 내부 Markdown link
- 중복되거나 충돌하는 결정 ID
- `TODO`, `미정`, `후속 조사` 목록
- end-of-support 날짜가 지난 dependency/OS
- 존재하지 않는 코드 경로
- 오래된 baseline commit
- 같은 용어의 상충 정의
- MSIX와 MSI처럼 폐기·보류된 배포 전제
- `main`, `latest`, `current`만 적힌 재현 불가능한 기준

### 17.3 결정과 조사 분리

- 결정 register: 현재 채택한 방향과 변경 이력
- open questions: 아직 결정하지 않은 쟁점과 결정 기한
- research note: 조사 당시의 사실과 링크
- implementation guide: 채택한 결정을 구현하는 방법
- validation plan: 완료를 증명하는 방법

새 조사 결과가 나왔다고 결정문을 조용히 덮어쓰지 않는다. 기존 결정의 상태를 `superseded`로 바꾸고 새 결정과 근거를 연결한다.

### 17.4 공개 문서로 승격

Windows 구현 시작 전에는 `windows_docs/`가 로컬 설계 공간일 수 있다. 구현이 시작되면 다음을 공개 저장소의 내구성 있는 문서로 옮긴다.

- 제품 불변식
- 파일·recipe·catalog schema
- scanner protocol
- baseline manifest 형식
- build/release 재현 절차
- 라이선스와 third-party notice 생성 절차
- 적합성 시험 계약

개인 로컬 경로나 특정 작업 세션 상태는 공개 사양에 넣지 않는다.

---

## 18. 사고 대응과 사후 분석

### 18.1 즉시 조치

- 영향받는 channel과 architecture를 식별한다.
- 추가 배포를 중지할지 판단한다.
- update metadata와 installer artifact를 보존한다.
- 사용자 데이터에 손상이 의심되면 자동 cleanup/migration을 중지한다.
- 재현 가능한 source/build/driver/OS 조합을 고정한다.

### 18.2 복구 선택

- 같은 버전 hotfix
- 이전 binary로 deployment rollback
- GPU kernel quarantine와 CPU fallback
- 문제 plugin만 비활성·철회
- update feed metadata 수정
- catalog recovery 도구 제공

어떤 선택도 사용자 catalog를 암묵적으로 downgrade하지 않는다.

### 18.3 사후 분석 필수 항목

- 사용자에게 발생한 실제 영향
- 최초 유입 변경과 놓친 gate
- 발견부터 완화까지 timeline
- 왜 기존 시험이 잡지 못했는지
- 재현 fixture
- 단기 완화와 영구 수정
- 문서·matrix·monitoring 변경
- owner와 완료 증거

`사람이 실수했다`를 root cause로 끝내지 않는다. 같은 실수가 release artifact에 도달한 시스템 조건을 찾는다.

---

## 19. 폐기와 지원 종료

### 19.1 폐기 대상

- 오래된 Windows feature update
- 지원 종료 .NET/Windows App SDK branch
- 구형 scanner protocol major
- 사용되지 않는 recipe algorithm version
- 알려진 취약 dependency
- 실기기 증거를 유지할 수 없는 scanner plugin
- 더 이상 서명·업데이트할 수 없는 배포 channel

### 19.2 폐기 절차

1. 사용 현황과 데이터 호환성 확인
2. 대체 경로 제공
3. Beta에서 경고
4. Stable release note와 앱 내 안내
5. 마지막 읽기/migration 지원 버전 지정
6. 지원 종료일 도달
7. 코드·시험·문서 제거는 별도 변경으로 수행
8. 오래된 artifact와 source provenance 보존

실행 경로를 제거하는 것과 과거 파일을 읽는 능력을 제거하는 것은 별도 결정이다.

---

## 20. 운영 주기

### 매 변경

- delta 분류
- 영향받는 version axis 확인
- 관련 문서·시험 수정
- exact baseline 입력 기록
- 플랫폼별 상태 갱신

### 매주

- 새 macOS delta triage
- Windows parity blocker 검토
- dependency/security 알림 triage
- flaky/disabled test와 만료 예정 면제 확인
- 실제 hardware lab 실패 확인

### 매월

- .NET/Windows/App SDK servicing 검토
- vcpkg/NuGet upstream·license·advisory 검토
- Windows 누적 update와 GPU driver smoke
- support bundle에서 반복되는 장치/성능 문제 분류
- 문서 link와 stale-date 검사

### 분기 또는 기능 단위

- 전체 x64/ARM64 CPU/GPU matrix
- 주요 WinUI 3 workflow 수동 QA
- scanner hardware matrix 순환 검증
- catalog migration/recovery rehearsal
- installer update/rollback rehearsal
- performance baseline 재측정
- known differences 재승인 또는 제거

### 릴리스 전

- 기준선 freeze
- dependency와 lifecycle 최신 확인
- 전체 conformance
- license/SBOM/provenance
- 서명·timestamp·설치·업데이트 검증
- 데이터 recovery 검증
- release note와 지원 matrix 확정

---

## 21. 역할과 책임

한 사람이 여러 역할을 맡더라도 승인 책임을 구분해 기록한다.

| 역할 | 책임 |
|---|---|
| 제품 사양 소유자 | 두 플랫폼의 기대 동작과 의도된 차이 승인 |
| macOS 구현 소유자 | macOS 변경과 delta 제출 |
| Windows 구현 소유자 | WinUI/C++ 구현과 platform evidence |
| 이미지 품질 소유자 | 수치 tolerance와 골든 변경 승인 |
| 데이터 소유자 | schema, migration, backup, recovery |
| 스캐너 소유자 | protocol, plugin, capability, 실기기 matrix |
| 릴리스 소유자 | baseline, artifact, 서명, update/rollback |
| 라이선스 소유자 | dependency/plugin provenance와 notices |
| QA 소유자 | 자동·수동·실장치 증거의 완결성 |

동일 인물이 구현과 승인을 모두 하면 최소한 별도의 시간에 checklist와 artifact를 다시 검토한다. `내 컴퓨터에서 됨`은 독립 검토를 대체하지 않는다.

---

## 22. 금지할 유지보수 패턴

- `macOS 최신 버전과 같음`만 적기
- moving `main`을 기준선으로 사용하기
- product version 하나로 모든 호환성을 판단하기
- Windows 자산을 수동 복사한 뒤 독립 수정하기
- macOS 픽셀을 항상 정답으로 간주하고 사양 변경을 생략하기
- 골든 실패를 해결하려고 tolerance를 일괄 확대하기
- compiler/runtime/dependency를 한 PR에서 대량 갱신하기
- WARP 통과를 물리 GPU 호환성으로 표현하기
- NVIDIA 성공을 Windows GPU 성공으로 일반화하기
- x64 성공을 ARM64 성공으로 일반화하기
- CUDA 구현을 공통 기능의 필수 조건으로 만들기
- driver 문제를 무조건 제조사 탓으로 돌리고 API 계약을 조사하지 않기
- 코어 앱 업데이트로 third-party plugin을 덮어쓰기
- plugin을 설치하지 않은 상태를 시험하지 않기
- binary rollback이 data rollback도 해결한다고 가정하기
- 손상된 catalog를 빈 catalog로 간주하기
- support bundle에 사진·전체 경로를 무단 포함하기
- 지원 종료된 SDK를 재현성을 이유로 영구 고정하기
- Preview/Experimental SDK를 Stable 제품 기반으로 삼기
- SBOM 생성만으로 license 검토를 완료했다고 하기
- 자동화 build 통과를 실제 UI·scanner·GPU QA로 표현하기
- 임시 예외에 owner와 만료일을 두지 않기
- 오래된 문서의 버전 숫자를 현재 사실처럼 인용하기

---

## 23. 구현 착수 시 만들어야 할 운영 산출물

다음 이름은 제안이며 Windows 저장소 구조에 맞춰 확정한다.

```text
governance/
  product-spec/
  decisions/
  deltas/
  baselines/
  known-differences/
  lifecycle/

conformance/
  fixtures/
  expectations/
  tolerances/
  manifests/

dependencies/
  licenses/
  notices/
  sbom/

validation/
  os-matrix/
  gpu-matrix/
  scanner-matrix/
  performance/
  release-evidence/
```

필수 파일의 논리 역할:

- 현재 제품 사양 버전
- macOS↔Windows baseline mapping
- delta ledger
- schema/ABI/protocol compatibility matrix
- dependency lifecycle calendar
- hardware lab inventory와 최근 검증일
- known differences와 만료일
- release evidence index
- incident/postmortem index

이 구조를 빈 폴더와 placeholder로 한꺼번에 만들 필요는 없다. 첫 구현 단계에서 실제 consumer가 생기는 순서로 추가한다.

---

## 24. 릴리스 전 유지보수 체크리스트

### 기준선

- [ ] macOS와 Windows exact clean commit을 기록했다.
- [ ] 제품 사양 버전을 기록했다.
- [ ] 모든 schema/ABI/protocol 버전을 기록했다.
- [ ] 자산과 셰이더 hash를 기록했다.
- [ ] 도구 체인과 dependency lock을 기록했다.
- [ ] known difference에 owner와 만료일이 있다.

### 플랫폼 동등성

- [ ] CPU scalar 기준 결과가 통과했다.
- [ ] x64 SIMD가 scalar와 허용 오차 내 일치한다.
- [ ] ARM64 SIMD가 scalar와 허용 오차 내 일치한다.
- [ ] WARP가 hosted 셰이더 검증을 통과했다.
- [ ] Intel/NVIDIA/AMD/Qualcomm 요구 matrix를 실기기에서 확인했다.
- [ ] 미리보기와 내보내기 의미가 일치한다.
- [ ] WinUI 3 주요 workflow를 실제로 조작했다.

### 데이터

- [ ] 지원하는 과거 catalog migration을 검증했다.
- [ ] 전원 손실·디스크 부족·중단 복구를 검증했다.
- [ ] downgrade 메시지와 recovery 경로를 확인했다.
- [ ] 원본과 third-party sidecar가 변경되지 않음을 확인했다.
- [ ] export 재구성 실패가 눈에 보이게 실패한다.

### 스캐너

- [ ] plugin 없는 상태에서 코어 앱이 정상 동작한다.
- [ ] protocol major/minor handshake를 검증했다.
- [ ] timeout·취소·process cleanup을 검증했다.
- [ ] UI가 capability만 노출한다.
- [ ] 지원을 주장하는 장치/format/ROI를 실기기로 검증했다.
- [ ] plugin별 서명·license·SBOM을 확인했다.

### 배포와 수명

- [ ] 지원 중인 Windows edition/build에서 시험했다.
- [ ] .NET과 Windows App SDK가 지원 중이며 최신 승인 patch다.
- [ ] Build Tools/MSVC/Windows SDK 지원 상태를 확인했다.
- [ ] x64/ARM64 installer를 각각 검증했다.
- [ ] signature와 timestamp를 검증했다.
- [ ] update/repair/uninstall/rollback을 rehearsal했다.
- [ ] architecture별 SBOM과 notices를 생성·검토했다.

---

## 25. 첫 Windows 구현 전 즉시 결정할 항목

1. baseline manifest의 실제 저장소와 schema owner
2. Windows v1이 기준으로 삼을 exact macOS commit
3. 공통 제품 사양을 어느 공개 위치에서 관리할지
4. canonical preset/profile/localization 자산 생성 방식
5. catalog/recipe/algorithm version의 초기 번호와 migration 규칙
6. native ABI와 scanner protocol compatibility window
7. 출시 시점의 minimum/tested/supported Windows matrix
8. 출시 시점의 지원 중인 .NET LTS와 Windows App SDK Stable branch
9. 실제 x64/ARM64, Intel/NVIDIA/AMD/Qualcomm hardware lab 구성
10. SBOM·license notice 생성과 승인 책임
11. Stable/Beta feed의 서명 key와 emergency rollback 권한
12. 사용자 데이터가 포함되지 않는 support bundle 정책

특히 `Windows 11 24H2`는 2026-08-04 기준 이미 Home/Pro end-of-servicing가 약 두 달 남은 상태이므로, 첫 출시 기준을 결정할 때 반드시 다시 검토한다.

---

## 26. 관련 문서

- [product-invariants.md](product-invariants.md)
- [baseline-manifest.md](baseline-manifest.md)
- [decision-register.md](../00-overview/decision-register.md)
- [open-questions.md](open-questions.md)
- [../12-performance/ci-and-testing.md](../12-performance/ci-and-testing.md)
- [../12-performance/profiling-tools.md](../12-performance/profiling-tools.md)
- [../13-build-and-deps/vcpkg-cmake.md](../13-build-and-deps/vcpkg-cmake.md)
- [../13-build-and-deps/third-party-licenses.md](../13-build-and-deps/third-party-licenses.md)
- [../10-scanner/plugin-architecture.md](../10-scanner/plugin-architecture.md)
- [../10-scanner/protocol-contract.md](../10-scanner/protocol-contract.md)
- [../10-scanner/plugin-security-and-lifecycle.md](../10-scanner/plugin-security-and-lifecycle.md)
- [../10-scanner/hardware-validation-matrix.md](../10-scanner/hardware-validation-matrix.md)
- [../11-distribution/deployment-channels.md](../11-distribution/deployment-channels.md)
- [../11-distribution/update-and-rollback.md](../11-distribution/update-and-rollback.md)
- [../16-cpu/simd-and-dispatch.md](../16-cpu/simd-and-dispatch.md)

---

## 27. 공식 근거

아래 링크의 버전과 날짜는 시간이 지나면 바뀐다. release baseline을 만들 때 다시 확인한다.

- [.NET Support Policy](https://dotnet.microsoft.com/en-us/platform/support/policy)
- [.NET and .NET Core official support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core)
- [Windows App SDK release channels](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-channels)
- [Windows App SDK downloads](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads)
- [Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)
- [Windows 11 Home and Pro lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-home-and-pro)
- [Windows 11 Enterprise and Education lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-enterprise-and-education)
- [Lifecycle FAQ — Windows](https://learn.microsoft.com/en-us/lifecycle/faq/windows)
- [Visual Studio 2022 product lifecycle and servicing](https://learn.microsoft.com/en-us/visualstudio/releases/2022/servicing-vs2022)
- [vcpkg manifest mode](https://learn.microsoft.com/en-us/vcpkg/concepts/manifest-mode)
- [vcpkg versioning reference](https://learn.microsoft.com/en-us/vcpkg/users/versioning)
- [Microsoft sbom-tool](https://github.com/microsoft/sbom-tool)

---

## 28. 완료 정의

장기 유지보수 체계가 준비됐다고 말하려면 문서만 존재해서는 안 된다. 다음 증거가 모두 있어야 한다.

- 한 릴리스를 exact source·asset·schema·shader·toolchain으로 재현할 수 있다.
- macOS 변경 하나가 delta ledger를 거쳐 Windows 적합성 결과까지 추적된다.
- 같은 recipe의 양쪽 결과 차이를 자동 보고하고 사람이 승인할 수 있다.
- x64와 ARM64, CPU와 주요 GPU vendor의 결과가 독립적으로 보인다.
- plugin을 코어와 별도로 업데이트·철회·감사할 수 있다.
- catalog migration 실패를 데이터 손실 없이 복구할 수 있다.
- 지원 종료가 다가오는 OS/runtime/SDK가 출시 직전에 발견되지 않는다.
- 골든 변경, 예외, known difference에 근거·owner·만료가 있다.
- 실제 UI·GPU·scanner 검증과 자동화 검증을 서로 바꿔 말하지 않는다.

이 상태가 되어야 macOS와 Windows가 독립적인 네이티브 제품이면서도 하나의 Negaflow 경험으로 장기 운영될 수 있다.
