using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.LibraryFrameFixture;

namespace Negaflow.Catalog.UnitTests;

internal static class LibraryFrameWritingTests
{
    public static void Run() => VerifyLibraryFrameWriting();

    private static void VerifyLibraryFrameWriting()
    {
        JsonObject original = FrameRecord();
        LibraryFrameEdit edit = new(
            new ToneAdjustment(
                1.25,
                -0.5,
                0.1,
                0.2,
                0.3,
                0.4,
                0.5,
                -0.6,
                0.7,
                -0.8,
                0.9),
            new ManualBaseRgb(0.31, 0.32, 0.33));

        LibraryFrameWriteResult write = LibraryFrameWriter.Apply(original, edit);
        Check(write.IsSuccess, "library_frame_write_success");
        if (write.FrameRecord is not { } updated)
        {
            return;
        }

        Check(
            original["params"]!["exposure"]!.GetValue<double>() == 0.5,
            "library_frame_write_leaves_input_alone");
        Check(
            updated["futureFrameValue"]!.GetValue<string>() == "preserve-me",
            "library_frame_write_preserves_unknown_frame_field");
        Check(
            updated["params"]!["unknownAdjustment"]!["value"]!.GetValue<int>() == 7,
            "library_frame_write_preserves_unknown_parameter_field");

        LibraryFrameReadResult reread = ReadFrame(updated);
        Check(reread.IsSuccess, "library_frame_write_round_trip");
        Check(reread.Frame?.Tone == edit.Tone, "library_frame_write_tone_round_trip");
        Check(
            updated["params"]!["density"]!.GetValue<double>() == 0.5 &&
                updated["params"]!["highlight"]!.GetValue<double>() == -0.6 &&
                updated["params"]!["shadow"]!.GetValue<double>() == 0.7 &&
                updated["params"]!["whites"]!.GetValue<double>() == -0.8 &&
                updated["params"]!["blacks"]!.GetValue<double>() == 0.9,
            "library_frame_write_basic_tone_names");
        Check(reread.Frame?.ManualBase == edit.ManualBase, "library_frame_write_base_round_trip");
        ImageTransformRecipe imageTransform = new(
            ImageRotation.Degrees270,
            true,
            true,
            new ImageCropRect(0.15, 0.10, 0.70, 0.75),
            -2.25,
            4.0 / 3.0);
        LibraryFrameWriteResult imageTransformWrite = LibraryFrameWriter.Apply(
            original,
            new LibraryFrameEdit(edit.Tone, edit.ManualBase, ImageTransform: imageTransform));
        Check(
            imageTransformWrite.IsSuccess &&
                ReadFrame(imageTransformWrite.FrameRecord!).Frame?.ImageTransform == imageTransform,
            "library_frame_image_transform_write_round_trip");
        TextureRecipe texture = new(0.25, 0.55, 0.15, 0.30, -0.20);
        NoiseReductionRecipe noiseReduction = new(0.65, 0.75, 0.45, 0.60, 0.80, 0.35);
        LibraryFrameWriteResult postProcessingWrite = LibraryFrameWriter.Apply(
            original,
            new LibraryFrameEdit(
                edit.Tone,
                edit.ManualBase,
                Texture: texture,
                NoiseReduction: noiseReduction));
        Check(
            postProcessingWrite.IsSuccess &&
                ReadFrame(postProcessingWrite.FrameRecord!).Frame is { } postProcessingFrame &&
                postProcessingFrame.Texture == texture &&
                postProcessingFrame.NoiseReduction == noiseReduction,
            "library_frame_post_processing_write_round_trip");
        Check(reread.Frame?.Base == new BaseRecipe(
                BaseEstimationMode.Preset,
                "kodak-portra-400",
                "v850-led",
                "noritsu__color-nega__kodak-portra-400"),
            "library_frame_write_preserves_base_recipe_when_not_edited");
        Check(reread.Frame?.PointCurves.Rgb.Count == 3,
            "library_frame_write_preserves_point_curves_when_not_edited");
        Check(reread.Frame?.ColorMixer.Hue[0] == 0.1 && reread.Frame.ColorMixer.Hue[2] == 0.0,
            "library_frame_write_preserves_color_mixer_when_not_edited");

        BaseRecipe manualRecipe = new(
            BaseEstimationMode.Manual,
            "kodak-portra-400",
            null,
            null);
        LibraryFrameWriteResult baseWrite = LibraryFrameWriter.Apply(
            original,
            new LibraryFrameEdit(edit.Tone, edit.ManualBase, manualRecipe));
        Check(baseWrite.IsSuccess, "library_frame_base_recipe_write_success");
        Check(ReadFrame(baseWrite.FrameRecord!).Frame?.Base == manualRecipe,
            "library_frame_base_recipe_write_round_trip");

        PointCurveRecipe pointCurveEdit = new(
            [
                new PointCurvePoint(1.0, 0.95),
                new PointCurvePoint(0.0, 0.05),
                new PointCurvePoint(0.5, 0.60),
            ],
            [],
            [new PointCurvePoint(0.25, 0.20)],
            []);
        LibraryFrameWriteResult pointCurveWrite = LibraryFrameWriter.Apply(
            original,
            new LibraryFrameEdit(edit.Tone, edit.ManualBase, PointCurves: pointCurveEdit));
        Check(pointCurveWrite.IsSuccess, "library_frame_point_curve_write_success");
        Check(
            pointCurveWrite.FrameRecord?["params"]!["pointCurves"]!["rgb"]![0]!["x"]!
                .GetValue<double>() == 0.0,
            "library_frame_point_curve_write_canonicalizes_order");
        LibraryFrameReadResult pointCurveReread = ReadFrame(pointCurveWrite.FrameRecord!);
        Check(pointCurveReread.IsSuccess &&
                pointCurveReread.Frame?.PointCurves.Rgb[1] == new PointCurvePoint(0.5, 0.60) &&
                pointCurveReread.Frame?.PointCurves.Green[0] == new PointCurvePoint(0.25, 0.20),
            "library_frame_point_curve_write_round_trip");

        ColorMixerRecipe colorMixerEdit = new(
            [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8],
            [-0.1, -0.2, -0.3, -0.4, -0.5, -0.6, -0.7, -0.8],
            new double[ColorMixerRecipe.BandCount]);
        LibraryFrameWriteResult colorMixerWrite = LibraryFrameWriter.Apply(
            original,
            new LibraryFrameEdit(edit.Tone, edit.ManualBase, ColorMixer: colorMixerEdit));
        Check(colorMixerWrite.IsSuccess &&
                colorMixerWrite.FrameRecord?["params"]!["colorMixer"]!["hue"]!.AsArray().Count ==
                    ColorMixerRecipe.BandCount,
            "library_frame_color_mixer_write_canonicalizes_eight_bands");
        LibraryFrameReadResult colorMixerReread = ReadFrame(colorMixerWrite.FrameRecord!);
        Check(colorMixerReread.IsSuccess &&
                colorMixerReread.Frame?.ColorMixer.Hue[7] == 0.8 &&
                colorMixerReread.Frame.ColorMixer.Saturation[7] == -0.8,
            "library_frame_color_mixer_write_round_trip");

        // base 를 지우는 것은 auto 추정으로 되돌린다는 뜻이므로 키를 없앱니다.
        LibraryFrameWriteResult cleared = LibraryFrameWriter.Apply(
            original,
            new LibraryFrameEdit(ToneAdjustment.Neutral, null));
        Check(cleared.IsSuccess, "library_frame_clear_base_write");
        Check(
            cleared.FrameRecord?["params"]!.AsObject().ContainsKey("manualBaseRGB") == false,
            "library_frame_clear_base_removes_key");

        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    new ToneAdjustment(double.NaN, 0, 0, 0, 0, 0),
                    null)).Error == LibraryFrameError.InvalidToneValue,
            "library_frame_write_rejects_nan_tone");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral with { Density = double.PositiveInfinity },
                    null)).Error == LibraryFrameError.InvalidToneValue,
            "library_frame_write_rejects_non_finite_basic_tone");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    new ManualBaseRgb(0.2, double.PositiveInfinity, 0.2)))
                .Error == LibraryFrameError.InvalidManualBase,
            "library_frame_write_rejects_infinite_base");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    null,
                    new BaseRecipe((BaseEstimationMode)99, null, null, null)))
                .Error == LibraryFrameError.InvalidBaseRecipe,
            "library_frame_write_rejects_unknown_base_mode");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    null,
                    PointCurves: new PointCurveRecipe(
                        [new PointCurvePoint(0.5, 0.5), new PointCurvePoint(0.5, 0.6)],
                        [], [], [])))
                .Error == LibraryFrameError.InvalidPointCurves,
            "library_frame_write_rejects_point_curve_duplicate_x");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    null,
                    PointCurves: new PointCurveRecipe(
                        [new PointCurvePoint(double.NaN, 0.5)],
                        [], [], [])))
                .Error == LibraryFrameError.InvalidPointCurves,
            "library_frame_write_rejects_point_curve_nonfinite_coordinate");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    null,
                    ColorMixer: new ColorMixerRecipe(
                        [0.0, 0.0],
                        new double[ColorMixerRecipe.BandCount],
                        new double[ColorMixerRecipe.BandCount])))
                .Error == LibraryFrameError.InvalidColorMixer,
            "library_frame_write_rejects_short_color_mixer");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    null,
                    ImageTransform: ImageTransformRecipe.Identity with
                    {
                        StraightenAngle = 60.0,
                    }))
                .Error == LibraryFrameError.InvalidImageTransform,
            "library_frame_write_rejects_out_of_range_straighten");
    }

}
