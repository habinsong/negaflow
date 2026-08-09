namespace Negaflow.Catalog;

/// <summary>
/// macOS <c>ColorMixer</c>와 같은 여덟 HSL 밴드의 조정 recipe입니다.
/// </summary>
public sealed record ColorMixerRecipe(
    IReadOnlyList<double> Hue,
    IReadOnlyList<double> Saturation,
    IReadOnlyList<double> Luminance)
{
    public const int BandCount = 8;

    public static ColorMixerRecipe Identity { get; } = new(
        new double[BandCount],
        new double[BandCount],
        new double[BandCount]);
}
