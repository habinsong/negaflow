using System.Text.RegularExpressions;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 화면 글자가 <b>한 언어로 박히지 않게</b> 지킵니다.
/// </summary>
/// <remarks>
/// <para>
/// 왜 있나 — 사용자가 "설정에서 앱 언어 바꿔도 그대로" 라고 두 번 짚었습니다. 두 갈래였습니다.
/// </para>
/// <list type="number">
/// <item>
/// XAML·C# 에 영어가 그대로 박힌 자리(<c>AutomationProperties.Name="Color Grading"</c>,
/// <c>"Arrow keys adjust by 0.01…"</c>). 어떤 언어를 골라도 안 바뀝니다.
/// </item>
/// <item>
/// 문구를 <b>생성자에서만</b> 걸어 두고 다시 거는 길이 없는 자리
/// (<c>ColorGradingEditor</c>·<c>ColorMixerEditor</c>). 언어를 바꾸면 그 컨트롤만 옛 언어로
/// 남습니다 — 담고 있는 구역의 <c>Localize()</c> 는 머리글만 다시 걸기 때문입니다.
/// </item>
/// </list>
/// <para>
/// 둘 다 사람 눈으로는 못 잡습니다. 새 컨트롤을 하나 더 붙일 때마다 같은 실수가 납니다.
/// </para>
/// </remarks>
internal static class LocalizedTextTests
{
    /// <summary>화면에 그대로 나가는 XAML 속성입니다.</summary>
    private static readonly string[] VisibleAttributes =
    [
        "Text", "Content", "Header", "PlaceholderText", "Description", "Title",
        "OnContent", "OffContent", "Label", "PrimaryButtonText", "SecondaryButtonText",
        "CloseButtonText", "AutomationProperties.Name", "AutomationProperties.HelpText",
        "AutomationProperties.FullDescription", "ToolTipService.ToolTip", "Message",
    ];

    /// <summary>C# 에서 화면 글자를 넣는 자리입니다.</summary>
    private static readonly string[] TextSinks =
    [
        "AutomationProperties.SetName", "AutomationProperties.SetHelpText",
        "AutomationProperties.SetFullDescription", "ToolTipService.SetToolTip",
    ];

    /// <summary>
    /// 번역할 것이 없는 값입니다. 앱 이름·글꼴 글리프·형식 이름·색 공간 이름·언어 이름은
    /// macOS 여섯 표에서도 모든 언어가 같은 글자입니다.
    /// </summary>
    private static readonly HashSet<string> Untranslated = new(StringComparer.Ordinal)
    {
        // 제품 이름입니다. 부팅 화면은 같은 이름을 대문자 워드마크로 세웁니다.
        "negaflow", "NEGAFLOW",
        // 파일 형식과 비트 깊이 — macOS 도 표에 넣지 않고 그대로 씁니다.
        "JPEG", "PNG", "TIFF", "8-bit", "16-bit",
        // 색 공간 이름은 고유 명사입니다.
        "sRGB", "Display P3", "Adobe RGB",
        // 언어 고르는 칸은 **그 언어로** 적힙니다 — 번역하면 안 되는 자리입니다.
        "System", "English", "한국어", "日本語", "简体中文", "Français", "Deutsch",
        // 법 문구입니다. macOS 는 여섯 InfoPlist.strings 어디에도 번역을 두지 않습니다.
        "Copyright 2026 Song Habin",
        // 촬영값 요약의 빈 상태입니다. macOS `WorkspaceInspectorPane.importedMetadata` 도
        // ISO·s·f/·mm 을 Swift 리터럴로 두고 번역하지 않습니다.
        "ISO — · — s · f/— · — mm",
    };

    public static void Run()
    {
        string? shell = FindShellDirectory();
        Check(shell is not null, "localized_shell_directory_found");
        if (shell is null)
        {
            return;
        }

        CheckXamlHasNoBakedText(shell);
        CheckCodeHasNoBakedText(shell);
        CheckConstructorTextCanBeRelocalized(shell);
    }

    /// <summary>
    /// ① XAML 속성에 글자를 박아 두면 어떤 언어를 골라도 그대로입니다.
    /// </summary>
    private static void CheckXamlHasNoBakedText(string shell)
    {
        Regex attribute = new(
            @"(?<!\w)(" + string.Join('|', VisibleAttributes.Select(Regex.Escape)) +
            @")\s*=\s*""([^""]*)""",
            RegexOptions.CultureInvariant);
        List<string> baked = [];
        foreach (string file in Directory.EnumerateFiles(shell, "*.xaml", SearchOption.AllDirectories))
        {
            string body = StripXmlComments(File.ReadAllText(file));
            foreach (Match match in attribute.Matches(body))
            {
                string value = match.Groups[2].Value.Trim();
                if (IsTranslatable(value))
                {
                    baked.Add(Path.GetFileName(file) + " " + match.Groups[1].Value + "=" + value);
                }
            }
        }
        Check(baked.Count == 0, "xaml_has_no_baked_display_text");
        foreach (string entry in baked.Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal))
        {
            Check(false, "xaml_baked_" + entry);
        }
    }

    /// <summary>
    /// ② 접근성 이름·도움말·풍선말에 리터럴을 바로 넣으면 화면 낭독기가 한 언어만 읽습니다.
    /// </summary>
    private static void CheckCodeHasNoBakedText(string shell)
    {
        Regex sink = new(
            @"(?<!\w)(" + string.Join('|', TextSinks.Select(Regex.Escape)) + @")\s*\(",
            RegexOptions.CultureInvariant);
        List<string> baked = [];
        foreach (string file in EnumerateSources(shell))
        {
            string body = StripLineComments(File.ReadAllText(file));
            foreach (Match match in sink.Matches(body))
            {
                string call = BalancedCall(body, match.Index);
                if (call.Contains("AppResources", StringComparison.Ordinal))
                {
                    continue;
                }
                foreach (string literal in Literals(call))
                {
                    if (IsTranslatable(literal))
                    {
                        baked.Add(Path.GetFileName(file) + " " + match.Groups[1].Value + " " + literal);
                    }
                }
            }
        }
        Check(baked.Count == 0, "code_has_no_baked_accessibility_text");
        foreach (string entry in baked.Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal))
        {
            Check(false, "code_baked_" + entry);
        }
    }

    /// <summary>
    /// ③ 생성자에서 문구를 거는 컨트롤은 <c>LocalizedElement.Track</c> 으로 스스로 다시
    /// 걸거나, 밖에서 부를 수 있는 <c>Localize()</c> 를 내놓아야 합니다.
    /// </summary>
    /// <remarks>
    /// 둘 다 없으면 그 컨트롤은 처음 만들어질 때의 언어에 <b>영원히</b> 머무릅니다.
    /// <c>ColorGradingEditor</c>(어두운 영역·중간톤·밝은 영역·색조·채도)가 그랬습니다.
    /// </remarks>
    private static void CheckConstructorTextCanBeRelocalized(string shell)
    {
        List<string> stuck = [];
        foreach (string file in EnumerateSources(shell))
        {
            string body = StripLineComments(File.ReadAllText(file));
            if (!body.Contains("AppResources.", StringComparison.Ordinal))
            {
                continue;
            }
            if (body.Contains("LocalizedElement.Track", StringComparison.Ordinal) ||
                Regex.IsMatch(body, @"(public|internal)\s+void\s+Localize\w*\s*\(",
                    RegexOptions.CultureInvariant))
            {
                continue;
            }
            // 생성자 안에서 부르는지 봅니다 — 그때그때 만드는 대화상자·메뉴는 부를 때마다
            // 새 언어로 만들어지므로 여기 걸리지 않습니다.
            string type = Path.GetFileName(file).Replace(".xaml.cs", string.Empty, StringComparison.Ordinal);
            type = Path.GetFileNameWithoutExtension(type);
            Match constructor = Regex.Match(
                body,
                @"(?<!\w)(?:public|internal)\s+" + Regex.Escape(type) + @"\s*\([^)]*\)\s*\{",
                RegexOptions.CultureInvariant);
            if (!constructor.Success)
            {
                continue;
            }
            string block = BalancedBlock(body, constructor.Index + constructor.Length - 1);
            if (block.Contains("AppResources.", StringComparison.Ordinal))
            {
                stuck.Add(Path.GetFileName(file));
            }
        }
        Check(stuck.Count == 0, "constructor_text_can_be_relocalized");
        foreach (string entry in stuck.Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal))
        {
            Check(false, "constructor_text_stuck_" + entry);
        }
    }

    /// <summary>번역해야 하는 글자인지 봅니다. 숫자·기호·글리프는 아닙니다.</summary>
    private static bool IsTranslatable(string value)
    {
        if (value.Length == 0 || value.StartsWith('{') || Untranslated.Contains(value))
        {
            return false;
        }
        // 글꼴 글리프는 글자가 아닙니다. XAML 은 `&#xE710;` 로, C# 은 사유 영역 문자
        // (U+E000‥U+F8FF, Segoe Fluent Icons)로 적습니다.
        if (value.StartsWith("&#x", StringComparison.Ordinal) ||
            value.All(character => character is >= '\uE000' and <= '\uF8FF'))
        {
            return false;
        }
        return value.Any(char.IsLetter);
    }

    private static IEnumerable<string> EnumerateSources(string shell) =>
        Directory.EnumerateFiles(shell, "*.cs", SearchOption.AllDirectories)
            .Where(file => !file.Contains(Path.DirectorySeparatorChar + "obj" + Path.DirectorySeparatorChar,
                       StringComparison.Ordinal)
                && !file.Contains(Path.DirectorySeparatorChar + "bin" + Path.DirectorySeparatorChar,
                       StringComparison.Ordinal));

    private static IEnumerable<string> Literals(string text)
    {
        foreach (Match match in Regex.Matches(text, "\"(?:[^\"\\\\]|\\\\.)*\""))
        {
            yield return match.Value[1..^1];
        }
    }

    private static string StripXmlComments(string text) =>
        Regex.Replace(text, "<!--.*?-->", string.Empty, RegexOptions.Singleline);

    /// <summary>
    /// 줄 주석만 지웁니다. 이 저장소의 설명은 <c>///</c> 와 <c>//</c> 이고, 그 안에 견본
    /// 문구가 자주 들어 있어 그대로 두면 헛짚습니다.
    /// </summary>
    private static string StripLineComments(string text) =>
        string.Join('\n', text.Split('\n').Select(line =>
        {
            int marker = line.IndexOf("//", StringComparison.Ordinal);
            if (marker < 0)
            {
                return line;
            }
            // 따옴표 안의 "//" 는 주석이 아닙니다(경로·URL).
            int quotes = line[..marker].Count(character => character == '"');
            return quotes % 2 == 0 ? line[..marker] : line;
        }));

    private static string BalancedCall(string text, int start)
    {
        int open = text.IndexOf('(', start);
        if (open < 0)
        {
            return string.Empty;
        }
        int depth = 0;
        for (int index = open; index < text.Length; ++index)
        {
            if (text[index] == '(')
            {
                ++depth;
            }
            else if (text[index] == ')')
            {
                --depth;
                if (depth == 0)
                {
                    return text[open..(index + 1)];
                }
            }
        }
        return text[open..];
    }

    private static string BalancedBlock(string text, int openBrace)
    {
        int depth = 0;
        for (int index = openBrace; index < text.Length; ++index)
        {
            if (text[index] == '{')
            {
                ++depth;
            }
            else if (text[index] == '}')
            {
                --depth;
                if (depth == 0)
                {
                    return text[openBrace..(index + 1)];
                }
            }
        }
        return text[openBrace..];
    }

    /// <summary>시험은 빌드 산출물 폴더에서 도므로 저장소 뿌리를 거슬러 올라가 찾습니다.</summary>
    private static string? FindShellDirectory()
    {
        DirectoryInfo? directory = new(AppContext.BaseDirectory);
        while (directory is not null)
        {
            string candidate = Path.Combine(directory.FullName, "src", "Shell");
            if (Directory.Exists(candidate))
            {
                return candidate;
            }
            directory = directory.Parent;
        }
        return null;
    }
}
