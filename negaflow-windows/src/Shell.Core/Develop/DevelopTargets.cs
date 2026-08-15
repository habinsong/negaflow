using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 현상 타깃 목록과 이름, 그리고 타깃을 바꿀 때 스캐너 프로파일을 어떻게 할지의 규칙입니다.
/// </summary>
/// <remarks>
/// 이름은 번역하지 않습니다 — MAIN·HS·SP·F135·HR 은 미니랩 기종·출력 규격의 이름이고 macOS 도
/// 언어와 무관하게 그대로 씁니다.
/// </remarks>
public static class DevelopTargets
{
    /// <summary>
    /// 고르개에 나오는 다섯입니다. PRINT 와 EXPIRED 는 MAIN 갈래 안에서 다시 고르므로 여기에
    /// 없습니다 — macOS <c>visibleTargets</c> 와 같습니다.
    /// </summary>
    public static IReadOnlyList<DevelopTarget> Visible { get; } =
    [
        DevelopTarget.Main,
        DevelopTarget.Noritsu,
        DevelopTarget.Sp3000,
        DevelopTarget.F135,
        DevelopTarget.Hr,
    ];

    /// <summary>MAIN 갈래 안의 세 가지입니다.</summary>
    public static IReadOnlyList<DevelopTarget> MainFamily { get; } =
    [
        DevelopTarget.Main,
        DevelopTarget.Print,
        DevelopTarget.Rescue,
    ];

    public static string DisplayName(DevelopTarget target) => target switch
    {
        DevelopTarget.Print => "PRINT",
        DevelopTarget.Noritsu => "HS",
        DevelopTarget.Sp3000 => "SP",
        DevelopTarget.F135 => "F135",
        DevelopTarget.Hr => "HR",
        DevelopTarget.Rescue => "EXPIRED",
        _ => "MAIN",
    };

    /// <summary>
    /// 실기 미니랩 재현 타깃인지. 그렇다면 네거티브 파이프라인이 MAIN 그레이드 대신 실측
    /// 프로파일 기반 그레이드를 씁니다.
    /// </summary>
    public static bool IsScannerEmulation(DevelopTarget target) =>
        target is DevelopTarget.Noritsu or DevelopTarget.Sp3000 or
            DevelopTarget.F135 or DevelopTarget.Hr;

    /// <summary>
    /// 고르개에서 이 사진이 어느 칸에 있는지. PRINT 와 EXPIRED 는 MAIN 칸에 듭니다.
    /// </summary>
    public static DevelopTarget Family(DevelopTarget target) =>
        target is DevelopTarget.Print or DevelopTarget.Rescue ? DevelopTarget.Main : target;

    /// <summary>
    /// 이 타깃·필름에 쓸 수 있는 스캐너 프로파일입니다. 기종과 필름 갈래가 모두 맞아야 합니다 —
    /// macOS <c>ScannerProfileMatcher.matchingProfiles</c> 와 같은 규칙입니다.
    /// </summary>
    /// <remarks>
    /// 프로파일 id 는 <c>기종__갈래__필름</c> 이며 그 세 토막이 곧 조건입니다. 흑백에는 프로파일이
    /// 없고, F135·HR 은 프로파일이 아니라 타깃 자체가 성격을 정하므로 목록이 빕니다.
    /// </remarks>
    public static IReadOnlyList<ScannerProfileOption> MatchingProfiles(
        DevelopTarget target,
        FilmType filmType)
    {
        string? scanner = target switch
        {
            DevelopTarget.Noritsu => "noritsu",
            DevelopTarget.Sp3000 => "sp-3000",
            _ => null,
        };
        string? kind = filmType switch
        {
            FilmType.ColorNegative => "color-nega",
            FilmType.ColorPositive => "color-slide",
            _ => null,
        };
        if (scanner is null || kind is null)
        {
            return [];
        }
        string prefix = $"{scanner}__{kind}__";
        return [.. BundledFilmBaseOptions.ScannerProfiles
            .Where(option => option.Id is { } id &&
                id.StartsWith(prefix, StringComparison.Ordinal))
            .OrderBy(option => option.Id, StringComparer.Ordinal)];
    }

    /// <summary>
    /// 타깃을 바꾼 뒤 남길 스캐너 프로파일입니다.
    /// </summary>
    /// <remarks>
    /// macOS <c>applyDevelopTarget</c> 과 같습니다. 미니랩 재현 타깃으로 가면 프로파일을
    /// <b>뗍니다</b> — 그 타깃은 프로파일이 아니라 타깃 자체가 성격을 정하므로, 남겨 두면 두
    /// 성격이 겹칩니다. MAIN·PRINT·EXPIRED 로 갈 때도 뗍니다: 그 셋에는 맞는 프로파일이
    /// 정의상 없기 때문입니다(프로파일은 기종에 매이고 그 셋은 기종이 아닙니다). 프로파일은
    /// 현상 화면의 Base 구획에서 따로 고릅니다.
    /// </remarks>
    public static string? ProfileAfterTargetChange(
        DevelopTarget target,
        FilmType filmType,
        string? currentProfileId)
    {
        if (IsScannerEmulation(target))
        {
            return null;
        }
        if (currentProfileId is null)
        {
            return null;
        }
        return MatchingProfiles(target, filmType)
            .Any(option => string.Equals(option.Id, currentProfileId, StringComparison.Ordinal))
                ? currentProfileId
                : null;
    }
}
