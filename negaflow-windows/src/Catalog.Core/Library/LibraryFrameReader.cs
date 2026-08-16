using static Negaflow.Catalog.BaseRecipeJsonReader;
using static Negaflow.Catalog.ColorRecipeJsonReader;
using static Negaflow.Catalog.ImageEffectRecipeJsonReader;
using static Negaflow.Catalog.LibraryFrameCoreJsonReader;
using static Negaflow.Catalog.LibraryJsonValueReader;
using static Negaflow.Catalog.LocalDodgeBurnJsonReader;
using static Negaflow.Catalog.ToneRecipeJsonReader;
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
    /// <summary>macOS 와 같이 params 형제입니다 — 레시피가 아니라 사진의 사실입니다.</summary>
    public const string AppMetadataName = "appMetadataOverlay";
    internal const string AppMetadataVersionName = "version";
    internal const string AppMetadataTitleName = "title";
    internal const string AppMetadataCaptionName = "caption";
    internal const string AppMetadataKeywordsName = "keywords";
    internal const string AppMetadataCopyrightName = "copyright";
    internal const string AppMetadataRevisionName = "revision";
    internal const string AppMetadataUpdatedAtName = "updatedAt";
    internal const string FilmShotName = "filmShot";
    internal const string FilmShotCameraMakeName = "cameraMake";
    internal const string FilmShotCameraModelName = "cameraModel";
    internal const string FilmShotLensModelName = "lensModel";
    internal const string FilmShotFilmStockName = "filmStock";
    internal const string FilmShotIsoSpeedName = "isoSpeed";
    internal const string FilmShotExposureTimeName = "exposureTimeSeconds";
    internal const string FilmShotFNumberName = "fNumber";
    internal const string FilmShotFocalLengthName = "focalLengthMM";
    /// <summary>Swift Date 의 기준시각입니다. 같은 숫자를 읽고 씁니다.</summary>
    public static readonly DateTimeOffset AppleReferenceDate =
        new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);
    internal const string DisplayNameName = "customDisplayName";
    internal const string ScanIndexName = "scanIndex";
    internal const string SourceKindName = "sourceKind";
    internal const string SourceFrameDisplayNameName = "sourceFrameDisplayName";
    internal const string SourceFrameIdName = "sourceFrameID";
    internal const string VirtualCopyNumberName = "virtualCopyNumber";
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
        if (!TryReadAppMetadata(frameRecord, out AppMetadataOverlay? appMetadata))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidAppMetadata);
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
            AppMetadata = appMetadata,
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
            ScanIndex = ReadScanIndex(frameRecord),
            SourceKind = ReadSourceKind(frameRecord),
            SourceFrameDisplayName = ReadOptionalText(frameRecord, SourceFrameDisplayNameName),
            SourceFrameId = ReadOptionalText(frameRecord, SourceFrameIdName),
            VirtualCopyNumber = ReadOptionalPositiveInt(frameRecord, VirtualCopyNumberName),
        });
    }

}
