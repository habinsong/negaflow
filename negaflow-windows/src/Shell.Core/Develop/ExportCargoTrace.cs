using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 내보낼 프레임 하나가 무엇을 싣고 가는지 한 줄로 남깁니다.
/// </summary>
/// <remarks>
/// 내보내기가 성공으로 끝나면서 현상이나 GrainMend 만 빠져 있으면, 기존 기록으로는 알 수
/// 없었습니다. 성공 줄만 남기 때문입니다. 결과 파일을 열어 봐야 알 수 있었고, 그러면 어느
/// 프레임에서 무엇이 빠졌는지 되짚기 어렵습니다.
///
/// 그래서 요청을 만든 직후에 실린 것을 적습니다. 카탈로그에 있는 결함 편집 수와 요청에
/// 실제로 담긴 수를 나란히 두므로, 둘이 다르면 그 줄 하나로 드러납니다.
/// </remarks>
public static class ExportCargoTrace
{
    private static readonly System.Globalization.CultureInfo Culture =
        System.Globalization.CultureInfo.InvariantCulture;

    public static void Write(LibraryFrameSnapshot frame, DevelopRequestResult built)
    {
        ArgumentNullException.ThrowIfNull(frame);
        int catalogEdits = frame.DefectRecipe?.Items.Count ?? 0;
        string carried = built.Request is { } request
            ? "defects=" + request.DefectEditOrder.Count.ToString(Culture) +
                "/" + catalogEdits.ToString(Culture) +
                " target=" + frame.DevelopTarget +
                " preset=" + (frame.LookPresetId ?? "none") +
                " base=" + (frame.AppliedBase is null ? "auto" : "stored") +
                " crop=" + (frame.ImageTransform.Crop is null ? "no" : "yes")
            : "request=none";
        ExportTrace.Write(
            $"      cargo frame={frame.Id} {carried} " +
            $"refusal={built.Refusal} droppedDefects={built.DroppedStaleDefectEdits}");
    }
}
