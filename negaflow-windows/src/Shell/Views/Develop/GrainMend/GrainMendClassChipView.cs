using System.Globalization;
using Microsoft.UI.Xaml.Media;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Windows.UI;
using Windows.UI.Text;

namespace Negaflow.Shell.Views.Develop.GrainMend;

/// <summary>
/// 종류별 칩 하나가 화면에 내는 값 전부입니다. macOS <c>DefectClassChip</c> 을 그대로 옮겼습니다 —
/// 분류색 점 + 이름 + 개수 + 평균 신뢰도(%), 전체 제외 상태는 흐리게 + 취소선.
/// </summary>
public sealed class GrainMendClassChipView
{
    /// <summary>macOS <c>Color.secondary.opacity(0.4)</c> — 전체 제외한 종류의 점입니다.</summary>
    private static readonly Color ExcludedDot = Color.FromArgb(0x66, 0x8A, 0x8A, 0x8A);

    public GrainMendClassChipView(GrainMendClassSummary summary, string name)
    {
        ArgumentException.ThrowIfNullOrEmpty(name);
        Classification = summary.Classification;
        Name = name;
        AllExcluded = summary.AllExcluded;
        DefectOverlayColor color = DefectClassPalette.For(summary.Classification);
        Dot = new SolidColorBrush(summary.AllExcluded
            ? ExcludedDot
            : Color.FromArgb(0xFF, color.Red, color.Green, color.Blue));
        CountText = summary.Count.ToString(CultureInfo.CurrentCulture);
        // macOS: "\(Int((meanConfidence * 100).rounded()))%". Swift 의 rounded() 는 반올림을
        // 0 에서 먼 쪽으로 합니다 — 레이어 목록의 %.0f(짝수 쪽)와 다른 규칙입니다.
        ConfidenceText = Math
            .Round(summary.MeanConfidence * 100.0, MidpointRounding.AwayFromZero)
            .ToString("F0", CultureInfo.CurrentCulture) + "%";
        // macOS: .strikethrough(summary.allExcluded) + .foregroundStyle(.secondary)
        NameDecorations = summary.AllExcluded
            ? TextDecorations.Strikethrough
            : TextDecorations.None;
        Opacity = summary.AllExcluded ? 0.55 : 1.0;
    }

    public DefectClassification Classification { get; }

    public string Name { get; }

    public bool AllExcluded { get; }

    public SolidColorBrush Dot { get; }

    public string CountText { get; }

    public string ConfidenceText { get; }

    public TextDecorations NameDecorations { get; }

    public double Opacity { get; }

    /// <summary>낭독기가 칩 하나를 한 문장으로 읽도록 합칩니다.</summary>
    public string AutomationName => $"{Name} {CountText} {ConfidenceText}";
}
