using System.Globalization;
using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// GrainMend 레이어 목록이 쓰는 문구입니다. 어느 말로 낼지는 화면이 정하고, 무엇을 낼지는
/// 투영이 정합니다 — macOS 는 표시 시점에 현재 언어로 짓고, 저장된 문자열을 쓰지 않습니다.
/// </summary>
/// <remarks>
/// 형식 문자열은 macOS <c>AppLocalizedPhrase</c> 표의 표기를 그대로 옮겼습니다:
/// <c>%d</c> 는 개수, <c>%@</c> 는 분류 나열, <c>%.0f</c> 는 백분율, <c>%%</c> 는 백분율 기호.
/// </remarks>
public sealed record DefectLayerText(
    string SectionTitle,
    string AutomaticTitleFormat,
    string GuidedTitleFormat,
    string BrushTitleFormat,
    string CloneTitleFormat,
    string InfraredTitleFormat,
    string BrushSummary,
    string CloneSummary,
    string ConfidenceFormat,
    IReadOnlyDictionary<DefectClassification, string> ClassNames,
    string Strength,
    string EnableLayer,
    string DisableLayer,
    string ShowMask,
    string HideMask,
    string DeleteLayer,
    string Done)
{
    /// <summary>
    /// macOS <c>DefectEditLabel.title(language:)</c> 와 같습니다. 값 하나를 <c>%d</c> 에 넣습니다.
    /// </summary>
    public string Title(DefectEditLabel label)
    {
        string format = label.Kind switch
        {
            DefectEditLabelKind.Automatic => AutomaticTitleFormat,
            DefectEditLabelKind.Guided => GuidedTitleFormat,
            DefectEditLabelKind.Brush => BrushTitleFormat,
            DefectEditLabelKind.Clone => CloneTitleFormat,
            DefectEditLabelKind.Infrared => InfraredTitleFormat,
            _ => AutomaticTitleFormat,
        };
        return Replace(format, "%d", label.Value.ToString(CultureInfo.CurrentCulture));
    }

    /// <summary>macOS <c>DefectEditSummary.text(language:)</c> 와 같습니다.</summary>
    public string Summary(DefectEditSummary summary)
    {
        ArgumentNullException.ThrowIfNull(summary);
        return summary.Kind switch
        {
            DefectEditSummaryKind.Brush => BrushSummary,
            DefectEditSummaryKind.Clone => CloneSummary,
            _ => summary.ClassBreakdown is { } breakdown
                ? Confidence(breakdown)
                : string.Empty,
        };
    }

    /// <summary>
    /// "먼지 7 · 가로 스크래치 2 · 신뢰도 82%". 순서는 저장된 순서를 그대로 씁니다 — macOS 도
    /// 만들 때 <c>DefectClass.allCases</c> 순으로 정렬해 두고 표시할 때는 다시 정렬하지 않습니다.
    /// </summary>
    private string Confidence(DefectClassBreakdown breakdown)
    {
        string classes = string.Join(
            " · ",
            breakdown.Counts.Select(count =>
                $"{Name(count.Classification)} {count.Count.ToString(CultureInfo.CurrentCulture)}"));
        // %.0f 는 소수점 없는 반올림입니다. C 의 printf 와 .NET 의 기본이 모두 짝수 쪽으로
        // 맞추므로 macOS 와 같은 값이 나옵니다.
        string percent = Math
            .Round(breakdown.MeanConfidence * 100.0, MidpointRounding.ToEven)
            .ToString("F0", CultureInfo.CurrentCulture);
        // 분류 이름을 마지막에 넣습니다 — 이름 안에 형식 표기가 들어 있어도 다시 해석되지
        // 않게 합니다.
        return Replace(Replace(Replace(ConfidenceFormat, "%.0f", percent), "%%", "%"), "%@", classes);
    }

    private string Name(DefectClassification classification) =>
        ClassNames.TryGetValue(classification, out string? name)
            ? name
            : classification.ToString();

    private static string Replace(string text, string marker, string value) =>
        text.Replace(marker, value, StringComparison.Ordinal);
}
