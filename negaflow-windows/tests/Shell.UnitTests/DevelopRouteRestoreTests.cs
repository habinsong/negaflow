using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class DevelopRouteRestoreTests
{
    internal static void Run()
    {
        foreach (var savedProcess in Enum.GetValues<DevelopmentProcess>())
        foreach (var activeProcess in Enum.GetValues<DevelopmentProcess>())
        foreach (bool legacy in new[] { false, true })
        {
            var record = FrameRecord("frame", "source.tif", 0);
            record["rawScanPath"] = Path.Combine(Path.GetTempPath(), "route-restore.tif");
            var saved = DevelopRouteWriter.Apply(record, DevelopRouteSelection.FromProcess(savedProcess)).FrameRecord!;
            saved["params"]!["developTarget"] = "hr";
            var versioned = LibraryVersions.Capture(saved, "saved", "saved", DateTimeOffset.UnixEpoch).FrameRecord!;
            if (legacy)
            {
                var entry = versioned["developSnapshots"]![0]!.AsObject();
                entry.Remove("filmType"); entry.Remove("sourceSignalKind");
            }
            var active = DevelopRouteWriter.Apply(versioned, DevelopRouteSelection.FromProcess(activeProcess)).FrameRecord!;
            active["params"]!["developTarget"] = "main";
            var restored = LibraryVersions.Restore(active, "saved").FrameRecord!;
            var read = LibraryFrameReader.Read(JsonSerializer.SerializeToElement(restored)).Frame;
            Check(read?.Route.DevelopmentProcess == savedProcess && read.DevelopTarget == DevelopTarget.Hr,
                $"restore_process_and_target_{savedProcess}_from_{activeProcess}");
            Check(restored["rawScanPath"]!.GetValue<string>() == record["rawScanPath"]!.GetValue<string>(),
                "restore_preserves_source_path");
        }
        var digital = Frame(null, SourceSignalKind.RenderedDigital, FilmType.ColorPositive);
        var flat = ExportFlatMaster.Neutralize(digital);
        Check(flat.Route.FilmEmulation == FilmEmulation.None && flat.Route.FilmEmulationIntensity == 0,
            "flat_master_does_not_keep_digital_film_look");
    }
}
