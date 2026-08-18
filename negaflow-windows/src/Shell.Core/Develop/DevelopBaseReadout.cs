using System.Globalization;
using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// macOS <c>AppLocalizedPhrase.baseReadoutFormat</c> — <c>base %.2f %.2f %.2f</c> 를
/// <c>String(format:)</c> 과 같이 앞에서부터 채웁니다.
/// </summary>
public static class DevelopBaseReadout
{
    public const string Fixed2Marker = "%.2f";

    public static string Format(string template, ManualBaseRgb rgb)
    {
        ArgumentException.ThrowIfNullOrEmpty(template);
        return Replace(Replace(Replace(template, rgb.Red), rgb.Green), rgb.Blue);
    }

    private static string Replace(string template, double value)
    {
        int marker = template.IndexOf(Fixed2Marker, StringComparison.Ordinal);
        if (marker < 0)
        {
            throw new InvalidOperationException("base readout format is missing %.2f");
        }

        return string.Concat(
            template.AsSpan(0, marker),
            value.ToString("0.00", CultureInfo.CurrentCulture),
            template.AsSpan(marker + Fixed2Marker.Length));
    }
}
