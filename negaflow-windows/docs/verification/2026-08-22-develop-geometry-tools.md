# Develop 편집 기하 도구 행 검증

기준은 macOS `GeometryToolSection.buttonGrid`와
`C:\Users\habin\맥negaflow 스크린샷\현상뷰\현상뷰_우측탭_아이콘6탭바_편집.png`입니다.

- `DevelopGeometryCard.xaml`: 36×34 도구 버튼, 6 간격, 1×24 세로선 두 개를 유지했습니다.
- `VectorIconPaths.cs`: crop 네모 본체와 돌출선, 좌·우 회전 원호와 화살촉, 좌우·상하 반전의 축과 화살표를 분리해 그립니다.
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-app.ps1 -Architecture x64 -Configuration Debug`: x64 Debug 패키지 빌드·등록·실행 성공, 오류 0개.
- `git diff --check`: 통과.

`mspdbcmf.exe`가 없어 심볼 패키지를 만들지 못했다는 패키징 경고 1개가 남습니다. 사용자가 명시적으로 요청하지 않았으므로 라이브 화면 확인은 수행하지 않았습니다.
