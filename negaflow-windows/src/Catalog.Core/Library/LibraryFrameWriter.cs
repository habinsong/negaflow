using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>셸이 한 번에 바꾸는 값들입니다. 지정하지 않은 것은 그대로 둡니다.</summary>
public sealed record LibraryFrameEdit(
    ToneAdjustment Tone,
    ManualBaseRgb? ManualBase,
    BaseRecipe? Base = null,
    PointCurveRecipe? PointCurves = null,
    ColorMixerRecipe? ColorMixer = null,
    ColorGradingRecipe? ColorGrading = null,
    PrimaryCalibrationRecipe? PrimaryCalibration = null,
    IReadOnlyList<LocalDodgeBurnAdjustment>? LocalDodgeBurn = null,
    ColorModelRecipe? ColorModel = null,
    bool? AutoLevels = null,
    bool? AutoNeutralBalance = null,
    DevelopTarget? DevelopTarget = null);

/// <summary>
/// 톤, 수동 base, 그리고 지정된 경우 base recipe를 갱신합니다. 입력 record 는 바꾸지 않고 깊은 복사본을 돌려주며, 이 writer 가
/// 모르는 frame/params field 는 전부 보존합니다. develop route 는
/// <see cref="DevelopRouteWriter"/> 가 계속 소유합니다.
/// </summary>
public static class LibraryFrameWriter
{
    public static LibraryFrameWriteResult Apply(JsonObject frameRecord, LibraryFrameEdit edit)
    {
        ArgumentNullException.ThrowIfNull(frameRecord);
        ArgumentNullException.ThrowIfNull(edit);

        if (!IsFiniteTone(edit.Tone))
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidToneValue);
        }
        if (edit.ManualBase is { } manualBase &&
            (!double.IsFinite(manualBase.Red) ||
             !double.IsFinite(manualBase.Green) ||
             !double.IsFinite(manualBase.Blue)))
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidManualBase);
        }
        if (edit.Base is { } baseRecipe && !IsValidBaseRecipe(baseRecipe))
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidBaseRecipe);
        }
        if (edit.PointCurves is { } pointCurves && !IsValidPointCurves(pointCurves))
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidPointCurves);
        }
        if (edit.ColorMixer is { } colorMixer && !IsValidColorMixer(colorMixer))
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidColorMixer);
        }
        if (edit.ColorGrading is { } colorGrading && !IsValidColorGrading(colorGrading))
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidColorGrading);
        }
        if (edit.PrimaryCalibration is { } primaryCalibration && !IsValidPrimaryCalibration(primaryCalibration))
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidPrimaryCalibration);
        }
        if (edit.LocalDodgeBurn is { } localDodgeBurn && !LocalDodgeBurnRecipe.IsValid(localDodgeBurn))
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidLocalDodgeBurn);
        }
        if (edit.ColorModel is { } colorModel && !colorModel.IsValid())
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidColorModel);
        }

        JsonObject updated = frameRecord.DeepClone().AsObject();
        JsonObject parameters;
        if (!updated.TryGetPropertyValue(
                LibraryFrameReader.ParametersName,
                out JsonNode? parameterNode) ||
            parameterNode is null)
        {
            parameters = [];
            updated[LibraryFrameReader.ParametersName] = parameters;
        }
        else if (parameterNode is JsonObject parameterObject)
        {
            parameters = parameterObject;
        }
        else
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.MissingParameters);
        }

        parameters[LibraryFrameReader.ExposureName] = edit.Tone.Exposure;
        parameters[LibraryFrameReader.ContrastName] = edit.Tone.Contrast;
        parameters[LibraryFrameReader.DensityName] = edit.Tone.Density;
        parameters[LibraryFrameReader.HighlightName] = edit.Tone.Highlight;
        parameters[LibraryFrameReader.ShadowName] = edit.Tone.Shadow;
        parameters[LibraryFrameReader.WhitesName] = edit.Tone.Whites;
        parameters[LibraryFrameReader.BlacksName] = edit.Tone.Blacks;
        parameters[LibraryFrameReader.CurveHighlightsName] = edit.Tone.CurveHighlights;
        parameters[LibraryFrameReader.CurveLightsName] = edit.Tone.CurveLights;
        parameters[LibraryFrameReader.CurveDarksName] = edit.Tone.CurveDarks;
        parameters[LibraryFrameReader.CurveShadowsName] = edit.Tone.CurveShadows;

        if (edit.ManualBase is { } writtenBase)
        {
            parameters[LibraryFrameReader.ManualBaseName] = new JsonArray(
                writtenBase.Red,
                writtenBase.Green,
                writtenBase.Blue);
        }
        else
        {
            // nil 은 macOS 에서 auto base 추정을 뜻합니다. `false` 나 0 을 쓰면 의미가 달라지므로
            // 키를 지웁니다.
            parameters.Remove(LibraryFrameReader.ManualBaseName);
        }

        if (edit.Base is { } baseRecipeToWrite)
        {
            parameters[LibraryFrameReader.BaseEstimationModeName] = ToStorageName(baseRecipeToWrite.Mode);
            WriteOptionalIdentifier(
                parameters,
                LibraryFrameReader.FilmStockDminIdName,
                baseRecipeToWrite.FilmStockDminId);
            WriteOptionalIdentifier(
                parameters,
                LibraryFrameReader.LightSourceProfileIdName,
                baseRecipeToWrite.LightSourceProfileId);
            WriteOptionalIdentifier(
                parameters,
                LibraryFrameReader.ScannerProfileIdName,
                baseRecipeToWrite.ScannerProfileId);
        }
        if (edit.PointCurves is { } pointCurvesToWrite)
        {
            parameters[LibraryFrameReader.PointCurvesName] = WritePointCurves(pointCurvesToWrite);
        }
        if (edit.ColorMixer is { } colorMixerToWrite)
        {
            parameters[LibraryFrameReader.ColorMixerName] = WriteColorMixer(colorMixerToWrite);
        }
        if (edit.ColorGrading is { } colorGradingToWrite)
        {
            parameters[LibraryFrameReader.ColorGradingName] = WriteColorGrading(colorGradingToWrite);
        }
        if (edit.PrimaryCalibration is { } primaryCalibrationToWrite)
        {
            parameters[LibraryFrameReader.PrimaryCalibrationName] = WritePrimaryCalibration(primaryCalibrationToWrite);
        }
        if (edit.LocalDodgeBurn is { } localDodgeBurnToWrite)
        {
            parameters[LibraryFrameReader.LocalDodgeBurnName] = WriteLocalDodgeBurn(localDodgeBurnToWrite);
        }
        if (edit.ColorModel is { } colorModelToWrite)
        {
            parameters[LibraryFrameReader.WarmthName] = colorModelToWrite.Warmth;
            parameters[LibraryFrameReader.TintName] = colorModelToWrite.Tint;
            parameters[LibraryFrameReader.ColorDepthName] = colorModelToWrite.ColorDepth;
            parameters[LibraryFrameReader.VibranceName] = colorModelToWrite.Vibrance;
            parameters[LibraryFrameReader.SaturationName] = colorModelToWrite.Saturation;
            parameters[LibraryFrameReader.RedPrimaryName] = colorModelToWrite.RedPrimary;
            parameters[LibraryFrameReader.GreenPrimaryName] = colorModelToWrite.GreenPrimary;
            parameters[LibraryFrameReader.BluePrimaryName] = colorModelToWrite.BluePrimary;
        }
        if (edit.AutoLevels is { } autoLevels)
        {
            parameters[LibraryFrameReader.AutoLevelsName] = autoLevels;
        }
        if (edit.AutoNeutralBalance is { } autoNeutralBalance)
        {
            parameters[LibraryFrameReader.AutoNeutralBalanceName] = autoNeutralBalance;
        }
        if (edit.DevelopTarget is { } developTarget)
        {
            if (!Enum.IsDefined(developTarget))
            {
                return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidDevelopTarget);
            }
            parameters[LibraryFrameReader.DevelopTargetName] = developTarget switch
            {
                DevelopTarget.Main => "main",
                DevelopTarget.Print => "print",
                DevelopTarget.Noritsu => "noritsu",
                DevelopTarget.Sp3000 => "sp-3000",
                DevelopTarget.F135 => "f135",
                DevelopTarget.Hr => "hr",
                DevelopTarget.Rescue => "rescue",
                _ => throw new ArgumentOutOfRangeException(nameof(developTarget)),
            };
        }

        return LibraryFrameWriteResult.Success(updated);
    }

    private static bool IsValidBaseRecipe(BaseRecipe recipe) =>
        Enum.IsDefined(recipe.Mode) &&
        IsValidOptionalIdentifier(recipe.FilmStockDminId) &&
        IsValidOptionalIdentifier(recipe.LightSourceProfileId) &&
        IsValidOptionalIdentifier(recipe.ScannerProfileId);

    private static bool IsValidOptionalIdentifier(string? identifier) =>
        identifier is null || !string.IsNullOrWhiteSpace(identifier);

    private static string ToStorageName(BaseEstimationMode mode) => mode switch
    {
        BaseEstimationMode.Auto => "auto",
        BaseEstimationMode.Preset => "preset",
        BaseEstimationMode.Manual => "manual",
        _ => throw new ArgumentOutOfRangeException(nameof(mode)),
    };

    private static void WriteOptionalIdentifier(
        JsonObject parameters,
        string name,
        string? identifier)
    {
        if (identifier is null)
        {
            parameters.Remove(name);
        }
        else
        {
            parameters[name] = identifier;
        }
    }

    private static bool IsFiniteTone(ToneAdjustment tone) =>
        double.IsFinite(tone.Exposure) &&
        double.IsFinite(tone.Contrast) &&
        double.IsFinite(tone.Density) &&
        double.IsFinite(tone.Highlight) &&
        double.IsFinite(tone.Shadow) &&
        double.IsFinite(tone.Whites) &&
        double.IsFinite(tone.Blacks) &&
        double.IsFinite(tone.CurveHighlights) &&
        double.IsFinite(tone.CurveLights) &&
        double.IsFinite(tone.CurveDarks) &&
        double.IsFinite(tone.CurveShadows);

    private static bool IsValidPointCurves(PointCurveRecipe pointCurves) =>
        IsValidPointCurveChannel(pointCurves.Rgb) &&
        IsValidPointCurveChannel(pointCurves.Red) &&
        IsValidPointCurveChannel(pointCurves.Green) &&
        IsValidPointCurveChannel(pointCurves.Blue);

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
        JsonArray result = [];
        foreach (PointCurvePoint point in points.OrderBy(point => point.X))
        {
            result.Add(new JsonObject
            {
                [LibraryFrameReader.PointCurveXName] = point.X,
                [LibraryFrameReader.PointCurveYName] = point.Y,
            });
        }
        return result;
    }

    private static bool IsValidColorMixer(ColorMixerRecipe colorMixer) =>
        IsValidColorMixerChannel(colorMixer.Hue) &&
        IsValidColorMixerChannel(colorMixer.Saturation) &&
        IsValidColorMixerChannel(colorMixer.Luminance);

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
        JsonArray result = [];
        foreach (double value in values)
        {
            result.Add(value);
        }
        return result;
    }

    private static bool IsValidColorGrading(ColorGradingRecipe colorGrading) =>
        IsValidColorGradeRegion(colorGrading.Shadows) &&
        IsValidColorGradeRegion(colorGrading.Midtones) &&
        IsValidColorGradeRegion(colorGrading.Highlights) &&
        double.IsFinite(colorGrading.Blending) && colorGrading.Blending is >= 0.0 and <= 1.0 &&
        double.IsFinite(colorGrading.Balance) && colorGrading.Balance is >= -1.0 and <= 1.0;

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

    private static bool IsValidPrimaryCalibration(PrimaryCalibrationRecipe calibration) =>
        new[]
        {
            calibration.RedHue, calibration.RedSaturation,
            calibration.GreenHue, calibration.GreenSaturation,
            calibration.BlueHue, calibration.BlueSaturation,
        }.All(value => double.IsFinite(value) && value is >= -1.0 and <= 1.0);

    private static JsonObject WritePrimaryCalibration(PrimaryCalibrationRecipe calibration) => new()
    {
        [LibraryFrameReader.PrimaryCalibrationRedHueName] = calibration.RedHue,
        [LibraryFrameReader.PrimaryCalibrationRedSaturationName] = calibration.RedSaturation,
        [LibraryFrameReader.PrimaryCalibrationGreenHueName] = calibration.GreenHue,
        [LibraryFrameReader.PrimaryCalibrationGreenSaturationName] = calibration.GreenSaturation,
        [LibraryFrameReader.PrimaryCalibrationBlueHueName] = calibration.BlueHue,
        [LibraryFrameReader.PrimaryCalibrationBlueSaturationName] = calibration.BlueSaturation,
    };

    private static JsonArray WriteLocalDodgeBurn(
        IReadOnlyList<LocalDodgeBurnAdjustment> adjustments)
    {
        JsonArray result = [];
        foreach (LocalDodgeBurnAdjustment adjustment in adjustments)
        {
            result.Add(new JsonObject
            {
                [LibraryFrameReader.LocalDodgeBurnIdName] = adjustment.Id.ToString(),
                [LibraryFrameReader.LocalDodgeBurnModeName] = adjustment.Mode == LocalDodgeBurnMode.Dodge
                    ? "dodge"
                    : "burn",
                [LibraryFrameReader.LocalDodgeBurnAmountName] = adjustment.Amount,
                [LibraryFrameReader.LocalDodgeBurnEnabledName] = adjustment.IsEnabled,
                [LibraryFrameReader.LocalDodgeBurnMaskName] = WriteLocalDodgeBurnMask(adjustment.Mask),
            });
        }
        return result;
    }

    private static JsonObject WriteLocalDodgeBurnMask(LocalDodgeBurnMask mask) => new()
    {
        [LibraryFrameReader.LocalDodgeBurnKindName] = mask.Kind switch
        {
            LocalDodgeBurnMaskKind.Brush => "brush",
            LocalDodgeBurnMaskKind.Radial => "radial",
            LocalDodgeBurnMaskKind.Linear => "linear",
            LocalDodgeBurnMaskKind.Polygon => "polygon",
            _ => throw new ArgumentOutOfRangeException(nameof(mask)),
        },
        [LibraryFrameReader.LocalDodgeBurnStrokesName] = WriteLocalDodgeBurnStrokes(mask.Strokes),
        [LibraryFrameReader.LocalDodgeBurnCenterName] = WriteLocalDodgeBurnPoint(mask.Center),
        [LibraryFrameReader.LocalDodgeBurnRadiusName] = mask.Radius,
        [LibraryFrameReader.LocalDodgeBurnFeatherName] = mask.Feather,
        [LibraryFrameReader.LocalDodgeBurnStartName] = WriteLocalDodgeBurnPoint(mask.Start),
        [LibraryFrameReader.LocalDodgeBurnEndName] = WriteLocalDodgeBurnPoint(mask.End),
        [LibraryFrameReader.LocalDodgeBurnPointsName] = WriteLocalDodgeBurnPoints(mask.Points),
    };

    private static JsonArray WriteLocalDodgeBurnStrokes(
        IReadOnlyList<LocalDodgeBurnStroke> strokes)
    {
        JsonArray result = [];
        foreach (LocalDodgeBurnStroke stroke in strokes)
        {
            result.Add(new JsonObject
            {
                [LibraryFrameReader.LocalDodgeBurnPointsName] = WriteLocalDodgeBurnPoints(stroke.Points),
                [LibraryFrameReader.LocalDodgeBurnThicknessName] = stroke.Thickness,
                [LibraryFrameReader.LocalDodgeBurnFeatherName] = stroke.Feather,
            });
        }
        return result;
    }

    private static JsonArray WriteLocalDodgeBurnPoints(
        IReadOnlyList<LocalDodgeBurnPoint> points)
    {
        JsonArray result = [];
        foreach (LocalDodgeBurnPoint point in points)
        {
            result.Add(WriteLocalDodgeBurnPoint(point));
        }
        return result;
    }

    private static JsonObject WriteLocalDodgeBurnPoint(LocalDodgeBurnPoint point) => new()
    {
        [LibraryFrameReader.PointCurveXName] = point.X,
        [LibraryFrameReader.PointCurveYName] = point.Y,
    };
}
