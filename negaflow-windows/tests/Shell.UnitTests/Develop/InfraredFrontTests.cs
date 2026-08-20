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
        Check(InfraredCleanPolicy.SelectionDebounceMilliseconds == 400, "ir_debounce_400");

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
            InfraredCleanPolicy.ShouldRearm(InfraredDefectApplyStatus.DetectionFailed) &&
            !InfraredCleanPolicy.ShouldRearm(InfraredDefectApplyStatus.NoDefects),
            "ir_rearm_only_transient");

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
    }
}
