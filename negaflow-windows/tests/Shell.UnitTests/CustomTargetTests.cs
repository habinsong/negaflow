using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class CustomTargetTests
{
    internal static void Run()
    {
        Check(DevelopTargets.Families.Count == 6 && DevelopTargets.Families[^1] == DevelopTargetFamily.Custom,
            "custom_capsule_is_sixth");
        Check(DevelopTargets.Custom.Count == 18 && DevelopTargets.Custom.Distinct().Count() == 18,
            "custom_targets_are_eighteen_unique_values");
        Check(DevelopTargets.CustomGroups.Select(x => x.Count).SequenceEqual(new[] { 11, 4, 3 }), "custom_groups_match_mac");
        Check(DevelopTargets.CustomRows.All(x => x.Count is 1 or 2) &&
            DevelopTargets.CustomRows.SelectMany(x => x).SequenceEqual(DevelopTargets.Custom), "custom_two_column_order");
        Check(DevelopTargets.MoveCustomSelection(DevelopTarget.Dichroic, 0, 1) == DevelopTarget.Wetzlar &&
            DevelopTargets.MoveCustomSelection(DevelopTarget.Rochester, 0, 1) == DevelopTarget.Cinema &&
            DevelopTargets.MoveCustomSelection(DevelopTarget.Emulsion, -1, 0) == DevelopTarget.Emulsion,
            "custom_keyboard_moves_across_group_boundaries");
        Check(LibraryFolderDevelopment.VisibleTargets.Count == 23 &&
            LibraryFolderDevelopment.VisibleTargets.Skip(5).SequenceEqual(DevelopTargets.Custom), "custom_folder_targets");
        Check(DevelopTargets.TargetForFamily(DevelopTargetFamily.Custom, DevelopTarget.Main) == DevelopTarget.Emulsion,
            "custom_entry_starts_at_emulsion");
        for (int index = 0; index < DevelopTargets.Custom.Count; ++index)
        {
            DevelopTarget target = DevelopTargets.Custom[index];
            Check((int)target == index + 7 && Enum.IsDefined((DevelopTargetMode)(int)target), "custom_native_vocabulary_" + target);
            Check(DevelopTargets.CapsuleFamily(target) == DevelopTargetFamily.Custom &&
                DevelopTargets.TargetForFamily(DevelopTargetFamily.Custom, target) == target, "custom_capsule_keeps_selection_" + target);
            Check(DevelopTargets.MatchingProfiles(target, FilmType.ColorNegative).Count == 0 &&
                DevelopTargets.ProfileAfterTargetChange(target, FilmType.ColorNegative, "noritsu__color-nega__kodak-portra-400") is null,
                "custom_drops_scanner_profile_" + target);
            foreach (FilmType film in Enum.GetValues<FilmType>())
            {
                var signal = film is FilmType.ColorPositive or FilmType.BlackAndWhitePositive
                    ? SourceSignalKind.FilmPositiveScan : SourceSignalKind.FilmNegativeScan;
                var frame = Frame(null, signal: signal, filmType: film, sourcePath: Path.Combine(Path.GetTempPath(), "custom-source.tif"))
                    with { DevelopTarget = target, Base = BaseRecipe.Auto with { ScannerProfileId = "stale-profile" } };
                var request = DevelopRequestFactory.Create(frame, Path.Combine(Path.GetTempPath(), "custom-output.tif"), DevelopExportFormat.Tiff16);
                Check(request.Request?.DevelopTarget == (DevelopTargetMode)(int)target, "custom_request_" + film + "_" + target);
                Check(request.Request is { ScannerProfileId: null }, "custom_request_ignores_stale_profile_" + film + "_" + target);
            }
            var digital = Frame(null, signal: SourceSignalKind.RenderedDigital, filmType: FilmType.ColorPositive,
                sourcePath: Path.Combine(Path.GetTempPath(), "custom-digital.tif")) with { DevelopTarget = target };
            var destination = Path.Combine(Path.GetTempPath(), "custom-output.tif");
            Check(DevelopRequestFactory.Create(digital, destination).Request?.DevelopTarget == (DevelopTargetMode)(int)target,
                "custom_rendered_digital_request_" + target);
            Check(DevelopRequestFactory.Create(digital, destination, uninvertedSource: true).Request?.DevelopTarget == DevelopTargetMode.Main,
                "custom_original_view_bypasses_grade_" + target);
        }
        Check(!Enum.IsDefined((DevelopTargetMode)25) && !DevelopTargets.IsCustom((DevelopTarget)25), "custom_upper_bound");
    }
}
