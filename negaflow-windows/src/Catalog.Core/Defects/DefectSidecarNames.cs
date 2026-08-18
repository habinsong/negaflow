using System.Text.Json;
using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

internal static class DefectSidecarNames
{
    public static string EditKind(DefectEditKind value) => value switch
    {
        DefectEditKind.Brush => "brush",
        DefectEditKind.Region => "region",
        DefectEditKind.Infrared => "infrared",
        DefectEditKind.Clone => "clone",
        _ => throw new ArgumentOutOfRangeException(nameof(value)),
    };

    public static bool TryEditKind(string? value, out DefectEditKind result)
    {
        result = value switch
        {
            "brush" => DefectEditKind.Brush,
            "region" => DefectEditKind.Region,
            "infrared" => DefectEditKind.Infrared,
            "clone" => DefectEditKind.Clone,
            _ => default,
        };
        return value is "brush" or "region" or "infrared" or "clone";
    }

    public static string Classification(DefectClassification value) => value switch
    {
        DefectClassification.Dust => "dust",
        DefectClassification.Pinhole => "pinhole",
        DefectClassification.ScratchHorizontal => "scratchHorizontal",
        DefectClassification.ScratchVertical => "scratchVertical",
        DefectClassification.ScratchDiagonal => "scratchDiagonal",
        DefectClassification.EmulsionDamage => "emulsionDamage",
        DefectClassification.MicroSpeck => "microSpeck",
        _ => throw new ArgumentOutOfRangeException(nameof(value)),
    };

    public static bool TryClassification(
        string? value,
        out DefectClassification result)
    {
        result = value switch
        {
            "dust" => DefectClassification.Dust,
            "pinhole" => DefectClassification.Pinhole,
            "scratchHorizontal" => DefectClassification.ScratchHorizontal,
            "scratchVertical" => DefectClassification.ScratchVertical,
            "scratchDiagonal" => DefectClassification.ScratchDiagonal,
            "emulsionDamage" => DefectClassification.EmulsionDamage,
            "microSpeck" => DefectClassification.MicroSpeck,
            _ => default,
        };
        return value is "dust" or "pinhole" or "scratchHorizontal" or
            "scratchVertical" or "scratchDiagonal" or "emulsionDamage" or
            "microSpeck";
    }

    public static string LabelKind(DefectEditLabelKind value) => value switch
    {
        DefectEditLabelKind.Automatic => "automatic",
        DefectEditLabelKind.Guided => "guided",
        DefectEditLabelKind.Brush => "brush",
        DefectEditLabelKind.Clone => "clone",
        DefectEditLabelKind.Infrared => "infrared",
        _ => throw new ArgumentOutOfRangeException(nameof(value)),
    };

    public static bool TryLabelKind(string? value, out DefectEditLabelKind result)
    {
        result = value switch
        {
            "automatic" => DefectEditLabelKind.Automatic,
            "guided" => DefectEditLabelKind.Guided,
            "brush" => DefectEditLabelKind.Brush,
            "clone" => DefectEditLabelKind.Clone,
            "infrared" => DefectEditLabelKind.Infrared,
            _ => default,
        };
        return value is "automatic" or "guided" or "brush" or "clone" or
            "infrared";
    }

    public static string SummaryKind(DefectEditSummaryKind value) => value switch
    {
        DefectEditSummaryKind.ClassBreakdown => "classBreakdown",
        DefectEditSummaryKind.Brush => "brush",
        DefectEditSummaryKind.Clone => "clone",
        _ => throw new ArgumentOutOfRangeException(nameof(value)),
    };

    public static bool TrySummaryKind(string? value, out DefectEditSummaryKind result)
    {
        result = value switch
        {
            "classBreakdown" => DefectEditSummaryKind.ClassBreakdown,
            "brush" => DefectEditSummaryKind.Brush,
            "clone" => DefectEditSummaryKind.Clone,
            _ => default,
        };
        return value is "classBreakdown" or "brush" or "clone";
    }
}
