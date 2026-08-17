> # ☠️ 하드코딩 · 가짜 구현 · 창작 · 병신 백엔드 · 병신 프론트엔드 = 죽음 ☠️
>
> **🔬 추측·가설 금지.** "냄새난다" 고 덮지 말고 **냄새의 원인을 찾아 없애십시오.**
> **🌐 모르면 웹 검색을 적극적으로** 하십시오 — 특히 GPU·최적화·UI/UX 구현.
> 규칙 [`00-index.md`](00-index.md)

---

> # ⛔⛔⛔ 저장소 · 라이선스 — 어기면 프로젝트가 죽습니다 ⛔⛔⛔
>
> # 1. **macOS 코드는 절대 건드리지 마십시오.**
>
> ## 두 저장소 **모두** 해당합니다.
>
> | 절대 쓰지 않는 곳 |
> |---|
> | `C:\Users\habin\negaflow\negaflow-mac\` |
> | `C:\Users\habin\negaflow-scanner-sane\negaflow-mac\` |
>
> **읽는 것은 자유. 쓰는 것은 절대 금지.** macOS 앱은 **완성돼 있고 정답**입니다.
> Windows 를 macOS 에 맞추는 것이지, macOS 를 Windows 에 맞추는 것이 아닙니다.
> macOS 파일이 한 글자라도 바뀌면 **기준 자체가 사라집니다.**
>
> ---
>
> # 2. **라이선스 · 특허 · 저작권 — 파쿠리 금지**
>
> ## negaflow = **Apache License 2.0**
> ## negaflow-scanner-sane = **GPL** (그래서 별도 프로세스 플러그인입니다)
>
> ### 절대 하지 말 것
>
> - **다른 프로젝트 코드를 베껴 오지 마십시오.** 한 줄도 안 됩니다.
>   Lightroom · Capture One · Negative Lab Pro · darktable · RawTherapee · GIMP ·
>   VueScan · SilverFast — **소스도 디컴파일도 참고 붙여넣기도 금지.**
> - **GPL/LGPL/AGPL 코드를 negaflow 본체에 넣지 마십시오.**
>   Apache 2.0 과 섞이면 **배포가 불가능해집니다.** 그래서 SANE 을 별도 저장소·
>   **별도 프로세스**로 뗀 것입니다 — 그 경계를 무너뜨리지 마십시오.
> - **특허 있는 알고리즘을 확인 없이 넣지 마십시오.**
> - **출처 없는 상수표·LUT·프로파일을 넣지 마십시오.** 측정해서 만들고
>   측정 근거를 문서에 남기십시오(예: `muted_scene_vibrance_table.cpp` 는
>   `docs/verification/macos-golden/vibrance/` 에 golden 해시가 있습니다).
> - **아이콘·글꼴·이미지도 라이선스를 봅니다.** SF Symbols 는 Apple 라이선스라
>   **그림을 그대로 쓸 수 없습니다** — 같은 뜻의 아이콘을 직접 그리십시오.
>
> ### 반드시 할 것
>
> - 새 의존성을 넣기 전에 **라이선스를 확인**하고 `THIRD_PARTY_NOTICES.md` 에 적으십시오.
> - macOS 에서 옮긴 코드는 **주석에 원본 Swift 심볼 이름**을 적으십시오
>   (같은 프로젝트 안이라 문제 없지만, 어디서 왔는지 추적 가능해야 합니다).
> - 헷갈리면 **넣지 말고 물어보십시오.**

---

# 12 — 저장소 구조와 라이선스

---

## 1. 저장소 두 개

### 1.1 `C:\Users\habin\negaflow\` — 본체 (**Apache License 2.0**)

```
C:\Users\habin\negaflow\
├── LICENSE                  Apache License 2.0
├── NOTICE
├── negaflow-mac\            ← macOS 원본 (Swift). 정답. 절대 고치지 말 것
│   ├── Sources\Chromabase\      엔진 159파일
│   ├── Sources\negaflowApp\     앱 529파일
│   └── Sources\ScannerKit\      스캐너 클라이언트 50파일
├── negaflow-windows\        ← Windows 판. 여기를 고칩니다
│   ├── src\Native\              C++ 엔진
│   ├── src\Shell.Core\          C# 로직
│   ├── src\Shell\               WinUI 3 화면
│   ├── src\Catalog.Core\        카탈로그
│   ├── src\Interop\             P/Invoke
│   └── docs\audit\              ← 이 문서
└── negaflow_mac_screenshot\ ← macOS 실행 화면 84장 (라이브러리 43·현상 24·인화 17)
```

### 1.2 `C:\Users\habin\negaflow-scanner-sane\` — 스캐너 플러그인 (**GPL**)

```
C:\Users\habin\negaflow-scanner-sane\
├── LICENSE                  GNU General Public License
├── COPYING
├── PROVENANCE.md            ← 코드 출처 기록
├── THIRD_PARTY_NOTICES.md
├── negaflow-mac\            ← macOS 플러그인. 절대 고치지 말 것
└── negaflow-windows\        ← Windows 플러그인
```

---

## 2. 왜 스캐너를 뗐나 — **라이선스 때문입니다**

| | negaflow 본체 | 스캐너 플러그인 |
|---|---|---|
| 라이선스 | **Apache License 2.0** | **GPL** |
| 섞을 수 있나 | — | **불가** |
| 어떻게 잇나 | **별도 프로세스 + 프로토콜** | 〃 |

SANE 은 GPL 입니다. GPL 코드를 Apache 2.0 본체에 **링크하면 본체까지 GPL 이 되어**
지금의 배포 방식이 무너집니다. 그래서:

- 스캐너는 **별도 저장소**에 있고
- **별도 실행 파일(별도 프로세스)** 로 돌고
- 본체와는 **프로토콜로만** 이야기합니다
  (`src/Shell.Core/Scanner/ScannerPluginProtocol.cs` · `ScannerPluginProcessHost.cs` ·
  `ScannerPluginDiscovery.cs` · `ScannerPluginTrustStore.cs`)

**이 경계를 무너뜨리지 마십시오.** SANE 헤더 하나, GPL 소스 한 줄도 본체에 들어가면 안 됩니다.
편하다고 본체에 직접 링크하면 **프로젝트를 배포할 수 없게 됩니다.**

---

## 3. macOS 코드를 고치면 안 되는 이유

1. **정답이 사라집니다.** 이 이식의 유일한 기준입니다. Windows 가 틀렸을 때
   "macOS 를 고치면 맞아진다" 는 유혹이 생기는데, 그러면 **비교할 대상이 없어집니다.**
2. **macOS 앱은 완성돼 있고 사용자가 쓰고 있습니다.** 건드리면 되던 것이 깨집니다.
3. **되돌린 30회의 원인이 전부 "Windows 를 macOS 에 맞추지 않은 것"** 입니다.
   반대 방향으로 맞추면 그 30회가 되풀이됩니다.

**읽기: 자유. 쓰기: 절대 금지.** 두 저장소 다 마찬가지입니다.

---

## 4. 코드 출처 규칙

| 상황 | 해야 할 것 |
|---|---|
| macOS negaflow 에서 옮김 | 주석에 원본 Swift 심볼 이름 |
| 새 라이브러리 추가 | 라이선스 확인 + `THIRD_PARTY_NOTICES.md` 기록 |
| 알고리즘을 논문·표준에서 가져옴 | 출처를 주석에 (예: Fritsch–Carlson PCHIP) |
| 값·LUT 를 측정해서 만듦 | 측정 방법과 golden 해시를 `docs/verification/` 에 |
| 다른 앱 코드 | **금지** |
| GPL 코드를 본체에 | **금지** |
| SF Symbols 그림 그대로 | **금지** — 같은 뜻의 아이콘을 직접 그림 |

**헷갈리면 넣지 말고 물어보십시오.** 나중에 지우는 것보다 안 넣는 것이 쌉니다.
