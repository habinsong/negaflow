using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.CatalogStorageFixtures;

namespace Negaflow.Catalog.UnitTests;

internal static class DefectTestFixture
{
    internal static IReadOnlyList<DefectEditItem> DefectRecipeItems()
    {
        DefectEditItem brush = new(
            Guid.Parse("1394d226-caff-4448-8669-b4dd09cf9946"),
            DefectEditKind.Brush,
            Enabled: true,
            Strength: 0.8,
            new DefectEditLabel(DefectEditLabelKind.Brush, 1),
            new DefectEditSummary(DefectEditSummaryKind.Brush),
            new DefectSize(4_000, 3_000),
            [])
        {
            Strokes =
            [
                new DefectStroke(
                    [new DefectPoint(0.1, 0.2), new DefectPoint(0.2, 0.3)],
                    0.01),
            ],
        };

        DefectEditItem region = new(
            Guid.Parse("83566683-7599-439b-8ba3-599548916110"),
            DefectEditKind.Region,
            Enabled: true,
            Strength: 1.0,
            new DefectEditLabel(DefectEditLabelKind.Guided, 1),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, 1)],
                    0.9)),
            new DefectSize(4_000, 3_000),
            [
                new DefectPreviewComponent(
                    DefectClassification.Dust,
                    0.9,
                    [new DefectPoint(0.25, 0.75)]),
            ])
        {
            RegionMask = new DefectMask(
                false,
                Enumerable.Range(0, 16).Select(value => (byte)value).ToArray()),
            RegionRoi = new DefectRect(12, 34, 2, 2),
            RegionWidth = 2,
            RegionHeight = 2,
        };

        byte[] infraredMask = Enumerable.Repeat((byte)255, 16).ToArray();
        DefectEditItem infrared = new(
            Guid.Parse("33dedb29-b303-4551-b48a-081a2b454fe3"),
            DefectEditKind.Infrared,
            Enabled: true,
            Strength: 0.75,
            new DefectEditLabel(DefectEditLabelKind.Infrared, 1),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Pinhole, 1)],
                    0.95)),
            new DefectSize(4_000, 3_000),
            [])
        {
            Clusters =
            [
                new DefectCluster(
                    new DefectRect(50, 60, 2, 2),
                    new DefectMask(true, CompressZlib(infraredMask)),
                    2,
                    2,
                    new DefectMask(
                        false,
                        new byte[]
                        {
                            0x00, 0x00,
                            0x01, 0x00,
                            0x34, 0x12,
                            0xff, 0xff,
                        })),
            ],
        };

        DefectEditItem clone = new(
            Guid.Parse("392b167c-78ce-4d0f-a90f-b6fbb976ebfe"),
            DefectEditKind.Clone,
            Enabled: false,
            Strength: 0.5,
            new DefectEditLabel(DefectEditLabelKind.Clone, 24),
            new DefectEditSummary(DefectEditSummaryKind.Clone),
            new DefectSize(4_000, 3_000),
            [])
        {
            CloneStrokes =
            [
                new DefectCloneStroke(
                    [new DefectPoint(0.4, 0.5), new DefectPoint(0.45, 0.55)],
                    0.05,
                    -0.02,
                    24,
                    0.6),
            ],
        };

        return [brush, region, infrared, clone];
    }

    internal static byte[] CompressZlib(byte[] data)
    {
        using MemoryStream output = new();
        using (ZLibStream zlib = new(output, CompressionLevel.SmallestSize, leaveOpen: true))
        {
            zlib.Write(data);
        }
        return output.ToArray();
    }

}
