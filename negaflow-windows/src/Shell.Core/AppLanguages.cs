namespace Negaflow.Shell;

/// <summary>
/// 앱이 내는 언어들입니다. 리소스가 실제로 있는 여섯뿐이며, 빈 문자열은 시스템 언어입니다.
/// </summary>
/// <remarks>
/// 목록에 리소스가 없는 언어를 올리면 고른 순간 화면이 영어로 돌아갑니다 — 고를 수 있는 것과
/// 있는 것이 같아야 합니다.
/// </remarks>
public static class AppLanguages
{
    /// <summary>시스템 언어를 뜻하는 값입니다.</summary>
    public const string System = "";

    /// <summary>고르개에 나오는 차례입니다. macOS 설정 목록과 같습니다.</summary>
    public static IReadOnlyList<string> All { get; } =
        [System, "en-US", "ko-KR", "ja-JP", "zh-Hans", "fr-FR", "de-DE"];

    /// <summary>모르는 값은 시스템으로 되돌립니다.</summary>
    public static string Normalize(string? language)
    {
        string trimmed = (language ?? string.Empty).Trim();
        return All.Contains(trimmed, StringComparer.OrdinalIgnoreCase) ? trimmed : System;
    }
}
