using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

public enum DevelopRequestRefusal
{
    None,

    /// <summary>Manual 모드에 저장된 Dmin 이 없습니다.</summary>
    MissingManualBase,

    MissingFilmStock,

    UnsupportedBaseEstimationMode,

    /// <summary>Scene-linear 또는 알 수 없는 digital source는 아직 지원하지 않습니다.</summary>
    UnsupportedDigitalSource,

    UnsupportedPositiveFilm,

    /// <summary>출력 형식이 알려진 값이 아닙니다.</summary>
    UnknownOutputFormat,

    /// <summary>출력 경로가 비었거나 절대 경로가 아닙니다.</summary>
    InvalidDestination,

    InvalidDefectRecipe,

    UnsupportedDefectEditKind,
}

public readonly record struct DevelopRequestResult(
    DevelopExportRequest? Request,
    DevelopRequestRefusal Refusal)
{
    public bool IsSuccess => Refusal == DevelopRequestRefusal.None && Request is not null;

    internal static DevelopRequestResult Success(DevelopExportRequest request) =>
        new(request, DevelopRequestRefusal.None);

    internal static DevelopRequestResult Failure(DevelopRequestRefusal refusal) =>
        new(null, refusal);
}

/// <summary>
/// catalog 에 저장된 frame 을 네이티브 현상 요청으로 옮깁니다. 이 계층이 catalog 와 엔진을 동시에
/// 아는 유일한 곳이며, 그래서 <c>Shell.Core</c> 가 Interop 과 같은 아키텍처에 묶여 있습니다.
/// XAML 을 참조하지 않으므로 UI 없이 그대로 시험할 수 있습니다.
/// </summary>
public static class DevelopRequestFactory
{
    public static DevelopRequestResult Create(
        LibraryFrameSnapshot frame,
        string destinationPath,
        DevelopExportFormat format = DevelopExportFormat.Png16)
    {
        ArgumentNullException.ThrowIfNull(frame);

        if (!Enum.IsDefined(format))
        {
            return DevelopRequestResult.Failure(DevelopRequestRefusal.UnknownOutputFormat);
        }
        if (string.IsNullOrWhiteSpace(destinationPath) ||
            !Path.IsPathFullyQualified(destinationPath))
        {
            return DevelopRequestResult.Failure(DevelopRequestRefusal.InvalidDestination);
        }
        bool renderedDigital = frame.Route.FilmLookSource == FilmLookSource.RenderedDigital;
        bool positive = frame.Route.FilmType is
            FilmType.ColorPositive or FilmType.BlackAndWhitePositive;
        if (frame.Route.SourceSignalKind is
            SourceSignalKind.SceneLinearDigital or SourceSignalKind.Unknown)
        {
            return DevelopRequestResult.Failure(DevelopRequestRefusal.UnsupportedDigitalSource);
        }
        if ((frame.Route.SourceSignalKind == SourceSignalKind.FilmNegativeScan && positive) ||
            (frame.Route.SourceSignalKind == SourceSignalKind.FilmPositiveScan && !positive) ||
            (renderedDigital && !positive))
        {
            return DevelopRequestResult.Failure(DevelopRequestRefusal.UnsupportedPositiveFilm);
        }
        DevelopBaseEstimationMode baseMode;
        ManualBaseRgb manualBase = default;
        string? filmStockDminId = null;
        string? lightSourceProfileId = null;
        if (positive)
        {
            // Positive film and digital input bypass Dmin/base resolution and inversion.
            // Manual+zero is an explicit inert ABI value; the native digital branch ignores it.
            baseMode = DevelopBaseEstimationMode.Manual;
        }
        else switch (frame.Base.Mode)
        {
            case BaseEstimationMode.Auto:
                baseMode = DevelopBaseEstimationMode.Auto;
                break;
            case BaseEstimationMode.Manual when frame.ManualBase is { } selectedManualBase:
                baseMode = DevelopBaseEstimationMode.Manual;
                manualBase = selectedManualBase;
                break;
            case BaseEstimationMode.Manual:
                return DevelopRequestResult.Failure(DevelopRequestRefusal.MissingManualBase);
            case BaseEstimationMode.Preset when !string.IsNullOrWhiteSpace(frame.Base.FilmStockDminId):
                baseMode = DevelopBaseEstimationMode.Preset;
                filmStockDminId = frame.Base.FilmStockDminId;
                lightSourceProfileId = frame.Base.LightSourceProfileId;
                break;
            case BaseEstimationMode.Preset:
                return DevelopRequestResult.Failure(DevelopRequestRefusal.MissingFilmStock);
            default:
                return DevelopRequestResult.Failure(
                    DevelopRequestRefusal.UnsupportedBaseEstimationMode);
        }
        if (!DefectRecipeProjector.TryProject(
                frame.DefectRecipe,
                out IReadOnlyList<DevelopDefectRegionEdit> defectRegions,
                out IReadOnlyList<DevelopDefectInfraredEdit> defectInfrared,
                out IReadOnlyList<DevelopDefectCloneEdit> defectClones,
                out IReadOnlyList<DevelopDefectBrushEdit> defectBrushes,
                out IReadOnlyList<DevelopDefectRecipeEditRef> defectEditOrder,
                out DevelopRequestRefusal defectRefusal))
        {
            return DevelopRequestResult.Failure(defectRefusal);
        }
        DevelopDefectSourceIdentity? defectSourceIdentity = null;
        if (defectEditOrder.Count != 0)
        {
            if (frame.DefectRecipe?.SourceIdentity is not { } sourceIdentity)
            {
                return DevelopRequestResult.Failure(
                    DevelopRequestRefusal.InvalidDefectRecipe);
            }
            defectSourceIdentity = new DevelopDefectSourceIdentity(
                sourceIdentity.ByteCount,
                sourceIdentity.Sha256);
        }

        return DevelopRequestResult.Success(new DevelopExportRequest
        {
            SourcePath = frame.SourcePath,
            DestinationPath = destinationPath,
            Format = format,
            FilmType = MapFilmType(frame.Route.FilmType),
            FilmPolarity = positive ? FilmPolarity.Positive : FilmPolarity.Negative,
            BaseEstimationMode = baseMode,
            DminRed = (float)manualBase.Red,
            DminGreen = (float)manualBase.Green,
            DminBlue = (float)manualBase.Blue,
            FilmStockDminId = filmStockDminId,
            LightSourceProfileId = lightSourceProfileId,
            ScannerProfileId = frame.Base.ScannerProfileId,
            ExposureStops = (float)frame.Tone.Exposure,
            Contrast = (float)frame.Tone.Contrast,
            Density = (float)frame.Tone.Density,
            Highlight = (float)frame.Tone.Highlight,
            Shadow = (float)frame.Tone.Shadow,
            Whites = (float)frame.Tone.Whites,
            Blacks = (float)frame.Tone.Blacks,
            Highlights = (float)frame.Tone.CurveHighlights,
            Lights = (float)frame.Tone.CurveLights,
            Darks = (float)frame.Tone.CurveDarks,
            Shadows = (float)frame.Tone.CurveShadows,
            Warmth = (float)frame.ColorModel.Warmth,
            Tint = (float)frame.ColorModel.Tint,
            ColorDepth = (float)frame.ColorModel.ColorDepth,
            Vibrance = (float)frame.ColorModel.Vibrance,
            Saturation = (float)frame.ColorModel.Saturation,
            RedPrimary = (float)frame.ColorModel.RedPrimary,
            GreenPrimary = (float)frame.ColorModel.GreenPrimary,
            BluePrimary = (float)frame.ColorModel.BluePrimary,
            AutoLevels = frame.AutoLevels,
            AutoNeutralBalance = frame.AutoNeutralBalance,
            DevelopTarget = frame.DevelopTarget switch
            {
                DevelopTarget.Main => DevelopTargetMode.Main,
                DevelopTarget.Print => DevelopTargetMode.Print,
                DevelopTarget.Noritsu => DevelopTargetMode.Noritsu,
                DevelopTarget.Sp3000 => DevelopTargetMode.Sp3000,
                DevelopTarget.F135 => DevelopTargetMode.F135,
                DevelopTarget.Hr => DevelopTargetMode.Hr,
                DevelopTarget.Rescue => DevelopTargetMode.Rescue,
                _ => throw new ArgumentOutOfRangeException(nameof(frame.DevelopTarget)),
            },
            PointCurves = new DevelopPointCurves
            {
                Rgb = frame.PointCurves.Rgb.Select(point =>
                    new DevelopPointCurvePoint(point.X, point.Y)).ToArray(),
                Red = frame.PointCurves.Red.Select(point =>
                    new DevelopPointCurvePoint(point.X, point.Y)).ToArray(),
                Green = frame.PointCurves.Green.Select(point =>
                    new DevelopPointCurvePoint(point.X, point.Y)).ToArray(),
                Blue = frame.PointCurves.Blue.Select(point =>
                    new DevelopPointCurvePoint(point.X, point.Y)).ToArray(),
            },
            ColorMixer = new DevelopColorMixer
            {
                Hue = frame.ColorMixer.Hue.Select(value => (float)value).ToArray(),
                Saturation = frame.ColorMixer.Saturation.Select(value => (float)value).ToArray(),
                Luminance = frame.ColorMixer.Luminance.Select(value => (float)value).ToArray(),
            },
            ColorGrading = new DevelopColorGrading
            {
                Shadows = MapColorGradeRegion(frame.ColorGrading.Shadows),
                Midtones = MapColorGradeRegion(frame.ColorGrading.Midtones),
                Highlights = MapColorGradeRegion(frame.ColorGrading.Highlights),
                Blending = (float)frame.ColorGrading.Blending,
                Balance = (float)frame.ColorGrading.Balance,
            },
            PrimaryCalibration = new DevelopPrimaryCalibration
            {
                RedHue = (float)frame.PrimaryCalibration.RedHue,
                RedSaturation = (float)frame.PrimaryCalibration.RedSaturation,
                GreenHue = (float)frame.PrimaryCalibration.GreenHue,
                GreenSaturation = (float)frame.PrimaryCalibration.GreenSaturation,
                BlueHue = (float)frame.PrimaryCalibration.BlueHue,
                BlueSaturation = (float)frame.PrimaryCalibration.BlueSaturation,
            },
            FilmLookSourceKind = renderedDigital
                ? DevelopSourceKind.RenderedDigital
                : DevelopSourceKind.FilmScan,
            FilmEmulation = MapFilmEmulation(frame.Route.FilmEmulation),
            FilmEmulationIntensity = frame.Route.FilmEmulationIntensity,
            ImageTransform = MapImageTransform(frame.ImageTransform),
            Grain = (float)frame.Texture.Grain,
            Sharpness = (float)frame.Texture.Sharpness,
            Halation = (float)frame.Texture.Halation,
            Clarity = (float)frame.Texture.Clarity,
            Vignette = (float)frame.Texture.Vignette,
            NoiseReductionStrength = (float)frame.NoiseReduction.Strength,
            NoiseReductionLuma = (float)frame.NoiseReduction.Luma,
            NoiseReductionChroma = (float)frame.NoiseReduction.Chroma,
            NoiseReductionDarkTone = (float)frame.NoiseReduction.DarkTone,
            NoiseReductionDetail = (float)frame.NoiseReduction.Detail,
            NoiseReductionGrainProtect = (float)frame.NoiseReduction.GrainProtect,
            NoiseReductionFilmProfile = MapNoiseReductionFilmProfile(frame.Route.FilmType),
            DefectRegions = defectRegions,
            DefectInfrared = defectInfrared,
            DefectClones = defectClones,
            DefectBrushes = defectBrushes,
            DefectEditOrder = defectEditOrder,
            DefectSourceIdentity = defectSourceIdentity,
            LocalDodgeBurn = frame.LocalDodgeBurn.Select(MapLocalDodgeBurn).ToArray(),
        });
    }

    private static NegativeFilmType MapFilmType(FilmType filmType) => filmType switch
    {
        FilmType.ColorNegative or FilmType.ColorPositive => NegativeFilmType.Color,
        FilmType.BlackAndWhiteNegative or FilmType.BlackAndWhitePositive =>
            NegativeFilmType.BlackAndWhite,
        _ => throw new ArgumentOutOfRangeException(nameof(filmType)),
    };

    private static DevelopImageTransform MapImageTransform(ImageTransformRecipe transform) => new()
    {
        Rotation = transform.Rotation switch
        {
            ImageRotation.Degrees0 => DevelopImageRotation.Degrees0,
            ImageRotation.Degrees90 => DevelopImageRotation.Degrees90,
            ImageRotation.Degrees180 => DevelopImageRotation.Degrees180,
            ImageRotation.Degrees270 => DevelopImageRotation.Degrees270,
            _ => throw new ArgumentOutOfRangeException(nameof(transform)),
        },
        FlipHorizontal = transform.FlipHorizontal,
        FlipVertical = transform.FlipVertical,
        Crop = transform.Crop is { } crop
            ? new DevelopCropRect(crop.X, crop.Y, crop.Width, crop.Height)
            : null,
        StraightenAngle = transform.StraightenAngle,
    };

    private static FilmScanDenoiseFilmProfile MapNoiseReductionFilmProfile(FilmType filmType) =>
        filmType switch
        {
            FilmType.ColorNegative => FilmScanDenoiseFilmProfile.ColorNegative,
            FilmType.ColorPositive => FilmScanDenoiseFilmProfile.ColorPositive,
            FilmType.BlackAndWhiteNegative => FilmScanDenoiseFilmProfile.BlackAndWhiteNegative,
            FilmType.BlackAndWhitePositive => FilmScanDenoiseFilmProfile.BlackAndWhitePositive,
            _ => throw new ArgumentOutOfRangeException(nameof(filmType)),
        };

    private static DevelopColorGradeRegion MapColorGradeRegion(ColorGradeRegionRecipe region) =>
        new((float)region.Hue, (float)region.Saturation, (float)region.Luminance);

    private static DevelopLocalDodgeBurnAdjustment MapLocalDodgeBurn(
        LocalDodgeBurnAdjustment adjustment) => new()
    {
        Mode = adjustment.Mode == LocalDodgeBurnMode.Dodge
            ? DevelopLocalDodgeBurnMode.Dodge
            : DevelopLocalDodgeBurnMode.Burn,
        Amount = adjustment.Amount,
        IsEnabled = adjustment.IsEnabled,
        Mask = new DevelopLocalDodgeBurnMask
        {
            Kind = adjustment.Mask.Kind switch
            {
                LocalDodgeBurnMaskKind.Brush => DevelopLocalDodgeBurnMaskKind.Brush,
                LocalDodgeBurnMaskKind.Radial => DevelopLocalDodgeBurnMaskKind.Radial,
                LocalDodgeBurnMaskKind.Linear => DevelopLocalDodgeBurnMaskKind.Linear,
                LocalDodgeBurnMaskKind.Polygon => DevelopLocalDodgeBurnMaskKind.Polygon,
                _ => throw new ArgumentOutOfRangeException(nameof(adjustment)),
            },
            Strokes = adjustment.Mask.Strokes.Select(stroke =>
                new DevelopLocalDodgeBurnStroke
                {
                    Points = stroke.Points.Select(MapLocalDodgeBurnPoint).ToArray(),
                    Thickness = stroke.Thickness,
                    Feather = stroke.Feather,
                }).ToArray(),
            Center = MapLocalDodgeBurnPoint(adjustment.Mask.Center),
            Radius = adjustment.Mask.Radius,
            Feather = adjustment.Mask.Feather,
            Start = MapLocalDodgeBurnPoint(adjustment.Mask.Start),
            End = MapLocalDodgeBurnPoint(adjustment.Mask.End),
            Points = adjustment.Mask.Points.Select(MapLocalDodgeBurnPoint).ToArray(),
        },
    };

    private static DevelopLocalDodgeBurnPoint MapLocalDodgeBurnPoint(
        LocalDodgeBurnPoint point) => new(point.X, point.Y);

    private static FilmEmulationProfile MapFilmEmulation(FilmEmulation emulation) =>
        emulation switch
        {
            FilmEmulation.None => FilmEmulationProfile.None,
            FilmEmulation.EktachromeE100 => FilmEmulationProfile.EktachromeE100,
            FilmEmulation.Provia100F => FilmEmulationProfile.Provia100F,
            FilmEmulation.Velvia50 => FilmEmulationProfile.Velvia50,
            FilmEmulation.Portra160 => FilmEmulationProfile.Portra160,
            FilmEmulation.Portra400 => FilmEmulationProfile.Portra400,
            FilmEmulation.Portra800 => FilmEmulationProfile.Portra800,
            FilmEmulation.Ektar100 => FilmEmulationProfile.Ektar100,
            FilmEmulation.Ultramax400 => FilmEmulationProfile.Ultramax400,
            FilmEmulation.ColorPlus200 => FilmEmulationProfile.ColorPlus200,
            FilmEmulation.FujicolorC200 => FilmEmulationProfile.FujicolorC200,
            FilmEmulation.Pro400H => FilmEmulationProfile.Pro400H,
            FilmEmulation.TriX400 => FilmEmulationProfile.TriX400,
            FilmEmulation.Hp5Plus => FilmEmulationProfile.Hp5Plus,
            FilmEmulation.Fp4Plus => FilmEmulationProfile.Fp4Plus,
            FilmEmulation.Delta100 => FilmEmulationProfile.Delta100,
            FilmEmulation.Delta400 => FilmEmulationProfile.Delta400,
            FilmEmulation.Delta3200 => FilmEmulationProfile.Delta3200,
            FilmEmulation.TMax100 => FilmEmulationProfile.TMax100,
            FilmEmulation.TMax400 => FilmEmulationProfile.TMax400,
            FilmEmulation.TMaxP3200 => FilmEmulationProfile.TMaxP3200,
            FilmEmulation.Kentmere400 => FilmEmulationProfile.Kentmere400,
            FilmEmulation.OrthoPlus => FilmEmulationProfile.OrthoPlus,
            FilmEmulation.Sfx200 => FilmEmulationProfile.Sfx200,
            FilmEmulation.RolleiIR => FilmEmulationProfile.RolleiIR,
            FilmEmulation.Scala200X => FilmEmulationProfile.Scala200X,
            FilmEmulation.RolleiSuperpan => FilmEmulationProfile.RolleiSuperpan,
            FilmEmulation.Velvia100 => FilmEmulationProfile.Velvia100,
            FilmEmulation.E100VS => FilmEmulationProfile.E100VS,
            FilmEmulation.Astia100F => FilmEmulationProfile.Astia100F,
            FilmEmulation.Kodachrome64 => FilmEmulationProfile.Kodachrome64,
            FilmEmulation.Gold200 => FilmEmulationProfile.Gold200,
            FilmEmulation.ProImage100 => FilmEmulationProfile.ProImage100,
            FilmEmulation.Superia400 => FilmEmulationProfile.Superia400,
            FilmEmulation.SuperiaPremium400 =>
                FilmEmulationProfile.SuperiaPremium400,
            FilmEmulation.Superia200 => FilmEmulationProfile.Superia200,
            FilmEmulation.Reala100 => FilmEmulationProfile.Reala100,
            FilmEmulation.Industrial100 => FilmEmulationProfile.Industrial100,
            FilmEmulation.LomoCn800 => FilmEmulationProfile.LomoCn800,
            FilmEmulation.Vision3_500T => FilmEmulationProfile.Vision3_500T,
            FilmEmulation.Vision3_250D => FilmEmulationProfile.Vision3_250D,
            FilmEmulation.Vision3_50D => FilmEmulationProfile.Vision3_50D,
            FilmEmulation.Vision3_200T => FilmEmulationProfile.Vision3_200T,
            _ => throw new ArgumentOutOfRangeException(nameof(emulation)),
        };
}
