using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>붙여넣기 범위 단추의 요약 문구입니다.</summary>
internal static class PasteScopeSummaryTests
{
    private static readonly PasteScopeText Text =
        new("모든 설정", "없음", "베이스", "톤", "색상", "디테일", "기하");

    public static void Run()
    {
        Check(PasteScopeSummary.Describe(DevelopSettingsPasteScope.All, Text) == "모든 설정",
            "paste_scope_says_all_for_the_full_scope");
        DevelopSettingsPasteScope none = DevelopSettingsPasteScope.All with
        {
            Base = false,
            Tone = false,
            Color = false,
            Detail = false,
            Geometry = false,
        };
        Check(none.IsEmpty && PasteScopeSummary.Describe(none, Text) == "없음",
            "paste_scope_says_none_when_nothing_is_on");
        // 켜진 묶음은 macOS 차례대로 이어 붙입니다.
        Check(PasteScopeSummary.Describe(none with { Tone = true, Base = true }, Text) ==
                "베이스/톤",
            "paste_scope_joins_the_on_groups_in_macos_order");
        Check(PasteScopeSummary.Describe(none with { Geometry = true }, Text) == "기하",
            "paste_scope_names_a_single_group");
        Check(PasteScopeSummary.Describe(
                none with { Color = true, Detail = true, Geometry = true }, Text) ==
                "색상/디테일/기하",
            "paste_scope_joins_three_groups");
    }
}
