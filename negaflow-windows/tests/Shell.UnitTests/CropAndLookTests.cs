using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;
using Negaflow.Shell.Shortcuts;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class CropAndLookTests
{
    public static void Run()
    {
        VerifyCropSession();
        VerifyLookPresetReachesTheEngine();
        VerifyDisplayToRawMapping();
        VerifyManualDefectCoordinatesMatchMacOS();
        VerifyDevelopedPixelSizeFollowsTheTransform();
        VerifyCropHandlesAreGrabbableWhereTheyAreDrawn();
        VerifyCropHitTestingUsesTheDisplayedFrameAcrossZoom();
        VerifyAspectLockUsesTheCurrentRectangleWhenNoRatioIsChosen();
        VerifyRotateAndFlipKeepTheCropWhereItWas();
    }

    /// <summary>
    /// 돌리기·뒤집기는 <b>크롭을 지킵니다</b>. macOS <c>rotatePreservingCrop</c> ·
    /// <c>toggleFlipPreservingCrop</c> 과 같은 값이어야 합니다.
    /// </summary>
    /// <remarks>
    /// 앞 판은 회전값·뒤집기 깃발만 바꿨습니다. 그래서 (가) 크롭해 둔 사진을 돌리면 잘린
    /// 자리가 옮겨 가고, (나) 90·270 으로 돌린 뒤 "좌우 뒤집기" 를 누르면 <b>상하</b>가
    /// 뒤집혔습니다 — 원본 축과 화면 축이 다르기 때문입니다.
    /// </remarks>
    private static void VerifyRotateAndFlipKeepTheCropWhereItWas()
    {
        ImageCropRect box = new(0.10, 0.20, 0.30, 0.40);
        ImageTransformRecipe start = ImageTransformRecipe.Identity with
        {
            Crop = box,
            CropAspect = 3.0 / 2.0,
            StraightenAngle = 4.0,
        };

        // 시계로 한 번: SIMD4(y, 1 - x - width, height, width)
        ImageTransformRecipe once = ImageTransformGeometry.Rotate(start, clockwise: true);
        Check(once.Rotation == ImageRotation.Degrees90, "clockwise turns 0 into 90");
        Check(
            once.Crop is { } turned &&
            Math.Abs(turned.X - 0.20) < 1e-12 &&
            Math.Abs(turned.Y - (1.0 - 0.10 - 0.30)) < 1e-12 &&
            Math.Abs(turned.Width - 0.40) < 1e-12 &&
            Math.Abs(turned.Height - 0.30) < 1e-12,
            "clockwise turns the crop with the photo");
        Check(
            once.CropAspect is { } flipped && Math.Abs(flipped - (2.0 / 3.0)) < 1e-12,
            "clockwise inverts the chosen ratio");

        // 네 번 돌리면 제자리입니다.
        ImageTransformRecipe full = once;
        for (int turn = 0; turn < 3; ++turn)
        {
            full = ImageTransformGeometry.Rotate(full, clockwise: true);
        }
        Check(full.Rotation == ImageRotation.Degrees0, "four turns come back to zero");
        Check(
            full.Crop is { } same &&
            Math.Abs(same.X - box.X) < 1e-12 &&
            Math.Abs(same.Y - box.Y) < 1e-12 &&
            Math.Abs(same.Width - box.Width) < 1e-12 &&
            Math.Abs(same.Height - box.Height) < 1e-12,
            "four turns come back to the same crop");
        Check(
            full.CropAspect is { } back && Math.Abs(back - (3.0 / 2.0)) < 1e-12,
            "four turns come back to the same ratio");

        // 시계 → 반시계는 제자리입니다.
        ImageTransformRecipe there = ImageTransformGeometry.Rotate(start, clockwise: true);
        ImageTransformRecipe andBack = ImageTransformGeometry.Rotate(there, clockwise: false);
        Check(andBack.Rotation == ImageRotation.Degrees0, "turning back returns to zero");
        Check(
            andBack.Crop is { } returned &&
            Math.Abs(returned.X - box.X) < 1e-12 &&
            Math.Abs(returned.Y - box.Y) < 1e-12,
            "turning back returns the crop");

        // 돌리지 않은 사진: 화면 좌우 = 원본 좌우.
        ImageTransformRecipe mirrored = ImageTransformGeometry.Flip(start, displayHorizontal: true);
        Check(mirrored.FlipHorizontal && !mirrored.FlipVertical, "unrotated left-right flips the source x");
        Check(
            mirrored.Crop is { } across && Math.Abs(across.X - (1.0 - 0.10 - 0.30)) < 1e-12,
            "the crop mirrors across");
        Check(
            Math.Abs(mirrored.StraightenAngle + 4.0) < 1e-12,
            "flipping negates the straighten angle");

        // 90 도로 돌린 사진: 화면 좌우 = 원본 <b>상하</b>.
        ImageTransformRecipe turnedOnce = ImageTransformGeometry.Rotate(start, clockwise: true);
        ImageTransformRecipe afterTurn =
            ImageTransformGeometry.Flip(turnedOnce, displayHorizontal: true);
        Check(
            !afterTurn.FlipHorizontal && afterTurn.FlipVertical,
            "after a quarter turn the screen's left-right is the source's up-down");

        // 두 번 뒤집으면 제자리입니다.
        ImageTransformRecipe twice =
            ImageTransformGeometry.Flip(mirrored, displayHorizontal: true);
        Check(
            !twice.FlipHorizontal && !twice.FlipVertical &&
            twice.Crop is { } home && Math.Abs(home.X - box.X) < 1e-12 &&
            Math.Abs(twice.StraightenAngle - 4.0) < 1e-12,
            "flipping twice comes back");
    }

    /// <summary>
    /// 크롭 핸들은 <b>그려진 사각형 그대로</b> 잡혀야 합니다. 모서리 핸들은 모서리를
    /// 가운데에 두고 14×14 로 그리므로 그 절반이 사각형 밖에 있습니다.
    /// </summary>
    /// <remarks>
    /// 실측으로 고정합니다 — 고치기 전에는 왼쪽 위 모서리를 <b>정확히</b> 눌러도
    /// <c>mapped=False</c> 로 죽었고(그림 밖 거부), 히트 영역은 정규 0.025 라 프레임 비율에
    /// 따라 가로 17.5 · 세로 26 처럼 제멋대로였습니다.
    /// </remarks>
    private static void VerifyCropHandlesAreGrabbableWhereTheyAreDrawn()
    {
        // 실행 중인 창에서 잰 값입니다: 프레임 700×1049 DIP, 크롭은 전체.
        const double frameWidth = 700.0;
        const double frameHeight = 1049.0;
        CropDisplayRect full = new(0.0, 0.0, 1.0, 1.0);
        double halfCorner = CropInteraction.HandleSize / 2.0;

        Check(
            CropInteraction.BeginDrag(new CropDisplayPoint(0.0, 0.0), full, frameWidth, frameHeight)
                == CropDragMode.TopLeft,
            "crop handle grabs at the very corner");
        Check(
            CropInteraction.BeginDrag(
                new CropDisplayPoint((halfCorner - 0.5) / frameWidth, (halfCorner - 0.5) / frameHeight),
                full,
                frameWidth,
                frameHeight) == CropDragMode.TopLeft,
            "crop handle grabs at its inner edge");
        Check(
            CropInteraction.BeginDrag(
                new CropDisplayPoint(8.0 / frameWidth, 8.0 / frameHeight),
                full,
                frameWidth,
                frameHeight) == CropDragMode.Create,
            "past the handle the drag creates a new rectangle");
        Check(
            CropInteraction.BeginDrag(
                new CropDisplayPoint(0.5 + (11.0 / frameWidth), 0.0),
                full,
                frameWidth,
                frameHeight) == CropDragMode.Top,
            "the top handle is long across");
        Check(
            CropInteraction.BeginDrag(
                new CropDisplayPoint(0.5 + (13.0 / frameWidth), 0.0),
                full,
                frameWidth,
                frameHeight) != CropDragMode.Top,
            "the top handle stops at its drawn width");

        // 그림 밖 여백까지 받아 가장자리로 붙입니다 — 핸들의 바깥 절반입니다.
        PreviewFrame frame = new(100.0, 50.0, frameWidth, frameHeight);
        bool outerMapped = frame.TryMapPoint(
            100.0 - 6.0,
            50.0 - 6.0,
            CropInteraction.LongHandleSize / 2.0,
            out CropDisplayPoint outer,
            out bool insideOuter);
        Check(outerMapped, "the outer half of a handle still maps");
        Check(!insideOuter, "the outer half is reported as outside");
        Check(outer.X == 0.0 && outer.Y == 0.0, "the outer half clamps to the edge");
        Check(
            !frame.TryMapPoint(
                100.0 - 40.0,
                50.0 - 40.0,
                CropInteraction.LongHandleSize / 2.0,
                out _,
                out _),
            "far outside the frame is still refused");
    }

    private static void VerifyCropHitTestingUsesTheDisplayedFrameAcrossZoom()
    {
        var crop = new CropWorkspaceState();
        crop.Begin(new ImageCropRect(0.1, 0.5, 0.2, 0.3), lockedNormalizedAspect: null);
        crop.MarkPreviewReady();

        PreviewFrame displayed = new(100.0, 50.0, 700.0, 1000.0);
        crop.SetOverlayFrame(displayed);
        CropDisplayRect selection = crop.Session!.Selection;
        double pointerX = displayed.Left + (selection.X + selection.Width / 2.0) * displayed.Width;
        double pointerY = displayed.Top + (selection.Y + selection.Height / 2.0) * displayed.Height;

        Check(
            displayed.TryMapPoint(pointerX, pointerY, out CropDisplayPoint displayedPoint) &&
            crop.TryBeginDrag(displayedPoint, displayed.Width, displayed.Height, allowCreate: true) &&
            crop.DragMode == CropDragMode.Move,
            "crop interior stays movable after the image zooms");
        crop.EndDrag();

        // 사진만 2배 확대된 프레임으로 같은 화면 좌표를 환산하면 선택 밖이 됩니다. 앞 판은
        // 이 좌표를 써서 내부 드래그를 새 사각형 만들기로 잘못 판정했습니다.
        PreviewFrame zoomedImage = new(-250.0, -450.0, 1400.0, 2000.0);
        Check(
            zoomedImage.TryMapPoint(pointerX, pointerY, out CropDisplayPoint wrongPoint) &&
            CropInteraction.BeginDrag(wrongPoint, selection, zoomedImage.Width, zoomedImage.Height)
                == CropDragMode.Create,
            "zoomed image coordinates reproduce the old redraw defect");

        PreviewFrame rotatedPreview = new(50.0, 100.0, 1000.0, 700.0);
        crop.SetOverlayFrame(rotatedPreview);
        Check(crop.OverlayFrame == rotatedPreview, "a new rotated preview refreshes the crop frame");
    }

    /// <summary>
    /// 비율을 고르지 않았을 때 자물쇠는 <b>지금 사각형</b>의 비율을 잠급니다 — macOS
    /// <c>cropAspectLockRatio(for:)</c> 와 같습니다. 앞 판은 null 을 내서 자물쇠가 아무
    /// 일도 하지 않았습니다.
    /// </summary>
    private static void VerifyAspectLockUsesTheCurrentRectangleWhenNoRatioIsChosen()
    {
        const uint width = 6000U;
        const uint height = 4000U;
        CropDisplayRect square = new(0.25, 0.25, 0.25, 0.375);

        double? free = CropInteraction.LockedNormalizedAspectRatio(
            true, null, width, height, ImageRotation.Degrees0, square);
        Check(free is not null, "the lock without a chosen ratio is not null");
        // 화소 비율 = 0.25*6000 / 0.375*4000 = 1500/1500 = 1 → 정규 = 1 * 4000/6000.
        Check(
            free is { } ratio && Math.Abs(ratio - (4000.0 / 6000.0)) < 1e-9,
            "the lock keeps the rectangle's own pixel ratio");

        double? chosen = CropInteraction.LockedNormalizedAspectRatio(
            true, 3.0 / 2.0, width, height, ImageRotation.Degrees0, square);
        Check(
            chosen is { } picked && Math.Abs(picked - (1.5 * 4000.0 / 6000.0)) < 1e-9,
            "a chosen ratio wins over the rectangle");

        Check(
            CropInteraction.LockedNormalizedAspectRatio(
                false, null, width, height, ImageRotation.Degrees0, square) is null,
            "an unlocked aspect is still null");

        double? whole = CropInteraction.LockedNormalizedAspectRatio(
            true, null, width, height, ImageRotation.Degrees0);
        Check(
            whole is { } all && Math.Abs(all - 1.0) < 1e-9,
            "without a rectangle the whole image ratio is locked");

        double? turned = CropInteraction.LockedNormalizedAspectRatio(
            true, 3.0 / 2.0, width, height, ImageRotation.Degrees90);
        Check(
            turned is { } spun && Math.Abs(spun - (1.5 * 6000.0 / 4000.0)) < 1e-9,
            "rotation swaps the pixel box");
    }

    private static void VerifyDevelopedPixelSizeFollowsTheTransform()
    {
        const uint width = 5088U;
        const uint height = 3401U;

        static bool Size(
            ImageTransformRecipe transform,
            out double developedWidth,
            out double developedHeight) =>
            DevelopDisplayGeometry.TryDevelopedPixelSize(
                transform, width, height, out developedWidth, out developedHeight);

        Check(Size(ImageTransformRecipe.Identity, out double w, out double h) &&
            Near(w, width) && Near(h, height),
            "developed_pixel_size_identity_is_the_source_size");

        // 가로 스캔을 90° 돌리면 세로가 됩니다. 여기가 어긋나면 인화가 가로 칸을 만듭니다.
        ImageTransformRecipe turned =
            ImageTransformRecipe.Identity with { Rotation = ImageRotation.Degrees90 };
        Check(Size(turned, out w, out h) && Near(w, height) && Near(h, width) && w < h,
            "developed_pixel_size_swaps_axes_on_quarter_turn");
        ImageTransformRecipe turnedBack =
            ImageTransformRecipe.Identity with { Rotation = ImageRotation.Degrees270 };
        Check(Size(turnedBack, out w, out h) && Near(w, height) && Near(h, width),
            "developed_pixel_size_swaps_axes_on_three_quarter_turn");

        // 180° 는 크기를 바꾸지 않습니다.
        Check(Size(ImageTransformRecipe.Identity with { Rotation = ImageRotation.Degrees180 },
                out w, out h) && Near(w, width) && Near(h, height),
            "developed_pixel_size_half_turn_keeps_the_size");

        // 크롭은 회전 뒤 크기 위에서 잘립니다 — 돌린 사진의 절반은 세로의 절반입니다.
        ImageTransformRecipe turnedAndCropped = turned with
        {
            Crop = new ImageCropRect(0.25, 0.25, 0.5, 0.5),
        };
        Check(Size(turnedAndCropped, out w, out h) &&
            Math.Abs(w - (height * 0.5)) <= 2.0 &&
            Math.Abs(h - (width * 0.5)) <= 2.0,
            "developed_pixel_size_crops_after_the_turn");

        // 세로 사진의 비율이 원본 가로 비율과 같아지면 인화가 다시 눌러 버립니다.
        Check(Size(turned, out w, out h) &&
            Math.Abs((w / h) - ((double)height / width)) < 1e-9,
            "developed_pixel_size_aspect_is_the_turned_aspect");
    }

    private static void VerifyCropSession()
    {
        var session = CropSession.Start(new ImageCropRect(0.2, 0.15, 0.6, 0.7));
        Check(NearRect(session.Selection, 0.2, 0.15, 0.6, 0.7),
            "crop_session_y_up_to_display");
        Check(session.Cancel() == new ImageCropRect(0.2, 0.15, 0.6, 0.7),
            "crop_session_cancel_restores_initial_crop");

        session.Select(new CropDisplayPoint(0.8, 0.75), new CropDisplayPoint(0.2, 0.25));
        Check(NearRect(session.Selection, 0.2, 0.25, 0.6, 0.5),
            "crop_session_selection_is_y_down_and_normalized");
        Check(session.Apply() is { } applied &&
            Near(applied.X, 0.2) && Near(applied.Y, 0.25) &&
            Near(applied.Width, 0.6) && Near(applied.Height, 0.5),
            "crop_session_apply_converts_to_engine_y_up");

        session.Resize(CropHandle.Left, new CropDisplayPoint(0.98, 0.5));
        Check(session.Selection.Width >= CropSession.MinimumSize && session.Selection.X <= 1.0 - session.Selection.Width,
            "crop_session_resize_clamps_minimum_and_bounds");
        session.Move(-10.0, 10.0);
        Check(session.Selection.X == 0.0 && session.Selection.Bottom == 1.0,
            "crop_session_move_clamps_bounds");

        session.Full();
        Check(session.Apply() is null && session.Cancel() is null,
            "crop_session_full_clears_crop_and_cancel_baseline");

        // 잠근 비율은 끄는 동안 유지돼야 합니다. 정규 좌표 1.5 는 폭 0.6 에 높이 0.4 입니다.
        var locked = CropSession.Start(null);
        locked.LockedNormalizedAspectRatio = 1.5;
        locked.Select(new CropDisplayPoint(0.1, 0.1), new CropDisplayPoint(0.7, 0.9));
        Check(
            Near(locked.Selection.Width, 0.6) && Near(locked.Selection.Height, 0.4),
            "crop_session_locked_aspect_drives_height");
        locked.Resize(CropHandle.Right, new CropDisplayPoint(0.4, 0.5));
        Check(
            Near(locked.Selection.Width / locked.Selection.Height, 1.5),
            "crop_session_locked_aspect_survives_resize");

        // 원본 화소 3:2 를 정중앙 최대 crop 으로 바꾸면 4000x3000 에서 세로가 2/3 로 줄어듭니다.
        ImageTransformRecipe framed = CropAspect.Apply(
            ImageTransformRecipe.Identity,
            new CropAspectOption("3:2", 3.0 / 2.0),
            4000U,
            3000U);
        Check(
            framed.Crop is { } aspectCrop &&
            Near(aspectCrop.Width, 1.0) && Near(aspectCrop.Height, 8.0 / 9.0) &&
            Near(aspectCrop.X, 0.0) && Near(aspectCrop.Y, 1.0 / 18.0),
            "crop_aspect_centres_the_largest_fitting_rect");
        Check(
            CropAspect.Apply(framed, new CropAspectOption("original", null), 4000U, 3000U)
                is { Crop: null, CropAspect: null },
            "crop_aspect_original_clears_crop_and_ratio");
    }

    /// <summary>
    /// 프리셋이 실제로 엔진 요청까지 도달하는지 봅니다. 이 팩토리가 preview·thumbnail·export 의
    /// 공통 관문이므로, 여기서 합성되면 세 경로가 같은 레시피를 씁니다.
    /// </summary>
    private static void VerifyLookPresetReachesTheEngine()
    {
        const string destination = @"C:\exports\IMG_0001.png";
        LibraryFrameSnapshot plain = Frame(new ManualBaseRgb(0.21, 0.22, 0.23));
        LibraryFrameSnapshot withPreset = plain with { LookPresetId = "warm-lab" };

        // 목록에 없는 id 는 프리셋 없이 현상합니다 — 거부하면 사진을 아예 못 봅니다.
        LookPresetLibrary.SetForTests([]);
        DevelopExportRequest? unresolved = DevelopRequestFactory.Create(withPreset, destination).Request;
        DevelopExportRequest? baseline = DevelopRequestFactory.Create(plain, destination).Request;
        Check(unresolved is not null && baseline is not null &&
            unresolved.ExposureStops == baseline.ExposureStops &&
            unresolved.Grain == baseline.Grain,
            "preset_unknown_id_falls_back_to_user_values");

        LookPresetLibrary.SetForTests([new LookPreset(
            "warm-lab",
            "Warm Lab",
            2,
            [FilmType.ColorNegative],
            new LookPresetTone(0.0, 0.12, 0.08, 0.30, -0.02, 0.02),
            new LookPresetColor(0.16, 0.01, 0.08, 0.03),
            new LookPresetTexture(0.04, 0.10, 0.04))]);
        try
        {
            Check(LookPresetLibrary.Resolve("warm-lab") is not null, "preset_library_resolves");
            if (DevelopRequestFactory.Create(withPreset, destination).Request is not { } request ||
                baseline is null)
            {
                Check(false, "preset_request_built");
                return;
            }

            // Frame() 의 톤은 exposure 1.5, density 0.5, highlight -0.6 입니다.
            Check(Near(request.ExposureStops, 1.5f + 0.002f), "preset_exposure_composes");
            Check(Near(request.Density, 0.5f + 0.12f), "preset_density_composes");
            // highlightRollOff 0.30 은 부호가 뒤집혀 -0.30 이 되고 여기에 사용자 -0.6 이 더해집니다.
            Check(Near(request.Highlight, -0.6f - 0.30f), "preset_highlight_roll_off_composes");
            Check(Near(request.Warmth, 0.16f), "preset_warmth_composes");
            // Frame() 은 질감을 지정하지 않아 0 입니다. 사용자가 0 이어도 프리셋 값이 남아야 합니다.
            Check(Near(request.Grain, 0.04f) && Near(request.Sharpness, 0.10f),
                "preset_texture_survives_zero_user_value");
            // 프리셋이 정하지 않는 축은 그대로여야 합니다.
            Check(request.Highlights == baseline.Highlights &&
                request.Vibrance == baseline.Vibrance &&
                request.Clarity == baseline.Clarity,
                "preset_leaves_unpreset_axes_alone");
        }
        finally
        {
            LookPresetLibrary.SetForTests([]);
        }
    }

    private static bool Near(double actual, double expected) =>
        Math.Abs(actual - expected) < 1e-6;

    private static bool NearRect(
        CropDisplayRect actual,
        double x,
        double y,
        double width,
        double height) =>
        Near(actual.X, x) && Near(actual.Y, y) &&
        Near(actual.Width, width) && Near(actual.Height, height);

    /// <summary>
    /// 표시 좌표 → 원본 좌표. 결함 편집이 저장되는 공간이 바뀌는 자리이므로, 변형이 걸린
    /// 프레임에서 어긋나면 엉뚱한 화소를 지웁니다. 네이티브가 하는 세 단계를 같은 식으로
    /// 되짚는지만 봅니다.
    /// </summary>
    private static void VerifyDisplayToRawMapping()
    {
        const uint width = 4000U;
        const uint height = 3000U;

        static bool Map(
            ImageTransformRecipe transform,
            double displayX,
            double displayY,
            out double rawX,
            out double rawY) =>
            DevelopDisplayGeometry.TryMapDisplayToRaw(
                transform, width, height, displayX, displayY, out rawX, out rawY);

        static bool Close(double actual, double expected) =>
            Math.Abs(actual - expected) < 1e-9;

        // 변형이 없으면 표시 좌표가 곧 원본 좌표입니다.
        Check(Map(ImageTransformRecipe.Identity, 0.25, 0.75, out double x, out double y) &&
            Close(x, 0.25) && Close(y, 0.75),
            "display_to_raw_identity");
        Check(Map(ImageTransformRecipe.Identity, 0.0, 0.0, out x, out y) &&
            Close(x, 0.0) && Close(y, 0.0),
            "display_to_raw_identity_origin");

        // 좌우 반전은 x 만 뒤집습니다.
        ImageTransformRecipe flipped = ImageTransformRecipe.Identity with { FlipHorizontal = true };
        Check(Map(flipped, 0.2, 0.6, out x, out y) && Close(x, 0.8) && Close(y, 0.6),
            "display_to_raw_flip_horizontal");

        // 90도 회전. 네이티브 orient 는 출력 (x,y) 를 원본 (y, H-1-x) 에서 읽으므로,
        // 표시 왼쪽 위는 원본 왼쪽 아래입니다.
        ImageTransformRecipe rotated =
            ImageTransformRecipe.Identity with { Rotation = ImageRotation.Degrees90 };
        Check(Map(rotated, 0.0, 0.0, out x, out y) && Close(x, 0.0) && Close(y, 1.0),
            "display_to_raw_rotate_90_origin");
        Check(Map(rotated, 1.0, 1.0, out x, out y) && Close(x, 1.0) && Close(y, 0.0),
            "display_to_raw_rotate_90_far_corner");

        ImageTransformRecipe halfTurn =
            ImageTransformRecipe.Identity with { Rotation = ImageRotation.Degrees180 };
        Check(Map(halfTurn, 0.3, 0.4, out x, out y) && Close(x, 0.7) && Close(y, 0.6),
            "display_to_raw_rotate_180");

        // 크롭: 표시 좌표 0.5 는 잘린 창의 가운데이고, 그것은 원본의 창 가운데입니다.
        // 저장된 crop 은 y-up 이라 y 는 뒤집혀 들어갑니다.
        ImageTransformRecipe cropped = ImageTransformRecipe.Identity with
        {
            Crop = new ImageCropRect(0.25, 0.5, 0.5, 0.25),
        };
        Check(Map(cropped, 0.5, 0.5, out x, out y) &&
            Math.Abs(x - 0.5) < 1e-3 && Math.Abs(y - 0.375) < 1e-3,
            "display_to_raw_crop_centre");
        Check(Map(cropped, 0.0, 0.0, out x, out y) &&
            Math.Abs(x - 0.25) < 1e-3 && Math.Abs(y - 0.25) < 1e-3,
            "display_to_raw_crop_origin");

        // 수평보정은 가운데를 가운데로 둡니다. 회전 중심이 어긋났다면 여기서 드러납니다.
        ImageTransformRecipe straightened =
            ImageTransformRecipe.Identity with { StraightenAngle = 7.5 };
        Check(Map(straightened, 0.5, 0.5, out x, out y) &&
            Math.Abs(x - 0.5) < 1e-6 && Math.Abs(y - 0.5) < 1e-6,
            "display_to_raw_straighten_keeps_centre");
        // 기울인 뒤의 가로 이동은 원본에서 살짝 위로 올라가야 합니다(시계 방향 보정).
        Check(Map(straightened, 1.0, 0.5, out x, out double tiltedY) &&
            Map(straightened, 0.0, 0.5, out _, out double tiltedOriginY) &&
            tiltedY < tiltedOriginY,
            "display_to_raw_straighten_tilts");

        // 변형을 겹쳐도 가운데는 가운데입니다.
        ImageTransformRecipe combined = new(
            ImageRotation.Degrees270,
            FlipHorizontal: true,
            FlipVertical: false,
            Crop: new ImageCropRect(0.2, 0.2, 0.6, 0.6),
            StraightenAngle: -3.0,
            CropAspect: null);
        Check(Map(combined, 0.5, 0.5, out x, out y) &&
            Math.Abs(x - 0.5) < 2e-3 && Math.Abs(y - 0.5) < 2e-3,
            "display_to_raw_combined_centre");

        Check(!Map(ImageTransformRecipe.Identity, double.NaN, 0.5, out _, out _),
            "display_to_raw_rejects_non_finite");
        Check(!DevelopDisplayGeometry.TryMapDisplayToRaw(
                ImageTransformRecipe.Identity, 1U, 1U, 0.5, 0.5, out _, out _),
            "display_to_raw_rejects_degenerate_source");

        VerifyRawToDisplayIsTheExactInverse(width, height);
    }

    private static void VerifyManualDefectCoordinatesMatchMacOS()
    {
        LibraryFrameSnapshot frame = Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with
        {
            SourceMetadata = new LibrarySourceMetadata(1UL, 100U, 100U, 3, 16, 1, 1),
            ImageTransform = ImageTransformRecipe.Identity with
            {
                Crop = new ImageCropRect(0.1, 0.0, 0.5, 1.0),
            },
        };
        Check(DevelopDefectCoordinateMapper.TryMapCloneDisplayToRaw(
                frame, new DefectPoint(0.5, 0.5), out DefectPoint cloneRaw) &&
            Math.Abs(cloneRaw.X - 0.35) < 1e-12 &&
            Math.Abs(cloneRaw.Y - 0.5) < 1e-12,
            "clone_coordinate_uses_the_macos_continuous_crop_affine");

        LibraryFrameSnapshot straightened = frame with
        {
            ImageTransform = ImageTransformRecipe.Identity with { StraightenAngle = 10.0 },
        };
        Check(DevelopDefectCoordinateMapper.TryMapBrushDisplayToRaw(
                straightened, new DefectPoint(1.0, 0.5), out DefectPoint brushRaw) &&
            brushRaw == new DefectPoint(1.0, 0.5),
            "brush_coordinate_skips_straighten_without_a_macos_base_size");
        Check(DevelopDefectCoordinateMapper.TryMapCloneDisplayToRaw(
                straightened, new DefectPoint(0.8, 0.4), out cloneRaw) &&
            DevelopDefectCoordinateMapper.TryMapCloneRawToDisplay(
                straightened, cloneRaw, out DefectPoint cloneDisplay) &&
            Math.Abs(cloneDisplay.X - 0.8) < 1e-12 &&
            Math.Abs(cloneDisplay.Y - 0.4) < 1e-12,
            "clone_coordinate_round_trips_the_macos_straighten_affine");

        LibraryFrameSnapshot identity = frame with { ImageTransform = ImageTransformRecipe.Identity };
        Check(DevelopDefectCoordinateMapper.TryMapCloneRawToDisplay(
                identity, new DefectPoint(1.2, -0.1), out DefectPoint outside) &&
            outside == new DefectPoint(1.2, -0.1),
            "clone_cursor_mapping_does_not_clamp_an_outside_source");
    }

    /// <summary>
    /// 원본 → 표시. macOS <c>ImageTransform.baseUnitToDisplay</c> 에 해당하며, 복제 도장이 원 안에
    /// 보여 줄 소스 화소의 자리를 이것으로 셉니다. 두 방향이 어긋나면 커서와 다른 자리의 화소가
    /// 보이므로, <b>왕복이 제자리로 돌아오는지</b>를 변형마다 고정합니다.
    /// </summary>
    private static void VerifyRawToDisplayIsTheExactInverse(uint width, uint height)
    {
        ImageTransformRecipe[] transforms =
        [
            ImageTransformRecipe.Identity,
            ImageTransformRecipe.Identity with { FlipHorizontal = true },
            ImageTransformRecipe.Identity with { FlipVertical = true },
            ImageTransformRecipe.Identity with { Rotation = ImageRotation.Degrees90 },
            ImageTransformRecipe.Identity with { Rotation = ImageRotation.Degrees180 },
            ImageTransformRecipe.Identity with { Rotation = ImageRotation.Degrees270 },
            ImageTransformRecipe.Identity with { StraightenAngle = 7.5 },
            ImageTransformRecipe.Identity with
            {
                Crop = new ImageCropRect(0.25, 0.5, 0.5, 0.25),
            },
            new(
                ImageRotation.Degrees270,
                FlipHorizontal: true,
                FlipVertical: false,
                Crop: new ImageCropRect(0.2, 0.2, 0.6, 0.6),
                StraightenAngle: -3.0,
                CropAspect: null),
        ];
        double[] samples = [0.1, 0.35, 0.5, 0.72, 0.9];

        bool roundTrips = true;
        foreach (ImageTransformRecipe transform in transforms)
        {
            foreach (double displayX in samples)
            {
                foreach (double displayY in samples)
                {
                    if (!DevelopDisplayGeometry.TryMapDisplayToRaw(
                            transform, width, height, displayX, displayY,
                            out double rawX, out double rawY) ||
                        !DevelopDisplayGeometry.TryMapRawToDisplay(
                            transform, width, height, rawX, rawY,
                            out double backX, out double backY) ||
                        Math.Abs(backX - displayX) > 1e-9 ||
                        Math.Abs(backY - displayY) > 1e-9)
                    {
                        roundTrips = false;
                    }
                }
            }
        }
        Check(roundTrips, "raw_to_display_round_trips_for_every_transform");

        // 변형이 없으면 원본 좌표가 곧 표시 좌표입니다.
        Check(DevelopDisplayGeometry.TryMapRawToDisplay(
                ImageTransformRecipe.Identity, width, height, 0.25, 0.75,
                out double identityX, out double identityY) &&
            Math.Abs(identityX - 0.25) < 1e-12 && Math.Abs(identityY - 0.75) < 1e-12,
            "raw_to_display_identity");

        // 잘려 나간 자리는 0~1 밖으로 나옵니다 — macOS 도 자르지 않고 내며 호출부가 거릅니다.
        ImageTransformRecipe cropped = ImageTransformRecipe.Identity with
        {
            Crop = new ImageCropRect(0.25, 0.25, 0.5, 0.5),
        };
        Check(DevelopDisplayGeometry.TryMapRawToDisplay(
                cropped, width, height, 0.05, 0.5, out double outsideX, out _) &&
            outsideX < 0.0,
            "raw_to_display_reports_points_outside_the_crop");

        Check(!DevelopDisplayGeometry.TryMapRawToDisplay(
                ImageTransformRecipe.Identity, width, height, double.NaN, 0.5, out _, out _),
            "raw_to_display_rejects_non_finite");
    }

    /// <summary>
    /// 검출 마스크(화소당 1바이트)가 catalog 의 region 항목(RGBA8)으로 넘어가는 자리입니다.
    /// 표현이 바뀌는 곳이라 화소가 어긋나면 엉뚱한 자리를 고칩니다.
    /// </summary>
}
