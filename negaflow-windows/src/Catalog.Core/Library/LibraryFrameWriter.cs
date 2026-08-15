using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>
/// 프리셋 변경 의사입니다. edit 에서 이 값이 null 이면 손대지 않고, 값이 있으면서
/// <see cref="Id"/> 가 null 이면 프리셋을 뗍니다 — "안 건드림"과 "떼기"는 다른 뜻이라
/// <c>string?</c> 하나로는 표현할 수 없습니다.
/// </summary>
public readonly record struct LookPresetSelection(string? Id)
{
    public static LookPresetSelection None => new((string?)null);
}

/// <summary>
/// 이름 변경 의사입니다. <see cref="LookPresetSelection"/> 과 같은 이유로 <c>string?</c> 하나로는
/// 모자랍니다 — "안 건드림"과 "직접 지은 이름 떼기(파일 이름으로 돌아가기)"는 다른 뜻입니다.
/// </summary>
public readonly record struct DisplayNameSelection(string? Name)
{
    public static DisplayNameSelection None => new((string?)null);

    /// <summary>
    /// macOS <c>renameDisplayName(to:)</c> 와 같이 앞뒤 공백을 떼고, 남는 것이 없으면 이름을 뗍니다.
    /// </summary>
    public static DisplayNameSelection Normalized(string? value)
    {
        string trimmed = (value ?? string.Empty).Trim();
        return new DisplayNameSelection(trimmed.Length == 0 ? null : trimmed);
    }
}

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
    DevelopTarget? DevelopTarget = null,
    ImageTransformRecipe? ImageTransform = null,
    TextureRecipe? Texture = null,
    NoiseReductionRecipe? NoiseReduction = null,
    BwToningRecipe? BwToning = null,
    double? DefectRemovalStrength = null,
    int? Rating = null,
    LookPresetSelection? LookPreset = null,
    FramePickState? PickState = null,
    DisplayNameSelection? DisplayName = null);

/// <summary>
/// 톤, 수동 base, 그리고 지정된 경우 base recipe를 갱신합니다. 입력 record 는 바꾸지 않고 깊은 복사본을 돌려주며, 이 writer 가
/// 모르는 frame/params field 는 전부 보존합니다. develop route 는
/// <see cref="DevelopRouteWriter"/> 가 계속 소유합니다.
/// </summary>
public static class LibraryFrameWriter
{
    /// <summary>
    /// 가상 사본의 frame record 를 만듭니다. 원본 payload 를 **통째로** 복제하고 신원 세 칸만
    /// 바꿉니다.
    /// </summary>
    /// <remarks>
    /// 아는 field 만 옮기면 이 빌드가 모르는 값이 사본에서 사라져 원본과 현상 결과가 갈립니다.
    /// 그래서 복제 뒤 덮어쓰기이며, 그 세 칸의 이름은 macOS catalog 와 같습니다.
    /// </remarks>
    public static JsonObject MakeVirtualCopy(
        JsonObject source,
        string copyId,
        string rootFrameId,
        int copyNumber,
        string? rootDisplayName)
    {
        ArgumentNullException.ThrowIfNull(source);
        ArgumentException.ThrowIfNullOrEmpty(copyId);
        ArgumentException.ThrowIfNullOrEmpty(rootFrameId);
        ArgumentOutOfRangeException.ThrowIfLessThan(copyNumber, 1);

        JsonObject copy = (JsonObject)source.DeepClone();
        copy[LibraryFrameReader.IdName] = copyId;
        copy[LibraryFrameReader.SourceFrameIdName] = rootFrameId;
        copy[LibraryFrameReader.VirtualCopyNumberName] = copyNumber;
        if (!string.IsNullOrWhiteSpace(rootDisplayName))
        {
            copy[LibraryFrameReader.SourceFrameDisplayNameName] = rootDisplayName;
        }
        return copy;
    }

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
        if (edit.ImageTransform is { } imageTransform && !imageTransform.IsValid)
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidImageTransform);
        }
        if (edit.Texture is { } texture && !texture.IsValid)
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidTexture);
        }
        if (edit.NoiseReduction is { } noiseReduction && !noiseReduction.IsValid)
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidNoiseReduction);
        }
        if (edit.BwToning is { } bwToning && !bwToning.IsValid)
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidBwToning);
        }
        if (edit.DefectRemovalStrength is { } defectRemoval &&
            (!double.IsFinite(defectRemoval) || defectRemoval is < 0.0 or > 1.0))
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidDefectRecipe);
        }
        if (edit.Rating is { } rating && rating is < 0 or > 5)
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidRating);
        }
        if (edit.LookPreset is { Id: { } presetId } && string.IsNullOrWhiteSpace(presetId))
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidLookPresetId);
        }

        JsonObject updated = frameRecord.DeepClone().AsObject();
        if (edit.Rating is { } writtenRating)
        {
            // 별점은 recipe 가 아니라 frame 자체의 성질이므로 macOS 와 같이 최상위에 둡니다.
            updated[LibraryFrameReader.RatingName] = writtenRating;
        }
        if (edit.PickState is { } writtenPick)
        {
            // 깃발도 별점과 같은 자리입니다. 깃발 없음을 키 삭제가 아니라 "unflagged" 로 적는 것은
            // macOS 가 enum raw value 를 그대로 내보내기 때문이며, reader 는 둘 다 읽습니다.
            updated[LibraryFrameReader.PickStateName] = writtenPick switch
            {
                FramePickState.Picked => "picked",
                FramePickState.Rejected => "rejected",
                _ => "unflagged",
            };
        }
        if (edit.DisplayName is { } writtenName)
        {
            // 이름을 뗄 때 빈 문자열을 남기면 reader 는 "이름이 있는데 비어 있다"로 읽어 파일
            // 이름으로 돌아가지 못합니다. macOS 처럼 키 자체를 지웁니다.
            if (writtenName.Name is { } displayName)
            {
                updated[LibraryFrameReader.DisplayNameName] = displayName;
            }
            else
            {
                updated.Remove(LibraryFrameReader.DisplayNameName);
            }
        }
        if (edit.LookPreset is { } presetSelection)
        {
            // 프리셋은 params 의 델타가 아니라 그 델타가 얹히는 바탕이므로 macOS 와 같이
            // params 바깥에 둡니다. 뗄 때는 키를 지웁니다 — Swift 도 nil 은 쓰지 않습니다.
            if (presetSelection.Id is { } writtenPresetId)
            {
                updated[LibraryFrameReader.LookPresetIdName] = writtenPresetId;
            }
            else
            {
                updated.Remove(LibraryFrameReader.LookPresetIdName);
            }
        }
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
        if (edit.ImageTransform is { } imageTransformToWrite)
        {
            parameters[LibraryFrameReader.ImageTransformName] = WriteImageTransform(imageTransformToWrite);
        }
        if (edit.Texture is { } textureToWrite)
        {
            parameters[LibraryFrameReader.GrainName] = textureToWrite.Grain;
            parameters[LibraryFrameReader.SharpnessName] = textureToWrite.Sharpness;
            parameters[LibraryFrameReader.HalationName] = textureToWrite.Halation;
            parameters[LibraryFrameReader.ClarityName] = textureToWrite.Clarity;
            parameters[LibraryFrameReader.VignetteName] = textureToWrite.Vignette;
        }
        if (edit.NoiseReduction is { } noiseReductionToWrite)
        {
            parameters[LibraryFrameReader.NoiseReductionName] = noiseReductionToWrite.Strength;
            parameters[LibraryFrameReader.NoiseReductionLumaName] = noiseReductionToWrite.Luma;
            parameters[LibraryFrameReader.NoiseReductionChromaName] = noiseReductionToWrite.Chroma;
            parameters[LibraryFrameReader.NoiseReductionDarkToneName] = noiseReductionToWrite.DarkTone;
            parameters[LibraryFrameReader.NoiseReductionDetailName] = noiseReductionToWrite.Detail;
            parameters[LibraryFrameReader.NoiseReductionGrainProtectName] =
                noiseReductionToWrite.GrainProtect;
        }

        if (edit.DefectRemovalStrength is { } defectRemovalToWrite)
        {
            parameters[LibraryFrameReader.DefectRemovalName] = defectRemovalToWrite;
        }

        if (edit.BwToning is { } bwToningToWrite)
        {
            // 끈 상태는 키를 지웁니다. macOS 도 기본값을 쓰지 않으며, 남겨 두면 흑백이 아닌
            // frame 의 params 에 쓸모없는 색조가 남습니다.
            if (bwToningToWrite.Mode == BwToningMode.None)
            {
                parameters.Remove(LibraryFrameReader.BwToningName);
            }
            else
            {
                parameters[LibraryFrameReader.BwToningName] = new JsonObject
                {
                    [LibraryFrameReader.BwToningModeName] = ToStorageName(bwToningToWrite.Mode),
                    [LibraryFrameReader.BwToningShadowHueName] = bwToningToWrite.ShadowHue,
                    [LibraryFrameReader.BwToningHighlightHueName] = bwToningToWrite.HighlightHue,
                    [LibraryFrameReader.BwToningStrengthName] = bwToningToWrite.Strength,
                };
            }
        }

        return LibraryFrameWriteResult.Success(updated);
    }

    private static string ToStorageName(BwToningMode mode) => mode switch
    {
        BwToningMode.Selenium => "selenium",
        BwToningMode.Sepia => "sepia",
        _ => "none",
    };

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

    private static JsonObject WriteImageTransform(ImageTransformRecipe transform)
    {
        JsonObject result = new()
        {
            [LibraryFrameReader.ImageTransformRotationName] = (int)transform.Rotation,
            [LibraryFrameReader.ImageTransformFlipHorizontalName] = transform.FlipHorizontal,
            [LibraryFrameReader.ImageTransformFlipVerticalName] = transform.FlipVertical,
            [LibraryFrameReader.ImageTransformStraightenAngleName] = transform.StraightenAngle,
        };
        if (transform.Crop is { } crop)
        {
            result[LibraryFrameReader.ImageTransformCropRectName] = new JsonArray(
                crop.X, crop.Y, crop.Width, crop.Height);
        }
        if (transform.CropAspect is { } cropAspect)
        {
            result[LibraryFrameReader.ImageTransformCropAspectName] = cropAspect;
        }
        return result;
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
