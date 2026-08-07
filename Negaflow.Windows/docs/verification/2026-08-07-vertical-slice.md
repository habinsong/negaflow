# 2026-08-07 세로 슬라이스 검증

기준일: 2026-08-07
대상: `카탈로그 → C ABI → WinUI 셸` 의 첫 관통 경로

## 종료 조건

`progress/next-steps.md` 2번의 종료 조건은 **"앱을 실행해 찍은 스크린샷 한 장"** 입니다.
충족했습니다. 실행 중인 앱에서 Export 를 눌러 현상된 PNG 가 디스크에 떨어졌습니다.

## 실제로 한 것

1. `Negaflow.Shell.exe` 를 실행합니다. 앱이 시작하면서 `%LOCALAPPDATA%\Negaflow\Library\` 에
   `library.sqlite`(118,784바이트)와 `library.sqlite.lock` 을 만듭니다. `CatalogSession` 이
   프로세스 lock 을 잡고 `ReadOrCreate` 가 빈 카탈로그를 만든 결과입니다.
2. 아직 import 경로가 없으므로 개발용 도구로 frame 한 건을 심었습니다. `rawScanPath` 는
   `Sources/ScannerKit/Resources/Frame.tiff`, 수동 base 는 0.25/0.25/0.25, Film Look 은
   portra400 강도 0.5 입니다.
3. 앱을 다시 실행하면 Develop 오른쪽 패널에 그 frame 이 나타납니다. 선택 콤보박스에
   `Frame.tiff (seeded)`, 경로 한 줄, Exposure 슬라이더 `0.00`, `Export PNG` 버튼입니다.
4. UI Automation 으로 `negaflow.develop.export` 를 invoke 했습니다.

결과:

```
Exported 631×403 in 142 ms
Frame-negaflow.png  1,285,445 바이트
```

상태 표시줄에 `대기 ABI 0.3 · X64` 가 함께 보입니다. 셸이 실제로 0.3 엔진을 물고 있다는 뜻입니다.

## 스크린샷을 잘못 찍고 있었던 것

첫 두 번의 캡처는 빈 라이브러리로 보였습니다. `PrimaryScreen.Bounds` 만 찍었는데 창은 보조
모니터에 있었습니다. UI Automation 으로 컨트롤 위치를 물어보니 `negaflow.develop.export` 가
`x=3231` 에 있었고, 주 모니터는 2560 까지입니다.

**데이터 계층을 먼저 의심하지 않고 확인한 것이 도움이 됐습니다.** headless 로
`LibraryDocument.Open(ResolveProduction())` 을 돌려 `records=1 frames=1 issues=0` 과
`canDevelop=True` 를 먼저 확인했으므로, 남은 후보는 UI 뿐이었습니다. 그다음 UI Automation
트리를 열어 컨트롤이 존재하고 화면 안에 있다는 것과 그 좌표를 함께 얻었습니다.

`negaflow.library.frames` 는 트리에 없었습니다. Library 워크스페이스가 접혀 있어서이며
(`selectedWorkspace: 1` = Develop) 버그가 아닙니다.

## 정리

- 심었던 frame 을 제거했습니다. 사용자 카탈로그는 다시 frame 0개입니다.
- `Sources/ScannerKit/Resources/Frame-negaflow.png` 를 지웠습니다. **macOS 트리는 이 작업의
  대상이 아니므로 산출물을 남기지 않습니다.**
- `library.sqlite` 와 `library.sqlite.lock` 은 남겨 둡니다. 앱이 정상적으로 만드는 파일입니다.

## 이 경로에서 발견한 것

`PresentationSettingsStore` 가 `StorageRootResolver` 를 거치지 않고 자기 경로를 만듭니다.
실제 디스크에 `%LOCALAPPDATA%\Negaflow\Development\presentation.json` 이 있고 resolver 가
선언한 `Settings\` 는 없습니다. 같은 트리의 `ScannerPlugins\` 도 resolver 의
`Plugins\Installed` 와 다릅니다. `windows_docs/14-persistence/catalog-and-storage.md` 6절은
모든 저장소가 단일 resolver 에서 경로를 받아야 한다고 적고 있으므로 어긋난 상태입니다.

경로를 그냥 바꾸면 기존 사용자의 창 배치·외관·SHA 설정이 조용히 초기화되므로 일회성 이관이
필요합니다. 이번 커밋 범위 밖으로 두고 별도 작업으로 남깁니다.

## 아직 아닌 것

- **import 이 없습니다.** frame 을 넣으려면 아직 도구가 필요합니다. 세로 슬라이스의 다음
  자연스러운 한 걸음입니다.
- 미리보기가 없습니다. 중앙은 여전히 "이미지를 가져오세요" 입니다. Export 는 파일을 쓰지만
  화면에 그리지는 않습니다.
- 취소와 진행률이 없습니다. 631×403 에서 142 ms 라 지금은 드러나지 않지만, 실제 스캔 해상도로
  가면 바로 필요합니다.
- 노출 말고 다른 조정이 UI 에 없습니다. 계약은 전부 있고 컨트롤만 없습니다.
- ARM64 는 교차 빌드만 했고 실행하지 않았습니다.
