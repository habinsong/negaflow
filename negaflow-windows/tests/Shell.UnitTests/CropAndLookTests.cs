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
