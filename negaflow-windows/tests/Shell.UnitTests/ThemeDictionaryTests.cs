using System.Text.RegularExpressions;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// **고대비 테마에서 앱 브러시가 빠지지 않았는지**입니다(W53).
/// </summary>
/// <remarks>
/// <para>
/// XAML 의 <c>ThemeDictionaries</c> 는 Light·Dark·HighContrast 세 벌을 나란히 둡니다.
/// 컨트롤은 <c>{ThemeResource NegaflowCardBrush}</c> 처럼 이름으로만 묶으므로, 한 벌에서
/// 이름이 빠지면 <b>그 테마에서만</b> 찾지 못합니다. 빌드는 통과하고, 고대비를 켠 사용자의
/// 화면에서만 컨트롤이 잘못 그려지거나 창이 열리다 죽습니다.
/// </para>
/// <para>
/// 브러시를 하나 더할 때 Light 와 Dark 는 눈에 보이니 같이 고치지만 HighContrast 는
/// 잊기 쉽습니다 — 개발자가 고대비를 켜고 일하지 않기 때문입니다. 그래서 게이트에서 봅니다.
/// </para>
/// <para>
/// <c>SystemAccentColor*</c> 는 일부러 뺍니다. 고대비에서는 사용자가 고른 대비 색이
/// 강조색이어야 하고, 앱이 그것을 덮으면 대비 테마를 고른 뜻이 사라집니다. 그래서
/// <c>Negaflow</c> 로 시작하는 <b>앱 자신의</b> 이름만 견줍니다.
/// </para>
/// </remarks>
internal static class ThemeDictionaryTests
{
    private const string AppPrefix = "Negaflow";

    private static readonly Regex ThemeBlock = new(
        @"<ResourceDictionary\.ThemeDictionaries>(.*?)</ResourceDictionary\.ThemeDictionaries>",
        RegexOptions.Singleline);

    private static readonly Regex Theme = new(
        @"<ResourceDictionary\s+x:Key=""(\w+)"">(.*?)</ResourceDictionary>",
        RegexOptions.Singleline);

    private static readonly Regex Key = new(@"x:Key=""([^""]+)""");

    internal static void Run()
    {
        string? shell = FindShellDirectory();
        Check(shell is not null, "theme_shell_directory_found");
        if (shell is null)
        {
            return;
        }

        string[] files = [.. Directory
            .EnumerateFiles(shell, "*.xaml", SearchOption.AllDirectories)
            .Where(path => File.ReadAllText(path).Contains(
                "ResourceDictionary.ThemeDictionaries", StringComparison.Ordinal))
            .OrderBy(path => path, StringComparer.Ordinal)];
        Check(files.Length > 0, "theme_dictionaries_exist", () => files.Length.ToString());

        foreach (string file in files)
        {
            string name = Path.GetFileName(file);
            string text = File.ReadAllText(file);
            foreach (Match block in ThemeBlock.Matches(text))
            {
                Dictionary<string, SortedSet<string>> byTheme = new(StringComparer.Ordinal);
                foreach (Match theme in Theme.Matches(block.Groups[1].Value))
                {
                    SortedSet<string> keys = new(StringComparer.Ordinal);
                    foreach (Match key in Key.Matches(theme.Groups[2].Value))
                    {
                        if (key.Groups[1].Value.StartsWith(AppPrefix, StringComparison.Ordinal))
                        {
                            keys.Add(key.Groups[1].Value);
                        }
                    }
                    byTheme[theme.Groups[1].Value] = keys;
                }

                Check(
                    byTheme.ContainsKey("Light") &&
                        byTheme.ContainsKey("Dark") &&
                        byTheme.ContainsKey("HighContrast"),
                    $"theme_{name}_has_all_three_themes",
                    () => string.Join(",", byTheme.Keys));
                if (!byTheme.ContainsKey("HighContrast"))
                {
                    continue;
                }

                SortedSet<string> contrast = byTheme["HighContrast"];
                foreach ((string themeName, SortedSet<string> keys) in byTheme)
                {
                    if (themeName == "HighContrast")
                    {
                        continue;
                    }
                    string[] missing = [.. keys.Except(contrast, StringComparer.Ordinal)];
                    Check(
                        missing.Length == 0,
                        $"theme_{name}_{themeName}_keys_exist_in_high_contrast",
                        () => string.Join(", ", missing));
                    string[] extra = [.. contrast.Except(keys, StringComparer.Ordinal)];
                    Check(
                        extra.Length == 0,
                        $"theme_{name}_high_contrast_has_no_orphan_keys",
                        () => string.Join(", ", extra));
                }
            }
        }
    }

    /// <summary>시험 실행 위치에서 위로 올라가며 <c>src/Shell</c> 을 찾습니다.</summary>
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
