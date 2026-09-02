using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 결함 편집을 기록할 때의 원본과 <b>지금 파일</b>이 같은지 봅니다. 요청 조립·ABI 매핑과는
/// 바뀌는 이유가 달라 파일을 나눕니다 — 이쪽은 "무엇을 근거로 같다고 볼 것인가" 만 다룹니다.
/// </summary>
public static partial class DevelopRequestFactory
{
    /// <summary>
    /// 결함 편집을 기록할 때의 바이트 수와 지금 파일이 같은지입니다.
    /// </summary>
    /// <remarks>
    /// 크기만 봅니다. 내용 해시는 렌더마다 원본을 통째로 다시 읽어야 하고(frame_1 104MB 에서
    /// 슬라이더 틱당 약 140ms), 파일이 바뀌면 크기가 먼저 달라집니다. 읽지 못하면
    /// <b>같다고 봅니다</b> — 못 읽는 것을 근거로 편집을 내려놓으면, 잠깐 잠긴 파일 때문에
    /// 사용자의 편집이 사라진 것처럼 보입니다.
    /// </remarks>
    private static bool SourceStillMatches(string sourcePath, ulong recordedByteCount)
    {
        try
        {
            return new FileInfo(sourcePath) is { Exists: true } info
                ? (ulong)info.Length == recordedByteCount
                : true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException
            or ArgumentException or NotSupportedException or PathTooLongException)
        {
            return true;
        }
    }

    /// <summary>지금 파일의 바이트 수입니다. 못 읽으면 <see langword="null"/> 입니다.</summary>
    private static ulong? CurrentSourceByteCount(string sourcePath)
    {
        try
        {
            return new FileInfo(sourcePath) is { Exists: true } info && info.Length > 0
                ? (ulong)info.Length
                : null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException
            or ArgumentException or NotSupportedException or PathTooLongException)
        {
            return null;
        }
    }

    /// <summary>
    /// 원본의 <b>화소 격자</b>가 가져올 때와 같은지입니다. 결함 마스크는 정규화 좌표로
    /// 살아 있으므로, 가로·세로가 그대로면 같은 화소에 얹힙니다.
    /// </summary>
    /// <remarks>
    /// 파일을 열지만 <b>바이트 수가 어긋난 그 한 번</b>만 옵니다 — 크기만 읽는 프로브라
    /// 화소를 만들지 않습니다. 기록된 치수가 없으면 견줄 것이 없으므로 같지 않다고 봅니다.
    /// </remarks>
    private static bool SourcePixelGridUnchanged(LibraryFrameSnapshot frame)
    {
        if (frame.SourceMetadata is not { PixelWidth: > 0U, PixelHeight: > 0U } recorded)
        {
            return false;
        }
        try
        {
            return LibrarySourceMetadataReader.Read(frame.SourcePath) is { } current &&
                current.PixelWidth == recorded.PixelWidth &&
                current.PixelHeight == recorded.PixelHeight;
        }
        catch (Exception)
        {
            // 크기를 못 읽으면 **같다고 보지 않습니다.** 확인할 수 없는 것을 근거로 마스크를
            // 얹으면 이 검사가 있는 이유가 없어집니다.
            return false;
        }
    }
}
