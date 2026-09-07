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
        if (args is ["--preview-thumbnail-only"])
        {
            DevelopRouteRestoreTests.Run();
            ThumbnailLifecycleTests.Run();
            ThumbnailCacheRegressionTests.Run();
            PreviewRouteDeliveryTests.Run();
            PreviewOrderingTests.Run();
            return Report("preview_thumbnail_tests");
        }
        if (args is ["--input-workflow-only"])
        {
            InputWorkflowRegressionTests.Run();
            InputWorkflowRouteTests.Run();
            ExportArtifactSafetyTests.Run();
            PrintOutputTests.Run();
            ExportUniqueDestinationTests.Run();
            ExportBatchTests.Run();
            PrintOutputProfileTests.Run();
            PrintCompositionTests.Run();
            PrintCustomPackageTests.Run();
            PrintPreviewResolutionTests.Run();
            ScanProgressTests.Run();
            ScannerMenuStateTests.Run();
            ScanRotationDefaultTests.Run();
            return Report("input_workflow_tests");
        }
        if (args is ["--auto-input-only"])
        {
            AutoAdjustInputTests.Run();
            return Report("auto_input_tests");
        }
        if (args is ["--input-gamma-only"])
        {
            SliderPointerSessionTests.Run();
            InputGammaWorkflowTests.Run();
            PasteScopeSummaryTests.Run();
            return Report("shell_input_gamma_tests");
        }
        if (args is ["--defect-source-identity-only"])
        {
            DefectSourceIdentityTests.Run();
            return Report("shell_defect_source_identity_tests");
        }
        if (ShellDiagnostics.TryRun(args, out int diagnosticExitCode))
        {
            return diagnosticExitCode;
        }
        DevelopRouteRestoreTests.Run();
        ThumbnailLifecycleTests.Run();
        ThumbnailCacheRegressionTests.Run();
        PreviewRouteDeliveryTests.Run();
        InputWorkflowRegressionTests.Run();
        InputWorkflowRouteTests.Run();
        ExportArtifactSafetyTests.Run();
        InputGammaWorkflowTests.Run();
        SliderPointerSessionTests.Run();
        AutoAdjustInputTests.Run();
        ResourceFileTests.Run();
        LocalizedTextTests.Run();
        ThemeDictionaryTests.Run();
        ShellPreferencesTests.Run();
        LibraryBrowsingTests.Run();
        ScanProgressTests.Run();
        ExportConfigurationTests.Run();
        PrintCustomPackageTests.Run();
        CropAndLookTests.Run();
        CropOverlayZoomTests.Run();
        GrainMendRecipeTests.Run();
        CloneStampOverlayTests.Run();
        DevelopRequestFactoryTests.Run();
        // 시험 기록을 사용자의 진단 파일과 섞지 않습니다.
        Negaflow.Shell.ScannerDiagnosticsLog.RedirectedLogDirectory =
            Path.Combine(Path.GetTempPath(), "negaflow-test-logs");
        ScannerPluginTests.Run();
        TestAssert.RunIfNativeIsPresent(InfraredRecipeTests.Run, nameof(InfraredRecipeTests));
        TestAssert.RunIfNativeIsPresent(InfraredSessionLifecycleTests.Run, nameof(InfraredSessionLifecycleTests));
        InfraredSelectionTriggerTests.Run();
        InfraredLateImportTests.Run();
        InfraredCleanCoordinatorTests.Run();
        TestAssert.RunIfNativeIsPresent(ScannerInfraredPublicationTests.Run, nameof(ScannerInfraredPublicationTests));
        DevelopCoordinatorTests.Run();
        LibraryDocumentTests.Run();
        SourceMoveTests.Run();
        SourceRelinkDefectTests.Run();
        VirtualCopyDefectReviewTests.Run();
        DefectTerminationTests.Run();
        RemovedDefectSidecarTests.Run();
        Negaflow.Shell.UnitTests.Defects.ColdExportDefectCoverageTests.Run();
        Negaflow.Shell.UnitTests.Develop.CropAspectExactnessTests.Run();
        GrainMendDetectionSessionTests.Run();
        GrainMendPreviewBuildStateTests.Run();
        GrainMendOverlayMappingTests.Run();
        GrainMendGuidedGestureTests.Run();
        DevelopTargetTests.Run();
        LibraryCullingTests.Run();
        PrintCompositionTests.Run();
        PrintPreviewResolutionTests.Run();
        FrameResidencyTests.Run();
        GpuCacheSettingsTests.Run();
        FrameCacheEngineLimitsTests.Run();
        DevelopRequestStaleDefectSourceTests.Run();
        ScannerFlatbedBatchTests.Run();
        ExportUniqueDestinationTests.Run();
        LibrarySortTests.Run();
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
        DevelopPresetNamingTests.Run();
        ScanRotationDefaultTests.Run();
        PixelSamplerTests.Run();
        AppLanguageTests.Run();
        WorkflowShortcutTests.Run();
        EditPersistenceTests.Run();
        LibraryHostTests.Run();
        LibraryBackupScheduleTests.Run();
        LibraryRecoveryTests.Run();
        LibraryUnreadableFrameTests.Run();
        LibraryCatalogRepairNeedTests.Run();
        FrameMarkSyncTests.Run();
        ExportConcurrencyTests.Run();
        PrintOutputProfileTests.Run();
        DevelopPresentationTests.Run();
        DevelopInspectorHeaderTests.Run();
        StaleDefectSourceExportTests.Run();
        FilmstripMultiSelectionTests.Run();
        PrintExportOutputCountTests.Run();
        DevelopPanelTests.Run();
        FrameImportTests.Run();
        SourceDeletionPlanTests.Run();
        GrainMendPaintOverlayTests.Run();
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
