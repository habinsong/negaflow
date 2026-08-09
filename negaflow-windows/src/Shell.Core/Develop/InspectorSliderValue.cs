using System.Globalization;
using System.Text.RegularExpressions;

namespace Negaflow.Shell.Develop;

/// <summary>
/// Inspector slider의 값 경계와 키보드 증분을 UI와 분리해 고정합니다.
/// </summary>
public static partial class InspectorSliderValue
{
    public const double FineStep = 0.01;
    public const double CoarseStep = 0.10;

    public static double Adjust(
        double value,
        double minimum,
        double maximum,
        bool increase,
        bool coarse)
    {
        ValidateRange(minimum, maximum);
        double step = coarse ? CoarseStep : FineStep;
        double adjusted = Math.Round(
            Clamp(value, minimum, maximum) + (increase ? step : -step),
            2,
            MidpointRounding.AwayFromZero);
        return Clamp(adjusted, minimum, maximum);
    }

    public static bool TryParse(string? text, double minimum, double maximum, out double value)
    {
        value = 0;
        ValidateRange(minimum, maximum);
        string trimmed = text?.Trim() ?? string.Empty;
        if (!DecimalPattern().IsMatch(trimmed))
        {
            return false;
        }

        if (!double.TryParse(
                trimmed,
                NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint,
                CultureInfo.InvariantCulture,
                out double parsed) ||
            !double.IsFinite(parsed) ||
            parsed < minimum ||
            parsed > maximum)
        {
            return false;
        }

        value = parsed;
        return true;
    }

    public static double Clamp(double value, double minimum, double maximum)
    {
        ValidateRange(minimum, maximum);
        return !double.IsFinite(value) ? minimum : Math.Clamp(value, minimum, maximum);
    }

    private static void ValidateRange(double minimum, double maximum)
    {
        if (!double.IsFinite(minimum) || !double.IsFinite(maximum) || minimum > maximum)
        {
            throw new ArgumentOutOfRangeException(nameof(minimum));
        }
    }

    [GeneratedRegex(@"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$", RegexOptions.CultureInvariant)]
    private static partial Regex DecimalPattern();
}
