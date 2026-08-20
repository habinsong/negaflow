using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.LibraryFrameFixture;

namespace Negaflow.Catalog.UnitTests;

internal static class LibraryFrameProjectionTests
{
    public static void Run() => VerifyLibraryFrameProjection();

    private static void VerifyLibraryFrameProjection()
    {
        LibraryFrameReadResult read = ReadFrame(FrameRecord());
        Check(read.IsSuccess, "library_frame_read_success");
        if (read.Frame is not { } frame)
        {
            return;
        }

        Check(frame.Id == "frame-1", "library_frame_id");
        Check(frame.SourcePath == @"C:\scans\roll-01\IMG_0001.tif", "library_frame_source_path");
        Check(frame.InfraredPath == @"C:\scans\roll-01\IMG_0001.ir.tif",
            "library_frame_infrared_source_path");
        Check(
            frame.SourceMetadata == new LibrarySourceMetadata(123456, 6400, 4200, 3, 16, 1, 1),
            "library_frame_source_metadata");
        Check(frame.EffectiveDisplayName == "Roll 01 / 1", "library_frame_display_name");
        Check(frame.Route.FilmType == FilmType.ColorNegative, "library_frame_route_film_type");
        Check(frame.CanDevelop, "library_frame_preset_with_stock_can_develop");
        Check(frame.ManualBase == new ManualBaseRgb(0.21, 0.22, 0.23), "library_frame_manual_base");
        Check(frame.Base.Mode == BaseEstimationMode.Preset, "library_frame_base_mode");
        Check(frame.Base.FilmStockDminId == "kodak-portra-400", "library_frame_film_stock_id");
        Check(frame.Base.LightSourceProfileId == "v850-led", "library_frame_light_source_id");
        Check(frame.Base.ScannerProfileId == "noritsu__color-nega__kodak-portra-400", "library_frame_scanner_profile_id");
        Check(frame.Tone.Exposure == 0.5, "library_frame_exposure");
        Check(frame.Tone.CurveShadows == -0.25, "library_frame_curve_shadows");
        Check(frame.PointCurves.Rgb.Count == 3, "library_frame_point_curve_rgb_count");
        Check(frame.PointCurves.Rgb[0] == new PointCurvePoint(0.0, 0.0),
            "library_frame_point_curve_sorts_rgb");
        Check(frame.PointCurves.Rgb[1] == new PointCurvePoint(0.45, 0.52),
            "library_frame_point_curve_rgb_middle");
        Check(frame.PointCurves.Red.Count == 2 && frame.PointCurves.Green.Count == 0 &&
                frame.PointCurves.Blue.Count == 0,
            "library_frame_point_curve_channel_shapes");
        Check(frame.ColorMixer.Hue[0] == 0.1 && frame.ColorMixer.Hue[1] == -0.2 &&
                frame.ColorMixer.Hue[2] == 0.0 && frame.ColorMixer.Saturation[0] == 0.3 &&
                frame.ColorMixer.Luminance[0] == -0.4,
            "library_frame_color_mixer_normalizes_mac_shape");
        Check(frame.ColorGrading == ColorGradingRecipe.Identity,
            "library_frame_missing_color_grading_defaults_to_identity");
        Check(frame.ColorModel == ColorModelRecipe.Identity,
            "library_frame_missing_color_model_defaults_to_identity");
        Check(!frame.AutoLevels && !frame.AutoNeutralBalance,
            "library_frame_missing_scene_correction_defaults_off");
        Check(frame.DevelopTarget == DevelopTarget.Main,
            "library_frame_missing_develop_target_defaults_main");
        Check(frame.ImageTransform == new ImageTransformRecipe(
                ImageRotation.Degrees90,
                true,
                false,
                new ImageCropRect(0.1, 0.2, 0.7, 0.6),
                1.5,
                1.5),
            "library_frame_image_transform_projection");
        // macOS `ImageTransform.displayName` — 편집 카드 머리줄 오른쪽에 그대로 나갑니다.
        Check(
            frame.ImageTransform.DisplayName == "90 H",
            "image_transform_display_name_adds_flip_letters");
        Check(
            ImageTransformRecipe.Identity.DisplayName == "0",
            "image_transform_display_name_is_zero_when_untouched");
        Check(
            (ImageTransformRecipe.Identity with
            {
                Rotation = ImageRotation.Degrees180,
                FlipVertical = true,
            }).DisplayName == "180 V",
            "image_transform_display_name_reads_180_v");
        Check(frame.Texture == new TextureRecipe(0.35, 0.45, 0.20, -0.15, 0.25),
            "library_frame_texture_projection");
        Check(frame.NoiseReduction == new NoiseReductionRecipe(0.60, 0.70, 0.40, 0.55, 0.65, 0.30),
            "library_frame_noise_reduction_projection");
        ColorGradingRecipe colorGrading = new(
            new ColorGradeRegionRecipe(45.0, 0.2, -0.1),
            new ColorGradeRegionRecipe(180.0, 0.4, 0.1),
            new ColorGradeRegionRecipe(300.0, 0.6, 0.2),
            0.35,
            -0.25);
        LibraryFrameWriteResult writtenColorGrading = LibraryFrameWriter.Apply(
            FrameRecord(),
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, ColorGrading: colorGrading));
        Check(
            writtenColorGrading.IsSuccess &&
                ReadFrame(writtenColorGrading.FrameRecord!).Frame?.ColorGrading == colorGrading,
            "library_frame_color_grading_write_round_trip");
        ColorModelRecipe colorModel = new(
            0.25, -0.2, 0.3, 0.4, -0.1, 0.1, -0.15, 0.2);
        LibraryFrameWriteResult writtenColorModel = LibraryFrameWriter.Apply(
            FrameRecord(),
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                ColorModel: colorModel,
                AutoLevels: true,
                AutoNeutralBalance: true,
                DevelopTarget: DevelopTarget.Rescue));
        Check(
            writtenColorModel.IsSuccess &&
                ReadFrame(writtenColorModel.FrameRecord!).Frame is { } correctedFrame &&
                correctedFrame.ColorModel == colorModel &&
                correctedFrame.AutoLevels && correctedFrame.AutoNeutralBalance &&
                correctedFrame.DevelopTarget == DevelopTarget.Rescue,
            "library_frame_color_model_scene_correction_and_target_write_round_trip");
        // 없는 톤 키는 macOS 와 같이 0 입니다.
        Check(frame.Tone.Contrast == 0.0, "library_frame_missing_tone_is_zero");

        // Preset resolver가 아직 없으면 manual base가 있어도 Auto로 바꾸어 추정하지 않습니다.
        JsonObject withoutBase = FrameRecord();
        withoutBase["params"]!.AsObject().Remove("manualBaseRGB");
        LibraryFrameReadResult noBase = ReadFrame(withoutBase);
        Check(noBase.IsSuccess, "library_frame_missing_base_still_reads");
        Check(noBase.Frame?.ManualBase is null, "library_frame_missing_base_is_absent");
        Check(noBase.Frame?.CanDevelop == true, "library_frame_preset_does_not_require_manual_base");

        JsonObject defaultBase = FrameRecord();
        JsonObject defaultBaseParams = defaultBase["params"]!.AsObject();
        defaultBaseParams.Remove("baseEstimationMode");
        defaultBaseParams.Remove("filmStockDminID");
        defaultBaseParams.Remove("lightSourceProfileID");
        defaultBaseParams.Remove("scannerProfileID");
        Check(ReadFrame(defaultBase).Frame?.Base == BaseRecipe.Auto,
            "library_frame_missing_base_recipe_defaults_to_auto");
        Check(ReadFrame(defaultBase).Frame?.CanDevelop == true,
            "library_frame_default_auto_can_develop");

        JsonObject withoutPointCurves = FrameRecord();
        withoutPointCurves["params"]!.AsObject().Remove("pointCurves");
        PointCurveRecipe? defaultPointCurves = ReadFrame(withoutPointCurves).Frame?.PointCurves;
        Check(defaultPointCurves is not null &&
                defaultPointCurves.Rgb.Count == 0 && defaultPointCurves.Red.Count == 0 &&
                defaultPointCurves.Green.Count == 0 && defaultPointCurves.Blue.Count == 0,
            "library_frame_missing_point_curves_defaults_to_identity");

        JsonObject withoutName = FrameRecord();
        withoutName.Remove("customDisplayName");
        Check(
            ReadFrame(withoutName).Frame?.EffectiveDisplayName == "IMG_0001.tif",
            "library_frame_falls_back_to_file_name");

    }

    /// <summary>
    /// 깃발과 이름은 라이브러리가 사진을 부르고 고르는 방식 그 자체입니다. 읽기만 되고 쓰기가
    /// 없으면 "선택한 사진만 보기" 필터는 영원히 비어 있습니다.
    /// </summary>
}
