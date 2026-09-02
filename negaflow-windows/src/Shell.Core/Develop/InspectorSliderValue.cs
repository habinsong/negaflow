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

    /// <summary>
    /// 화면에 적는 눈금 자릿수입니다. 값 글자·편집기·화살표·툴팁이 모두 이 자리를 씁니다.
    /// </summary>
    public const int DisplayDecimals = 2;

    /// <summary>
    /// macOS <c>sliderInputText</c>:
    /// <c>abs(value) &lt; 0.005 ? "0" : String(format: "%.2f", value)</c>.
    /// </summary>
    public static string InputText(double value) =>
        !double.IsFinite(value) || Math.Abs(value) < 0.005
            ? "0"
            : value.ToString("0.00", CultureInfo.InvariantCulture);

    /// <summary>
    /// 값을 화면 눈금에 맞춥니다. WinUI 슬라이더는 <c>StepFrequency</c> 를 끌 때만 걸고 트랙
    /// 클릭에는 걸지 않아, 같은 칸이 <c>0.38</c> 이 되기도 <c>0.37546181678772</c> 가 되기도
    /// 합니다. 들어오는 길이 무엇이든 여기 한 곳을 지나게 해서 저장값과 표시값을 같게 합니다.
    /// </summary>
    public static double Quantize(double value) =>
        !double.IsFinite(value)
            ? value
            : Math.Round(value, DisplayDecimals, MidpointRounding.AwayFromZero);

    public static double Adjust(
        double value,
        double minimum,
        double maximum,
        bool increase,
        bool coarse)
    {
        ValidateRange(minimum, maximum);
        double step = coarse ? CoarseStep : FineStep;
        double adjusted = Quantize(Clamp(value, minimum, maximum) + (increase ? step : -step));
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
