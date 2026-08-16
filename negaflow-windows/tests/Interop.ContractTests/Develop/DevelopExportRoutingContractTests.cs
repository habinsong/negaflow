using System.Runtime.InteropServices;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class DevelopExportRoutingContractTests
{
    internal static void Verify(ContractTestContext context)
    {
        string temporaryRoot = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-develop-export-{Guid.NewGuid():N}");
        string absentSource = Path.Combine(temporaryRoot, "absent.tif");
        string destination = Path.Combine(temporaryRoot, "out.png");

        // A missing source must be reported as an observation failure, not as a
        // malformed request, so the shell can tell a user error from a bug.
        DevelopExportResult missing = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
        });
        context.Check(!missing.Succeeded, "develop_export_missing_source_fails");
        context.Check(
            missing.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_missing_source_stage");
        context.Check(missing.FailureName.Length > 0, "develop_export_failure_name_present");
        context.Check(missing.FailureName != "ok", "develop_export_failure_name_not_ok");
        context.Check(!File.Exists(destination), "develop_export_failure_writes_nothing");

        DevelopExportResult autoMissing = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            BaseEstimationMode = DevelopBaseEstimationMode.Auto,
        });
        context.Check(
            autoMissing.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_auto_reaches_source_observation");

        DevelopExportResult digital = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            FilmLookSourceKind = DevelopSourceKind.RenderedDigital,
            FilmEmulation = FilmEmulationProfile.Vision3_500T,
        });
        context.Check(!digital.Succeeded, "develop_export_digital_source_fails");
        context.Check(
            digital.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_vision3_digital_source_stage");
        context.Check(
            digital.FailureName != "ok",
            "develop_export_digital_source_name");

        DevelopExportResult outputSharpening = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            OutputSharpening = 0.80F,
            OutputSharpeningMedium = OutputSharpeningMedium.MattePaper,
            OutputSharpeningDpi = 300,
        });
        context.Check(
            outputSharpening.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_output_sharpening_reaches_source_observation");

        DevelopExportResult local = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            LocalDodgeBurn =
            [
                new DevelopLocalDodgeBurnAdjustment
                {
                    Mode = DevelopLocalDodgeBurnMode.Dodge,
                    Amount = 0.6,
                    Mask = new DevelopLocalDodgeBurnMask
                    {
                        Kind = DevelopLocalDodgeBurnMaskKind.Brush,
                        Strokes =
                        [
                            new DevelopLocalDodgeBurnStroke
                            {
                                Points =
                                [
                                    new DevelopLocalDodgeBurnPoint(0.4, 0.5),
                                    new DevelopLocalDodgeBurnPoint(0.6, 0.5),
                                ],
                            },
                        ],
                    },
                },
            ],
        });
        context.Check(
            local.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_local_mask_reaches_source_observation");
    }
}
