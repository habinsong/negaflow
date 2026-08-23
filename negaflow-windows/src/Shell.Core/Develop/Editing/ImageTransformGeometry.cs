using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 돌리기·뒤집기가 <b>크롭을 지키며</b> 어떻게 바뀌는지입니다. macOS
/// <c>AppModel+TransformControls.swift</c> 의 <c>private extension ImageTransform</c> 과
/// 같은 계산이며, 카탈로그를 만지지 않으므로 그대로 시험할 수 있습니다.
/// </summary>
public static class ImageTransformGeometry
{
    /// <summary>
    /// macOS <c>rotatePreservingCrop(clockwise:)</c>. 고른 비율은 뒤집히고, 크롭 사각형은
    /// 같은 자리를 가리키도록 함께 돕니다.
    /// </summary>
    /// <remarks>
    /// 이것이 없으면 크롭해 둔 사진을 돌렸을 때 잘린 자리가 엉뚱한 곳으로 옮겨 갑니다.
    /// </remarks>
    public static ImageTransformRecipe Rotate(ImageTransformRecipe transform, bool clockwise)
    {
        ArgumentNullException.ThrowIfNull(transform);
        ImageRotation rotation = clockwise
            ? transform.Rotation switch
            {
                ImageRotation.Degrees0 => ImageRotation.Degrees90,
                ImageRotation.Degrees90 => ImageRotation.Degrees180,
                ImageRotation.Degrees180 => ImageRotation.Degrees270,
                _ => ImageRotation.Degrees0,
            }
            : transform.Rotation switch
            {
                ImageRotation.Degrees0 => ImageRotation.Degrees270,
                ImageRotation.Degrees90 => ImageRotation.Degrees0,
                ImageRotation.Degrees180 => ImageRotation.Degrees90,
                _ => ImageRotation.Degrees180,
            };

        double? aspect = transform.CropAspect is { } chosen && chosen > 0.0
            ? 1.0 / chosen
            : transform.CropAspect;
        ImageCropRect? crop = transform.Crop is { } box
            ? clockwise
                // macOS: SIMD4(y, 1 - x - width, height, width)
                ? new ImageCropRect(box.Y, 1.0 - box.X - box.Width, box.Height, box.Width)
                // macOS: SIMD4(1 - y - height, x, height, width)
                : new ImageCropRect(1.0 - box.Y - box.Height, box.X, box.Height, box.Width)
            : null;

        return transform with { Rotation = rotation, CropAspect = aspect, Crop = crop };
    }

    /// <summary>
    /// macOS <c>toggleFlipPreservingCrop(displayHorizontal:)</c>.
    /// </summary>
    /// <remarks>
    /// 사용자가 누르는 축은 <b>화면에 보이는</b> 축입니다. 변형 순서가 뒤집기 → 돌리기라
    /// 90·270 에서는 원본의 좌우 뒤집기가 화면에서 상하로 나타납니다 — 그래서 돌린 뒤
    /// "좌우 뒤집기" 를 누르면 상하가 뒤집혔습니다. 화면 축을 원본 축으로 옮겨 켭니다.
    /// 수평 보정 각도는 부호가 뒤집히고, 크롭 사각형은 누른 축 그대로 미러합니다.
    /// </remarks>
    public static ImageTransformRecipe Flip(
        ImageTransformRecipe transform,
        bool displayHorizontal)
    {
        ArgumentNullException.ThrowIfNull(transform);
        bool rotationSwapsAxes =
            transform.Rotation is ImageRotation.Degrees90 or ImageRotation.Degrees270;
        bool flipHorizontal = transform.FlipHorizontal;
        bool flipVertical = transform.FlipVertical;
        if (displayHorizontal != rotationSwapsAxes)
        {
            flipHorizontal = !flipHorizontal;
        }
        else
        {
            flipVertical = !flipVertical;
        }

        ImageCropRect? crop = transform.Crop is { } box
            ? displayHorizontal
                ? box with { X = 1.0 - box.X - box.Width }
                : box with { Y = 1.0 - box.Y - box.Height }
            : null;

        return transform with
        {
            FlipHorizontal = flipHorizontal,
            FlipVertical = flipVertical,
            // 0 을 뒤집으면 -0 이 됩니다. 카탈로그에 "-0" 이 적히지 않게 되돌립니다.
            StraightenAngle = -transform.StraightenAngle + 0.0,
            Crop = crop,
        };
    }
}
