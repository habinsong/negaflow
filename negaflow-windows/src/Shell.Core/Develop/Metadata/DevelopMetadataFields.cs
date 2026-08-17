using System.Globalization;
using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 촬영 기록 편집기가 받는 글자와 카탈로그가 담는 값 사이의 변환입니다. 화면 배치나 이벤트와
/// 다른 이유로 바뀌므로(사진가가 적는 표기법이 바뀔 때) 뷰 밖에 둡니다.
/// </summary>
public static class DevelopMetadataFields
{
    /// <summary>쉼표로 나눕니다. macOS 의 편집기도 한 줄에 쉼표로 적습니다.</summary>
    public static IReadOnlyList<string> SplitKeywords(string? text) =>
        AppMetadataOverlay.NormalizeKeywords(
            (text ?? string.Empty).Split(',', StringSplitOptions.TrimEntries));

    public static int? ParseInteger(string? text) =>
        int.TryParse(text, NumberStyles.Integer, CultureInfo.CurrentCulture, out int value) &&
        value > 0
            ? value
            : null;

    public static double? ParseNumber(string? text) =>
        double.TryParse(text, NumberStyles.Float, CultureInfo.CurrentCulture, out double value) &&
        double.IsFinite(value) && value > 0
            ? value
            : null;

    /// <summary>
    /// 셔터는 사진가가 적는 대로 <c>1/125</c> 또는 <c>2</c> 로 받습니다. 카탈로그에는 초로 둡니다.
    /// </summary>
    public static double? ParseShutter(string? text)
    {
        string value = (text ?? string.Empty).Trim();
        if (value.Length == 0)
        {
            return null;
        }
        int slash = value.IndexOf('/');
        if (slash < 0)
        {
            return ParseNumber(value);
        }
        double? numerator = ParseNumber(value[..slash]);
        double? denominator = ParseNumber(value[(slash + 1)..]);
        return numerator is { } top && denominator is { } bottom ? top / bottom : null;
    }

    public static string FormatShutter(double? seconds)
    {
        if (seconds is not { } value)
        {
            return string.Empty;
        }
        if (value >= 1.0)
        {
            return value.ToString("0.##", CultureInfo.CurrentCulture);
        }
        // 1 초보다 짧으면 사진가가 읽는 분수로 되돌립니다.
        return string.Create(CultureInfo.CurrentCulture, $"1/{Math.Round(1.0 / value)}");
    }

    /// <summary>
    /// 편집기가 낸 값이 이미 담긴 값과 같은지 봅니다. 개정 번호와 수정 시각은 저장할 때마다
    /// 달라지므로 견주지 않습니다 — 그것까지 견주면 바뀐 것이 없어도 매번 다시 씁니다.
    /// </summary>
    public static bool Equivalent(AppMetadataOverlay stored, AppMetadataOverlay candidate)
    {
        AppMetadataOverlay left = stored.Normalized() with { Revision = 0, UpdatedAt = default };
        AppMetadataOverlay right = candidate.Normalized() with { Revision = 0, UpdatedAt = default };
        return left.Title == right.Title &&
            left.Caption == right.Caption &&
            left.Copyright == right.Copyright &&
            left.FilmShot == right.FilmShot &&
            left.Keywords.SequenceEqual(right.Keywords, StringComparer.Ordinal);
    }
}
