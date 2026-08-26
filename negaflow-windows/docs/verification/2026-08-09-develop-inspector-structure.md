# Develop inspector histogram·전폭 구조 검증

기준일: 2026-08-09

고정 macOS 기준: `2fa1d6297378673b58b8bec72025e968ccc3125c`

대상: Windows x64 Debug, 150% DPI

## 범위

- Histogram이 6-tab strip보다 앞에 있는지
- 오른쪽 Inspector 카드와 내부 control이 macOS inset 사이 전폭을 쓰는지
- section당 visual surface가 하나인지
- 한 section만 확장되고 UIA Expand/Collapse 의미를 제공하는지
- 새 문자열이 6개 로캘 리소스에 존재하는지

비교 캡처는 당시 `negaflow_mac_screenshot/develop_right_basic_restored.png`,
`develop_right_base_panel.png`, `develop_overview.png`입니다. Windows 로컬 렌더 캡처는
`C:\Users\habin\.codex\visualizations\2026\08\09\019fe570-d6dc-7ee0-ad46-6cff083952ae\windows-develop-fit-full.png`입니다.
**(2026-08-19: `negaflow_mac_screenshot/` 폐기. 같은 구역의 살아 있는 화면은 `C:\Users\habin\맥negaflow 스크린샷\현상뷰\현상뷰_기본.png` · `현상뷰_우측탭_아이콘6탭바_베이스_자동.png`.)**

## 실행

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-managed.ps1 -Preset x64-debug
```

UTF-8을 명시해 Develop XAML 2개와 6개 `Resources.resw`를 `XmlReader`로 끝까지 읽었습니다.
`rg`로 `DevelopWorkspaceView.xaml`의 기본 `Expander`가 0개임도 확인했습니다.

빌드된 `Negaflow.Shell.exe`를 시작한 뒤 UI Automation으로 다음 AutomationId를 조회했습니다.

- `negaflow.develop.histogram`
- `negaflow.develop.section.tone`
- `negaflow.develop.section.tone-curve`
- `negaflow.develop.section.tone-curve.header`
- `negaflow.develop.exposure`

## 결과

- 관리형 빌드: warning 0, error 0
- Catalog unit: 338 assertions, failure 0
- Shell unit: 300 assertions, failure 0
- UTF-8 XML: 8/8 통과
- Histogram/card: `left=3207, width=603` physical pixel
- Exposure slider: `left=3228, width=561` physical pixel; card의 14 DIP inset 뒤 전폭
- Tone Curve header: `ExpandCollapsePattern=true`, `Collapsed → Expanded`
- 확장 뒤 Tone 높이 81, Tone Curve 높이 967 physical pixel; 동시 확장 없음
- Histogram 접근성 이름과 도움말은 실행 언어인 한국어 리소스에서 로드됨

## 남은 검증

Edit/Defects/Info/Reset의 고유 content, Color/BW Toning/Calibration/Detail sections, tab Selection
pattern, tool-state 취소, compact/high contrast, 실제 ARM64 runtime은 이번 검증 범위가 아닙니다.
사용자 우선순위에 따라 추가 UI 작업은 보류하고 backend 수명주기 작업으로 전환합니다.
