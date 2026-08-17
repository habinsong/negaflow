using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>정보 카드 한 줄입니다. 표시 문구를 XAML 이 짓지 않도록 여기서 만듭니다.</summary>
public readonly record struct DevelopInfoRow(string Label, string Value);

/// <summary>
/// 정보 카드가 쓰는 이름표와 고정 문구입니다. 어느 말로 낼지는 화면이 정하고, 무엇을 낼지는
/// 투영이 정합니다.
/// </summary>
public sealed record DevelopInfoCardText(
    string SourceLabel,
    string SidecarLabel,
    string CameraLabel,
    string DateLabel,
    string TitleLabel,
    string KeywordsLabel,
    string NotAvailable,
    string OriginScan,
    string OriginImport,
    string SidecarUnknown,
    string SidecarNotFound);

/// <summary>
/// 정보 탭의 여섯 줄을 만듭니다. 화면 배치·이벤트와 다른 이유로 바뀌므로 뷰 밖에 둡니다.
/// 지역화 문구와 파일 확인은 밖에서 받습니다 — 이 타입은 무엇을 낼지만 정합니다.
/// </summary>
public static class DevelopInfoCardProjection
{
    public static IReadOnlyList<DevelopInfoRow> Rows(
        LibraryFrameSnapshot? frame,
        DevelopInfoCardText text,
        Func<string, bool> sidecarExists)
    {
        if (frame is null)
        {
            return [];
        }

        // 값과 출처를 가운뎃점으로 잇는 macOS 표기입니다. 둘 다 없으면 "— · —" 가 됩니다.
        string empty = text.NotAvailable + " · " + text.NotAvailable;
        string origin = frame.Route.SourceTransport == FrameSourceTransport.Scanner
            ? text.OriginScan
            : text.OriginImport;
        return
        [
            new DevelopInfoRow(
                text.SourceLabel,
                origin + " · " + Path.GetFileName(frame.SourcePath)),
            new DevelopInfoRow(text.SidecarLabel, DescribeSidecar(frame, text, sidecarExists)),
            new DevelopInfoRow(text.CameraLabel, DescribeCamera(frame, empty)),
            new DevelopInfoRow(text.DateLabel, empty),
            new DevelopInfoRow(text.TitleLabel, frame.AppMetadata?.Title ?? empty),
            new DevelopInfoRow(
                text.KeywordsLabel,
                frame.AppMetadata is { Keywords.Count: > 0 } withKeywords
                    ? string.Join(", ", withKeywords.Keywords)
                    : empty),
        ];
    }

    /// <summary>
    /// 카메라 줄은 적어 둔 촬영 기록에서 옵니다. 스캔 파일에 적힌 카메라는 스캐너의 것이지
    /// 그 사진을 찍은 카메라의 것이 아니므로 쓰지 않습니다.
    /// </summary>
    public static string DescribeCamera(LibraryFrameSnapshot frame, string empty)
    {
        if (frame.AppMetadata?.FilmShot is not { } shot)
        {
            return empty;
        }
        string[] parts = [.. new[] { shot.CameraMake, shot.CameraModel }.OfType<string>()];
        return parts.Length == 0 ? empty : string.Join(" · ", parts);
    }

    /// <summary>
    /// XMP sidecar 는 아직 읽지 않습니다. 옆에 파일이 없다는 것은 확실히 말할 수 있고, 있는
    /// 경우에 "읽음"이라고 하면 읽지 않은 것을 읽었다고 말하는 것이라 "미확인"입니다.
    /// </summary>
    public static string DescribeSidecar(
        LibraryFrameSnapshot frame,
        DevelopInfoCardText text,
        Func<string, bool> sidecarExists)
    {
        try
        {
            string sidecarPath = Path.ChangeExtension(frame.SourcePath, ".xmp");
            return sidecarExists(sidecarPath) ? text.SidecarUnknown : text.SidecarNotFound;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException)
        {
            return text.SidecarUnknown;
        }
    }
}
