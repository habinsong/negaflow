using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>색 보정 편집기입니다.</summary>
public sealed partial class DevelopColorGradingSection : UserControl
{
    private DevelopPanelState? panel;
    private bool isSynchronizing;

    public DevelopColorGradingSection() => InitializeComponent();

    public event EventHandler? PreviewRequested;

    public event EventHandler? ToggleRequested;

    public event EventHandler<DisclosureExpansionRequestedEventArgs>? ExpansionRequested;

    public event EventHandler<Func<DevelopPanelState, LibraryFrameError>>? ResetRequested;

    public void Bind(DevelopPanelState hostPanel)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        panel = hostPanel;
    }

    public void Localize() =>
        DevelopInspectorSectionChrome.Localize(
            ColorGradingSection,
            ColorGradingHeaderButton,
            ColorGradingSectionTitleText,
            ColorGradingResetButton,
            AppResources.Get("developSectionColorGrading", "Text"));

    public void Show(DevelopPanelState hostPanel)
    {
        isSynchronizing = true;
        try
        {
            ColorGradingEditor.Grading = hostPanel.Color.ColorGrading;
        }
        finally
        {
            isSynchronizing = false;
        }
    }

    public void SetEnabled(bool enabled) => ColorGradingEditor.IsEnabled = enabled;

    public void ApplyExpanded(bool expanded) =>
        DevelopInspectorSectionChrome.Apply(
            ColorGradingHeaderButton, ColorGradingChevron, ColorGradingEditor, expanded);

    private void OnColorGradingChanged(object? sender, ColorGradingChangedEventArgs args)
    {
        _ = sender;
        if (panel is null || isSynchronizing)
        {
            return;
        }
        if (panel.Color.SetColorGrading(args.Grading) == LibraryFrameError.None)
        {
            PreviewRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnColorGradingResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetRequested?.Invoke(this, static state => state.Color.ResetColorGrading());
    }

    private void OnInspectorSectionHeaderClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ToggleRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnInspectorSectionExpansionRequested(
        object? sender,
        DisclosureExpansionRequestedEventArgs args)
    {
        _ = sender;
        ExpansionRequested?.Invoke(this, args);
    }
}
