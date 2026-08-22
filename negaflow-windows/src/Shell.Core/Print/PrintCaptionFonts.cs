namespace Negaflow.Shell.Print;

/// <summary>
/// 캡션 글꼴 목록입니다. macOS <c>PrintPackageInspectorControls.captionFontNames</c> 와 같은
/// 규칙입니다 — 설치된 글꼴 <b>가족</b>에 <c>Helvetica</c> 를 합쳐 가나다순으로 냅니다.
/// </summary>
/// <remarks>
/// <para>
/// macOS 는 <c>NSFontManager.availableFontFamilies</c> 로 <b>가족</b>만 받습니다. Windows 의
/// 글꼴 레지스트리는 <c>Arial Bold Italic</c> 처럼 <b>낱개 글꼴</b> 이름을 주므로 그대로 쓰면
/// 목록이 수백 줄이 되고, 그 수백 줄을 한 번에 메뉴로 지으면 팝업을 여는 순간 화면이 멈춥니다.
/// 그래서 뒤에 붙은 굵기·기울기 낱말을 떼어 가족으로 되돌립니다.
/// </para>
/// <para>
/// macOS 는 기본값이 <c>Helvetica</c> 라 설치 목록에 없더라도 반드시 고를 수 있어야 합니다 —
/// 목록에 없으면 팝업이 아무것도 고르지 않은 상태로 열려 빈 칸처럼 보입니다.
/// </para>
/// </remarks>
public static class PrintCaptionFonts
{
    /// <summary>macOS 기본 캡션 글꼴입니다.</summary>
    public const string DefaultName = "Helvetica";

    /// <summary>
    /// 가족 이름 뒤에 붙는 낱말입니다. 이것만으로 이루어진 꼬리는 떼어 냅니다.
    /// </summary>
    private static readonly string[] StyleWords =
    [
        "thin", "extralight", "ultralight", "light", "regular", "normal", "book",
        "medium", "semibold", "demibold", "demi", "bold", "extrabold", "ultrabold",
        "heavy", "black", "italic", "oblique", "condensed", "semicondensed",
        "extracondensed", "narrow", "expanded", "semiexpanded", "wide",
    ];

    /// <summary>설치된 글꼴에 기본 글꼴을 합쳐 가나다순으로 냅니다.</summary>
    public static IReadOnlyList<string> Merge(IEnumerable<string> installed)
    {
        ArgumentNullException.ThrowIfNull(installed);
        HashSet<string> names = new(StringComparer.OrdinalIgnoreCase) { DefaultName };
        foreach (string name in installed)
        {
            if (Family(name) is { Length: > 0 } family)
            {
                _ = names.Add(family);
            }
        }
        return [.. names.OrderBy(name => name, StringComparer.CurrentCultureIgnoreCase)];
    }

    /// <summary>
    /// 낱개 글꼴 이름에서 가족만 남깁니다. <c>Arial Bold Italic</c> → <c>Arial</c>.
    /// 낱말이 전부 굵기·기울기면(예: <c>Bold</c>) 그대로 둡니다 — 가족 이름 자체일 수 있습니다.
    /// </summary>
    public static string Family(string fontName)
    {
        if (string.IsNullOrWhiteSpace(fontName))
        {
            return string.Empty;
        }
        // 레지스트리는 "이름 (TrueType)" 처럼 종류를 괄호로 붙입니다.
        string name = fontName.Trim();
        int marker = name.LastIndexOf(" (", StringComparison.Ordinal);
        if (marker > 0)
        {
            name = name[..marker].Trim();
        }
        // 한 항목에 여러 이름이 쉼표로 묶여 오기도 합니다("Arial,Arial Bold").
        int comma = name.IndexOf(',', StringComparison.Ordinal);
        if (comma > 0)
        {
            name = name[..comma].Trim();
        }
        string[] words = name.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        int keep = words.Length;
        while (keep > 1 && IsStyleWord(words[keep - 1]))
        {
            --keep;
        }
        return string.Join(' ', words[..keep]);
    }

    private static bool IsStyleWord(string word)
    {
        foreach (string style in StyleWords)
        {
            if (string.Equals(word, style, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }
}
