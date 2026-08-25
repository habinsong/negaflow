using System.Globalization;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 크롭 오버레이는 <b>사진이 놓인 그 프레임</b> 위에 그려져야 합니다. macOS 는
/// <c>canvasFittedImageFrame(..., scale:offset:)</c> 하나를 <c>imageLayer</c> 와
/// <c>CropOverlay</c> 에 똑같이 넘깁니다(<c>CanvasView.swift</c>).
/// </summary>
/// <remarks>
/// 앞 판은 줌·팬 때 사진만 다시 놓고 크롭은 옛 프레임에 남겨 뒀습니다
/// (<c>DevelopPreviewCanvas.ApplyImageFrame</c> 이 <c>RenderCropOverlay</c> 를 부르지 않았고,
/// <c>CropWorkspaceState.OverlayFrame</c> 주석이 "줌·팬은 사진만 바꾸므로 이 값은 유지" 라고
/// 적어 두었습니다). 그래서 확대하면 크롭이 사진 안쪽으로 들어가고, 축소하면 <b>사진보다
/// 넓게</b> 잡혔습니다. 사용자가 실제로 본 증상입니다.
/// </remarks>
internal static class CropOverlayZoomTests
{
    private const double CanvasWidth = 1200.0;
    private const double CanvasHeight = 800.0;
    private const int PixelWidth = 3000;
    private const int PixelHeight = 2000;
    private const double ActionBarHeight = 42.0;

    public static void Run()
    {
        CropDisplayRect selection = new(0.25, 0.25, 0.5, 0.5);

        // 축소·기본·확대, 그리고 팬까지 섞어 봅니다.
        (double Scale, double OffsetX, double OffsetY)[] views =
        [
            (0.4, 0.0, 0.0),
            (1.0, 0.0, 0.0),
            (2.5, 0.0, 0.0),
            (2.5, -180.0, 90.0),
        ];

        foreach ((double scale, double offsetX, double offsetY) in views)
        {
            string label = string.Create(
                CultureInfo.InvariantCulture,
                $"scale_{scale:0.0}_offset_{offsetX:0}_{offsetY:0}");
            Check(
                PreviewFrame.TryFromViewport(
                    CanvasWidth,
                    CanvasHeight,
                    PixelWidth,
                    PixelHeight,
                    scale,
                    offsetX,
                    offsetY,
                    out PreviewFrame image),
                "crop_overlay_viewport_frame_exists_" + label);

            CropOverlayPlacement box = CropInteraction
                .Layout(image, selection, ActionBarHeight)
                .Selection;

            Check(
                Math.Abs(box.Left - (image.Left + selection.X * image.Width)) < 1e-9 &&
                Math.Abs(box.Top - (image.Top + selection.Y * image.Height)) < 1e-9 &&
                Math.Abs(box.Width - selection.Width * image.Width) < 1e-9 &&
                Math.Abs(box.Height - selection.Height * image.Height) < 1e-9,
                "crop_overlay_tracks_the_image_frame_" + label);

            // 어떤 줌에서도 사진 밖으로 나가지 않습니다.
            Check(
                box.Left >= image.Left - 1e-9 &&
                box.Top >= image.Top - 1e-9 &&
                box.Left + box.Width <= image.Right + 1e-9 &&
                box.Top + box.Height <= image.Bottom + 1e-9,
                "crop_overlay_stays_inside_the_photo_" + label);
        }

        VerifyStaleFrameReproducesTheDefect(selection);
    }

    /// <summary>
    /// 프레임을 갱신하지 않았을 때 화면에 나온 모습을 그대로 재현합니다. 이 단언이 깨지면
    /// 위 검사가 실제로 무엇을 막고 있는지 알 수 없게 됩니다.
    /// </summary>
    private static void VerifyStaleFrameReproducesTheDefect(CropDisplayRect selection)
    {
        Check(
            PreviewFrame.TryFromViewport(
                CanvasWidth, CanvasHeight, PixelWidth, PixelHeight, 1.0, 0.0, 0.0,
                out PreviewFrame fitted) &&
            PreviewFrame.TryFromViewport(
                CanvasWidth, CanvasHeight, PixelWidth, PixelHeight, 0.4, 0.0, 0.0,
                out PreviewFrame shrunk) &&
            CropInteraction.Layout(fitted, selection, ActionBarHeight).Selection.Width >
                shrunk.Width,
            "stale_frame_reproduces_crop_wider_than_the_photo");

        Check(
            PreviewFrame.TryFromViewport(
                CanvasWidth, CanvasHeight, PixelWidth, PixelHeight, 1.0, 0.0, 0.0,
                out PreviewFrame same) &&
            PreviewFrame.TryFromViewport(
                CanvasWidth, CanvasHeight, PixelWidth, PixelHeight, 2.5, 0.0, 0.0,
                out PreviewFrame magnified) &&
            CropInteraction.Layout(same, selection, ActionBarHeight).Selection.Width <
                CropInteraction.Layout(magnified, selection, ActionBarHeight).Selection.Width,
            "stale_frame_reproduces_crop_shrinking_into_the_photo");
    }
}
