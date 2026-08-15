namespace Negaflow.Shell;

/// <summary>
/// 라이브러리 왼쪽 세로 막대가 고르는 소스입니다. macOS <c>LibrarySourceSection</c> 과 같은
/// 순서입니다.
/// </summary>
public enum LibrarySourceKind
{
    Importing,
    Files,
    Collections,
}

/// <summary>
/// 파일 소스 트리 한 줄입니다. 폴더는 그 안의 frame 을 자식으로 답니다.
/// </summary>
/// <remarks>
/// 문자열을 XAML 이 아니라 여기서 만들어야 개수 표기와 접근성 이름이 한 곳에서만 정해집니다.
/// </remarks>
public sealed record LibrarySourceNode(string Title, string Detail, string Glyph, string? FrameId)
{
    /// <summary>
    /// 폴더 줄이면 그 폴더의 경로입니다. 사진 줄은 null 입니다 — 원본을 끌어다 놓을 자리를
    /// 정하는 데 씁니다.
    /// </summary>
    public string? FolderPath { get; init; }

    /// <summary>Segoe Fluent Icons 의 폴더와 사진 글리프입니다.</summary>
    private const string FolderGlyph = "";
    private const string FrameGlyph = "";

    public static LibrarySourceNode Folder(
        string title,
        string countText,
        string? folderPath = null) =>
        new(title, countText, FolderGlyph, null) { FolderPath = folderPath };

    public static LibrarySourceNode Frame(string title, string frameId) =>
        new(title, string.Empty, FrameGlyph, frameId);
}
