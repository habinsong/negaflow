namespace Negaflow.Shell.Library;

/// <summary>
/// 더 이상 쓰지 않는 캐시 폴더를 한 번 치웁니다.
/// </summary>
/// <remarks>
/// <para>
/// 현상 프리뷰 디스크 캐시(<c>Cache\DevelopedPreviews</c>)는 맥에 없는 Windows 창작이라
/// 걷어냈습니다. 코드에서 지우는 것만으로는 <b>이미 설치된 기계에 쌓인 파일이 영영
/// 남습니다</b> — 실측(2026-09-02) 한 대에서 42~53개, 1.2~1.6GB 였고 예산 상한은 8GiB
/// 였습니다. 판올림한 사용자가 그만큼을 계속 지고 가게 두지 않습니다.
/// </para>
/// <para>
/// 지우는 것은 <b>캐시</b>뿐입니다. 사진·카탈로그·사이드카는 이 아래에 없습니다. 실패하면
/// 그냥 둡니다 — 캐시를 못 지웠다고 앱이 뜨지 않을 이유가 없습니다.
/// </para>
/// </remarks>
public static class StaleCacheFolders
{
    /// <summary>지금은 쓰지 않는 캐시 폴더 이름들입니다.</summary>
    /// <remarks>
    /// 접두사로 지웁니다 - 실기에는 <c>DevelopedPreviews-preidentityfix-20260821-2020</c>
    /// 처럼 손으로 옆에 치워 둔 사본도 함께 남아 있었습니다.
    /// </remarks>
    private static readonly string[] RetiredPrefixes =
    [
        "DevelopedPreviews",
        "DevelopedPreviewWorker",
    ];

    public static void Remove(string cacheRoot)
    {
        if (string.IsNullOrWhiteSpace(cacheRoot))
        {
            return;
        }
        string[] entries;
        try
        {
            if (!Directory.Exists(cacheRoot))
            {
                return;
            }
            entries = Directory.GetDirectories(cacheRoot);
        }
        catch (Exception error) when (IsExpected(error))
        {
            return;
        }
        foreach (string entry in entries)
        {
            string name = Path.GetFileName(entry);
            if (!RetiredPrefixes.Any(prefix =>
                    name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)))
            {
                continue;
            }
            try
            {
                Directory.Delete(entry, recursive: true);
            }
            catch (Exception error) when (IsExpected(error))
            {
                // 다음 실행에서 다시 시도합니다.
            }
        }
    }

    private static bool IsExpected(Exception error) =>
        error is IOException or UnauthorizedAccessException or ArgumentException
            or NotSupportedException or PathTooLongException
            or DirectoryNotFoundException or System.Security.SecurityException;
}
