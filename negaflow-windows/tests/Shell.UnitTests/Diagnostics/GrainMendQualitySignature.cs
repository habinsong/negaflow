using System.Security.Cryptography;
using System.Text;
using Negaflow.Catalog;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 실행마다 달라지는 edit ID를 빼고 검출·수리 내용을 해시합니다. 같은 입력의 반복 실행에서
/// 이 값이 달라지면 성능 수치보다 먼저 품질 불일치로 판정합니다.
/// </summary>
internal static class GrainMendQualitySignature
{
    public static string FromRecipe(DefectRecipeSnapshot recipe)
    {
        string joined = string.Join('\n', recipe.Items.Select(FromEdit));
        return Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(joined)));
    }

    public static string FromEdit(DefectEditItem item)
    {
        using MemoryStream stream = new();
        using BinaryWriter writer = new(stream, Encoding.UTF8, leaveOpen: true);
        writer.Write((int)item.Kind);
        writer.Write(item.Enabled);
        writer.Write(BitConverter.DoubleToInt64Bits(item.Strength));
        writer.Write((int)item.Label.Kind);
        writer.Write(item.Label.Value);
        writer.Write((int)item.Summary.Kind);
        WriteBreakdown(writer, item.Summary.ClassBreakdown);
        WriteSize(writer, item.BaseSize);
        WritePreview(writer, item.Preview);
        WriteStrokes(writer, item.Strokes);
        WriteCloneStrokes(writer, item.CloneStrokes);
        WriteRegion(writer, item);
        WriteClusters(writer, item.Clusters);
        writer.Flush();
        return Convert.ToHexStringLower(SHA256.HashData(stream.GetBuffer().AsSpan(0, (int)stream.Length)));
    }

    public static string FromPixels(byte[] pixels) =>
        Convert.ToHexStringLower(SHA256.HashData(pixels));

    private static void WriteBreakdown(BinaryWriter writer, DefectClassBreakdown? breakdown)
    {
        writer.Write(breakdown is not null);
        if (breakdown is null)
        {
            return;
        }
        writer.Write(BitConverter.DoubleToInt64Bits(breakdown.MeanConfidence));
        writer.Write(breakdown.Counts.Count);
        foreach (DefectClassCount count in breakdown.Counts)
        {
            writer.Write((int)count.Classification);
            writer.Write(count.Count);
        }
    }

    private static void WriteSize(BinaryWriter writer, DefectSize? size)
    {
        writer.Write(size.HasValue);
        if (size is { } value)
        {
            WriteDouble(writer, value.Width);
            WriteDouble(writer, value.Height);
        }
    }

    private static void WritePreview(
        BinaryWriter writer,
        IReadOnlyList<DefectPreviewComponent> components)
    {
        writer.Write(components.Count);
        foreach (DefectPreviewComponent component in components)
        {
            writer.Write((int)component.Classification);
            WriteDouble(writer, component.Confidence);
            writer.Write(component.Points.Count);
            foreach (DefectPoint point in component.Points)
            {
                WritePoint(writer, point);
            }
        }
    }

    private static void WriteStrokes(
        BinaryWriter writer,
        IReadOnlyList<DefectStroke>? strokes)
    {
        writer.Write(strokes?.Count ?? -1);
        foreach (DefectStroke stroke in strokes ?? [])
        {
            WriteDouble(writer, stroke.Thickness);
            writer.Write(stroke.Points.Count);
            foreach (DefectPoint point in stroke.Points)
            {
                WritePoint(writer, point);
            }
        }
    }

    private static void WriteCloneStrokes(
        BinaryWriter writer,
        IReadOnlyList<DefectCloneStroke>? strokes)
    {
        writer.Write(strokes?.Count ?? -1);
        foreach (DefectCloneStroke stroke in strokes ?? [])
        {
            WriteDouble(writer, stroke.OffsetX);
            WriteDouble(writer, stroke.OffsetY);
            WriteDouble(writer, stroke.Diameter);
            WriteDouble(writer, stroke.Hardness);
            writer.Write(stroke.Points.Count);
            foreach (DefectPoint point in stroke.Points)
            {
                WritePoint(writer, point);
            }
        }
    }

    private static void WriteRegion(BinaryWriter writer, DefectEditItem item)
    {
        writer.Write(item.RegionRoi.HasValue);
        if (item.RegionRoi is { } roi)
        {
            WriteRect(writer, roi);
        }
        writer.Write(item.RegionWidth ?? -1);
        writer.Write(item.RegionHeight ?? -1);
        WriteMask(writer, item.RegionMask);
    }

    private static void WriteClusters(
        BinaryWriter writer,
        IReadOnlyList<DefectCluster>? clusters)
    {
        writer.Write(clusters?.Count ?? -1);
        foreach (DefectCluster cluster in clusters ?? [])
        {
            WriteRect(writer, cluster.Roi);
            writer.Write(cluster.Width);
            writer.Write(cluster.Height);
            WriteMask(writer, cluster.Mask);
            WriteMask(writer, cluster.AttenuationR16);
        }
    }

    private static void WriteMask(BinaryWriter writer, DefectMask? mask)
    {
        writer.Write(mask is not null);
        if (mask is null)
        {
            return;
        }
        writer.Write(mask.IsZlib);
        writer.Write(mask.Data.Length);
        writer.Write(mask.Data);
    }

    private static void WriteRect(BinaryWriter writer, DefectRect value)
    {
        WriteDouble(writer, value.X);
        WriteDouble(writer, value.Y);
        WriteDouble(writer, value.Width);
        WriteDouble(writer, value.Height);
    }

    private static void WritePoint(BinaryWriter writer, DefectPoint value)
    {
        WriteDouble(writer, value.X);
        WriteDouble(writer, value.Y);
    }

    private static void WriteDouble(BinaryWriter writer, double value) =>
        writer.Write(BitConverter.DoubleToInt64Bits(value == 0.0 ? 0.0 : value));
}
