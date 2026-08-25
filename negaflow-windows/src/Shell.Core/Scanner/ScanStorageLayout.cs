using System.Globalization;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

/// <summary>
/// 스캔한 원본이 놓이는 자리입니다. macOS <c>FrameStorageNaming</c> 과 같은 모양으로
/// <c>&lt;스캔 루트&gt;/yyyyMMdd/&lt;필름 종류&gt;/&lt;롤 이름&gt;/</c> 아래에 씁니다.
/// </summary>
/// <remarks>
/// 필름 종류 폴더 이름은 macOS 와 같은 ASCII 고정값입니다. 언어를 바꿔도 경로가 흔들리지 않아야
/// 이미 쓴 롤이 다른 롤처럼 보이지 않습니다.
/// </remarks>
public static class ScanStorageLayout
{
    public static string DateFolderName(DateTime date) =>
        date.ToString("yyyyMMdd", CultureInfo.InvariantCulture);

    public static string FilmTypeFolderName(FilmType filmType) => filmType switch
    {
        FilmType.ColorNegative => "color-negative",
        FilmType.ColorPositive => "color-slide",
        FilmType.BlackAndWhiteNegative => "bw-negative",
        FilmType.BlackAndWhitePositive => "bw-slide",
        _ => "color-negative",
    };

    /// <summary>스캐너 표시명을 폴더·파일명용 축약명으로 줄입니다. macOS 와 같은 규칙입니다.</summary>
    public static string ScannerAbbreviation(string? displayName)
    {
        string name = displayName ?? string.Empty;
        // 괄호 주석은 모델을 구분하지 않으므로 걷어냅니다 — "(Demo)" 같은 꼬리입니다.
        while (name.IndexOf('(') is int open and >= 0 &&
            name.IndexOf(')', open) is int close and > 0)
        {
            name = name.Remove(open, close - open + 1);
        }
        string[] tokens = name.Split(
            [' ', '\t'],
            StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (tokens.Length > 1 && Vendors.Contains(tokens[0], StringComparer.OrdinalIgnoreCase))
        {
            tokens = tokens[1..];
        }
        string joined = ExportNamingTemplate.SanitizeComponent(string.Concat(tokens));
        if (joined.Length == 0)
        {
            return "scanner";
        }
        return joined.Length <= 24 ? joined : joined[..24];
    }

    /// <summary>
    /// 프리뷰 그림이 사는 캐시 폴더 이름입니다. macOS <c>diskStorage.scanPreviewsURL</c> 자리이며,
    /// 스캔 원본 폴더와 <b>반드시</b> 달라야 합니다 - 섞이면 프리뷰가 사진 번호를 차지합니다.
    /// </summary>
    public const string PreviewCacheFolderName = "Scan Previews";

    /// <summary>
    /// 프리뷰 파일 이름의 머리입니다. macOS <c>removeOwnedPreviewFile</c> 이 이 머리로 "우리가
    /// 만든 것"을 가려 지우므로, 지우는 쪽과 만드는 쪽이 같은 머리를 써야 합니다.
    /// </summary>
    public const string PreviewFilePrefix = "negaflow_preview_";

    /// <summary>
    /// 프리뷰 한 장이 놓일 자리입니다. 번호를 세지 않습니다 - 프리뷰는 본 스캔으로 대체되는
    /// 휘발 산출물이라 이름에 차례가 없습니다(macOS <c>ScanTempFile.makeURL</c>).
    /// </summary>
    public static string NewPreviewPath(string directory)
    {
        ArgumentException.ThrowIfNullOrEmpty(directory);
        return Path.Combine(
            directory,
            PreviewFilePrefix + Guid.NewGuid().ToString("N", CultureInfo.InvariantCulture) + ".tif");
    }

    /// <summary>우리가 만든 프리뷰 파일인지. 아니면 손대지 않습니다.</summary>
    public static bool IsOwnedPreviewFile(string path) =>
        !string.IsNullOrEmpty(path) &&
        Path.GetFileName(path).StartsWith(PreviewFilePrefix, StringComparison.Ordinal);

    /// <summary>
    /// 대체된 프리뷰 파일을 지웁니다. macOS <c>removeOwnedPreviewFile(at:)</c> 과 같이 <b>우리가
    /// 지은 이름</b>만 지웁니다 - 사용자가 고른 원본이 이 길로 지워지면 안 됩니다.
    /// </summary>
    public static void RemoveOwnedPreviewFile(string path)
    {
        if (!IsOwnedPreviewFile(path))
        {
            return;
        }
        try
        {
            File.Delete(path);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // 지우지 못해도 스캔은 계속합니다 - 캐시 한 장이 남는 것뿐입니다.
        }
    }

    /// <summary>이번 롤이 들어갈 폴더입니다. 없으면 만듭니다.</summary>
    public static string EnsureRollDirectory(
        string scanRoot,
        FilmType filmType,
        string rollName,
        DateTime date)
    {
        ArgumentException.ThrowIfNullOrEmpty(scanRoot);
        string safeRoll = ExportNamingTemplate.SanitizeComponent(rollName);
        string directory = Path.Combine(
            scanRoot,
            DateFolderName(date),
            FilmTypeFolderName(filmType),
            safeRoll.Length == 0 ? "untitled" : safeRoll);
        Directory.CreateDirectory(directory);
        return directory;
    }

    /// <summary>
    /// 아직 쓰이지 않은 파일 이름입니다. 플러그인 경계는 이미 있는 파일을 목적지로 받으면
    /// 거부하므로, 이어서 뜨는 배치가 서로를 덮지 않도록 여기서 비어 있는 번호를 찾습니다.
    /// </summary>
    public static string NextAvailablePath(string directory, string stem)
    {
        ArgumentException.ThrowIfNullOrEmpty(directory);
        string safeStem = ExportNamingTemplate.SanitizeComponent(stem);
        if (safeStem.Length == 0)
        {
            safeStem = "scan";
        }
        for (int index = 1; index < 100000; ++index)
        {
            string candidate = Path.Combine(
                directory,
                string.Create(CultureInfo.InvariantCulture, $"{safeStem}-{index:D4}.tif"));
            if (!File.Exists(candidate))
            {
                return candidate;
            }
        }
        throw new IOException("Scan destination names are exhausted.");
    }

    private static readonly string[] Vendors =
    [
        "plustek", "epson", "canon", "nikon", "fujifilm", "fuji", "noritsu",
        "kodak", "reflecta", "pacific", "microtek", "hp", "brother",
    ];
}
