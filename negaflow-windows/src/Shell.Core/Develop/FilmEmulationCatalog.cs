using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>macOS <c>FilmEmulation.Kind</c> 와 같은 필름 묶음입니다.</summary>
public enum FilmEmulationKind
{
    Slide,
    Negative,
    MotionPicture,
    BlackAndWhiteNegative,
    BlackAndWhiteReversal,
}

/// <summary>
/// 42종 필름 에뮬레이션의 묶음과 표시 이름입니다. 엔진은 이미 전부 구현하고 있었는데 고를
/// 길이 없었습니다 — 이 표가 그 목록입니다.
/// </summary>
/// <remarks>
/// 필름 상표는 그 실물 필름을 지목하기 위한 지시적 사용입니다. macOS 쪽 같은 표의 주석과
/// 저장소 최상위 <c>TRADEMARKS.md</c> 를 따릅니다.
/// </remarks>
public static class FilmEmulationCatalog
{
    private static readonly (FilmEmulation Emulation, FilmEmulationKind Kind, string Name)[] Entries =
    [
        (FilmEmulation.EktachromeE100, FilmEmulationKind.Slide, "Kodak Ektachrome E100"),
        (FilmEmulation.Provia100F, FilmEmulationKind.Slide, "Fujichrome Provia 100F"),
        (FilmEmulation.Velvia50, FilmEmulationKind.Slide, "Fujichrome Velvia 50"),
        (FilmEmulation.Velvia100, FilmEmulationKind.Slide, "Fujichrome Velvia 100"),
        (FilmEmulation.E100VS, FilmEmulationKind.Slide, "Kodak Ektachrome E100VS"),
        (FilmEmulation.Astia100F, FilmEmulationKind.Slide, "Fujichrome Astia 100F"),
        (FilmEmulation.Kodachrome64, FilmEmulationKind.Slide, "Kodachrome 64"),

        (FilmEmulation.Portra160, FilmEmulationKind.Negative, "Kodak Portra 160"),
        (FilmEmulation.Portra400, FilmEmulationKind.Negative, "Kodak Portra 400"),
        (FilmEmulation.Portra800, FilmEmulationKind.Negative, "Kodak Portra 800"),
        (FilmEmulation.Ektar100, FilmEmulationKind.Negative, "Kodak Ektar 100"),
        (FilmEmulation.Ultramax400, FilmEmulationKind.Negative, "Kodak UltraMax 400"),
        (FilmEmulation.ColorPlus200, FilmEmulationKind.Negative, "Kodak ColorPlus 200"),
        (FilmEmulation.FujicolorC200, FilmEmulationKind.Negative, "Fujicolor C200"),
        (FilmEmulation.Pro400H, FilmEmulationKind.Negative, "Fujicolor Pro 400H"),
        (FilmEmulation.Gold200, FilmEmulationKind.Negative, "Kodak Gold 200"),
        (FilmEmulation.ProImage100, FilmEmulationKind.Negative, "Kodak Pro Image 100"),
        (FilmEmulation.Superia400, FilmEmulationKind.Negative, "Fujicolor Superia 400"),
        (FilmEmulation.SuperiaPremium400, FilmEmulationKind.Negative, "Fujicolor Superia Premium 400"),
        (FilmEmulation.Superia200, FilmEmulationKind.Negative, "Fujicolor Superia 200"),
        (FilmEmulation.Reala100, FilmEmulationKind.Negative, "Fujicolor Reala 100"),
        (FilmEmulation.Industrial100, FilmEmulationKind.Negative, "Fujicolor Industrial 100"),
        (FilmEmulation.LomoCn800, FilmEmulationKind.Negative, "Lomography CN 800"),

        (FilmEmulation.Vision3_500T, FilmEmulationKind.MotionPicture, "Kodak Vision3 500T"),
        (FilmEmulation.Vision3_250D, FilmEmulationKind.MotionPicture, "Kodak Vision3 250D"),
        (FilmEmulation.Vision3_50D, FilmEmulationKind.MotionPicture, "Kodak Vision3 50D"),
        (FilmEmulation.Vision3_200T, FilmEmulationKind.MotionPicture, "Kodak Vision3 200T"),

        (FilmEmulation.TriX400, FilmEmulationKind.BlackAndWhiteNegative, "Kodak Tri-X 400"),
        (FilmEmulation.Hp5Plus, FilmEmulationKind.BlackAndWhiteNegative, "Ilford HP5 Plus 400"),
        (FilmEmulation.Fp4Plus, FilmEmulationKind.BlackAndWhiteNegative, "Ilford FP4 Plus 125"),
        (FilmEmulation.Delta100, FilmEmulationKind.BlackAndWhiteNegative, "Ilford Delta 100"),
        (FilmEmulation.Delta400, FilmEmulationKind.BlackAndWhiteNegative, "Ilford Delta 400"),
        (FilmEmulation.Delta3200, FilmEmulationKind.BlackAndWhiteNegative, "Ilford Delta 3200"),
        (FilmEmulation.TMax100, FilmEmulationKind.BlackAndWhiteNegative, "Kodak T-Max 100"),
        (FilmEmulation.TMax400, FilmEmulationKind.BlackAndWhiteNegative, "Kodak T-Max 400"),
        (FilmEmulation.TMaxP3200, FilmEmulationKind.BlackAndWhiteNegative, "Kodak T-Max P3200"),
        (FilmEmulation.Kentmere400, FilmEmulationKind.BlackAndWhiteNegative, "Kentmere Pan 400"),
        (FilmEmulation.OrthoPlus, FilmEmulationKind.BlackAndWhiteNegative, "Ilford Ortho Plus 80"),
        (FilmEmulation.Sfx200, FilmEmulationKind.BlackAndWhiteNegative, "Ilford SFX 200"),
        (FilmEmulation.RolleiIR, FilmEmulationKind.BlackAndWhiteNegative, "Rollei Infrared 400"),

        (FilmEmulation.Scala200X, FilmEmulationKind.BlackAndWhiteReversal, "Agfa Scala 200X"),
        (FilmEmulation.RolleiSuperpan, FilmEmulationKind.BlackAndWhiteReversal, "Rollei Superpan 200"),
    ];

    /// <summary>
    /// macOS 가 그 필름 종류에 내놓는 묶음 순서입니다. 흑백은 반전·음화 둘, 컬러는 슬라이드·
    /// 음화·시네 셋입니다.
    /// </summary>
    public static IReadOnlyList<FilmEmulationKind> KindsFor(FilmType filmType) =>
        filmType is FilmType.BlackAndWhiteNegative or FilmType.BlackAndWhitePositive
            ? [FilmEmulationKind.BlackAndWhiteReversal, FilmEmulationKind.BlackAndWhiteNegative]
            : [FilmEmulationKind.Slide, FilmEmulationKind.Negative, FilmEmulationKind.MotionPicture];

    public static IReadOnlyList<FilmEmulation> Films(FilmEmulationKind kind)
    {
        List<FilmEmulation> films = [];
        foreach ((FilmEmulation emulation, FilmEmulationKind entryKind, _) in Entries)
        {
            if (entryKind == kind)
            {
                films.Add(emulation);
            }
        }
        return films;
    }

    /// <summary>필름 상표는 번역하지 않습니다 — 실물 제품 이름입니다.</summary>
    public static string DisplayName(FilmEmulation emulation)
    {
        foreach ((FilmEmulation entry, _, string name) in Entries)
        {
            if (entry == emulation)
            {
                return name;
            }
        }
        return string.Empty;
    }

    public static int Count => Entries.Length;
}
