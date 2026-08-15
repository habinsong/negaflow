namespace Negaflow.Shell;

/// <summary>
/// Native Film base resolver가 식별자로 해석할 수 있는 번들 선택지입니다.
/// 이 목록은 UI 표시와 입력 검증에만 사용하며, 해석 수치의 원본은 native resolver입니다.
/// </summary>
public sealed record FilmStockOption(string? Id, string DisplayName);

public sealed record LightSourceOption(string? Id, string DisplayName);

/// <summary>
/// macOS <c>ScannerProfileValidationStatus</c> 와 같습니다. 프로파일이 무엇으로 만들어졌는지를
/// 말하며, 라이브러리의 "검증되지 않은 프로파일" 필터가 이 값을 봅니다.
/// </summary>
public enum ScannerProfileValidationStatus
{
    Draft,
    RealOnly,
    PairedSmoke,
    PairedValidated,
}

/// <summary>
/// 고를 수 있는 스캐너 프로파일 하나입니다. 수치는 native 가 들고 있고(같은 manifest 에서 온
/// 같은 15개), 여기 있는 것은 고르기 위한 이름뿐입니다.
/// </summary>
public sealed record ScannerProfileOption(
    string? Id,
    string DisplayName,
    ScannerProfileValidationStatus Status);

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

    /// <summary>
    /// native <c>scanner_profile_grade.cpp</c> 가 들고 있는 것과 **같은 15개, 같은 차례**입니다.
    /// 여기에만 있고 native 에 없는 id 를 고르면 프로파일이 걸리지 않은 채 현상되고, 사용자는
    /// 고른 것이 왜 아무 일도 하지 않는지 알 수 없습니다.
    /// </summary>
    public static IReadOnlyList<ScannerProfileOption> ScannerProfiles { get; } =
    [
        new("noritsu__color-nega__fuji-c200", "NORITSU color nega fuji c200",
            ScannerProfileValidationStatus.RealOnly),
        new("noritsu__color-nega__kodak-ektar-100", "NORITSU color nega kodak ektar 100",
            ScannerProfileValidationStatus.RealOnly),
        new("noritsu__color-nega__kodak-portra-160", "NORITSU color nega kodak portra 160",
            ScannerProfileValidationStatus.RealOnly),
        new("noritsu__color-nega__kodak-portra-400", "NORITSU color nega kodak portra 400",
            ScannerProfileValidationStatus.RealOnly),
        new("noritsu__color-nega__kodak-portra-800", "NORITSU color nega kodak portra 800",
            ScannerProfileValidationStatus.RealOnly),
        new("noritsu__color-nega__kodak-pro-image-100", "NORITSU color nega kodak pro image 100",
            ScannerProfileValidationStatus.RealOnly),
        new("noritsu__color-nega__kodak-ultramax-400", "NORITSU color nega kodak ultramax 400",
            ScannerProfileValidationStatus.RealOnly),
        new("noritsu__color-nega__kodak-vision3-250d", "NORITSU color nega kodak vision3 250d",
            ScannerProfileValidationStatus.RealOnly),
        new("noritsu__color-nega__kodak-vision3-50d", "NORITSU color nega kodak vision3 50d",
            ScannerProfileValidationStatus.RealOnly),
        new("noritsu__color-slide__kodak-ektachrome-100",
            "NORITSU color slide kodak ektachrome 100",
            ScannerProfileValidationStatus.RealOnly),
        new("noritsu__color-slide__kodak-ektachrome-100d",
            "NORITSU color slide kodak ektachrome 100d",
            ScannerProfileValidationStatus.RealOnly),
        new("sp-3000__color-nega__kodak-ektar-100", "SP-3000 color nega kodak ektar 100",
            ScannerProfileValidationStatus.RealOnly),
        new("sp-3000__color-nega__kodak-portra-160", "SP-3000 color nega kodak portra 160",
            ScannerProfileValidationStatus.RealOnly),
        new("sp-3000__color-nega__kodak-vision3-250d", "SP-3000 color nega kodak vision3 250d",
            ScannerProfileValidationStatus.RealOnly),
        new("sp-3000__color-slide__kodak-ektachrome-100d",
            "SP-3000 color slide kodak ektachrome 100d",
            ScannerProfileValidationStatus.RealOnly),
    ];

    public static bool IsKnownScannerProfile(string? id) =>
        id is null ||
        ScannerProfiles.Any(option => string.Equals(option.Id, id, StringComparison.Ordinal));

    public static bool IsKnownFilmStock(string? id) =>
        FilmStocks.Any(option => string.Equals(option.Id, id, StringComparison.Ordinal));

    public static bool IsKnownLightSource(string? id) =>
        LightSources.Any(option => string.Equals(option.Id, id, StringComparison.Ordinal));
}
