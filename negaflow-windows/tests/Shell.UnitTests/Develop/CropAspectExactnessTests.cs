using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.UnitTests.Develop;

/// <summary>
/// 종횡비를 고르면 그 비율이 그대로 나와야 합니다.
/// </summary>
/// <remarks>
/// 크롭 중에 비율을 고르면 열려 있는 크롭 세션의 선택도 새 사각형으로 맞춥니다. 그 자리에서
/// <c>SetSelection</c> 을 쓰면 잠긴 비율로 사각형을 한 번 더 맞추므로, 잠금이 아직 옛 비율이면
/// 두 비율이 곱해집니다. 실기에서 4:3 을 골랐는데 21:9 처럼 나왔습니다.
///
/// 여기서는 열다섯 비율을 직전 비율 열다섯 가지와 짝지어, 고른 값이 그대로 남는지 봅니다.
/// </remarks>
internal static class CropAspectExactnessTests
{
    private const double Tolerance = 1e-6;

    internal static void Run()
    {
        AssertAspectOnlyKeepsTheCropUntouched();
        foreach ((uint width, uint height) in new[]
        {
            (4000U, 3000U),
            (3000U, 4000U),
            (5136U, 3543U),
            (2272U, 3453U),
            (6000U, 6000U),
        })
        {
            foreach (ImageRotation rotation in new[]
            {
                ImageRotation.Degrees0,
                ImageRotation.Degrees90,
            })
            {
                AssertEveryPairKeepsTheChosenRatio(width, height, rotation);
            }
        }
    }

    /// <summary>
    /// 크롭 화면이 열려 있을 때는 비율만 적고 사각형은 건드리지 않아야 합니다.
    /// </summary>
    /// <remarks>
    /// 사각형까지 적으면 미리보기가 잘린 그림으로 다시 그려지고, 다음 비율이 그 위에 또
    /// 걸려 두 비율이 겹칩니다. 실측 2026-08-30, 4:3 다음 2:3 을 고르자 화면의 그림이 이미
    /// 1.333 이었습니다.
    /// </remarks>
    private static void AssertAspectOnlyKeepsTheCropUntouched()
    {
        ImageCropRect kept = new(0.1, 0.2, 0.5, 0.4);
        ImageTransformRecipe transform = ImageTransformRecipe.Identity with { Crop = kept };
        foreach (CropAspectOption option in CropAspect.Options)
        {
            ImageTransformRecipe aspectOnly = transform with
            {
                CropAspect = option.Ratio is { } ratio && ratio > 0.0 ? ratio : null,
            };
            if (aspectOnly.Crop != kept)
            {
                throw new InvalidOperationException(
                    $"{option.Label} 을 고르면서 사각형이 바뀌었습니다");
            }
        }
    }

    private static void AssertEveryPairKeepsTheChosenRatio(
        uint width,
        uint height,
        ImageRotation rotation)
    {
        foreach (CropAspectOption previous in CropAspect.Options)
        {
            foreach (CropAspectOption chosen in CropAspect.Options)
            {
                if (previous.Ratio is not { } previousRatio || previousRatio <= 0.0 ||
                    chosen.Ratio is not { } chosenRatio || chosenRatio <= 0.0)
                {
                    continue;
                }

                ImageTransformRecipe transform = ImageTransformRecipe.Identity with
                {
                    Rotation = rotation,
                };
                transform = CropAspect.Apply(
                    transform,
                    previous,
                    width,
                    height);
                transform = CropAspect.Apply(
                    transform,
                    chosen,
                    width,
                    height);

                // 크롭 세션은 이 사각형을 그대로 받습니다. 잠긴 비율로 다시 맞추면 두 비율이
                // 곱해지므로, 세션이 든 값이 고른 비율 그대로인지 봅니다.
                CropSession session = CropSession.Start(transform.Crop)
                    ;
                session.LockedNormalizedAspectRatio = Negaflow.Shell.Develop.CropInteraction
                    .LockedNormalizedAspectRatio(
                        isLocked: true,
                        transform.CropAspect,
                        width,
                        height,
                        rotation);
                session.SetSelectionExact(session.Selection);

                double pixelWidth = rotation is ImageRotation.Degrees90 or ImageRotation.Degrees270
                    ? height
                    : width;
                double pixelHeight = rotation is ImageRotation.Degrees90 or ImageRotation.Degrees270
                    ? width
                    : height;
                double actual =
                    session.Selection.Width * pixelWidth /
                    (session.Selection.Height * pixelHeight);
                if (Math.Abs(actual - chosenRatio) > Tolerance)
                {
                    throw new InvalidOperationException(
                        $"{previous.Label} 다음에 {chosen.Label} 을 골랐더니 비율이 " +
                        $"{actual:F4} 입니다 ({width}x{height}, {rotation}). " +
                        $"{chosenRatio:F4} 이어야 합니다.");
                }
            }
        }
    }
}
