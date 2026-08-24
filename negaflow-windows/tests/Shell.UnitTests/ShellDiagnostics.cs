using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class ShellDiagnostics
{
    public static bool TryRun(string[] args, out int exitCode)
    {
        return CatalogSeedDiagnostics.TryRun(args, out exitCode) ||
            CatalogInspectionDiagnostics.TryRun(args, out exitCode) ||
            DevelopPipelineDiagnostics.TryRun(args, out exitCode) ||
            FirstActionLatencyDiagnostics.TryRun(args, out exitCode) ||
            LiveScannerEndToEndDiagnostics.TryRun(args, out exitCode) ||
            SliderDragDiagnostics.TryRun(args, out exitCode) ||
            DefectRoundTripDiagnostics.TryRun(args, out exitCode) ||
            DefectToolDiagnostics.TryRun(args, out exitCode) ||
            GrainMendDetectionOverlayDiagnostics.TryRun(args, out exitCode) ||
            GrainMendInfraredStatusDiagnostics.TryRun(args, out exitCode) ||
            GrainMendInfraredFolderDiagnostics.TryRun(args, out exitCode) ||
            GrainMendDevicePerformanceDiagnostics.TryRun(args, out exitCode) ||
            CloneCursorBenchmark.TryRun(args, out exitCode);
    }

}
