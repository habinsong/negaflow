namespace Negaflow.Catalog;

internal static class DevelopRouteJsonNames
{
    public static bool TryParseSourceTransport(
        string value,
        out FrameSourceTransport sourceTransport)
    {
        switch (value)
        {
            case "scanner":
                sourceTransport = FrameSourceTransport.Scanner;
                return true;
            case "imported":
                sourceTransport = FrameSourceTransport.Imported;
                return true;
            default:
                sourceTransport = default;
                return false;
        }
    }

    public static bool TryParseSourceSignalKind(
        string value,
        out SourceSignalKind sourceSignalKind)
    {
        switch (value)
        {
            case "filmNegativeScan":
                sourceSignalKind = SourceSignalKind.FilmNegativeScan;
                return true;
            case "filmPositiveScan":
                sourceSignalKind = SourceSignalKind.FilmPositiveScan;
                return true;
            case "renderedDigital":
                sourceSignalKind = SourceSignalKind.RenderedDigital;
                return true;
            case "sceneLinearDigital":
                sourceSignalKind = SourceSignalKind.SceneLinearDigital;
                return true;
            case "unknown":
                sourceSignalKind = SourceSignalKind.Unknown;
                return true;
            default:
                sourceSignalKind = default;
                return false;
        }
    }

    public static string FormatSourceSignalKind(SourceSignalKind value) => value switch
    {
        SourceSignalKind.FilmNegativeScan => "filmNegativeScan",
        SourceSignalKind.FilmPositiveScan => "filmPositiveScan",
        SourceSignalKind.RenderedDigital => "renderedDigital",
        SourceSignalKind.SceneLinearDigital => "sceneLinearDigital",
        SourceSignalKind.Unknown => "unknown",
        _ => throw new ArgumentOutOfRangeException(nameof(value)),
    };

    public static bool TryParseFilmType(string value, out FilmType filmType)
    {
        switch (value)
        {
            case "colorNegative":
                filmType = FilmType.ColorNegative;
                return true;
            case "colorPositive":
                filmType = FilmType.ColorPositive;
                return true;
            case "bwNegative":
                filmType = FilmType.BlackAndWhiteNegative;
                return true;
            case "bwPositive":
                filmType = FilmType.BlackAndWhitePositive;
                return true;
            default:
                filmType = default;
                return false;
        }
    }

    public static string FormatFilmType(FilmType value) => value switch
    {
        FilmType.ColorNegative => "colorNegative",
        FilmType.ColorPositive => "colorPositive",
        FilmType.BlackAndWhiteNegative => "bwNegative",
        FilmType.BlackAndWhitePositive => "bwPositive",
        _ => throw new ArgumentOutOfRangeException(nameof(value)),
    };

    public static bool TryParseFilmEmulation(string value, out FilmEmulation filmEmulation)
    {
        switch (value)
        {
            case "none":
                filmEmulation = FilmEmulation.None;
                return true;
            case "ektachromeE100":
                filmEmulation = FilmEmulation.EktachromeE100;
                return true;
            case "provia100F":
                filmEmulation = FilmEmulation.Provia100F;
                return true;
            case "velvia50":
                filmEmulation = FilmEmulation.Velvia50;
                return true;
            case "portra160":
                filmEmulation = FilmEmulation.Portra160;
                return true;
            case "portra400":
                filmEmulation = FilmEmulation.Portra400;
                return true;
            case "portra800":
                filmEmulation = FilmEmulation.Portra800;
                return true;
            case "ektar100":
                filmEmulation = FilmEmulation.Ektar100;
                return true;
            case "ultramax400":
                filmEmulation = FilmEmulation.Ultramax400;
                return true;
            case "colorPlus200":
                filmEmulation = FilmEmulation.ColorPlus200;
                return true;
            case "fujicolorC200":
                filmEmulation = FilmEmulation.FujicolorC200;
                return true;
            case "pro400H":
                filmEmulation = FilmEmulation.Pro400H;
                return true;
            default:
                filmEmulation = default;
                return false;
        }
    }

    public static string FormatFilmEmulation(FilmEmulation value) => value switch
    {
        FilmEmulation.None => "none",
        FilmEmulation.EktachromeE100 => "ektachromeE100",
        FilmEmulation.Provia100F => "provia100F",
        FilmEmulation.Velvia50 => "velvia50",
        FilmEmulation.Portra160 => "portra160",
        FilmEmulation.Portra400 => "portra400",
        FilmEmulation.Portra800 => "portra800",
        FilmEmulation.Ektar100 => "ektar100",
        FilmEmulation.Ultramax400 => "ultramax400",
        FilmEmulation.ColorPlus200 => "colorPlus200",
        FilmEmulation.FujicolorC200 => "fujicolorC200",
        FilmEmulation.Pro400H => "pro400H",
        _ => throw new ArgumentOutOfRangeException(nameof(value)),
    };
}
