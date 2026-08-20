using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>macOS <c>InfraredFilmCompatibility</c> — 은이 남으면 IR 자동 보정 금지.</summary>
public enum InfraredFilmCompatibility
{
    DyeImage,
    SilverImage,
}

public static class InfraredFilmCompatibilityRules
{
    public static InfraredFilmCompatibility From(FilmType filmType) =>
        filmType is FilmType.ColorNegative or FilmType.ColorPositive
            ? InfraredFilmCompatibility.DyeImage
            : InfraredFilmCompatibility.SilverImage;

    public static bool AllowsAutomaticCorrection(FilmType filmType) =>
        From(filmType) == InfraredFilmCompatibility.DyeImage;
}
