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

    /// <summary>
    /// rendered-digital graph 는 미구현입니다. 네이티브도 같은 이유로 거부하지만, 여기서 먼저
    /// 막아야 사용자가 현상이 시작된 뒤가 아니라 버튼을 누르기 전에 알 수 있습니다.
    /// </summary>
    UnsupportedDigitalSource,

    UnsupportedPositiveFilm,

    /// <summary>출력 형식이 알려진 값이 아닙니다.</summary>
    UnknownOutputFormat,

    /// <summary>출력 경로가 비었거나 절대 경로가 아닙니다.</summary>
    InvalidDestination,
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
        if (frame.Route.FilmLookSource != FilmLookSource.FilmScan)
        {
            return DevelopRequestResult.Failure(
                DevelopRequestRefusal.UnsupportedDigitalSource);
        }
        if (frame.Route.FilmType is not (FilmType.ColorNegative or FilmType.BlackAndWhiteNegative))
        {
            return DevelopRequestResult.Failure(DevelopRequestRefusal.UnsupportedPositiveFilm);
        }
        DevelopBaseEstimationMode baseMode;
        ManualBaseRgb manualBase = default;
        string? filmStockDminId = null;
        string? lightSourceProfileId = null;
        switch (frame.Base.Mode)
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

        return DevelopRequestResult.Success(new DevelopExportRequest
        {
            SourcePath = frame.SourcePath,
            DestinationPath = destinationPath,
            Format = format,
            FilmType = MapFilmType(frame.Route.FilmType),
            BaseEstimationMode = baseMode,
            DminRed = (float)manualBase.Red,
            DminGreen = (float)manualBase.Green,
            DminBlue = (float)manualBase.Blue,
            FilmStockDminId = filmStockDminId,
            LightSourceProfileId = lightSourceProfileId,
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
            FilmLookSourceKind = DevelopSourceKind.FilmScan,
            FilmEmulation = MapFilmEmulation(frame.Route.FilmEmulation),
            FilmEmulationIntensity = frame.Route.FilmEmulationIntensity,
        });
    }

    // 이 factory는 positive route를 명시 거부한 뒤에만 부릅니다. 포지티브를 color negative로
    // 뭉개면 Auto가 반전된 artifact를 정상 결과처럼 publish할 수 있습니다.
    private static NegativeFilmType MapFilmType(FilmType filmType) => filmType switch
    {
        FilmType.ColorNegative => NegativeFilmType.Color,
        FilmType.BlackAndWhiteNegative => NegativeFilmType.BlackAndWhite,
        _ => throw new ArgumentOutOfRangeException(nameof(filmType)),
    };

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
            _ => throw new ArgumentOutOfRangeException(nameof(emulation)),
        };
}
