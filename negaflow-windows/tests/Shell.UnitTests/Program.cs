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
        if (args is ["--defect-source-identity-only"])
        {
            DefectSourceIdentityTests.Run();
            return Report("shell_defect_source_identity_tests");
        }
        if (ShellDiagnostics.TryRun(args, out int diagnosticExitCode))
        {
            return diagnosticExitCode;
        }
        ResourceFileTests.Run();
        LocalizedTextTests.Run();
        ShellPreferencesTests.Run();
        LibraryBrowsingTests.Run();
        ExportConfigurationTests.Run();
        PrintCustomPackageTests.Run();
        CropAndLookTests.Run();
        CropOverlayZoomTests.Run();
        GrainMendRecipeTests.Run();
        CloneStampOverlayTests.Run();
        DevelopRequestFactoryTests.Run();
        DevelopedPreviewDiskCacheTests.Run();
        ScannerPluginTests.Run();
        InfraredRecipeTests.Run();
        InfraredSessionLifecycleTests.Run();
        InfraredSelectionTriggerTests.Run();
        InfraredLateImportTests.Run();
        InfraredCleanCoordinatorTests.Run();
        ScannerInfraredPublicationTests.Run();
        DevelopCoordinatorTests.Run();
        LibraryDocumentTests.Run();
        SourceMoveTests.Run();
        SourceRelinkDefectTests.Run();
        VirtualCopyDefectReviewTests.Run();
        DefectTerminationTests.Run();
        RemovedDefectSidecarTests.Run();
        GrainMendDetectionSessionTests.Run();
        GrainMendPreviewBuildStateTests.Run();
        GrainMendOverlayMappingTests.Run();
        GrainMendGuidedGestureTests.Run();
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
        DefectLayerFrameInteractionTests.Run();
        DefectUndoFrameOwnershipTests.Run();
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
        ScannerCapabilityMatrixTests.Run();
        FilmFrameFormatTests.Run();
        LocalAdjustmentTests.Run();
        PrintLayoutTemplateTests.Run();

        return Report("shell_unit_tests");
    }

    private static int Report(string operation)
    {
        var report = new
        {
            status = Failures.Count == 0 ? "ok" : "failed",
            operation,
            assertions = AssertionCount,
            failures = Failures,
        };
        Console.WriteLine(JsonSerializer.Serialize(report));
        return Failures.Count == 0 ? 0 : 1;
    }

}
