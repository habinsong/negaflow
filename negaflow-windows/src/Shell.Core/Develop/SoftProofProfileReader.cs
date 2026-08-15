using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

/// <summary>
/// ICC 파일에서 용지 흰색과 잉크 검정을 읽습니다.
/// </summary>
/// <remarks>
/// **한 번 읽고 담아 둡니다.** 미리보기는 슬라이더를 움직일 때마다 도는데, 그때마다 프로파일을
/// 디스크에서 다시 읽으면 손이 느려집니다. 파일이 바뀌면 쓴 시각이 달라지므로 다시 읽습니다.
/// </remarks>
public static class SoftProofProfileReader
{
    private static readonly Lock Gate = new();
    private static string cachedPath = string.Empty;
    private static DateTime cachedWriteTime;
    private static SoftProofMedia? cached;

    /// <summary>
    /// 이 프로파일의 매체입니다. 읽을 수 없거나 RGB 출력 프로파일이 아니면 null 이며, 그때는
    /// 프루프가 용지·잉크를 흉내 내지 않습니다 — 없는 값을 지어내지 않습니다.
    /// </summary>
    public static SoftProofMedia? Read(string? profilePath)
    {
        if (string.IsNullOrWhiteSpace(profilePath) || !File.Exists(profilePath))
        {
            return null;
        }
        DateTime writeTime;
        try
        {
            writeTime = File.GetLastWriteTimeUtc(profilePath);
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException)
        {
            return null;
        }

        lock (Gate)
        {
            if (cached is not null &&
                string.Equals(cachedPath, profilePath, StringComparison.OrdinalIgnoreCase) &&
                cachedWriteTime == writeTime)
            {
                return cached;
            }
        }

        SoftProofMedia? media;
        try
        {
            media = NativeSoftProof.ReadMedia(File.ReadAllBytes(profilePath));
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or NativeBootstrapException)
        {
            return null;
        }
        // 입력 전용이나 CMYK 프로파일은 프루프 목적지가 될 수 없습니다.
        if (media is not { IsRgbOutputProfile: true })
        {
            return null;
        }

        lock (Gate)
        {
            cachedPath = profilePath;
            cachedWriteTime = writeTime;
            cached = media;
        }
        return media;
    }
}
