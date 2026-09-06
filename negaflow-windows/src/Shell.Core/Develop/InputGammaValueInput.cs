using System.Globalization;
using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

public static class InputGammaValueInput
{
    public const double Step = 0.1;
    public static double Round(double value) => Math.Round(value * 10, MidpointRounding.AwayFromZero) / 10;
    public static string Format(double value) => Round(value).ToString("0.0", CultureInfo.InvariantCulture);

    public static bool Accepts(string text)
    {
        if (!ValidSyntax(text)) { return false; }
        if (text is "" or "." or "0" or "0.") { return true; }
        if (text.EndsWith('.')) { return TryValue(text[..^1], out _); }
        return TryValue(text, out _);
    }

    public static bool TryValue(string text, out InputGammaInterpretation gamma)
    {
        gamma = InputGammaInterpretation.Automatic;
        if (!ValidSyntax(text) || text.Length == 0 || text.EndsWith('.') ||
            !double.TryParse(text, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out double value) ||
            !InputGammaInterpretation.IsValidPower(value)) { return false; }
        gamma = InputGammaInterpretation.Power(value);
        return true;
    }

    private static bool ValidSyntax(string text)
    {
        if (text.Length > 6 || text.Any(c => (c < '0' || c > '9') && c != '.') || text.Count(c => c == '.') > 1) { return false; }
        int dot = text.IndexOf('.');
        return dot < 0 || text.Length - dot - 1 <= 1;
    }
}
