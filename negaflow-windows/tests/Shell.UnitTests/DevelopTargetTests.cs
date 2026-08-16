using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;
using Negaflow.Shell.Shortcuts;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class DevelopTargetTests
{
    public static void Run()
    {
        VerifyDevelopTargets();
    }

    private static void VerifyDevelopTargets()
    {
        Check(
            DevelopTargets.Visible.Count == 5 &&
                DevelopTargets.Visible[0] == DevelopTarget.Main &&
                DevelopTargets.Visible[4] == DevelopTarget.Hr,
            "develop_target_visible_list_matches_mac");
        Check(
            DevelopTargets.DisplayName(DevelopTarget.Noritsu) == "HS" &&
                DevelopTargets.DisplayName(DevelopTarget.Sp3000) == "SP" &&
                DevelopTargets.DisplayName(DevelopTarget.Rescue) == "EXPIRED",
            "develop_target_names_are_not_translated");

        // PRINT 와 EXPIRED 는 MAIN 칸에서 다시 고릅니다.
        Check(
            DevelopTargets.Family(DevelopTarget.Print) == DevelopTarget.Main &&
                DevelopTargets.Family(DevelopTarget.Rescue) == DevelopTarget.Main &&
                DevelopTargets.Family(DevelopTarget.Sp3000) == DevelopTarget.Sp3000,
            "develop_target_family");

        Check(
            DevelopTargets.IsScannerEmulation(DevelopTarget.F135) &&
                !DevelopTargets.IsScannerEmulation(DevelopTarget.Print),
            "develop_target_scanner_emulation");

        // 프로파일 목록은 기종과 필름 갈래가 모두 맞는 것뿐입니다.
        IReadOnlyList<ScannerProfileOption> noritsuNegative =
            DevelopTargets.MatchingProfiles(DevelopTarget.Noritsu, FilmType.ColorNegative);
        Check(
            noritsuNegative.Count == 9 &&
                noritsuNegative.All(option =>
                    option.Id!.StartsWith("noritsu__color-nega__", StringComparison.Ordinal)),
            "develop_target_matching_profiles_filter_by_scanner_and_kind");
        Check(
            DevelopTargets.MatchingProfiles(DevelopTarget.Noritsu, FilmType.BlackAndWhiteNegative)
                .Count == 0,
            "develop_target_no_profiles_for_monochrome");
        Check(
            DevelopTargets.MatchingProfiles(DevelopTarget.F135, FilmType.ColorNegative).Count == 0,
            "develop_target_f135_has_no_profiles");

        // 미니랩 재현 타깃으로 가면 프로파일을 뗍니다 — 두 성격이 겹치지 않게.
        Check(
            DevelopTargets.ProfileAfterTargetChange(
                DevelopTarget.Noritsu,
                FilmType.ColorNegative,
                "noritsu__color-nega__kodak-portra-400") is null,
            "develop_target_emulation_drops_the_profile");
        // MAIN 갈래에도 맞는 프로파일이 정의상 없으므로 역시 뗍니다.
        Check(
            DevelopTargets.ProfileAfterTargetChange(
                DevelopTarget.Main,
                FilmType.ColorNegative,
                "noritsu__color-nega__kodak-portra-400") is null,
            "develop_target_main_drops_the_profile");
    }


    /// <summary>
    /// 되돌리기가 없으면 제거는 물어봐야 하는 조작이 됩니다. 되살아난 사진이 원래 자리와 원래
    /// 소속을 되찾지 못하면 되돌린 것이 아닙니다.
    /// </summary>
}
