using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

internal static class ColorRecipeJsonCodec
{
    internal static bool IsValid(PointCurveRecipe pointCurves) =>
        IsValidPointCurveChannel(pointCurves.Rgb) &&
        IsValidPointCurveChannel(pointCurves.Red) &&
        IsValidPointCurveChannel(pointCurves.Green) &&
        IsValidPointCurveChannel(pointCurves.Blue);

    internal static bool IsValid(ColorMixerRecipe colorMixer) =>
        IsValidColorMixerChannel(colorMixer.Hue) &&
        IsValidColorMixerChannel(colorMixer.Saturation) &&
        IsValidColorMixerChannel(colorMixer.Luminance);

    internal static bool IsValid(ColorGradingRecipe colorGrading) =>
        IsValidColorGradeRegion(colorGrading.Shadows) &&
        IsValidColorGradeRegion(colorGrading.Midtones) &&
        IsValidColorGradeRegion(colorGrading.Highlights) &&
        double.IsFinite(colorGrading.Blending) && colorGrading.Blending is >= 0.0 and <= 1.0 &&
        double.IsFinite(colorGrading.Balance) && colorGrading.Balance is >= -1.0 and <= 1.0;

    internal static bool IsValid(PrimaryCalibrationRecipe calibration) =>
        new[]
        {
            calibration.RedHue, calibration.RedSaturation,
            calibration.GreenHue, calibration.GreenSaturation,
            calibration.BlueHue, calibration.BlueSaturation,
        }.All(value => double.IsFinite(value) && value is >= -1.0 and <= 1.0);

    internal static void Write(JsonObject parameters, LibraryFrameEdit edit)
    {
        if (edit.PointCurves is { } pointCurves)
        {
            parameters[LibraryFrameReader.PointCurvesName] = WritePointCurves(pointCurves);
        }
        if (edit.ColorMixer is { } colorMixer)
        {
            parameters[LibraryFrameReader.ColorMixerName] = WriteColorMixer(colorMixer);
        }
        if (edit.ColorGrading is { } colorGrading)
        {
            parameters[LibraryFrameReader.ColorGradingName] = WriteColorGrading(colorGrading);
        }
        if (edit.PrimaryCalibration is { } calibration)
        {
            parameters[LibraryFrameReader.PrimaryCalibrationName] =
                WritePrimaryCalibration(calibration);
        }
        if (edit.ColorModel is { } colorModel)
        {
            parameters[LibraryFrameReader.WarmthName] = colorModel.Warmth;
            parameters[LibraryFrameReader.TintName] = colorModel.Tint;
            parameters[LibraryFrameReader.ColorDepthName] = colorModel.ColorDepth;
            parameters[LibraryFrameReader.VibranceName] = colorModel.Vibrance;
            parameters[LibraryFrameReader.SaturationName] = colorModel.Saturation;
            parameters[LibraryFrameReader.RedPrimaryName] = colorModel.RedPrimary;
            parameters[LibraryFrameReader.GreenPrimaryName] = colorModel.GreenPrimary;
            parameters[LibraryFrameReader.BluePrimaryName] = colorModel.BluePrimary;
        }
        if (edit.AutoLevels is { } autoLevels)
        {
            parameters[LibraryFrameReader.AutoLevelsName] = autoLevels;
        }
        if (edit.AutoNeutralBalance is { } autoNeutralBalance)
        {
            parameters[LibraryFrameReader.AutoNeutralBalanceName] = autoNeutralBalance;
        }
        if (edit.DevelopTarget is { } target)
        {
            parameters[LibraryFrameReader.DevelopTargetName] = target switch
            {
                DevelopTarget.Main => "main",
                DevelopTarget.Print => "print",
                DevelopTarget.Noritsu => "noritsu",
                DevelopTarget.Sp3000 => "sp-3000",
                DevelopTarget.F135 => "f135",
                DevelopTarget.Hr => "hr",
                DevelopTarget.Rescue => "rescue",
                _ => throw new ArgumentOutOfRangeException(nameof(target)),
            };
        }
    }

    private static bool IsValidPointCurveChannel(IReadOnlyList<PointCurvePoint> points)
    {
        if (points.Count > PointCurveRecipe.MaximumPointsPerChannel)
        {
            return false;
        }
        double? previousX = null;
        foreach (PointCurvePoint point in points.OrderBy(point => point.X))
        {
            if (!double.IsFinite(point.X) || !double.IsFinite(point.Y) ||
                point.X is < 0.0 or > 1.0 || point.Y is < 0.0 or > 1.0 ||
                previousX is { } x && point.X - x < 1.0e-9)
            {
                return false;
            }
            previousX = point.X;
        }
        return true;
    }

    private static JsonObject WritePointCurves(PointCurveRecipe pointCurves) => new()
    {
        [LibraryFrameReader.PointCurveRgbName] = WritePointCurveChannel(pointCurves.Rgb),
        [LibraryFrameReader.PointCurveRedName] = WritePointCurveChannel(pointCurves.Red),
        [LibraryFrameReader.PointCurveGreenName] = WritePointCurveChannel(pointCurves.Green),
        [LibraryFrameReader.PointCurveBlueName] = WritePointCurveChannel(pointCurves.Blue),
    };

    private static JsonArray WritePointCurveChannel(IReadOnlyList<PointCurvePoint> points)
    {
        JsonArray array = [];
        foreach (PointCurvePoint point in points.OrderBy(point => point.X))
        {
            array.Add(new JsonObject
            {
                [LibraryFrameReader.PointCurveXName] = point.X,
                [LibraryFrameReader.PointCurveYName] = point.Y,
            });
        }
        return array;
    }

    private static bool IsValidColorMixerChannel(IReadOnlyList<double> values) =>
        values.Count == ColorMixerRecipe.BandCount &&
        values.All(value => double.IsFinite(value) && value is >= -1.0 and <= 1.0);

    private static JsonObject WriteColorMixer(ColorMixerRecipe colorMixer) => new()
    {
        [LibraryFrameReader.ColorMixerHueName] = WriteColorMixerChannel(colorMixer.Hue),
        [LibraryFrameReader.ColorMixerSaturationName] = WriteColorMixerChannel(colorMixer.Saturation),
        [LibraryFrameReader.ColorMixerLuminanceName] = WriteColorMixerChannel(colorMixer.Luminance),
    };

    private static JsonArray WriteColorMixerChannel(IReadOnlyList<double> values)
    {
        JsonArray array = [];
        foreach (double value in values)
        {
            array.Add(value);
        }
        return array;
    }

    private static bool IsValidColorGradeRegion(ColorGradeRegionRecipe region) =>
        double.IsFinite(region.Hue) && region.Hue is >= 0.0 and <= 360.0 &&
        double.IsFinite(region.Saturation) && region.Saturation is >= 0.0 and <= 1.0 &&
        double.IsFinite(region.Luminance) && region.Luminance is >= -1.0 and <= 1.0;

    private static JsonObject WriteColorGrading(ColorGradingRecipe colorGrading) => new()
    {
        [LibraryFrameReader.ColorGradingShadowsName] = WriteColorGradeRegion(colorGrading.Shadows),
        [LibraryFrameReader.ColorGradingMidtonesName] = WriteColorGradeRegion(colorGrading.Midtones),
        [LibraryFrameReader.ColorGradingHighlightsName] = WriteColorGradeRegion(colorGrading.Highlights),
        [LibraryFrameReader.ColorGradingBlendingName] = colorGrading.Blending,
        [LibraryFrameReader.ColorGradingBalanceName] = colorGrading.Balance,
    };

    private static JsonObject WriteColorGradeRegion(ColorGradeRegionRecipe region) => new()
    {
        [LibraryFrameReader.ColorGradingHueName] = region.Hue,
        [LibraryFrameReader.ColorGradingSaturationName] = region.Saturation,
        [LibraryFrameReader.ColorGradingLuminanceName] = region.Luminance,
    };

    private static JsonObject WritePrimaryCalibration(PrimaryCalibrationRecipe calibration) => new()
    {
        [LibraryFrameReader.PrimaryCalibrationRedHueName] = calibration.RedHue,
        [LibraryFrameReader.PrimaryCalibrationRedSaturationName] = calibration.RedSaturation,
        [LibraryFrameReader.PrimaryCalibrationGreenHueName] = calibration.GreenHue,
        [LibraryFrameReader.PrimaryCalibrationGreenSaturationName] = calibration.GreenSaturation,
        [LibraryFrameReader.PrimaryCalibrationBlueHueName] = calibration.BlueHue,
        [LibraryFrameReader.PrimaryCalibrationBlueSaturationName] = calibration.BlueSaturation,
    };
}
