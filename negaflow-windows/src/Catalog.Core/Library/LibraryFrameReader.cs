using System.Globalization;
using System.Text.Json;

namespace Negaflow.Catalog;

/// <summary>
/// catalog frame payload 를 셸이 쓸 수 있는 형태로 투영합니다. key 이름은 macOS 와 같습니다 —
/// <c>rawScanPath</c>, <c>customDisplayName</c>, <c>params.manualBaseRGB</c>,
/// <c>params.exposure</c> 계열 — 그래야 recipe payload 수준의 호환이 유지됩니다.
/// develop route 부분은 <see cref="DevelopRouteReader"/> 가 계속 소유합니다.
/// </summary>
public static class LibraryFrameReader
{
    internal const string IdName = "id";
    public const string SourcePathName = "rawScanPath";
    public const string SourceMetadataName = "sourceMetadata";
    public const string SourceFileBytesName = "fileBytes";
    public const string SourcePixelWidthName = "pixelWidth";
    public const string SourcePixelHeightName = "pixelHeight";
    public const string SourceSamplesPerPixelName = "samplesPerPixel";
    public const string SourceBitsPerSampleName = "bitsPerSample";
    public const string SourceSampleFormatName = "sampleFormat";
    public const string SourceOrientationName = "orientation";
    public const string InfraredPathName = "infraredScanPath";
    internal const string DisplayNameName = "customDisplayName";
    internal const string RatingName = "rating";
    internal const string PickStateName = "pickState";
    internal const string ScannedAtName = "scannedAt";
    internal const string ParametersName = "params";
    /// <summary>macOS 와 같이 <c>params</c> 형제입니다. 델타와 프리셋을 섞어 두지 않습니다.</summary>
    public const string LookPresetIdName = "presetID";
    internal const string BaseEstimationModeName = "baseEstimationMode";
    internal const string ManualBaseName = "manualBaseRGB";
    internal const string FilmStockDminIdName = "filmStockDminID";
    internal const string LightSourceProfileIdName = "lightSourceProfileID";
    internal const string ScannerProfileIdName = "scannerProfileID";
    internal const string ExposureName = "exposure";
    internal const string ContrastName = "contrast";
    internal const string DensityName = "density";
    internal const string HighlightName = "highlight";
    internal const string ShadowName = "shadow";
    internal const string WhitesName = "whites";
    internal const string BlacksName = "blacks";
    internal const string CurveHighlightsName = "curveHighlights";
    internal const string CurveLightsName = "curveLights";
    internal const string CurveDarksName = "curveDarks";
    internal const string CurveShadowsName = "curveShadows";
    internal const string PointCurvesName = "pointCurves";
    internal const string PointCurveRgbName = "rgb";
    internal const string PointCurveRedName = "red";
    internal const string PointCurveGreenName = "green";
    internal const string PointCurveBlueName = "blue";
    internal const string PointCurveXName = "x";
    internal const string PointCurveYName = "y";
    internal const string ColorMixerName = "colorMixer";
    internal const string ColorMixerHueName = "hue";
    internal const string ColorMixerSaturationName = "saturation";
    internal const string ColorMixerLuminanceName = "luminance";
    internal const string ColorGradingName = "colorGrading";
    internal const string BwToningName = "bwToning";
    internal const string BwToningModeName = "mode";
    internal const string BwToningShadowHueName = "shadowHue";
    internal const string BwToningHighlightHueName = "highlightHue";
    internal const string BwToningStrengthName = "strength";
    internal const string ColorGradingShadowsName = "shadows";
    internal const string ColorGradingMidtonesName = "midtones";
    internal const string ColorGradingHighlightsName = "highlights";
    internal const string ColorGradingHueName = "hue";
    internal const string ColorGradingSaturationName = "saturation";
    internal const string ColorGradingLuminanceName = "luminance";
    internal const string ColorGradingBlendingName = "blending";
    internal const string ColorGradingBalanceName = "balance";
    internal const string PrimaryCalibrationName = "calibration";
    internal const string PrimaryCalibrationRedHueName = "redHue";
    internal const string PrimaryCalibrationRedSaturationName = "redSat";
    internal const string PrimaryCalibrationGreenHueName = "greenHue";
    internal const string PrimaryCalibrationGreenSaturationName = "greenSat";
    internal const string PrimaryCalibrationBlueHueName = "blueHue";
    internal const string PrimaryCalibrationBlueSaturationName = "blueSat";
    internal const string LocalDodgeBurnName = "localDodgeBurn";
    internal const string LocalDodgeBurnIdName = "id";
    internal const string LocalDodgeBurnModeName = "mode";
    internal const string LocalDodgeBurnAmountName = "amount";
    internal const string LocalDodgeBurnEnabledName = "isEnabled";
    internal const string LocalDodgeBurnMaskName = "mask";
    internal const string LocalDodgeBurnKindName = "kind";
    internal const string LocalDodgeBurnStrokesName = "strokes";
    internal const string LocalDodgeBurnPointsName = "points";
    internal const string LocalDodgeBurnThicknessName = "thickness";
    internal const string LocalDodgeBurnFeatherName = "feather";
    internal const string LocalDodgeBurnCenterName = "center";
    internal const string LocalDodgeBurnRadiusName = "radius";
    internal const string LocalDodgeBurnStartName = "start";
    internal const string LocalDodgeBurnEndName = "end";
    internal const string WarmthName = "warmth";
    internal const string TintName = "tint";
    internal const string ColorDepthName = "colorDepth";
    internal const string VibranceName = "vibrance";
    internal const string SaturationName = "saturation";
    internal const string RedPrimaryName = "redPrimary";
    internal const string GreenPrimaryName = "greenPrimary";
    internal const string BluePrimaryName = "bluePrimary";
    internal const string AutoLevelsName = "autoLevels";
    internal const string AutoNeutralBalanceName = "autoNeutralBalance";
    internal const string DevelopTargetName = "developTarget";
    internal const string ImageTransformName = "imageTransform";
    internal const string ImageTransformRotationName = "rotation";
    internal const string ImageTransformFlipHorizontalName = "flipHorizontal";
    internal const string ImageTransformFlipVerticalName = "flipVertical";
    internal const string ImageTransformCropRectName = "cropRect";
    internal const string ImageTransformStraightenAngleName = "straightenAngle";
    internal const string ImageTransformCropAspectName = "cropAspect";
    internal const string GrainName = "grain";
    internal const string SharpnessName = "sharpness";
    internal const string HalationName = "halation";
    internal const string ClarityName = "clarity";
    internal const string VignetteName = "vignette";
    internal const string DefectRemovalName = "defectRemoval";
    internal const string NoiseReductionName = "noiseReduction";
    internal const string NoiseReductionLumaName = "noiseReductionLuma";
    internal const string NoiseReductionChromaName = "noiseReductionChroma";
    internal const string NoiseReductionDarkToneName = "noiseReductionDarkTone";
    internal const string NoiseReductionDetailName = "noiseReductionDetail";
    internal const string NoiseReductionGrainProtectName = "noiseReductionGrainProtect";

    public static LibraryFrameReadResult Read(JsonElement frameRecord)
    {
        if (frameRecord.ValueKind != JsonValueKind.Object)
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.FrameNotObject);
        }

        if (!frameRecord.TryGetProperty(IdName, out JsonElement idElement))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.MissingId);
        }
        if (idElement.ValueKind != JsonValueKind.String ||
            idElement.GetString() is not { Length: > 0 } id ||
            string.IsNullOrWhiteSpace(id))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidId);
        }

        if (!frameRecord.TryGetProperty(SourcePathName, out JsonElement sourceElement))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.MissingSourcePath);
        }
        if (sourceElement.ValueKind != JsonValueKind.String ||
            sourceElement.GetString() is not { Length: > 0 } sourcePath ||
            string.IsNullOrWhiteSpace(sourcePath) ||
            !Path.IsPathFullyQualified(sourcePath))
        {
            // 상대 경로는 무엇을 기준으로 푸는지가 catalog 에 없습니다. 추측해서 열면 엉뚱한 파일을
            // 현상할 수 있으므로 거부합니다.
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidSourcePath);
        }
        if (!TryReadInfraredPath(frameRecord, sourcePath, out string? infraredPath))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidInfraredPath);
        }
        if (!TryReadSourceMetadata(frameRecord, out LibrarySourceMetadata? sourceMetadata))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidSourceMetadata);
        }

        string? displayName = null;
        if (frameRecord.TryGetProperty(DisplayNameName, out JsonElement displayElement) &&
            displayElement.ValueKind != JsonValueKind.Null)
        {
            if (displayElement.ValueKind != JsonValueKind.String)
            {
                return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidDisplayName);
            }
            displayName = displayElement.GetString();
        }

        // 빈 문자열은 "프리셋 없음"과 구별되지 않으므로 조용히 넘기지 않습니다. 잘못 읽으면
        // 프리셋이 통째로 사라진 그림이 나옵니다.
        string? lookPresetId = null;
        if (frameRecord.TryGetProperty(LookPresetIdName, out JsonElement presetElement) &&
            presetElement.ValueKind != JsonValueKind.Null)
        {
            if (presetElement.ValueKind != JsonValueKind.String ||
                presetElement.GetString() is not { Length: > 0 } parsedPresetId ||
                string.IsNullOrWhiteSpace(parsedPresetId))
            {
                return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidLookPresetId);
            }
            lookPresetId = parsedPresetId;
        }

        if (!TryReadRating(frameRecord, out int rating))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidRating);
        }
        if (!LibraryVersions.TryRead(frameRecord, out IReadOnlyList<LibraryVersionSnapshot> versions))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidVersion);
        }
        if (!TryReadPickState(frameRecord, out FramePickState pickState))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidPickState);
        }
        if (!TryReadScannedAt(frameRecord, out DateTimeOffset? scannedAt))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidScannedAt);
        }

        if (!frameRecord.TryGetProperty(ParametersName, out JsonElement parameters) ||
            parameters.ValueKind != JsonValueKind.Object)
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.MissingParameters);
        }

        if (!TryReadManualBase(parameters, out ManualBaseRgb? manualBase))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidManualBase);
        }
        if (!TryReadBaseRecipe(parameters, out BaseRecipe baseRecipe))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidBaseRecipe);
        }
        if (!TryReadTone(parameters, out ToneAdjustment tone))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidToneValue);
        }
        if (!TryReadPointCurves(parameters, out PointCurveRecipe pointCurves))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidPointCurves);
        }
        if (!TryReadColorMixer(parameters, out ColorMixerRecipe colorMixer))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidColorMixer);
        }
        if (!TryReadColorGrading(parameters, out ColorGradingRecipe colorGrading))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidColorGrading);
        }
        if (!TryReadPrimaryCalibration(parameters, out PrimaryCalibrationRecipe primaryCalibration))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidPrimaryCalibration);
        }
        if (!TryReadLocalDodgeBurn(parameters, out IReadOnlyList<LocalDodgeBurnAdjustment> localDodgeBurn))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidLocalDodgeBurn);
        }
        if (!TryReadColorModel(parameters, out ColorModelRecipe colorModel))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidColorModel);
        }
        if (!TryReadImageTransform(parameters, out ImageTransformRecipe imageTransform))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidImageTransform);
        }
        if (!TryReadTexture(parameters, out TextureRecipe texture))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidTexture);
        }
        if (!TryReadNoiseReduction(parameters, out NoiseReductionRecipe noiseReduction))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidNoiseReduction);
        }
        if (!TryReadOptionalFiniteDouble(
                parameters,
                DefectRemovalName,
                0.0,
                out double defectRemoval) ||
            defectRemoval is < 0.0 or > 1.0)
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidDefectRecipe);
        }
        if (!TryReadBwToning(parameters, out BwToningRecipe bwToning))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidBwToning);
        }
        if (!TryReadOptionalBoolean(parameters, AutoLevelsName, false, out bool autoLevels) ||
            !TryReadOptionalBoolean(
                parameters,
                AutoNeutralBalanceName,
                false,
                out bool autoNeutralBalance))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidSceneCorrection);
        }
        if (!TryReadDevelopTarget(parameters, out DevelopTarget developTarget))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidDevelopTarget);
        }

        DevelopRouteReadResult route = DevelopRouteReader.Read(frameRecord);
        if (route.Route is not { } snapshot)
        {
            return LibraryFrameReadResult.RouteFailure(route.Error);
        }

        return LibraryFrameReadResult.Success(new LibraryFrameSnapshot(
            id,
            sourcePath,
            displayName,
            snapshot,
            manualBase,
            tone)
        {
            InfraredPath = infraredPath,
            SourceMetadata = sourceMetadata,
            Base = baseRecipe,
            LookPresetId = lookPresetId,
            PointCurves = pointCurves,
            ColorMixer = colorMixer,
            ColorGrading = colorGrading,
            PrimaryCalibration = primaryCalibration,
            LocalDodgeBurn = localDodgeBurn,
            ColorModel = colorModel,
            AutoLevels = autoLevels,
            AutoNeutralBalance = autoNeutralBalance,
            DevelopTarget = developTarget,
            ImageTransform = imageTransform,
            Texture = texture,
            NoiseReduction = noiseReduction,
            BwToning = bwToning,
            DefectRemovalStrength = defectRemoval,
            Rating = rating,
            PickState = pickState,
            ScannedAt = scannedAt,
            Versions = versions,
        });
    }

    /// <summary>
    /// macOS <c>FramePickState</c> 의 raw value 입니다. 키가 없으면 깃발 없음입니다.
    /// </summary>
    private static bool TryReadPickState(JsonElement frameRecord, out FramePickState pickState)
    {
        pickState = FramePickState.Unflagged;
        if (!frameRecord.TryGetProperty(PickStateName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.String)
        {
            return false;
        }
        switch (element.GetString())
        {
            case "unflagged":
                return true;
            case "picked":
                pickState = FramePickState.Picked;
                return true;
            case "rejected":
                pickState = FramePickState.Rejected;
                return true;
            default:
                return false;
        }
    }

    /// <summary>
    /// 스캔·가져오기 시각입니다. 시간순 정렬에만 씁니다. Swift 는 이 자리를 초 단위 실수로도
    /// 쓰므로 두 형태를 모두 읽습니다. 없는 legacy row 는 null 로 두고 정렬에서 뒤로 보냅니다.
    /// </summary>
    private static bool TryReadScannedAt(JsonElement frameRecord, out DateTimeOffset? scannedAt)
    {
        scannedAt = null;
        if (!frameRecord.TryGetProperty(ScannedAtName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind == JsonValueKind.String)
        {
            if (!DateTimeOffset.TryParse(
                    element.GetString(),
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.RoundtripKind,
                    out DateTimeOffset parsed))
            {
                return false;
            }
            scannedAt = parsed;
            return true;
        }
        if (element.ValueKind != JsonValueKind.Number ||
            !element.TryGetDouble(out double seconds) ||
            !double.IsFinite(seconds))
        {
            return false;
        }
        // Swift 의 기준 시각은 2001-01-01 UTC 입니다.
        scannedAt = new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero)
            .AddSeconds(seconds);
        return true;
    }

    /// <summary>
    /// macOS 와 같은 0...5 별점입니다. frame record 최상위에 있고, 키가 없는 legacy row 는 0 입니다.
    /// 범위를 벗어난 값은 조용히 자르지 않고 거부합니다 — 카탈로그가 손상됐다는 뜻입니다.
    /// </summary>
    private static bool TryReadRating(JsonElement frameRecord, out int rating)
    {
        rating = 0;
        if (!frameRecord.TryGetProperty(RatingName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Number ||
            !element.TryGetInt32(out int value) ||
            value is < 0 or > 5)
        {
            return false;
        }
        rating = value;
        return true;
    }

    private static bool TryReadTexture(JsonElement parameters, out TextureRecipe texture)
    {
        texture = TextureRecipe.Identity;
        if (!TryReadOptionalFiniteDouble(parameters, GrainName, 0.0, out double grain) ||
            !TryReadOptionalFiniteDouble(parameters, SharpnessName, 0.0, out double sharpness) ||
            !TryReadOptionalFiniteDouble(parameters, HalationName, 0.0, out double halation) ||
            !TryReadOptionalFiniteDouble(parameters, ClarityName, 0.0, out double clarity) ||
            !TryReadOptionalFiniteDouble(parameters, VignetteName, 0.0, out double vignette))
        {
            return false;
        }
        texture = new TextureRecipe(grain, sharpness, halation, clarity, vignette);
        return texture.IsValid;
    }

    private static bool TryReadNoiseReduction(
        JsonElement parameters,
        out NoiseReductionRecipe noiseReduction)
    {
        noiseReduction = NoiseReductionRecipe.Identity;
        if (!TryReadOptionalFiniteDouble(parameters, NoiseReductionName, 0.0, out double strength) ||
            !TryReadOptionalFiniteDouble(parameters, NoiseReductionLumaName, 0.5, out double luma) ||
            !TryReadOptionalFiniteDouble(parameters, NoiseReductionChromaName, 0.5, out double chroma) ||
            !TryReadOptionalFiniteDouble(parameters, NoiseReductionDarkToneName, 0.5, out double darkTone) ||
            !TryReadOptionalFiniteDouble(parameters, NoiseReductionDetailName, 0.5, out double detail) ||
            !TryReadOptionalFiniteDouble(
                parameters,
                NoiseReductionGrainProtectName,
                0.0,
                out double grainProtect))
        {
            return false;
        }
        noiseReduction = new NoiseReductionRecipe(
            strength, luma, chroma, darkTone, detail, grainProtect);
        return noiseReduction.IsValid;
    }

    private static bool TryReadImageTransform(
        JsonElement parameters,
        out ImageTransformRecipe imageTransform)
    {
        imageTransform = ImageTransformRecipe.Identity;
        if (!parameters.TryGetProperty(ImageTransformName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Object ||
            !TryReadOptionalRotation(element, out ImageRotation rotation) ||
            !TryReadOptionalBoolean(
                element,
                ImageTransformFlipHorizontalName,
                false,
                out bool flipHorizontal) ||
            !TryReadOptionalBoolean(
                element,
                ImageTransformFlipVerticalName,
                false,
                out bool flipVertical) ||
            !TryReadOptionalFiniteDouble(
                element,
                ImageTransformStraightenAngleName,
                0.0,
                out double straightenAngle) ||
            !TryReadOptionalCrop(element, out ImageCropRect? crop) ||
            !TryReadOptionalPositiveDouble(
                element,
                ImageTransformCropAspectName,
                out double? cropAspect))
        {
            return false;
        }

        imageTransform = new ImageTransformRecipe(
            rotation,
            flipHorizontal,
            flipVertical,
            crop,
            straightenAngle,
            cropAspect);
        return imageTransform.IsValid;
    }

    private static bool TryReadOptionalRotation(JsonElement owner, out ImageRotation rotation)
    {
        rotation = ImageRotation.Degrees0;
        if (!owner.TryGetProperty(ImageTransformRotationName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Number || !element.TryGetInt32(out int raw))
        {
            return false;
        }
        rotation = (ImageRotation)raw;
        return Enum.IsDefined(rotation);
    }

    private static bool TryReadOptionalCrop(JsonElement owner, out ImageCropRect? crop)
    {
        crop = null;
        if (!owner.TryGetProperty(ImageTransformCropRectName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Array || element.GetArrayLength() != 4)
        {
            return false;
        }
        JsonElement.ArrayEnumerator values = element.EnumerateArray();
        double[] coordinates = new double[4];
        for (int index = 0; index < coordinates.Length; index++)
        {
            if (!values.MoveNext() || values.Current.ValueKind != JsonValueKind.Number ||
                !values.Current.TryGetDouble(out coordinates[index]) ||
                !double.IsFinite(coordinates[index]))
            {
                return false;
            }
        }
        ImageCropRect parsed = new(
            coordinates[0], coordinates[1], coordinates[2], coordinates[3]);
        if (!parsed.IsValid)
        {
            return false;
        }
        crop = parsed;
        return true;
    }

    private static bool TryReadOptionalPositiveDouble(
        JsonElement owner,
        string name,
        out double? value)
    {
        value = null;
        if (!owner.TryGetProperty(name, out JsonElement element) || element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Number || !element.TryGetDouble(out double parsed) ||
            !double.IsFinite(parsed) || parsed <= 0.0)
        {
            return false;
        }
        value = parsed;
        return true;
    }

    private static bool TryReadSourceMetadata(
        JsonElement frameRecord,
        out LibrarySourceMetadata? sourceMetadata)
    {
        sourceMetadata = null;
        if (!frameRecord.TryGetProperty(SourceMetadataName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Object ||
            !TryReadRequiredUInt64(element, SourceFileBytesName, out ulong fileBytes) ||
            !TryReadRequiredUInt32(element, SourcePixelWidthName, out uint pixelWidth) ||
            !TryReadRequiredUInt32(element, SourcePixelHeightName, out uint pixelHeight) ||
            !TryReadRequiredUInt16(element, SourceSamplesPerPixelName, out ushort samplesPerPixel) ||
            !TryReadRequiredUInt16(element, SourceBitsPerSampleName, out ushort bitsPerSample) ||
            !TryReadRequiredUInt16(element, SourceSampleFormatName, out ushort sampleFormat) ||
            !TryReadRequiredUInt16(element, SourceOrientationName, out ushort orientation))
        {
            return false;
        }
        LibrarySourceMetadata parsed = new(
            fileBytes, pixelWidth, pixelHeight, samplesPerPixel, bitsPerSample, sampleFormat,
            orientation);
        if (!parsed.IsValid)
        {
            return false;
        }
        sourceMetadata = parsed;
        return true;
    }

    private static bool TryReadRequiredUInt64(JsonElement owner, string name, out ulong value)
    {
        value = 0;
        return owner.TryGetProperty(name, out JsonElement element) &&
               element.ValueKind == JsonValueKind.Number && element.TryGetUInt64(out value);
    }

    private static bool TryReadRequiredUInt32(JsonElement owner, string name, out uint value)
    {
        value = 0;
        return owner.TryGetProperty(name, out JsonElement element) &&
               element.ValueKind == JsonValueKind.Number && element.TryGetUInt32(out value);
    }

    private static bool TryReadRequiredUInt16(JsonElement owner, string name, out ushort value)
    {
        value = 0;
        return owner.TryGetProperty(name, out JsonElement element) &&
               element.ValueKind == JsonValueKind.Number && element.TryGetUInt16(out value);
    }

    private static bool TryReadInfraredPath(
        JsonElement frameRecord,
        string sourcePath,
        out string? infraredPath)
    {
        infraredPath = null;
        if (!frameRecord.TryGetProperty(InfraredPathName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.String ||
            element.GetString() is not { Length: > 0 } path ||
            string.IsNullOrWhiteSpace(path) ||
            !Path.IsPathFullyQualified(path))
        {
            return false;
        }
        try
        {
            if (string.Equals(
                    Path.TrimEndingDirectorySeparator(Path.GetFullPath(path)),
                    Path.TrimEndingDirectorySeparator(Path.GetFullPath(sourcePath)),
                    StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException or
            PathTooLongException)
        {
            return false;
        }
        infraredPath = path;
        return true;
    }

    private static bool TryReadManualBase(
        JsonElement parameters,
        out ManualBaseRgb? manualBase)
    {
        manualBase = null;
        if (!parameters.TryGetProperty(ManualBaseName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Array || element.GetArrayLength() != 3)
        {
            return false;
        }

        Span<double> channels = stackalloc double[3];
        int index = 0;
        foreach (JsonElement channel in element.EnumerateArray())
        {
            if (channel.ValueKind != JsonValueKind.Number ||
                !channel.TryGetDouble(out double value) ||
                !double.IsFinite(value))
            {
                return false;
            }
            channels[index++] = value;
        }

        manualBase = new ManualBaseRgb(channels[0], channels[1], channels[2]);
        return true;
    }

    private static bool TryReadBaseRecipe(
        JsonElement parameters,
        out BaseRecipe baseRecipe)
    {
        baseRecipe = BaseRecipe.Auto;
        BaseEstimationMode mode = BaseEstimationMode.Auto;
        if (parameters.TryGetProperty(BaseEstimationModeName, out JsonElement modeElement) &&
            modeElement.ValueKind != JsonValueKind.Null)
        {
            if (modeElement.ValueKind != JsonValueKind.String)
            {
                return false;
            }
            mode = modeElement.GetString() switch
            {
                "auto" => BaseEstimationMode.Auto,
                "preset" => BaseEstimationMode.Preset,
                "manual" => BaseEstimationMode.Manual,
                _ => (BaseEstimationMode)(-1),
            };
            if (!Enum.IsDefined(mode))
            {
                return false;
            }
        }

        if (!TryReadOptionalIdentifier(parameters, FilmStockDminIdName, out string? filmStockDminId) ||
            !TryReadOptionalIdentifier(parameters, LightSourceProfileIdName, out string? lightSourceProfileId) ||
            !TryReadOptionalIdentifier(parameters, ScannerProfileIdName, out string? scannerProfileId))
        {
            return false;
        }

        baseRecipe = new BaseRecipe(mode, filmStockDminId, lightSourceProfileId, scannerProfileId);
        return true;
    }

    private static bool TryReadOptionalIdentifier(
        JsonElement parameters,
        string name,
        out string? identifier)
    {
        identifier = null;
        if (!parameters.TryGetProperty(name, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.String ||
            string.IsNullOrWhiteSpace(element.GetString()))
        {
            return false;
        }

        identifier = element.GetString();
        return true;
    }

    private static bool TryReadTone(JsonElement parameters, out ToneAdjustment tone)
    {
        tone = default;
        if (!TryReadFiniteDouble(parameters, ExposureName, out double exposure) ||
            !TryReadFiniteDouble(parameters, ContrastName, out double contrast) ||
            !TryReadFiniteDouble(parameters, DensityName, out double density) ||
            !TryReadFiniteDouble(parameters, HighlightName, out double highlight) ||
            !TryReadFiniteDouble(parameters, ShadowName, out double shadow) ||
            !TryReadFiniteDouble(parameters, WhitesName, out double whites) ||
            !TryReadFiniteDouble(parameters, BlacksName, out double blacks) ||
            !TryReadFiniteDouble(parameters, CurveHighlightsName, out double highlights) ||
            !TryReadFiniteDouble(parameters, CurveLightsName, out double lights) ||
            !TryReadFiniteDouble(parameters, CurveDarksName, out double darks) ||
            !TryReadFiniteDouble(parameters, CurveShadowsName, out double shadows))
        {
            return false;
        }

        tone = new ToneAdjustment(
            exposure,
            contrast,
            highlights,
            lights,
            darks,
            shadows,
            density,
            highlight,
            shadow,
            whites,
            blacks);
        return true;
    }

    private static bool TryReadPointCurves(
        JsonElement parameters,
        out PointCurveRecipe pointCurves)
    {
        pointCurves = PointCurveRecipe.Identity;
        if (!parameters.TryGetProperty(PointCurvesName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Object ||
            !TryReadPointCurveChannel(element, PointCurveRgbName, out IReadOnlyList<PointCurvePoint> rgb) ||
            !TryReadPointCurveChannel(element, PointCurveRedName, out IReadOnlyList<PointCurvePoint> red) ||
            !TryReadPointCurveChannel(element, PointCurveGreenName, out IReadOnlyList<PointCurvePoint> green) ||
            !TryReadPointCurveChannel(element, PointCurveBlueName, out IReadOnlyList<PointCurvePoint> blue))
        {
            return false;
        }

        pointCurves = new PointCurveRecipe(rgb, red, green, blue);
        return true;
    }

    private static bool TryReadPointCurveChannel(
        JsonElement pointCurves,
        string channelName,
        out IReadOnlyList<PointCurvePoint> points)
    {
        points = [];
        if (!pointCurves.TryGetProperty(channelName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Array ||
            element.GetArrayLength() > PointCurveRecipe.MaximumPointsPerChannel)
        {
            return false;
        }

        List<PointCurvePoint> parsed = new(element.GetArrayLength());
        foreach (JsonElement point in element.EnumerateArray())
        {
            if (point.ValueKind != JsonValueKind.Object ||
                !point.TryGetProperty(PointCurveXName, out JsonElement xElement) ||
                !point.TryGetProperty(PointCurveYName, out JsonElement yElement) ||
                xElement.ValueKind != JsonValueKind.Number ||
                yElement.ValueKind != JsonValueKind.Number ||
                !xElement.TryGetDouble(out double x) ||
                !yElement.TryGetDouble(out double y) ||
                !double.IsFinite(x) || !double.IsFinite(y) ||
                x is < 0.0 or > 1.0 || y is < 0.0 or > 1.0)
            {
                return false;
            }
            parsed.Add(new PointCurvePoint(x, y));
        }

        parsed.Sort(static (left, right) => left.X.CompareTo(right.X));
        for (int index = 1; index < parsed.Count; index++)
        {
            if (parsed[index].X - parsed[index - 1].X < 1.0e-9)
            {
                return false;
            }
        }
        points = parsed;
        return true;
    }

    private static bool TryReadColorMixer(JsonElement parameters, out ColorMixerRecipe colorMixer)
    {
        colorMixer = ColorMixerRecipe.Identity;
        if (!parameters.TryGetProperty(ColorMixerName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Object ||
            !TryReadColorMixerChannel(element, ColorMixerHueName, out IReadOnlyList<double> hue) ||
            !TryReadColorMixerChannel(element, ColorMixerSaturationName, out IReadOnlyList<double> saturation) ||
            !TryReadColorMixerChannel(element, ColorMixerLuminanceName, out IReadOnlyList<double> luminance))
        {
            return false;
        }
        colorMixer = new ColorMixerRecipe(hue, saturation, luminance);
        return true;
    }

    private static bool TryReadColorMixerChannel(
        JsonElement colorMixer,
        string channelName,
        out IReadOnlyList<double> values)
    {
        values = new double[ColorMixerRecipe.BandCount];
        if (!colorMixer.TryGetProperty(channelName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Array ||
            element.GetArrayLength() > ColorMixerRecipe.BandCount)
        {
            return false;
        }
        double[] parsed = new double[ColorMixerRecipe.BandCount];
        int index = 0;
        foreach (JsonElement value in element.EnumerateArray())
        {
            if (value.ValueKind != JsonValueKind.Number || !value.TryGetDouble(out double parsedValue) ||
                !double.IsFinite(parsedValue) || parsedValue is < -1.0 or > 1.0)
            {
                return false;
            }
            parsed[index++] = parsedValue;
        }
        values = parsed;
        return true;
    }

    /// <summary>
    /// 색조 두 값은 키가 없으면 0 이 아니라 <b>그 모드의 기본 색조</b>입니다. macOS 와 같으며,
    /// 0 으로 채우면 sepia 를 골랐을 뿐인데 전혀 다른 색으로 물듭니다.
    /// </summary>
    private static bool TryReadBwToning(JsonElement parameters, out BwToningRecipe bwToning)
    {
        bwToning = BwToningRecipe.None;
        if (!parameters.TryGetProperty(BwToningName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        BwToningMode mode = BwToningMode.None;
        if (element.TryGetProperty(BwToningModeName, out JsonElement modeElement) &&
            modeElement.ValueKind != JsonValueKind.Null)
        {
            switch (modeElement.ValueKind == JsonValueKind.String ? modeElement.GetString() : null)
            {
                case "none":
                    mode = BwToningMode.None;
                    break;
                case "selenium":
                    mode = BwToningMode.Selenium;
                    break;
                case "sepia":
                    mode = BwToningMode.Sepia;
                    break;
                default:
                    return false;
            }
        }

        if (!TryReadOptionalFiniteDouble(
                element,
                BwToningShadowHueName,
                BwToningRecipe.DefaultShadowHue(mode),
                out double shadowHue) ||
            !TryReadOptionalFiniteDouble(
                element,
                BwToningHighlightHueName,
                BwToningRecipe.DefaultHighlightHue(mode),
                out double highlightHue) ||
            !TryReadOptionalFiniteDouble(
                element,
                BwToningStrengthName,
                0.0,
                out double strength))
        {
            return false;
        }

        BwToningRecipe read = new(mode, shadowHue, highlightHue, strength);
        if (!read.IsValid)
        {
            return false;
        }
        bwToning = read;
        return true;
    }

    private static bool TryReadColorGrading(JsonElement parameters, out ColorGradingRecipe colorGrading)
    {
        colorGrading = ColorGradingRecipe.Identity;
        if (!parameters.TryGetProperty(ColorGradingName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Object ||
            !TryReadColorGradeRegion(element, ColorGradingShadowsName, out ColorGradeRegionRecipe shadows) ||
            !TryReadColorGradeRegion(element, ColorGradingMidtonesName, out ColorGradeRegionRecipe midtones) ||
            !TryReadColorGradeRegion(element, ColorGradingHighlightsName, out ColorGradeRegionRecipe highlights) ||
            !TryReadFiniteDouble(element, ColorGradingBlendingName, out double blending) ||
            !TryReadFiniteDouble(element, ColorGradingBalanceName, out double balance) ||
            blending is < 0.0 or > 1.0 || balance is < -1.0 or > 1.0)
        {
            return false;
        }
        colorGrading = new ColorGradingRecipe(shadows, midtones, highlights, blending, balance);
        return true;
    }

    private static bool TryReadColorGradeRegion(
        JsonElement colorGrading,
        string name,
        out ColorGradeRegionRecipe region)
    {
        region = default;
        if (!colorGrading.TryGetProperty(name, out JsonElement element) ||
            element.ValueKind != JsonValueKind.Object ||
            !TryReadFiniteDouble(element, ColorGradingHueName, out double hue) ||
            !TryReadFiniteDouble(element, ColorGradingSaturationName, out double saturation) ||
            !TryReadFiniteDouble(element, ColorGradingLuminanceName, out double luminance) ||
            hue is < 0.0 or > 360.0 || saturation is < 0.0 or > 1.0 ||
            luminance is < -1.0 or > 1.0)
        {
            return false;
        }
        region = new ColorGradeRegionRecipe(hue, saturation, luminance);
        return true;
    }

    private static bool TryReadPrimaryCalibration(
        JsonElement parameters,
        out PrimaryCalibrationRecipe calibration)
    {
        calibration = PrimaryCalibrationRecipe.Identity;
        if (!parameters.TryGetProperty(PrimaryCalibrationName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Object ||
            !TryReadFiniteDouble(element, PrimaryCalibrationRedHueName, out double redHue) ||
            !TryReadFiniteDouble(element, PrimaryCalibrationRedSaturationName, out double redSaturation) ||
            !TryReadFiniteDouble(element, PrimaryCalibrationGreenHueName, out double greenHue) ||
            !TryReadFiniteDouble(element, PrimaryCalibrationGreenSaturationName, out double greenSaturation) ||
            !TryReadFiniteDouble(element, PrimaryCalibrationBlueHueName, out double blueHue) ||
            !TryReadFiniteDouble(element, PrimaryCalibrationBlueSaturationName, out double blueSaturation) ||
            new[] { redHue, redSaturation, greenHue, greenSaturation, blueHue, blueSaturation }
                .Any(value => value is < -1.0 or > 1.0))
        {
            return false;
        }
        calibration = new PrimaryCalibrationRecipe(
            redHue, redSaturation, greenHue, greenSaturation, blueHue, blueSaturation);
        return true;
    }

    // 키가 없으면 macOS 와 같이 0 입니다. 있는데 수가 아니면 조용히 0 으로 만들지 않고 거부합니다.
    private static bool TryReadLocalDodgeBurn(
        JsonElement parameters,
        out IReadOnlyList<LocalDodgeBurnAdjustment> adjustments)
    {
        adjustments = [];
        if (!parameters.TryGetProperty(LocalDodgeBurnName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Array ||
            element.GetArrayLength() > LocalDodgeBurnRecipe.MaximumAdjustments)
        {
            return false;
        }

        List<LocalDodgeBurnAdjustment> parsed = new(element.GetArrayLength());
        foreach (JsonElement adjustment in element.EnumerateArray())
        {
            if (!TryReadLocalDodgeBurnAdjustment(adjustment, out LocalDodgeBurnAdjustment? value))
            {
                return false;
            }
            parsed.Add(value!);
        }
        if (!LocalDodgeBurnRecipe.IsValid(parsed))
        {
            return false;
        }
        adjustments = parsed;
        return true;
    }

    private static bool TryReadLocalDodgeBurnAdjustment(
        JsonElement element,
        out LocalDodgeBurnAdjustment? adjustment)
    {
        adjustment = null;
        if (element.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        Guid id = Guid.NewGuid();
        if (element.TryGetProperty(LocalDodgeBurnIdName, out JsonElement idElement) &&
            idElement.ValueKind != JsonValueKind.Null &&
            (idElement.ValueKind != JsonValueKind.String ||
             !Guid.TryParse(idElement.GetString(), out id)))
        {
            return false;
        }

        LocalDodgeBurnMode mode = LocalDodgeBurnMode.Dodge;
        if (element.TryGetProperty(LocalDodgeBurnModeName, out JsonElement modeElement) &&
            modeElement.ValueKind != JsonValueKind.Null)
        {
            if (modeElement.ValueKind != JsonValueKind.String)
            {
                return false;
            }
            mode = modeElement.GetString() switch
            {
                "dodge" => LocalDodgeBurnMode.Dodge,
                "burn" => LocalDodgeBurnMode.Burn,
                _ => (LocalDodgeBurnMode)(-1),
            };
        }

        if (!TryReadOptionalFiniteDouble(element, LocalDodgeBurnAmountName, 0.0, out double amount) ||
            !TryReadOptionalBoolean(element, LocalDodgeBurnEnabledName, true, out bool isEnabled) ||
            !element.TryGetProperty(LocalDodgeBurnMaskName, out JsonElement maskElement) ||
            !TryReadLocalDodgeBurnMask(maskElement, out LocalDodgeBurnMask? mask))
        {
            return false;
        }
        adjustment = new LocalDodgeBurnAdjustment(id, mode, amount, isEnabled, mask!);
        return true;
    }

    private static bool TryReadLocalDodgeBurnMask(
        JsonElement element,
        out LocalDodgeBurnMask? mask)
    {
        mask = null;
        if (element.ValueKind != JsonValueKind.Object ||
            !element.TryGetProperty(LocalDodgeBurnKindName, out JsonElement kindElement) ||
            kindElement.ValueKind != JsonValueKind.String)
        {
            return false;
        }
        LocalDodgeBurnMaskKind kind = kindElement.GetString() switch
        {
            "brush" => LocalDodgeBurnMaskKind.Brush,
            "radial" => LocalDodgeBurnMaskKind.Radial,
            "linear" => LocalDodgeBurnMaskKind.Linear,
            "polygon" => LocalDodgeBurnMaskKind.Polygon,
            _ => (LocalDodgeBurnMaskKind)(-1),
        };
        if (!TryReadLocalDodgeBurnStrokes(element, out IReadOnlyList<LocalDodgeBurnStroke> strokes) ||
            !TryReadOptionalPoint(element, LocalDodgeBurnCenterName, new(0.5, 0.5), out LocalDodgeBurnPoint center) ||
            !TryReadOptionalFiniteDouble(element, LocalDodgeBurnRadiusName, 0.25, out double radius) ||
            !TryReadOptionalFiniteDouble(element, LocalDodgeBurnFeatherName, 0.25, out double feather) ||
            !TryReadOptionalPoint(element, LocalDodgeBurnStartName, new(0.5, 0.0), out LocalDodgeBurnPoint start) ||
            !TryReadOptionalPoint(element, LocalDodgeBurnEndName, new(0.5, 1.0), out LocalDodgeBurnPoint end) ||
            !TryReadLocalDodgeBurnPoints(element, LocalDodgeBurnPointsName, out IReadOnlyList<LocalDodgeBurnPoint> points))
        {
            return false;
        }
        mask = new LocalDodgeBurnMask(kind, strokes, center, radius, feather, start, end, points);
        return true;
    }

    private static bool TryReadLocalDodgeBurnStrokes(
        JsonElement mask,
        out IReadOnlyList<LocalDodgeBurnStroke> strokes)
    {
        strokes = [];
        if (!mask.TryGetProperty(LocalDodgeBurnStrokesName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Array ||
            element.GetArrayLength() > LocalDodgeBurnRecipe.MaximumStrokesPerMask)
        {
            return false;
        }
        List<LocalDodgeBurnStroke> parsed = new(element.GetArrayLength());
        foreach (JsonElement stroke in element.EnumerateArray())
        {
            if (stroke.ValueKind != JsonValueKind.Object ||
                !TryReadLocalDodgeBurnPoints(stroke, LocalDodgeBurnPointsName, out IReadOnlyList<LocalDodgeBurnPoint> points) ||
                !TryReadOptionalFiniteDouble(stroke, LocalDodgeBurnThicknessName, 0.04, out double thickness) ||
                !TryReadOptionalFiniteDouble(stroke, LocalDodgeBurnFeatherName, 0.02, out double feather))
            {
                return false;
            }
            parsed.Add(new LocalDodgeBurnStroke(points, thickness, feather));
        }
        strokes = parsed;
        return true;
    }

    private static bool TryReadLocalDodgeBurnPoints(
        JsonElement owner,
        string name,
        out IReadOnlyList<LocalDodgeBurnPoint> points)
    {
        points = [];
        if (!owner.TryGetProperty(name, out JsonElement element) || element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Array ||
            element.GetArrayLength() > LocalDodgeBurnRecipe.MaximumPoints)
        {
            return false;
        }
        List<LocalDodgeBurnPoint> parsed = new(element.GetArrayLength());
        foreach (JsonElement point in element.EnumerateArray())
        {
            if (!TryReadLocalDodgeBurnPoint(point, out LocalDodgeBurnPoint value))
            {
                return false;
            }
            parsed.Add(value);
        }
        points = parsed;
        return true;
    }

    private static bool TryReadOptionalPoint(
        JsonElement owner,
        string name,
        LocalDodgeBurnPoint defaultValue,
        out LocalDodgeBurnPoint point)
    {
        point = defaultValue;
        return !owner.TryGetProperty(name, out JsonElement element) || element.ValueKind == JsonValueKind.Null
            ? true
            : TryReadLocalDodgeBurnPoint(element, out point);
    }

    private static bool TryReadLocalDodgeBurnPoint(
        JsonElement element,
        out LocalDodgeBurnPoint point)
    {
        point = default;
        if (element.ValueKind != JsonValueKind.Object ||
            !element.TryGetProperty(PointCurveXName, out JsonElement xElement) ||
            !element.TryGetProperty(PointCurveYName, out JsonElement yElement) ||
            xElement.ValueKind != JsonValueKind.Number || yElement.ValueKind != JsonValueKind.Number ||
            !xElement.TryGetDouble(out double x) || !yElement.TryGetDouble(out double y) ||
            !double.IsFinite(x) || !double.IsFinite(y))
        {
            return false;
        }
        point = new LocalDodgeBurnPoint(x, y);
        return true;
    }

    private static bool TryReadOptionalFiniteDouble(
        JsonElement owner,
        string name,
        double defaultValue,
        out double value)
    {
        value = defaultValue;
        if (!owner.TryGetProperty(name, out JsonElement element) || element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        return element.ValueKind == JsonValueKind.Number &&
               element.TryGetDouble(out value) && double.IsFinite(value);
    }

    private static bool TryReadOptionalBoolean(
        JsonElement owner,
        string name,
        bool defaultValue,
        out bool value)
    {
        value = defaultValue;
        if (!owner.TryGetProperty(name, out JsonElement element) || element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
        {
            return false;
        }
        value = element.GetBoolean();
        return true;
    }

    private static bool TryReadDevelopTarget(
        JsonElement parameters,
        out DevelopTarget developTarget)
    {
        developTarget = DevelopTarget.Main;
        if (!parameters.TryGetProperty(DevelopTargetName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.String)
        {
            return false;
        }
        developTarget = element.GetString() switch
        {
            "main" => DevelopTarget.Main,
            "print" => DevelopTarget.Print,
            "noritsu" => DevelopTarget.Noritsu,
            "sp-3000" => DevelopTarget.Sp3000,
            "f135" => DevelopTarget.F135,
            "hr" => DevelopTarget.Hr,
            "rescue" => DevelopTarget.Rescue,
            _ => (DevelopTarget)(-1),
        };
        return Enum.IsDefined(developTarget);
    }

    private static bool TryReadColorModel(
        JsonElement parameters,
        out ColorModelRecipe colorModel)
    {
        if (!TryReadFiniteDouble(parameters, WarmthName, out double warmth) ||
            !TryReadFiniteDouble(parameters, TintName, out double tint) ||
            !TryReadFiniteDouble(parameters, ColorDepthName, out double colorDepth) ||
            !TryReadFiniteDouble(parameters, VibranceName, out double vibrance) ||
            !TryReadFiniteDouble(parameters, SaturationName, out double saturation) ||
            !TryReadFiniteDouble(parameters, RedPrimaryName, out double redPrimary) ||
            !TryReadFiniteDouble(parameters, GreenPrimaryName, out double greenPrimary) ||
            !TryReadFiniteDouble(parameters, BluePrimaryName, out double bluePrimary))
        {
            colorModel = ColorModelRecipe.Identity;
            return false;
        }
        colorModel = new ColorModelRecipe(
            warmth, tint, colorDepth, vibrance, saturation,
            redPrimary, greenPrimary, bluePrimary);
        return colorModel.IsValid();
    }

    private static bool TryReadFiniteDouble(
        JsonElement parameters,
        string name,
        out double value)
    {
        value = 0.0;
        if (!parameters.TryGetProperty(name, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Number ||
            !element.TryGetDouble(out double parsed) ||
            !double.IsFinite(parsed))
        {
            return false;
        }
        value = parsed;
        return true;
    }
}
