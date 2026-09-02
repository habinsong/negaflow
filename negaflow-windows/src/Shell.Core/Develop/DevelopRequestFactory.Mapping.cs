using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

/// <summary>
/// 카탈로그 레시피 값을 <b>ABI 가 받는 모양</b>으로 옮기는 자리입니다. 요청을 어떻게 조립할지
/// (무엇을 거절하고 무엇을 자동으로 흘려보낼지)와는 바뀌는 이유가 달라 파일을 나눕니다 —
/// 이쪽은 ABI 열거·구조가 바뀔 때만 손댑니다.
/// </summary>
public static partial class DevelopRequestFactory
{
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
