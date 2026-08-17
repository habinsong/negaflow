using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>색 혼합 편집기입니다.</summary>
public sealed partial class DevelopColorMixerSection : UserControl
{
    private DevelopPanelState? panel;
    private bool isSynchronizing;

    public DevelopColorMixerSection() => InitializeComponent();

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
            ColorMixerSection,
            ColorMixerHeaderButton,
            ColorMixerSectionTitleText,
            ColorMixerResetButton,
            AppResources.Get("developSectionColorMixer", "Text"));

    public void Show(DevelopPanelState hostPanel)
    {
        isSynchronizing = true;
        try
        {
            ColorMixerEditor.Mixer = hostPanel.Color.ColorMixer;
        }
        finally
        {
            isSynchronizing = false;
        }
    }

    public void SetEnabled(bool enabled) => ColorMixerEditor.IsEnabled = enabled;

    public void ApplyExpanded(bool expanded) =>
        DevelopInspectorSectionChrome.Apply(
            ColorMixerHeaderButton, ColorMixerChevron, ColorMixerEditor, expanded);

    private void OnColorMixerChanged(object? sender, ColorMixerChangedEventArgs args)
    {
        _ = sender;
        if (panel is null || isSynchronizing)
        {
            return;
        }
        if (panel.Color.SetColorMixer(args.Mixer) == LibraryFrameError.None)
        {
            PreviewRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnColorMixerResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetRequested?.Invoke(this, static state => state.Color.ResetColorMixer());
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
