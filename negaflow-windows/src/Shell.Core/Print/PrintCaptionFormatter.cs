using Negaflow.Catalog;

namespace Negaflow.Shell.Print;

/// <summary>
/// 칸 아래에 적을 글자입니다. macOS <c>PrintPackageCaptionFormatter</c> 와 같은 규칙입니다.
/// </summary>
public static class PrintCaptionFormatter
{
    /// <summary>
    /// 이 칸의 캡션입니다. 캡션을 끄면 null 입니다.
    /// </summary>
    /// <param name="sequenceNumber">판 위에서 몇 번째 칸인지. 1부터입니다.</param>
    public static string? Caption(
        LibraryFrameSnapshot frame,
        PrintPackageCaptionMode mode,
        int sequenceNumber)
    {
        ArgumentNullException.ThrowIfNull(frame);
        return mode switch
        {
            // 파일 이름은 **확장자까지** 적습니다 — 같은 이름의 TIFF 와 PNG 를 구별해야 합니다.
            PrintPackageCaptionMode.FileName => Path.GetFileName(frame.SourcePath),
            PrintPackageCaptionMode.FrameNumber => frame.ScanIndex.ToString(
                System.Globalization.CultureInfo.CurrentCulture),
            PrintPackageCaptionMode.SequenceNumber => sequenceNumber.ToString(
                System.Globalization.CultureInfo.CurrentCulture),
            // 별점 0 은 빈칸이 아니라 줄표입니다. 빈칸이면 캡션이 켜졌는지 알 수 없습니다.
            PrintPackageCaptionMode.Rating => frame.Rating > 0
                ? new string('★', frame.Rating)
                : "—",
            _ => null,
        };
    }
}
