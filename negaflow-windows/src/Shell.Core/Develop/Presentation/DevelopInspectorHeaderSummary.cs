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
/// 사용자가 가져온 파일은 <b>파일에 실제로 적힌</b> EXIF 만 냅니다. 태그가 없는 자리는
/// <b>아예 적지 않고</b>, 하나도 없으면 이 줄 자체가 사라집니다.
/// </para>
/// <para>
/// 여기는 macOS 와 다릅니다. macOS <c>importedMetadata(_:)</c> 는 빈 자리를 <c>—</c> 로 채워
/// <c>"ISO — · — s · f/— · — mm"</c> 를 냅니다. 필름 스캔은 EXIF 가 없는 것이 정상인데 그 줄이
/// 늘 떠 있으면 "값을 못 읽었다" 로 읽히므로, 사용자 지시로 빈 자리를 지웁니다(2026-09-03).
/// 있는 값의 표기 · 차례 · 구분자는 macOS 그대로입니다.
/// </para>
/// </remarks>
public static class DevelopInspectorHeaderSummary
{
    private const string SecondsUnit = "s";

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

    /// <summary>파일에 적힌 값만 냅니다. 하나도 없으면 빈 문자열입니다.</summary>
    public static string ImportedMetadata(ImageShotMetadata shot)
    {
        List<string> parts = new(4);
        if (shot.IsoSpeed is { } iso)
        {
            parts.Add($"ISO {iso.ToString(CultureInfo.CurrentCulture)}");
        }
        if (FormatShutter(shot.ExposureTimeSeconds) is { } shutter)
        {
            parts.Add(shutter);
        }
        if (shot.FNumber is { } aperture)
        {
            parts.Add($"f/{FormatNumber(aperture)}");
        }
        if (shot.FocalLengthMm is { } focal)
        {
            parts.Add($"{FormatNumber(focal)} mm");
        }
        return parts.Count == 0 ? string.Empty : string.Join(" · ", parts);
    }

    /// <summary>
    /// 1 초보다 짧으면 사진가가 읽는 <c>1/125</c> 로 되돌립니다. 되돌린 값이 실제 값과
    /// 8% 넘게 벌어지면 분수로 속이지 않고 초를 그대로 냅니다 — macOS 와 같은 기준입니다.
    /// 값이 없으면 <c>null</c> 이며, 부르는 쪽이 그 자리를 통째로 뺍니다.
    /// </summary>
    private static string? FormatShutter(double? seconds)
    {
        if (seconds is not { } value || !double.IsFinite(value) || value <= 0)
        {
            return null;
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
