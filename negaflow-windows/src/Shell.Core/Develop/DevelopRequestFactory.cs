using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

public enum DevelopRequestRefusal
{
    None,

    /// <summary>수동 Dmin 이 없습니다. Windows 에는 아직 auto base 추정이 없습니다.</summary>
    MissingManualBase,

    /// <summary>
    /// rendered-digital graph 는 미구현입니다. 네이티브도 같은 이유로 거부하지만, 여기서 먼저
    /// 막아야 사용자가 현상이 시작된 뒤가 아니라 버튼을 누르기 전에 알 수 있습니다.
    /// </summary>
    UnsupportedDigitalSource,

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
        if (frame.ManualBase is not { } manualBase)
        {
            return DevelopRequestResult.Failure(DevelopRequestRefusal.MissingManualBase);
        }

        return DevelopRequestResult.Success(new DevelopExportRequest
        {
            SourcePath = frame.SourcePath,
            DestinationPath = destinationPath,
            Format = format,
            FilmType = MapFilmType(frame.Route.FilmType),
            DminRed = (float)manualBase.Red,
            DminGreen = (float)manualBase.Green,
            DminBlue = (float)manualBase.Blue,
            ExposureStops = (float)frame.Tone.Exposure,
            Contrast = (float)frame.Tone.Contrast,
            Highlights = (float)frame.Tone.CurveHighlights,
            Lights = (float)frame.Tone.CurveLights,
            Darks = (float)frame.Tone.CurveDarks,
            Shadows = (float)frame.Tone.CurveShadows,
            FilmLookSourceKind = DevelopSourceKind.FilmScan,
            FilmEmulation = MapFilmEmulation(frame.Route.FilmEmulation),
            FilmEmulationIntensity = frame.Route.FilmEmulationIntensity,
        });
    }

    // 네거티브 현상은 컬러와 흑백 두 갈래뿐입니다. 포지티브 필름 타입은 반전 자체가 다른 경로이며
    // 아직 없으므로, 여기서 컬러로 뭉개지 않고 route 가 이미 걸러 준 것에만 의존합니다.
    private static NegativeFilmType MapFilmType(FilmType filmType) => filmType switch
    {
        FilmType.BlackAndWhiteNegative or FilmType.BlackAndWhitePositive =>
            NegativeFilmType.BlackAndWhite,
        _ => NegativeFilmType.Color,
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
