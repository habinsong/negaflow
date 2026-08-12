using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 종횡비 선택입니다. macOS <c>ToolStripSection.aspectOptions</c> 와 같은 목록·같은 순서입니다.
/// </summary>
public readonly record struct CropAspectOption(string Label, double? Ratio)
{
    /// <summary>사용자가 직접 끈 자유 비율입니다. macOS 의 <c>-1</c> 자리입니다.</summary>
    public bool IsCustom => Ratio is -1.0;

    /// <summary>원본 비율로 되돌립니다 — 비율과 crop 을 함께 지웁니다.</summary>
    public bool IsOriginal => Ratio is null;
}

public static class CropAspect
{
    public static IReadOnlyList<CropAspectOption> Options { get; } =
    [
        new("original", null),
        new("custom", -1.0),
        new("2:3", 2.0 / 3.0),
        new("3:2", 3.0 / 2.0),
        new("4:3", 4.0 / 3.0),
        new("3:4", 3.0 / 4.0),
        new("4:5", 4.0 / 5.0),
        new("5:4", 5.0 / 4.0),
        new("16:9", 16.0 / 9.0),
        new("9:16", 9.0 / 16.0),
        new("16:10", 16.0 / 10.0),
        new("10:16", 10.0 / 16.0),
        new("65:24", 65.0 / 24.0),
        new("24:65", 24.0 / 65.0),
        new("3:1", 3.0),
        new("1:3", 1.0 / 3.0),
        new("1:1", 1.0),
    ];

    /// <summary>
    /// 지금 걸린 비율에 붙일 이름입니다. 비율이 없으면 crop 유무에 따라 원본/사용자 지정입니다.
    /// </summary>
    public static string LabelFor(ImageTransformRecipe transform)
    {
        ArgumentNullException.ThrowIfNull(transform);
        if (transform.CropAspect is not { } aspect)
        {
            return transform.Crop is null ? "original" : "custom";
        }
        foreach (CropAspectOption option in Options)
        {
            if (option.Ratio is { } ratio && ratio > 0.0 && Math.Abs(ratio - aspect) < 1e-3)
            {
                return option.Label;
            }
        }
        return "custom";
    }

    /// <summary>
    /// 비율을 고르면 그 비율로 가운데 정렬된 최대 crop 을 만듭니다. macOS 와 같이 회전이
    /// 90/270 이면 가로세로를 바꿔 계산합니다.
    /// </summary>
    /// <param name="pixelWidth">회전 전 원본 가로 화소.</param>
    /// <param name="pixelHeight">회전 전 원본 세로 화소.</param>
    public static ImageTransformRecipe Apply(
        ImageTransformRecipe transform,
        CropAspectOption option,
        uint pixelWidth,
        uint pixelHeight)
    {
        ArgumentNullException.ThrowIfNull(transform);
        if (option.IsCustom)
        {
            // 자유 비율은 지금 crop 을 그대로 두고 잠금만 풉니다.
            return transform with { CropAspect = null };
        }
        if (option.Ratio is not { } ratio || ratio <= 0.0)
        {
            return transform with { CropAspect = null, Crop = null };
        }
        if (pixelWidth == 0U || pixelHeight == 0U)
        {
            // 크기를 모르면 비율만 기억해 둡니다. 다음에 크기를 알 때 crop 이 만들어집니다.
            return transform with { CropAspect = ratio };
        }

        double width = pixelWidth;
        double height = pixelHeight;
        if (transform.Rotation is ImageRotation.Degrees90 or ImageRotation.Degrees270)
        {
            (width, height) = (height, width);
        }
        double cropWidth;
        double cropHeight;
        if (width / height > ratio)
        {
            cropHeight = height;
            cropWidth = ratio * height;
        }
        else
        {
            cropWidth = width;
            cropHeight = width / ratio;
        }
        double normalizedWidth = cropWidth / width;
        double normalizedHeight = cropHeight / height;
        return transform with
        {
            CropAspect = ratio,
            Crop = new ImageCropRect(
                (1.0 - normalizedWidth) / 2.0,
                (1.0 - normalizedHeight) / 2.0,
                normalizedWidth,
                normalizedHeight),
        };
    }
}
