using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 사용자 프리셋 이름 규칙입니다.
/// </summary>
/// <remarks>
/// 앞 판은 이름을 묻지 않고 "프리셋 N" 을 붙였고, N 이 개수+1 이라 중간을 지우면 이미 있는
/// 번호와 부딪혔습니다. 프리셋은 나중에 목록에서 골라 쓰는 것이라 이름이 곧 정체입니다.
/// </remarks>
internal static class DevelopPresetNamingTests
{
    private static string Auto(int index) => $"프리셋 {index}";

    public static void Run()
    {
        EmptyNameGetsTheFirstFreeNumber();
        TypedNameIsKept();
        DuplicatesNeverCollide();
    }

    private static void EmptyNameGetsTheFirstFreeNumber()
    {
        Check(DevelopPresetNaming.Resolve(null, [], Auto) == "프리셋 1",
            "preset_naming_starts_at_one");
        Check(DevelopPresetNaming.Resolve("   ", ["프리셋 1"], Auto) == "프리셋 2",
            "preset_naming_skips_a_taken_number");
        // 개수+1 이 아니라 **비어 있는 첫 번호**입니다. 가운데를 지운 목록에서 갈립니다.
        Check(DevelopPresetNaming.Resolve("", ["프리셋 1", "프리셋 3"], Auto) == "프리셋 2",
            "preset_naming_fills_the_gap_instead_of_counting");
    }

    private static void TypedNameIsKept()
    {
        Check(DevelopPresetNaming.Resolve("Portra", [], Auto) == "Portra",
            "preset_naming_keeps_what_the_user_typed");
        Check(DevelopPresetNaming.Resolve("  Portra  ", [], Auto) == "Portra",
            "preset_naming_trims_the_typed_name");
    }

    private static void DuplicatesNeverCollide()
    {
        Check(DevelopPresetNaming.Resolve("Portra", ["Portra"], Auto) == "Portra 2",
            "preset_naming_numbers_a_duplicate");
        Check(DevelopPresetNaming.Resolve("Portra", ["Portra", "Portra 2"], Auto) == "Portra 3",
            "preset_naming_keeps_numbering_until_free");
        // 목록에서 사람이 읽고 고르는 이름이라 대소문자만 다른 것도 같은 이름으로 봅니다.
        Check(DevelopPresetNaming.Resolve("portra", ["Portra"], Auto) == "portra 2",
            "preset_naming_treats_case_as_the_same_name");
    }
}
