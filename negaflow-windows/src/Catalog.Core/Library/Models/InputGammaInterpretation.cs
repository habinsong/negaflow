namespace Negaflow.Catalog;

public readonly record struct InputGammaInterpretation
{
    public double? Value { get; }
    public bool IsAutomatic => Value is null;
    public static InputGammaInterpretation Automatic => default;

    private InputGammaInterpretation(double value) => Value = value;

    public static InputGammaInterpretation Power(double value)
    {
        if (!IsValidPower(value)) { throw new ArgumentOutOfRangeException(nameof(value)); }
        return new(value);
    }

    public static bool IsValidPower(double value) => double.IsFinite(value) && value is >= 0.10 and <= 4.00;
}
