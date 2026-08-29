using System.Globalization;
using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 현상 인스펙터 머리줄 오른쪽의 한 줄입니다. macOS
/// <c>DevelopInspectorHeaderSummary</c> 를 그대로 옮겼습니다.
/// </summary>
/// <remarks>
/// <para>
/// 스캐너 TIFF 는 <b>타깃 · 현상 공정</b>을 냅니다 — 필름 카메라는 EXIF 를 남기지 않고,
/// 스캔 파일에 적힌 노출은 스캐너의 것이라 그 사진의 촬영 기록이 아닙니다.
/// </para>
/// <para>
/// 사용자가 가져온 파일은 <b>파일에 실제로 적힌</b> EXIF 를 냅니다. 태그가 없는 자리는
/// macOS 와 같이 <c>—</c> 로 비웁니다.
/// </para>
/// </remarks>
public static class DevelopInspectorHeaderSummary
{
    private const string SecondsUnit = "s";

    private const string Missing = "—";

    /// <summary>이 사진의 머리줄 한 줄입니다.</summary>
    public static string Text(LibraryFrameSnapshot frame, ImageShotMetadata shot) =>
        frame.SourceKind == FrameSourceKind.ScannerTiff
            ? ScannerSummary(frame)
            : ImportedMetadata(shot);

    /// <summary>macOS <c>targetFilmSummaryFormat</c> — 여섯 언어 모두 <c>"%@ · %@"</c> 입니다.</summary>
    private static string ScannerSummary(LibraryFrameSnapshot frame) =>
        string.Join(
            " · ",
            DevelopTargets.DisplayName(frame.DevelopTarget),
            DevelopProcesses.DisplayName(
                DevelopProcesses.From(frame.Route.FilmType, isDigitalSource: false)));

    /// <summary>macOS <c>importedMetadata(_:)</c> 그대로입니다.</summary>
    public static string ImportedMetadata(ImageShotMetadata shot) =>
        string.Join(
            " · ",
            shot.IsoSpeed is { } iso
                ? $"ISO {iso.ToString(CultureInfo.CurrentCulture)}"
                : $"ISO {Missing}",
            FormatShutter(shot.ExposureTimeSeconds),
            shot.FNumber is { } aperture ? $"f/{FormatNumber(aperture)}" : $"f/{Missing}",
            shot.FocalLengthMm is { } focal
                ? $"{FormatNumber(focal)} mm"
                : $"{Missing} mm");

    /// <summary>
    /// 1 초보다 짧으면 사진가가 읽는 <c>1/125</c> 로 되돌립니다. 되돌린 값이 실제 값과
    /// 8% 넘게 벌어지면 분수로 속이지 않고 초를 그대로 냅니다 — macOS 와 같은 기준입니다.
    /// </summary>
    private static string FormatShutter(double? seconds)
    {
        if (seconds is not { } value || !double.IsFinite(value) || value <= 0)
        {
            return $"{Missing} {SecondsUnit}";
        }
        if (value < 1.0)
        {
            int denominator = Math.Max(1, (int)Math.Round(1.0 / value));
            double reciprocal = 1.0 / denominator;
            if (Math.Abs(reciprocal - value) / value < 0.08)
            {
                return $"1/{denominator.ToString(CultureInfo.CurrentCulture)} {SecondsUnit}";
            }
        }
        return $"{FormatNumber(value)} {SecondsUnit}";
    }

    private static string FormatNumber(double value) =>
        Math.Abs(Math.Round(value) - value) < 0.005
            ? ((int)Math.Round(value)).ToString(CultureInfo.CurrentCulture)
            : value.ToString("0.0", CultureInfo.CurrentCulture);
}
