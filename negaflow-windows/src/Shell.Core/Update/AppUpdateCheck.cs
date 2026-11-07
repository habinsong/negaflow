using System.Security.Cryptography;
using System.Text.Json;

namespace Negaflow.Shell.Update;

public sealed record AppUpdateAsset(string Name, Uri DownloadUrl);

/// <summary>GitHub 최신 릴리스 하나입니다. 버전은 태그에서 읽고(<c>v1.2.7</c> → <c>1.2.7</c>), 앱에 박아 두지 않습니다.</summary>
public sealed record AppUpdateRelease(
    string Version,
    Uri PageUrl,
    AppUpdateAsset? Installer,
    AppUpdateAsset? Checksums);

/// <summary>확인 결과입니다. <see cref="Release"/> 가 있으면 새 버전입니다.</summary>
public sealed record AppUpdateCheckResult(AppUpdateRelease? Release)
{
    public static AppUpdateCheckResult UpToDate { get; } = new((AppUpdateRelease?)null);

    public bool IsUpdateAvailable => Release is not null;
}

/// <summary>
/// 업데이트 확인의 순수한 부분입니다(응답 해석, 버전 비교, 설치 파일 고르기, 체크섬 대조).
/// macOS <c>AppUpdateCheck</c> 와 같은 규칙입니다.
/// </summary>
public static class AppUpdateCheck
{
    public static Uri LatestReleaseApi { get; } = new("https://api.github.com/repos/habinsong/negaflow/releases/latest");

    public static Uri RepositoryUrl { get; } = new("https://github.com/habinsong/negaflow");

    /// <summary><c>releases/latest</c> 응답을 지금 버전과 비교합니다. 해석할 수 없으면 null 입니다.</summary>
    public static AppUpdateCheckResult? Parse(string json, string currentVersion)
    {
        try
        {
            using JsonDocument document = JsonDocument.Parse(json);
            JsonElement root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !root.TryGetProperty("tag_name", out JsonElement tag) || tag.ValueKind != JsonValueKind.String ||
                !root.TryGetProperty("html_url", out JsonElement page) || page.ValueKind != JsonValueKind.String ||
                !Uri.TryCreate(page.GetString(), UriKind.Absolute, out Uri? pageUrl) ||
                IsTrue(root, "draft") || IsTrue(root, "prerelease") ||
                VersionComponents(tag.GetString() ?? string.Empty) is not { } remote ||
                VersionComponents(currentVersion) is not { } local)
            {
                return null;
            }
            if (Compare(remote, local) <= 0)
            {
                return AppUpdateCheckResult.UpToDate;
            }
            List<AppUpdateAsset> assets = [];
            if (root.TryGetProperty("assets", out JsonElement list) && list.ValueKind == JsonValueKind.Array)
            {
                foreach (JsonElement asset in list.EnumerateArray())
                {
                    if (asset.TryGetProperty("name", out JsonElement name) && name.ValueKind == JsonValueKind.String &&
                        asset.TryGetProperty("browser_download_url", out JsonElement url) &&
                        url.ValueKind == JsonValueKind.String &&
                        Uri.TryCreate(url.GetString(), UriKind.Absolute, out Uri? download))
                    {
                        assets.Add(new AppUpdateAsset(name.GetString() ?? string.Empty, download));
                    }
                }
            }
            return new AppUpdateCheckResult(new AppUpdateRelease(
                string.Join('.', remote),
                pageUrl,
                assets.FirstOrDefault(asset => asset.Name.EndsWith("-win-x64.exe", StringComparison.Ordinal)),
                assets.FirstOrDefault(asset => asset.Name == "SHA256SUMS.txt")));
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static bool IsTrue(JsonElement root, string name) =>
        root.TryGetProperty(name, out JsonElement value) && value.ValueKind == JsonValueKind.True;

    /// <summary><c>v1.2.7</c>, <c>1.2.7</c>, <c>1.2.7-beta</c> → [1, 2, 7]. 숫자가 아닌 마디가 있으면 null.</summary>
    public static int[]? VersionComponents(string text)
    {
        string value = (text ?? string.Empty).Trim();
        if (value.StartsWith('v') || value.StartsWith('V'))
        {
            value = value[1..];
        }
        int cut = value.IndexOfAny(['-', '+']);
        if (cut >= 0)
        {
            value = value[..cut];
        }
        string[] parts = value.Split('.');
        if (parts.Length is 0 or > 4)
        {
            return null;
        }
        int[] numbers = new int[parts.Length];
        for (int index = 0; index < parts.Length; ++index)
        {
            if (parts[index].Length == 0 || !parts[index].All(char.IsAsciiDigit) ||
                !int.TryParse(parts[index], System.Globalization.NumberStyles.None,
                    System.Globalization.CultureInfo.InvariantCulture, out numbers[index]))
            {
                return null;
            }
        }
        return numbers;
    }

    /// <summary>빠진 마디는 0 으로 봅니다(1.3 == 1.3.0).</summary>
    public static int Compare(IReadOnlyList<int> left, IReadOnlyList<int> right)
    {
        for (int index = 0; index < Math.Max(left.Count, right.Count); ++index)
        {
            int a = index < left.Count ? left[index] : 0;
            int b = index < right.Count ? right[index] : 0;
            if (a != b)
            {
                return a < b ? -1 : 1;
            }
        }
        return 0;
    }

    /// <summary><c>SHA256SUMS.txt</c>(<c>&lt;hex&gt;  &lt;이름&gt;</c>)에서 파일 하나의 해시입니다.</summary>
    public static string? ExpectedSha256(string sums, string fileName)
    {
        foreach (string line in (sums ?? string.Empty).Split('\n'))
        {
            string[] fields = line.Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (fields.Length < 2)
            {
                continue;
            }
            string name = fields[^1].TrimStart('*');
            string hash = fields[0].ToLowerInvariant();
            if (name == fileName && hash.Length == 64 && hash.All(Uri.IsHexDigit))
            {
                return hash;
            }
        }
        return null;
    }

    public static string Sha256Hex(string path)
    {
        using FileStream stream = File.OpenRead(path);
        return Convert.ToHexStringLower(SHA256.HashData(stream));
    }

    /// <summary>같은 이름이 있으면 덮지 않고 <c>이름 (2).exe</c> 처럼 비어 있는 이름을 고릅니다.</summary>
    public static string AvailableDestination(string folder, string fileName)
    {
        string first = Path.Combine(folder, fileName);
        if (!File.Exists(first))
        {
            return first;
        }
        string stem = Path.GetFileNameWithoutExtension(fileName);
        string extension = Path.GetExtension(fileName);
        for (int index = 2; ; ++index)
        {
            string candidate = Path.Combine(folder, $"{stem} ({index}){extension}");
            if (!File.Exists(candidate))
            {
                return candidate;
            }
        }
    }
}
