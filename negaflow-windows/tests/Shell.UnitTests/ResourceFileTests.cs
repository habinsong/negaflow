using System.Xml.Linq;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// resw 파일의 모양을 지킵니다.
///
/// 왜 있나 — 2026-08-20 에 **같은 실수로 앱이 두 번 안 떴습니다.** 새 항목을 여러 줄짜리
/// 항목 바로 뒤에 끼워 넣다가 그 항목 <b>안쪽에</b> 들어갔습니다. XML 로는 올바르므로
/// 파서도 정규식 검사도 통과하지만, <b>MakePri 는 중첩된 <c>&lt;data&gt;</c> 를 세지 않습니다.</b>
/// 그래서 PRI 에서 통째로 빠지고, 앱은 <c>Missing localized resource</c> 로 창을 열지 못합니다
/// (`XamlParseException`). 첫 번째는 인화 문구 20개, 두 번째는 <c>libraryClearSearch.Text</c>.
///
/// 사람이 눈으로 잡을 수 있는 실수가 아니므로 게이트에서 잡습니다.
/// </summary>
internal static class ResourceFileTests
{
    /// <summary>부르는 자리를 찾는 무늬입니다. 열쇠와 속성 두 조각을 잡습니다.</summary>
    private const string RawPattern =
        """AppResources\.(?:Get|FormatInteger|FormatIntegers)\(\s*"([^"]+)"\s*,\s*"([^"]+)""";

    private static readonly string[] Languages =
        ["en-US", "ko-KR", "ja-JP", "de-DE", "fr-FR", "zh-Hans"];

    public static void Run()
    {
        string? root = FindStringsDirectory();
        Check(root is not null, "resw_strings_directory_found");
        if (root is null)
        {
            return;
        }

        int expected = -1;
        foreach (string language in Languages)
        {
            string path = Path.Combine(root, language, "Resources.resw");
            Check(File.Exists(path), "resw_exists_" + language);
            if (!File.Exists(path))
            {
                continue;
            }

            XElement document = XElement.Load(path);
            List<XElement> entries = [.. document.Elements("data")];

            // ① 중첩 금지 — MakePri 가 무시하고 앱이 시작하다 죽습니다.
            int nested = entries.Sum(entry => entry.Elements("data").Count());
            Check(nested == 0, "resw_has_no_nested_data_" + language);

            // ② 이름 중복 금지 — MRT 이름은 대소문자를 가리지 않습니다.
            int distinct = entries
                .Select(entry => (string?)entry.Attribute("name") ?? string.Empty)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Count();
            Check(distinct == entries.Count, "resw_has_no_duplicate_names_" + language);

            // ③ 언어마다 항목 수가 같아야 합니다 — 한 언어에만 있는 문구는 화면에서 비어 보입니다.
            if (expected < 0)
            {
                expected = entries.Count;
            }
            Check(entries.Count == expected, "resw_entry_count_matches_" + language);

            // ④ 값이 비어 있으면 화면도 빕니다.
            bool allValued = entries.All(entry =>
                !string.IsNullOrEmpty((string?)entry.Element("value")));
            Check(allValued, "resw_every_entry_has_a_value_" + language);
        }

        CheckEveryCalledKeyExists(root);
    }

    /// <summary>
    /// 코드가 부르는 문구가 resw 에 다 있는지 봅니다.
    /// </summary>
    /// <remarks>
    /// <c>AppResources.Get</c> 은 없는 열쇠에 <see cref="InvalidOperationException"/> 을 던집니다.
    /// 그 던짐이 창을 만드는 도중에 나면 <b>앱이 아예 뜨지 않습니다</b> - 2026-08-22 에
    /// <c>canvasBackgroundMenu.Text</c> 하나로 그렇게 됐습니다. 새 문구를 코드에만 적고
    /// resw 에 안 넣는 실수는 눈으로 못 잡으므로 여기서 잡습니다.
    /// </remarks>
    private static void CheckEveryCalledKeyExists(string stringsRoot)
    {
        if (Path.GetDirectoryName(Path.GetDirectoryName(stringsRoot)) is not { } shellRoot)
        {
            return;
        }
        HashSet<string> available = [];
        foreach (string language in Languages)
        {
            string path = Path.Combine(stringsRoot, language, "Resources.resw");
            if (!File.Exists(path))
            {
                continue;
            }
            foreach (XElement entry in XElement.Load(path).Elements("data"))
            {
                if ((string?)entry.Attribute("name") is { Length: > 0 } name)
                {
                    available.Add(name);
                }
            }
        }

        System.Text.RegularExpressions.Regex call = new(
            RawPattern,
            System.Text.RegularExpressions.RegexOptions.CultureInvariant);
        List<string> missing = [];
        foreach (string file in Directory.EnumerateFiles(shellRoot, "*.cs", SearchOption.AllDirectories))
        {
            foreach (System.Text.RegularExpressions.Match match in call.Matches(File.ReadAllText(file)))
            {
                string name = match.Groups[1].Value + "." + match.Groups[2].Value;
                if (!available.Contains(name))
                {
                    missing.Add(name);
                }
            }
        }
        Check(missing.Count == 0, "resw_has_every_key_the_code_asks_for");
        foreach (string name in missing.Distinct().Order(StringComparer.Ordinal))
        {
            Check(false, "resw_missing_" + name);
        }
    }

    /// <summary>
    /// 시험은 빌드 산출물 폴더에서 도므로 저장소 뿌리를 거슬러 올라가 찾습니다.
    /// </summary>
    private static string? FindStringsDirectory()
    {
        DirectoryInfo? directory = new(AppContext.BaseDirectory);
        while (directory is not null)
        {
            string candidate = Path.Combine(directory.FullName, "src", "Shell", "Strings");
            if (Directory.Exists(candidate))
            {
                return candidate;
            }
            directory = directory.Parent;
        }
        return null;
    }
}
