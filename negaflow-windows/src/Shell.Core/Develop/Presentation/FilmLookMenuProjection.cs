using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>필름 룩 목록의 한 칸입니다. 고른 표시까지 여기서 정합니다.</summary>
public sealed record FilmLookChoice(FilmEmulation Emulation, string Name, bool IsSelected);

/// <summary>필름 룩 목록의 한 묶음입니다.</summary>
public sealed record FilmLookGroup(string Title, IReadOnlyList<FilmLookChoice> Films);

/// <summary>
/// 필름 룩 고르개의 묶음과 차례입니다. 필름 목록이 늘거나 macOS 의 묶음 이름이 바뀔 때
/// 바뀌므로, 화면 배치·이벤트와 같은 자리에 두지 않습니다. 묶음 이름은 밖에서 받습니다.
/// </summary>
public static class FilmLookMenuProjection
{
    public static IReadOnlyList<FilmLookGroup> Groups(
        FilmType filmType,
        FilmEmulation current,
        string noneTitle,
        Func<FilmEmulationKind, string> groupTitle)
    {
        List<FilmLookGroup> groups =
        [
            // macOS 와 같이 첫 자리는 룩을 끄는 선택입니다.
            new FilmLookGroup(
                noneTitle,
                [new FilmLookChoice(
                    FilmEmulation.None,
                    noneTitle,
                    current == FilmEmulation.None)]),
        ];
        foreach (FilmEmulationKind kind in FilmEmulationCatalog.KindsFor(filmType))
        {
            List<FilmLookChoice> films = [];
            foreach (FilmEmulation emulation in FilmEmulationCatalog.Films(kind))
            {
                films.Add(new FilmLookChoice(
                    emulation,
                    FilmEmulationCatalog.DisplayName(emulation),
                    emulation == current));
            }
            groups.Add(new FilmLookGroup(groupTitle(kind), films));
        }
        return groups;
    }

    /// <summary>묶음 이름의 지역화 키입니다. 어느 말로 낼지는 화면이 정합니다.</summary>
    public static string GroupTitleKey(FilmEmulationKind kind) => kind switch
    {
        FilmEmulationKind.Slide => "filmTypeColorPositive",
        FilmEmulationKind.Negative => "filmTypeColorNegative",
        FilmEmulationKind.MotionPicture => "developFilmGroupMotion",
        FilmEmulationKind.BlackAndWhiteReversal => "developFilmGroupBWSlide",
        _ => "filmTypeBlackAndWhiteNegative",
    };
}
