namespace Negaflow.Catalog;

/// <summary>macOS Color Grading의 그림자·중간톤·하이라이트 조정 값입니다.</summary>
public readonly record struct ColorGradeRegionRecipe(
    double Hue,
    double Saturation,
    double Luminance);

/// <summary>macOS Color Grading recipe입니다.</summary>
public sealed record ColorGradingRecipe(
    ColorGradeRegionRecipe Shadows,
    ColorGradeRegionRecipe Midtones,
    ColorGradeRegionRecipe Highlights,
    double Blending,
    double Balance)
{
    public static ColorGradingRecipe Identity { get; } = new(
        new ColorGradeRegionRecipe(0.0, 0.0, 0.0),
        new ColorGradeRegionRecipe(0.0, 0.0, 0.0),
        new ColorGradeRegionRecipe(0.0, 0.0, 0.0),
        0.5,
        0.0);
}
