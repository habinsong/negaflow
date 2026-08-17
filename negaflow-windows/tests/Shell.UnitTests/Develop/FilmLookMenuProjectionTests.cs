using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 필름 룩 고르개의 묶음과 차례입니다. 이 계약은 `DevelopWorkspaceView` 안에 있을 때는 창을
/// 띄우지 않고 확인할 수 없었습니다.
/// </summary>
internal static class FilmLookMenuProjectionTests
{
    public static void Run()
    {
        VerifyNoneComesFirst();
        VerifySelectionMarking();
        VerifyGroupsFollowTheFilmType();
        VerifyGroupTitleKeys();
    }

    private static IReadOnlyList<FilmLookGroup> Groups(
        FilmType filmType,
        FilmEmulation current) =>
        FilmLookMenuProjection.Groups(filmType, current, "없음", kind => kind.ToString());

    private static void VerifyNoneComesFirst()
    {
        IReadOnlyList<FilmLookGroup> groups =
            Groups(FilmType.ColorNegative, FilmEmulation.None);
        // macOS 와 같이 첫 자리는 룩을 끄는 선택입니다.
        Check(groups.Count > 1 && groups[0].Title == "없음" && groups[0].Films.Count == 1 &&
            groups[0].Films[0].Emulation == FilmEmulation.None,
            "film_look_puts_none_first");
        Check(groups[0].Films[0].IsSelected,
            "film_look_marks_none_when_no_look_is_applied");
    }

    private static void VerifySelectionMarking()
    {
        IReadOnlyList<FilmLookGroup> groups =
            Groups(FilmType.ColorNegative, FilmEmulation.Portra400);
        IReadOnlyList<FilmLookChoice> all =
            [.. groups.SelectMany(group => group.Films)];
        Check(all.Count(choice => choice.IsSelected) == 1,
            "film_look_marks_exactly_one_choice");
        Check(all.Single(choice => choice.IsSelected).Emulation == FilmEmulation.Portra400,
            "film_look_marks_the_applied_film");
        Check(!groups[0].Films[0].IsSelected,
            "film_look_unmarks_none_when_a_film_is_applied");
        Check(all.All(choice => choice.Name.Length > 0),
            "film_look_names_every_choice");
    }

    private static void VerifyGroupsFollowTheFilmType()
    {
        // 묶음은 카탈로그가 필름 종류별로 내는 차례를 그대로 따릅니다.
        foreach (FilmType filmType in new[]
                 {
                     FilmType.ColorNegative,
                     FilmType.ColorPositive,
                     FilmType.BlackAndWhiteNegative,
                 })
        {
            IReadOnlyList<FilmLookGroup> groups = Groups(filmType, FilmEmulation.None);
            IReadOnlyList<FilmEmulationKind> expected =
                [.. FilmEmulationCatalog.KindsFor(filmType)];
            Check(groups.Count == expected.Count + 1,
                $"film_look_group_count_follows_{filmType}");
            Check(groups.Skip(1).Select(group => group.Title)
                    .SequenceEqual(expected.Select(kind => kind.ToString()), StringComparer.Ordinal),
                $"film_look_group_order_follows_{filmType}");
        }
    }

    private static void VerifyGroupTitleKeys()
    {
        Check(FilmLookMenuProjection.GroupTitleKey(FilmEmulationKind.Slide) ==
                "filmTypeColorPositive" &&
            FilmLookMenuProjection.GroupTitleKey(FilmEmulationKind.Negative) ==
                "filmTypeColorNegative" &&
            FilmLookMenuProjection.GroupTitleKey(FilmEmulationKind.MotionPicture) ==
                "developFilmGroupMotion" &&
            FilmLookMenuProjection.GroupTitleKey(FilmEmulationKind.BlackAndWhiteReversal) ==
                "developFilmGroupBWSlide",
            "film_look_group_titles_keep_their_macos_keys");
    }
}
