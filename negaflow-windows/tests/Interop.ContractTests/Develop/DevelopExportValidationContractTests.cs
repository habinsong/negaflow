using System.Runtime.InteropServices;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class DevelopExportValidationContractTests
{
    internal static void Verify(ContractTestContext context)
    {
        string temporaryRoot = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-develop-export-{Guid.NewGuid():N}");
        string absentSource = Path.Combine(temporaryRoot, "absent.tif");
        string destination = Path.Combine(temporaryRoot, "out.png");

        DevelopExportResult colorModel = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            Warmth = 0.25F,
            Tint = -0.2F,
            ColorDepth = 0.3F,
            Vibrance = 0.4F,
            Saturation = -0.1F,
            RedPrimary = 0.1F,
            GreenPrimary = -0.1F,
            BluePrimary = 0.2F,
        });
        context.Check(
            colorModel.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_color_model_reaches_source_observation");

        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                LocalDodgeBurn =
                [
                    new DevelopLocalDodgeBurnAdjustment
                    {
                        Amount = 0.5,
                        Mask = new DevelopLocalDodgeBurnMask
                        {
                            Kind = DevelopLocalDodgeBurnMaskKind.Polygon,
                            Points = [new DevelopLocalDodgeBurnPoint(double.NaN, 0.5)],
                        },
                    },
                ],
            }),
            "develop_export_invalid_local_mask_rejected");

        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                FilmEmulation = (FilmEmulationProfile)99,
            }),
            "develop_export_undefined_enum_rejected");

        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                BaseEstimationMode = (DevelopBaseEstimationMode)99,
            }),
            "develop_export_undefined_base_mode_rejected");

        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                FilmPolarity = (FilmPolarity)99,
            }),
            "develop_export_undefined_film_polarity_rejected");

        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                PointCurves = new DevelopPointCurves
                {
                    Rgb =
                    [
                        new DevelopPointCurvePoint(0.5, 0.5),
                        new DevelopPointCurvePoint(0.5, 0.6),
                    ],
                },
            }),
            "develop_export_duplicate_point_curve_rejected");

        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                ColorMixer = new DevelopColorMixer
                {
                    Hue = [0.0f, 0.0f],
                },
            }),
            "develop_export_short_color_mixer_rejected");

        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                ColorGrading = new DevelopColorGrading
                {
                    Midtones = new DevelopColorGradeRegion(361.0f, 0.0f, 0.0f),
                },
            }),
            "develop_export_invalid_color_grading_rejected");

        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectRemovalStrength = double.NaN,
            }),
            "develop_export_invalid_grain_mend_strength_rejected");

        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                NoiseReductionDetail = float.NaN,
            }),
            "develop_export_invalid_noise_reduction_control_rejected");

        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                Vignette = 1.01F,
            }),
            "develop_export_invalid_texture_control_rejected");

        context.CheckThrows<ArgumentNullException>(
            () => NativeDevelopExporter.Run(null!),
            "develop_export_null_request_rejected");
    }
}
