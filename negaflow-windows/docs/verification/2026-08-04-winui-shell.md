# 2026-08-04 WinUI 셸 검증 기록

기준일: 2026-08-04
대상: 첫 localized WinUI 3 셸 기반, x64 실행과 ARM64 교차 빌드

## 검증 범위

- Windows App SDK component package graph와 locked restore
- x64/ARM64 Debug·Release managed build
- 기존 x64 native test와 C ABI contract 회귀
- Swift 원본 기반 6개 언어 리소스와 UTF-8 XML
- 표시 설정 기본값, panel 계산과 기준 치수 unit test
- 최대화 main window, 오른쪽 Windows caption 영역, Settings와 SHA-256 기본 `끔`
- 알려진 NuGet 취약점과 불필요한 AI/ML/Widgets payload 부재

## 실행한 명령

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-managed.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-managed.ps1 -Preset x64-release
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-managed.ps1 -Preset arm64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-managed.ps1 -Preset arm64-release

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1 -Preset x64-release
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-debug
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-interop.ps1 -Preset x64-release

dotnet run --project .\tests\Shell.UnitTests\Negaflow.Shell.UnitTests.csproj --no-restore
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-swift-ui-strings.ps1 -Check
dotnet format .\Negaflow.Windows.slnx --verify-no-changes --no-restore
dotnet list .\src\Shell\Negaflow.Shell.csproj package --vulnerable --include-transitive --no-restore --format json
```

XML 검사는 PowerShell 5.1의 기본 text decoding에 의존하지 않고 각 파일을 `-Encoding UTF8`로 읽어
`XmlDocument.LoadXml`에 전달했습니다.

## 결과

| 검사 | 결과 |
|---|---|
| x64 managed Debug/Release | 둘 다 경고 0, 오류 0 |
| ARM64 managed Debug/Release | 둘 다 교차 빌드 통과, 경고 0, 오류 0 |
| x64 native Debug/Release | 각각 CTest 18/18 통과 |
| x64 Interop Debug/Release | 각각 13 assertion 통과 |
| Shell.Core unit test | 45 assertion 통과 |
| Swift 문자열 동기화 | 6개 언어, 변경 필요 0 |
| XML-family 파일 | UTF-8 100개 parse 통과 |
| 형식 검사 | 변경 필요 0 |
| NuGet 취약점 검사 | direct/transitive 취약 package 보고 0 |
| fresh x64 Debug output | 하위 파일 포함 50개, 40,633,234 byte |
| 불필요 payload 이름 검사 | AI/ML/Widgets/ONNX/DirectML 0개 |

ARM64 restore 뒤 x64 locked restore를 연속 실행했을 때 처음에는 lock file에 단일 RID만 남는 문제가
드러났습니다. 셸 project에 `win-x64;win-arm64`를 함께 선언해 lock을 재생성한 뒤 두 architecture의
`--locked-mode` restore를 각각 다시 통과시켰습니다.

## 실제 UI 확인

Windows 앱 제어로 매 입력 직전 화면 상태를 다시 읽으며 다음을 확인했습니다.

- main window가 현재 모니터의 2560×1392 전체 작업영역으로 최대화됨
- 최소화·최대화·닫기 버튼이 오른쪽에 있고 toolbar control과 겹치지 않음
- Library, Develop, Print 전환과 한국어 PRI 문자열 표시
- sidebar, filmstrip, inspector 상태와 workspace 선택이 접근성 tree에 노출됨
- Settings 실제 창이 열리고 Disk category로 이동 가능함
- `settings.disk.image-sha256` toggle의 접근성 상태가 `끔`임

SHA-256 toggle은 검증 중 켜지 않았습니다. Settings capture는 748×634로 관찰돼 760×640 설계 계약과의
DPI/non-client pixel 차이는 후속 matrix에서 다시 판정합니다.

## 의존성·권리 검토

- 제품 코드는 Apache-2.0 경계를 유지합니다.
- Windows App SDK 1.8 binplaced 파일은 Microsoft Windows App SDK license를 따릅니다.
- WebView2 transitive binary는 BSD-3-Clause notice 재현이 필요합니다.
- 2.3 component graph는 Engineering Preview license와 불필요한 AI/ML/Widgets 때문에 채택하지 않았습니다.
- Microsoft sample, 외부 UI template, icon pack 또는 제3자 사진 코드는 복사하지 않았습니다.
- 이 검토는 법률 의견이 아니며 최종 installer payload의 SBOM·notice·서명 검토는 M17 release gate입니다.

## 남은 위험

- ARM64는 x64 호스트에서 교차 빌드만 했으며 실제 ARM64 Windows 실행은 미검증입니다.
- 900×640, 1339/1340 경계, 150/200% DPI, High Contrast와 접근성 전체 keyboard matrix는 미검증입니다.
- framework-dependent 배포의 .NET 10과 Windows App Runtime 1.8 설치 연결은 아직 installer에 없습니다.
- 현재 셸은 실제 catalog/import, GPU canvas, Develop graph, export, print engine과 scanner host를 구현하지 않습니다.
