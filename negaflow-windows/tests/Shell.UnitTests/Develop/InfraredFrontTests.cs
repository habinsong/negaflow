using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>macOS <c>InfraredFilmCompatibility</c> · <c>runInfraredCleanIfNeeded</c> · pairing.</summary>
internal static class InfraredFrontTests
{
    public static void Run()
    {
        Check(
            InfraredFilmCompatibilityRules.From(FilmType.ColorNegative) ==
            InfraredFilmCompatibility.DyeImage,
            "ir_color_neg_is_dye");
        Check(
            InfraredFilmCompatibilityRules.From(FilmType.ColorPositive) ==
            InfraredFilmCompatibility.DyeImage,
            "ir_color_pos_is_dye");
        Check(
            InfraredFilmCompatibilityRules.From(FilmType.BlackAndWhiteNegative) ==
            InfraredFilmCompatibility.SilverImage,
            "ir_bw_is_silver");
        Check(
            InfraredFilmCompatibilityRules.AllowsAutomaticCorrection(FilmType.ColorNegative) &&
            !InfraredFilmCompatibilityRules.AllowsAutomaticCorrection(FilmType.BlackAndWhiteNegative),
            "ir_auto_only_dye");
        Check(InfraredCleanPolicy.SelectionDebounceMilliseconds == 350, "ir_debounce_350");

        LibraryFrameSnapshot color = Frame(null);
        Check(!InfraredCleanPolicy.ShouldRun(color, alreadyAttempted: false), "ir_no_path_skips");
        LibraryFrameSnapshot withIr = color with { InfraredPath = @"C:\scans\a.ir.tif" };
        Check(InfraredCleanPolicy.ShouldRun(withIr, alreadyAttempted: false), "ir_color_with_path_runs");
        Check(!InfraredCleanPolicy.ShouldRun(withIr, alreadyAttempted: true), "ir_attempted_skips");
        Check(
            !InfraredCleanPolicy.ShouldRun(
                withIr with { Route = withIr.Route with { FilmType = FilmType.BlackAndWhiteNegative } },
                alreadyAttempted: false),
            "ir_bw_skips");
        Check(
            InfraredCleanPolicy.ShouldRearm(InfraredDefectApplyStatus.Cancelled) &&
            !InfraredCleanPolicy.ShouldRearm(InfraredDefectApplyStatus.DetectionFailed) &&
            !InfraredCleanPolicy.ShouldRearm(InfraredDefectApplyStatus.SourceMismatch) &&
            !InfraredCleanPolicy.ShouldRearm(InfraredDefectApplyStatus.PersistenceFailed) &&
            !InfraredCleanPolicy.ShouldRearm(InfraredDefectApplyStatus.NoDefects),
            "ir_rearm_only_cancelled");

        Check(InfraredImportPairing.InfraredCoreName(@"C:\scans\foo.tiff.ir.tiff") == "foo.tiff",
            "ir_core_scan_suffix");
        Check(InfraredImportPairing.InfraredCoreName(@"C:\scans\foo_ir.tif") == "foo",
            "ir_core_underscore");
        Check(InfraredImportPairing.InfraredCoreName(@"C:\scans\foo-infrared.tif") == "foo",
            "ir_core_infrared_token");
        Check(InfraredImportPairing.InfraredCoreName(@"C:\scans\noir.tiff") is null,
            "ir_core_rejects_noir");
        Check(InfraredImportPairing.InfraredCoreName(@"C:\scans\foo_ir.jpg") is null,
            "ir_core_rejects_jpeg");

        InfraredImportPairing.Resolution pair = InfraredImportPairing.Resolve(
            [@"C:\scans\a.tif", @"C:\scans\a_ir.tif"]);
        Check(pair.BasePaths.Count == 1 && pair.BasePaths[0] == @"C:\scans\a.tif", "pair_keeps_base");
        Check(pair.PairedInfraredPaths.Count == 1, "pair_hides_ir_file");
        Check(
            pair.InfraredByBaseIdentity[InfraredImportPairing.ImportIdentity(@"C:\scans\a.tif")] ==
            @"C:\scans\a_ir.tif",
            "pair_maps_base_to_ir");

        string programData = Environment.GetFolderPath(
            Environment.SpecialFolder.CommonApplicationData);
        string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        string? usersDirectory = Path.GetDirectoryName(userProfile);
        string allUsersLink = Path.Combine(usersDirectory ?? string.Empty, "All Users");
        Check(Directory.Exists(allUsersLink) && Directory.Exists(programData),
            "pair_directory_link_fixture_exists");
        if (Directory.Exists(allUsersLink) && Directory.Exists(programData))
        {
            string linkedInfrared = Path.Combine(allUsersLink, "gm-link-base_ir.tif");
            string targetVisible = Path.Combine(programData, "gm-link-base.tif");
            InfraredImportPairing.Resolution linked = InfraredImportPairing.Resolve(
                [targetVisible, linkedInfrared]);
            Check(
                InfraredImportPairing.ImportIdentity(linkedInfrared) ==
                    Path.Combine(programData, "gm-link-base_ir.tif") &&
                linked.BasePaths.SequenceEqual([targetVisible]) &&
                linked.PairedInfraredPaths.SequenceEqual([linkedInfrared]) &&
                linked.InfraredByBaseIdentity[
                    InfraredImportPairing.ImportIdentity(targetVisible)] == linkedInfrared,
                "pair_resolves_directory_link_to_physical_bucket");

            // **같은 파일의 다른 표기는 한 건입니다.** 등록 폴더를 훑어 나온 경로와 카탈로그에
            // 적힌 경로가 링크를 사이에 두고 다르게 적혀 있을 수 있는데, 그 둘을 두 후보로
            // 세면 IR 짝짓기가 "후보가 둘이라 못 고르겠다" 로 조용히 실패합니다. 중복 판정은
            // 경로 글자가 아니라 **푼 물리 경로**로 합니다.
            string duplicateVisibleThroughLink = Path.Combine(allUsersLink, "gm-link-base.tif");
            InfraredImportPairing.Resolution deduped = InfraredImportPairing.Resolve(
                [targetVisible, duplicateVisibleThroughLink, linkedInfrared]);
            Check(
                deduped.PairedInfraredPaths.SequenceEqual([linkedInfrared]) &&
                deduped.InfraredByBaseIdentity[
                    InfraredImportPairing.ImportIdentity(targetVisible)] == linkedInfrared,
                "pair_treats_two_spellings_of_one_file_as_one_candidate");
        }

        InfraredImportPairing.Resolution stray = InfraredImportPairing.Resolve(
            [@"C:\scans\a_ir.tif"]);
        Check(stray.BasePaths.Count == 1 && stray.PairedInfraredPaths.Count == 0,
            "unpaired_ir_stays_photo");

        bool Exists(string path) => !path.Contains("missing", StringComparison.Ordinal);
        int counter = 0;
        string NextId() => $"ir-imp-{++counter}";
        FrameImportPlan planned = FrameImport.Plan(
            [@"C:\scans\a.tif", @"C:\scans\a_ir.tif"],
            [],
            DevelopmentProcess.C41,
            Exists,
            NextId);
        Check(planned.Rows.Count == 1, "import_pairs_ir_not_second_frame");
        Check(
            planned.Rows[0].Payload[LibraryFrameReader.InfraredPathName]!.GetValue<string>() ==
            @"C:\scans\a_ir.tif",
            "import_writes_infrared_path");

        LibraryFrameSnapshot existingBase = color with
        {
            Id = "existing-ir-base",
            SourcePath = @"C:\scans\late.tif",
            InfraredPath = null,
        };
        FrameImportPlan lateInfrared = FrameImport.Plan(
            [@"C:\scans\late_ir.tif"],
            [existingBase],
            DevelopmentProcess.C41,
            Exists,
            NextId);
        Check(
            lateInfrared.Rows.Count == 0 && lateInfrared.Rejected.Count == 0 &&
            lateInfrared.InfraredAttachments.Single() == new FrameInfraredAttachment(
                existingBase.Id,
                @"C:\scans\late_ir.tif"),
            "import_plans_late_ir_for_existing_frame");
    }
}
