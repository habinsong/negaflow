namespace Negaflow.Catalog;

/// <summary>macOS <c>CalibrationAdjust</c>의 R/G/B primary hue·saturation recipe입니다.</summary>
public sealed record PrimaryCalibrationRecipe(
    double RedHue,
    double RedSaturation,
    double GreenHue,
    double GreenSaturation,
    double BlueHue,
    double BlueSaturation)
{
    public static PrimaryCalibrationRecipe Identity { get; } = new(0, 0, 0, 0, 0, 0);
}
