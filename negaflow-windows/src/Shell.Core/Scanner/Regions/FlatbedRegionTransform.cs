using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 평판 프레임 한 장을 게시할 때 처음 걸 변환입니다. 프리뷰에서 맞춘 방향은 이어받고, 자르기와
/// 비율은 버리며, 검출이 잰 기울기를 곧게 펴기로 겁니다.
/// </summary>
internal static class FlatbedRegionTransform
{
    internal static ImageTransformRecipe Initial(
        ImageTransformRecipe? previewTransform,
        ImageRotation defaultRotation,
        FlatbedScanRegion region)
    {
        ArgumentNullException.ThrowIfNull(region);
        ImageTransformRecipe orientation = previewTransform is null
            ? ImageTransformRecipe.Identity
            : previewTransform with
            {
                Crop = null,
                StraightenAngle = 0.0,
                CropAspect = null,
            };
        if (orientation == ImageTransformRecipe.Identity)
        {
            orientation = ImageTransformRecipe.Identity with { Rotation = defaultRotation };
        }
        return orientation with
        {
            Crop = null,
            StraightenAngle = orientation.FlipHorizontal != orientation.FlipVertical
                ? -region.StraightenAngle
                : region.StraightenAngle,
            CropAspect = null,
        };
    }
}
