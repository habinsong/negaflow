namespace Negaflow.Catalog;

public sealed record ColorModelRecipe(
    double Warmth,
    double Tint,
    double ColorDepth,
    double Vibrance,
    double Saturation,
    double RedPrimary,
    double GreenPrimary,
    double BluePrimary)
{
    public static ColorModelRecipe Identity { get; } = new(0, 0, 0, 0, 0, 0, 0, 0);

    internal bool IsValid() =>
        new[]
        {
            Warmth, Tint, ColorDepth, Vibrance, Saturation,
            RedPrimary, GreenPrimary, BluePrimary,
        }.All(value => double.IsFinite(value) && value is >= -1.0 and <= 1.0);
}
