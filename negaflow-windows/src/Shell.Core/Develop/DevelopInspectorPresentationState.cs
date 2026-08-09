namespace Negaflow.Shell;

public enum DevelopInspectorTab
{
    Basic,
    Base,
    Edit,
    Defects,
    Info,
    Reset,
}

public enum DevelopInspectorSection
{
    Tone,
    ToneCurve,
    Color,
    ColorMixer,
    ColorGrading,
    BlackAndWhiteToning,
    Calibration,
    DetailAndEffects,
    Debug,
}

/// <summary>
/// macOS Develop inspector의 선택 tab과 단일 확장 section 계약을 UI와 분리해 고정합니다.
/// </summary>
public sealed class DevelopInspectorPresentationState
{
    public static IReadOnlyList<DevelopInspectorTab> TabOrder { get; } = Array.AsReadOnly(
        new[]
        {
            DevelopInspectorTab.Basic,
            DevelopInspectorTab.Base,
            DevelopInspectorTab.Edit,
            DevelopInspectorTab.Defects,
            DevelopInspectorTab.Info,
            DevelopInspectorTab.Reset,
        });

    public static IReadOnlyList<DevelopInspectorSection> SectionOrder { get; } = Array.AsReadOnly(
        new[]
        {
            DevelopInspectorSection.Tone,
            DevelopInspectorSection.ToneCurve,
            DevelopInspectorSection.Color,
            DevelopInspectorSection.ColorMixer,
            DevelopInspectorSection.ColorGrading,
            DevelopInspectorSection.BlackAndWhiteToning,
            DevelopInspectorSection.Calibration,
            DevelopInspectorSection.DetailAndEffects,
            DevelopInspectorSection.Debug,
        });

    public DevelopInspectorTab SelectedTab { get; private set; } = DevelopInspectorTab.Basic;

    public DevelopInspectorSection? ExpandedSection { get; private set; } = DevelopInspectorSection.Tone;

    public bool ShowsAdjustmentSections => SelectedTab != DevelopInspectorTab.Info;

    public void SelectTab(DevelopInspectorTab tab)
    {
        if (!TabOrder.Contains(tab))
        {
            throw new ArgumentOutOfRangeException(nameof(tab));
        }

        SelectedTab = tab;
    }

    public void Expand(DevelopInspectorSection section)
    {
        if (!SectionOrder.Contains(section))
        {
            throw new ArgumentOutOfRangeException(nameof(section));
        }

        ExpandedSection = section;
    }

    public void Collapse(DevelopInspectorSection section)
    {
        if (ExpandedSection == section)
        {
            ExpandedSection = null;
        }
    }
}
