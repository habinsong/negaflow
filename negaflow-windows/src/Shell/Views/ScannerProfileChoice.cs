namespace Negaflow.Shell.Views;

/// <summary>
/// 스캐너 프로파일 고르개의 한 줄입니다. <c>Label</c> 은 이름과 검증 상태를 macOS 와 같은
/// "<c>이름 · 상태</c>" 모양으로 이어 붙인 것이며, 상태 문구는 언어마다 달라 셸이 만듭니다.
/// </summary>
/// <remarks>
/// 값 자체(<c>Id</c>)는 native 가 아는 프로파일 id 그대로입니다 — 화면에 보이는 글자를 저장하면
/// 언어를 바꾼 순간 프로파일이 사라집니다.
/// </remarks>
public sealed record ScannerProfileChoice(string? Id, string Label);
