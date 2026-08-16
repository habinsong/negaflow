using System.Runtime.InteropServices;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class DevelopExportDefectContractTests
{
    internal static void Verify(ContractTestContext context)
    {
        string temporaryRoot = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-develop-export-{Guid.NewGuid():N}");
        string absentSource = Path.Combine(temporaryRoot, "absent.tif");
        string destination = Path.Combine(temporaryRoot, "out.png");

        DevelopExportResult defects = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            DefectRegions =
            [
                new DevelopDefectRegionEdit
                {
                    RoiX = 12,
                    RoiY = 20,
                    Width = 8,
                    Height = 8,
                    Mask = new byte[64],
                    Strength = 0.75,
                    PreferredAngleDegrees = 90.0,
                },
            ],
            DefectSourceIdentity = new DevelopDefectSourceIdentity(
                1,
                new string('0', 64)),
        });
        context.Check(
            defects.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_defect_region_reaches_source_observation");

        DevelopExportRequest infraredRequest = new()
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            DefectInfrared =
            [
                new DevelopDefectInfraredEdit
                {
                    Strength = 0.75,
                    Clusters =
                    [
                        new DevelopDefectInfraredCluster
                        {
                            RoiX = 12,
                            RoiY = 20,
                            Width = 8,
                            Height = 8,
                            CoreMask = new byte[64],
                            AttenuationR16 = new byte[128],
                        },
                    ],
                },
            ],
            DefectEditOrder =
            [
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Infrared, 0),
            ],
            DefectSourceIdentity = new DevelopDefectSourceIdentity(
                1,
                new string('0', 64)),
        };
        DevelopExportResult infrared = NativeDevelopExporter.Run(infraredRequest);
        context.Check(
            infrared.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_infrared_reaches_source_observation");
        Span<byte> infraredPreviewPixels = stackalloc byte[4];
        DevelopExportResult infraredPreview = NativeDevelopExporter.Preview(
            infraredRequest, 1, 1, infraredPreviewPixels);
        context.Check(
            infraredPreview.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_preview_infrared_reaches_source_observation");

        DevelopDefectInfraredCluster maximumCluster = new()
        {
            Width = 3,
            Height = 3,
            CoreMask = new byte[9],
        };
        DevelopDefectInfraredCluster[] maximumClusters = Enumerable.Repeat(
            maximumCluster,
            4_096).ToArray();
        DevelopDefectCloneEdit maximumClone = new() { IsEnabled = false };
        DevelopDefectCloneEdit[] maximumClones = Enumerable.Repeat(
            maximumClone,
            4_096).ToArray();
        DevelopDefectRecipeEditRef[] maximumOrder =
        [
            new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Infrared, 0),
            .. Enumerable.Range(0, 4_096).Select(index =>
                new DevelopDefectRecipeEditRef(
                    DevelopDefectEditKind.Clone,
                    checked((uint)index))),
        ];
        DevelopExportRequest maximumInfraredRequest = new()
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            DefectInfrared =
            [
                new DevelopDefectInfraredEdit { Clusters = maximumClusters },
            ],
            DefectClones = maximumClones,
            DefectEditOrder = maximumOrder,
            DefectSourceIdentity = new DevelopDefectSourceIdentity(
                1,
                new string('0', 64)),
        };
        context.Check(
            NativeDevelopExporter.Run(maximumInfraredRequest).FailedStage ==
                DevelopExportStage.ObserveSourceBefore,
            "develop_export_accepts_4096_flat_regions_and_8192_expanded_order");
        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectInfrared =
                [
                    new DevelopDefectInfraredEdit
                    {
                        Clusters = [.. maximumClusters, maximumCluster],
                    },
                ],
                DefectClones = [],
                DefectEditOrder =
                [
                    new DevelopDefectRecipeEditRef(
                        DevelopDefectEditKind.Infrared,
                        0),
                ],
                DefectSourceIdentity = new DevelopDefectSourceIdentity(
                    1,
                    new string('0', 64)),
            }),
            "develop_export_rejects_4097_flat_regions_before_marshalling");
        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectInfrared =
                [
                    new DevelopDefectInfraredEdit { Clusters = maximumClusters },
                ],
                DefectClones = maximumClones,
                DefectBrushes = [new DevelopDefectBrushEdit { IsEnabled = false }],
                DefectEditOrder =
                [
                    .. maximumOrder,
                    new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Brush, 0),
                ],
                DefectSourceIdentity = new DevelopDefectSourceIdentity(
                    1,
                    new string('0', 64)),
            }),
            "develop_export_rejects_8193_expanded_order_before_marshalling");

        DevelopExportResult clone = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            DefectClones =
            [
                new DevelopDefectCloneEdit
                {
                    Strength = 0.75,
                    Strokes =
                    [
                        new DevelopDefectCloneStroke
                        {
                            Points = [new DevelopDefectClonePoint(0.5, 0.5)],
                            OffsetX = 0.1,
                            DiameterPixels = 9.0,
                            Hardness = 0.8,
                        },
                    ],
                },
            ],
            DefectEditOrder =
            [
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Clone, 0),
            ],
            DefectSourceIdentity = new DevelopDefectSourceIdentity(
                1,
                new string('0', 64)),
        });
        context.Check(
            clone.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_clone_reaches_source_observation");

        DevelopExportResult brush = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            DefectBrushes =
            [
                new DevelopDefectBrushEdit
                {
                    Strength = 0.75,
                    Strokes =
                    [
                        new DevelopDefectBrushStroke
                        {
                            Points =
                            [
                                new DevelopDefectBrushPoint(0.4, 0.5),
                                new DevelopDefectBrushPoint(0.6, 0.5),
                            ],
                            Thickness = 0.02,
                        },
                    ],
                },
            ],
            DefectEditOrder =
            [
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Brush, 0),
            ],
            DefectSourceIdentity = new DevelopDefectSourceIdentity(
                1,
                new string('0', 64)),
        });
        context.Check(
            brush.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_brush_reaches_source_observation");

        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectClones = [new DevelopDefectCloneEdit()],
                DefectSourceIdentity = new DevelopDefectSourceIdentity(
                    1,
                    new string('0', 64)),
            }),
            "develop_export_clone_requires_order");

        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectBrushes =
                [
                    new DevelopDefectBrushEdit
                    {
                        Strokes =
                        [
                            new DevelopDefectBrushStroke
                            {
                                Points = [new DevelopDefectBrushPoint(2.0, 0.5)],
                                Thickness = 0.02,
                            },
                        ],
                    },
                ],
                DefectEditOrder =
                [
                    new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Brush, 0),
                ],
                DefectSourceIdentity = new DevelopDefectSourceIdentity(
                    1,
                    new string('0', 64)),
            }),
            "develop_export_invalid_brush_geometry_rejected");

        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectRegions =
                [
                    new DevelopDefectRegionEdit
                    {
                        Width = 8,
                        Height = 8,
                        Mask = new byte[64],
                    },
                ],
            }),
            "develop_export_defect_region_requires_source_identity");

        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectRegions =
                [
                    new DevelopDefectRegionEdit
                    {
                        Width = 8,
                        Height = 8,
                        Mask = new byte[63],
                    },
                ],
            }),
            "develop_export_short_defect_mask_rejected");

        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectInfrared =
                [
                    new DevelopDefectInfraredEdit
                    {
                        Clusters =
                        [
                            new DevelopDefectInfraredCluster
                            {
                                Width = 8,
                                Height = 8,
                                CoreMask = new byte[64],
                                AttenuationR16 = new byte[127],
                            },
                        ],
                    },
                ],
                DefectEditOrder =
                [
                    new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Infrared, 0),
                ],
                DefectSourceIdentity = new DevelopDefectSourceIdentity(
                    1,
                    new string('0', 64)),
            }),
            "develop_export_short_infrared_attenuation_rejected");

        context.CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                DefectInfrared =
                [
                    new DevelopDefectInfraredEdit
                    {
                        Clusters =
                        [
                            new DevelopDefectInfraredCluster
                            {
                                Width = 8,
                                Height = 8,
                                CoreMask = new byte[64],
                                AttenuationStrideBytes = 15,
                                AttenuationR16 = new byte[128],
                            },
                        ],
                    },
                ],
                DefectEditOrder =
                [
                    new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Infrared, 0),
                ],
                DefectSourceIdentity = new DevelopDefectSourceIdentity(
                    1,
                    new string('0', 64)),
            }),
            "develop_export_short_infrared_stride_rejected");
    }
}
