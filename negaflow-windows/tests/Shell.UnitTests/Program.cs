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

internal static class Program
{
    private static int Main(string[] args)
    {
        if (ShellDiagnostics.TryRun(args, out int diagnosticExitCode))
        {
            return diagnosticExitCode;
        }
        ResourceFileTests.Run();
        ShellPreferencesTests.Run();
        LibraryBrowsingTests.Run();
        ExportConfigurationTests.Run();
        CropAndLookTests.Run();
        GrainMendRecipeTests.Run();
        CloneStampOverlayTests.Run();
        DevelopRequestFactoryTests.Run();
        DevelopedPreviewDiskCacheTests.Run();
        ScannerPluginTests.Run();
        InfraredRecipeTests.Run();
        DevelopCoordinatorTests.Run();
        LibraryDocumentTests.Run();
        SourceMoveTests.Run();
        DevelopTargetTests.Run();
        LibraryCullingTests.Run();
        PrintCompositionTests.Run();
        PrintPreviewResolutionTests.Run();
        FrameResidencyTests.Run();
        PreviewOrderingTests.Run();
        DevelopMetadataTests.Run();
        DevelopMenuStateTests.Run();
        ScannerMenuStateTests.Run();
        LibraryFolderDevelopmentTests.Run();
        ExportPanelProjectionTests.Run();
        FilmLookMenuProjectionTests.Run();
        GrainMendCardProjectionTests.Run();
        DefectLayerSectionTests.Run();
        InfraredCleanStatusTests.Run();
        VersionListProjectionTests.Run();
        PasteScopeSummaryTests.Run();
        ScanRotationDefaultTests.Run();
        PixelSamplerTests.Run();
        AppLanguageTests.Run();
        WorkflowShortcutTests.Run();
        EditPersistenceTests.Run();
        LibraryHostTests.Run();
        DevelopPresentationTests.Run();
        DevelopPanelTests.Run();
        FrameImportTests.Run();
        PreviewAndAutoAdjustmentTests.Run();
        ExportBatchTests.Run();
        LibraryOrganizationTests.Run();
        ScannerWorkflowTests.Run();
        PrintOutputTests.Run();
        FilmBaseSidecarTests.Run();
        ScanSessionTests.Run();
        LocalAdjustmentTests.Run();
        PrintLayoutTemplateTests.Run();

        var report = new
        {
            status = Failures.Count == 0 ? "ok" : "failed",
            operation = "shell_unit_tests",
            assertions = AssertionCount,
            failures = Failures,
        };
        Console.WriteLine(JsonSerializer.Serialize(report));
        return Failures.Count == 0 ? 0 : 1;
    }

}
