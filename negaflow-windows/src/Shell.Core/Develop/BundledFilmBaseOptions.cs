namespace Negaflow.Shell;

/// <summary>
/// Native Film base resolver가 식별자로 해석할 수 있는 번들 선택지입니다.
/// 이 목록은 UI 표시와 입력 검증에만 사용하며, 해석 수치의 원본은 native resolver입니다.
/// </summary>
public sealed record FilmStockOption(string? Id, string DisplayName);

public sealed record LightSourceOption(string? Id, string DisplayName);

public static class BundledFilmBaseOptions
{
    public static IReadOnlyList<FilmStockOption> FilmStocks { get; } =
    [
        new(null, "None"),
        new("kodak-portra-160", "Kodak Portra 160"),
        new("kodak-portra-400", "Kodak Portra 400"),
        new("kodak-portra-800", "Kodak Portra 800"),
        new("kodak-ektar-100", "Kodak Ektar 100"),
        new("kodak-gold-200", "Kodak Gold 200"),
        new("kodak-ultramax-400", "Kodak Ultramax 400"),
        new("kodak-pro-image-100", "Kodak Pro Image 100"),
        new("kodak-colorplus-200", "Kodak ColorPlus 200"),
        new("fuji-c200", "Fujicolor C200"),
        new("fuji-200", "Fujifilm 200"),
        new("fuji-400", "Fujifilm 400"),
        new("fuji-superia-400", "Fujifilm Superia 400"),
        new("fuji-100", "Fujifilm 100"),
        new("vision3-50d", "Kodak Vision3 50D"),
        new("vision3-200t", "Kodak Vision3 200T"),
        new("vision3-250d", "Kodak Vision3 250D"),
        new("vision3-500t", "Kodak Vision3 500T"),
        new("cinestill-50d", "Cinestill 50D"),
        new("cinestill-400d", "Cinestill 400D"),
        new("cinestill-800t", "Cinestill 800T"),
        new("lomo-cn-100", "Lomography Color Negative 100"),
        new("lomo-cn-400", "Lomography Color Negative 400"),
        new("lomo-cn-800", "Lomography Color Negative 800"),
        new("harman-phoenix-200", "Harman Phoenix 200"),
        new("harman-phoenix-ii", "Harman Phoenix II"),
        new("orwo-wolfen-nc400", "ORWO Wolfen NC400"),
        new("orwo-wolfen-nc500", "ORWO Wolfen NC500"),
    ];

    public static IReadOnlyList<LightSourceOption> LightSources { get; } =
    [
        new(null, "None (neutral)"),
        new("neutral", "Neutral"),
        new("white-led", "White LED"),
        new("warm-led", "Warm LED"),
        new("halogen", "Halogen"),
        new("fluorescent", "Fluorescent"),
    ];

    public static bool IsKnownFilmStock(string? id) =>
        FilmStocks.Any(option => string.Equals(option.Id, id, StringComparison.Ordinal));

    public static bool IsKnownLightSource(string? id) =>
        LightSources.Any(option => string.Equals(option.Id, id, StringComparison.Ordinal));
}
