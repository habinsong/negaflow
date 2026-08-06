# ADR-0022: 쓰지 않는 WebView2 페이로드를 배포물에서 제외한다

- 상태: 채택
- 날짜: 2026-08-06

## 문제

셸을 빌드하면 WinUI package graph가 출력 디렉터리에 WebView2 바이너리 3개를 binplace합니다.

| 파일 | 크기 |
|---|---:|
| `Microsoft.Web.WebView2.Core.dll` | 785,488 B |
| `Microsoft.Web.WebView2.Core.Projection.dll` | 666,192 B |
| `WebView2Loader.dll` | 165,488 B |

합계 약 1.6MB입니다. 그런데 셸 source 전체에 WebView2 참조가 **0건**입니다. 웹 콘텐츠를 렌더링하는
화면이 없고 계획에도 없습니다.

이 페이로드를 그대로 배포하면 실제 의무가 따라옵니다.

1. `Microsoft.Web.WebView2`는 BSD-3-Clause입니다. 바이너리 재배포 시 저작권 고지·조건·면책을 문서나
   동봉 자료에 재현해야 합니다.
2. WebView2 package의 `NOTICE.txt`는 Microsoft가 WebView2에 포함한 제3자 구성요소를 나열하고,
   copyleft 구성요소에 대한 소스 제공 청약을 담고 있습니다. 재배포하면 이 사슬도 함께 전달해야
   합니다.
3. `third_party/manifest/components.json`의 `runtime_payload` 경계와 "네이티브 엔진 제3자 runtime
   dependency 0개"라는 프로젝트 기준에 어긋나는 인상을 줍니다.

쓰지도 않는 브라우저 로더 때문에 Apache-2.0 프로젝트가 감수할 이유가 없는 의무입니다.

## 결정

`src/Shell/Negaflow.Shell.csproj`에 `ResolveReferences` 이후 실행되는 `RemoveUnusedWebView2Payload`
target을 추가해 `ReferenceCopyLocalPaths`에서 WebView2 항목을 제거합니다. package 참조 자체는 건드리지
않으므로 WinUI projection의 빌드 시점 그래프는 그대로 유지되고, 출력물에만 복사되지 않습니다.

package graph에서 WebView2를 아예 끊는 방법(`ExcludeAssets`)은 채택하지 않았습니다. 중앙 package 버전
관리 아래에서 transitive package에 직접 참조를 새로 선언해야 하고, WinUI XAML 컴파일 경로에 미치는
영향이 이 변경보다 큽니다. 얻는 결과는 같습니다.

## 검증

- x64 Release clean build: 경고 0, 오류 0. 출력 디렉터리에 WebView2 파일 0개.
- ARM64 Release clean build: 경고 0, 오류 0. 출력 디렉터리에 WebView2 파일 0개.
- x64 Release 셸 실제 실행: 프로세스가 8초 이상 유지되고 주 창 제목 `negaflow` 확인 후 정상 종료.
  WebView2 부재로 인한 조기 종료나 type load 실패가 없습니다.

증분 빌드에서는 이전 빌드가 남긴 WebView2 파일이 출력 디렉터리에 그대로 남습니다. target은 복사를
막을 뿐 기존 파일을 지우지 않습니다. 따라서 **배포 payload는 반드시 clean build 결과로 만들어야
합니다.** 이 조건은 M17 packaging 작업의 종료 조건에 포함합니다.

## 결과

- BSD-3-Clause 재현 의무와 WebView2가 끌고 오던 하위 notice 사슬이 배포 대상에서 사라집니다.
- 배포물이 약 1.6MB 줄어듭니다.
- 남는 제3자 재배포 의무는 Windows App SDK/WinUI 하나로 좁혀집니다. 이것은 셸의 실행 기반이므로
  제거할 수 없고, `THIRD-PARTY-NOTICES.md`에서 처리합니다.

## 되돌리는 조건

WebView2 XAML 컨트롤을 쓰기 시작하면 이 target을 삭제하고, `THIRD-PARTY-NOTICES.md`의 WebView2 절을
"배포함" 상태로 바꾸며, package의 `NOTICE.txt`를 배포물에 동봉해야 합니다. csproj의 주석에 같은 조건을
적어 뒀습니다.
