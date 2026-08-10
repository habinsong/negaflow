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
            case "triX400":
                filmEmulation = FilmEmulation.TriX400;
                return true;
            case "hp5Plus":
                filmEmulation = FilmEmulation.Hp5Plus;
                return true;
            case "fp4Plus":
                filmEmulation = FilmEmulation.Fp4Plus;
                return true;
            case "delta100":
                filmEmulation = FilmEmulation.Delta100;
                return true;
            case "delta400":
                filmEmulation = FilmEmulation.Delta400;
                return true;
            case "delta3200":
                filmEmulation = FilmEmulation.Delta3200;
                return true;
            case "tmax100":
                filmEmulation = FilmEmulation.TMax100;
                return true;
            case "tmax400":
                filmEmulation = FilmEmulation.TMax400;
                return true;
            case "tmaxP3200":
                filmEmulation = FilmEmulation.TMaxP3200;
                return true;
            case "kentmere400":
                filmEmulation = FilmEmulation.Kentmere400;
                return true;
            case "orthoPlus":
                filmEmulation = FilmEmulation.OrthoPlus;
                return true;
            case "sfx200":
                filmEmulation = FilmEmulation.Sfx200;
                return true;
            case "rolleiIR":
                filmEmulation = FilmEmulation.RolleiIR;
                return true;
            case "scala200X":
                filmEmulation = FilmEmulation.Scala200X;
                return true;
            case "rolleiSuperpan":
                filmEmulation = FilmEmulation.RolleiSuperpan;
                return true;
            case "velvia100":
                filmEmulation = FilmEmulation.Velvia100;
                return true;
            case "e100VS":
                filmEmulation = FilmEmulation.E100VS;
                return true;
            case "astia100F":
                filmEmulation = FilmEmulation.Astia100F;
                return true;
            case "kodachrome64":
                filmEmulation = FilmEmulation.Kodachrome64;
                return true;
            case "gold200":
                filmEmulation = FilmEmulation.Gold200;
                return true;
            case "proImage100":
                filmEmulation = FilmEmulation.ProImage100;
                return true;
            case "superia400":
                filmEmulation = FilmEmulation.Superia400;
                return true;
            case "superiaPremium400":
                filmEmulation = FilmEmulation.SuperiaPremium400;
                return true;
            case "superia200":
                filmEmulation = FilmEmulation.Superia200;
                return true;
            case "reala100":
                filmEmulation = FilmEmulation.Reala100;
                return true;
            case "industrial100":
                filmEmulation = FilmEmulation.Industrial100;
                return true;
            case "lomoCn800":
                filmEmulation = FilmEmulation.LomoCn800;
                return true;
            case "vision3_500T":
                filmEmulation = FilmEmulation.Vision3_500T;
                return true;
            case "vision3_250D":
                filmEmulation = FilmEmulation.Vision3_250D;
                return true;
            case "vision3_50D":
                filmEmulation = FilmEmulation.Vision3_50D;
                return true;
            case "vision3_200T":
                filmEmulation = FilmEmulation.Vision3_200T;
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
        FilmEmulation.TriX400 => "triX400",
        FilmEmulation.Hp5Plus => "hp5Plus",
        FilmEmulation.Fp4Plus => "fp4Plus",
        FilmEmulation.Delta100 => "delta100",
        FilmEmulation.Delta400 => "delta400",
        FilmEmulation.Delta3200 => "delta3200",
        FilmEmulation.TMax100 => "tmax100",
        FilmEmulation.TMax400 => "tmax400",
        FilmEmulation.TMaxP3200 => "tmaxP3200",
        FilmEmulation.Kentmere400 => "kentmere400",
        FilmEmulation.OrthoPlus => "orthoPlus",
        FilmEmulation.Sfx200 => "sfx200",
        FilmEmulation.RolleiIR => "rolleiIR",
        FilmEmulation.Scala200X => "scala200X",
        FilmEmulation.RolleiSuperpan => "rolleiSuperpan",
        FilmEmulation.Velvia100 => "velvia100",
        FilmEmulation.E100VS => "e100VS",
        FilmEmulation.Astia100F => "astia100F",
        FilmEmulation.Kodachrome64 => "kodachrome64",
        FilmEmulation.Gold200 => "gold200",
        FilmEmulation.ProImage100 => "proImage100",
        FilmEmulation.Superia400 => "superia400",
        FilmEmulation.SuperiaPremium400 => "superiaPremium400",
        FilmEmulation.Superia200 => "superia200",
        FilmEmulation.Reala100 => "reala100",
        FilmEmulation.Industrial100 => "industrial100",
        FilmEmulation.LomoCn800 => "lomoCn800",
        FilmEmulation.Vision3_500T => "vision3_500T",
        FilmEmulation.Vision3_250D => "vision3_250D",
        FilmEmulation.Vision3_50D => "vision3_50D",
        FilmEmulation.Vision3_200T => "vision3_200T",
        _ => throw new ArgumentOutOfRangeException(nameof(value)),
    };
}
