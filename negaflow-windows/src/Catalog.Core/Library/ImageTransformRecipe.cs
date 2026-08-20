namespace Negaflow.Catalog;

/// <summary>
/// macOS <c>ImageTransform</c>와 같은 회전 값입니다. 저장값은 Swift recipe의 raw value와
/// 같고, crop 좌표는 y-up 정규화 좌표를 사용합니다.
/// </summary>
public enum ImageRotation
{
    Degrees0 = 0,
    Degrees90 = 1,
    Degrees180 = 2,
    Degrees270 = 3,
}

public readonly record struct ImageCropRect(double X, double Y, double Width, double Height)
{
    public bool IsValid =>
        double.IsFinite(X) && double.IsFinite(Y) &&
        double.IsFinite(Width) && double.IsFinite(Height) &&
        X >= 0.0 && Y >= 0.0 && Width > 0.0 && Height > 0.0 &&
        X + Width <= 1.0 && Y + Height <= 1.0;
}

/// <summary>
/// 현상과 내보내기에 공통으로 적용되는 macOS 호환 기하 보정 recipe입니다.
/// </summary>
public sealed record ImageTransformRecipe(
    ImageRotation Rotation,
    bool FlipHorizontal,
    bool FlipVertical,
    ImageCropRect? Crop,
    double StraightenAngle,
    double? CropAspect)
{
    public static ImageTransformRecipe Identity { get; } = new(
        ImageRotation.Degrees0,
        false,
        false,
        null,
        0.0,
        null);

    public bool IsValid =>
        Enum.IsDefined(Rotation) &&
        (Crop is null || Crop.Value.IsValid) &&
        double.IsFinite(StraightenAngle) && StraightenAngle is >= -45.0 and <= 45.0 &&
        (CropAspect is null || (double.IsFinite(CropAspect.Value) && CropAspect.Value > 0.0));

    /// <summary>
    /// macOS <c>ImageTransform.displayName</c> — 편집 카드 머리줄 오른쪽에 적는 값입니다.
    /// 각도 뒤에 뒤집기를 <c>H</c>·<c>V</c> 로 덧붙여 <c>"180 H"</c> 처럼 냅니다.
    /// </summary>
    public string DisplayName
    {
        get
        {
            string text = Rotation switch
            {
                ImageRotation.Degrees90 => "90",
                ImageRotation.Degrees180 => "180",
                ImageRotation.Degrees270 => "270",
                _ => "0",
            };
            if (FlipHorizontal)
            {
                text += " H";
            }
            if (FlipVertical)
            {
                text += " V";
            }
            return text;
        }
    }
}
