using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>노이즈 감소와 텍스처 슬라이더입니다.</summary>
public sealed partial class DevelopDetailSection : UserControl
{
    private DevelopPanelState? panel;
    private bool isSynchronizing;

    public DevelopDetailSection() => InitializeComponent();

    public event EventHandler? PreviewRequested;

    public event EventHandler? RefreshRequested;

    public event EventHandler? ToggleRequested;

    public event EventHandler<DisclosureExpansionRequestedEventArgs>? ExpansionRequested;

    public event EventHandler<Func<DevelopPanelState, LibraryFrameError>>? ResetRequested;

    public void Bind(DevelopPanelState hostPanel)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        panel = hostPanel;
    }

    public void ConfigureRanges(double toneControl)
    {
        foreach (InspectorSlider slider in new[]
                 {
                     NoiseReductionStrengthControl,
                     NoiseReductionLumaControl,
                     NoiseReductionChromaControl,
                     NoiseReductionDarkToneControl,
                     NoiseReductionDetailControl,
                     NoiseReductionGrainProtectControl,
                     GrainControl,
                     SharpnessControl,
                     HalationControl,
                 })
        {
            slider.Minimum = 0;
            slider.Maximum = 1;
        }
        ClarityControl.Minimum = -toneControl;
        ClarityControl.Maximum = toneControl;
        VignetteControl.Minimum = -toneControl;
        VignetteControl.Maximum = toneControl;
    }

    public void Localize()
    {
        DevelopInspectorSectionChrome.Localize(
            DetailAndEffectsSection,
            DetailAndEffectsHeaderButton,
            DetailAndEffectsSectionTitleText,
            DetailAndEffectsResetButton,
            AppResources.Get("developSectionDetailAndEffects", "Text"));
        NoiseReductionLabelText.Text = AppResources.Get("developNoiseReduction", "Text");
        NoiseReductionStrengthControl.Label = AppResources.Get("developNoiseReductionStrength", "Text");
        NoiseReductionLumaControl.Label = AppResources.Get("developNoiseReductionLuminance", "Text");
        NoiseReductionChromaControl.Label = AppResources.Get("developNoiseReductionColor", "Text");
        NoiseReductionDarkToneControl.Label = AppResources.Get("developNoiseReductionDarkTones", "Text");
        NoiseReductionDetailControl.Label = AppResources.Get("developNoiseReductionDetail", "Text");
        NoiseReductionGrainProtectControl.Label = AppResources.Get("developNoiseReductionGrainProtect", "Text");
        GrainControl.Label = AppResources.Get("developTextureGrain", "Text");
        SharpnessControl.Label = AppResources.Get("developTextureSharpness", "Text");
        ClarityControl.Label = AppResources.Get("developTextureClarity", "Text");
        HalationControl.Label = AppResources.Get("developTextureHalation", "Text");
        VignetteControl.Label = AppResources.Get("developTextureVignette", "Text");
    }

    public void Show(DevelopPanelState hostPanel)
    {
        NoiseReductionRecipe noiseReduction = hostPanel.NoiseReduction;
        TextureRecipe texture = hostPanel.Texture;
        isSynchronizing = true;
        try
        {
            NoiseReductionToggle.IsOn = noiseReduction.Strength > 0.001;
            NoiseReductionControls.Visibility = NoiseReductionToggle.IsOn
                ? Visibility.Visible
                : Visibility.Collapsed;
            NoiseReductionStrengthControl.Value = noiseReduction.Strength;
            NoiseReductionLumaControl.Value = noiseReduction.Luma;
            NoiseReductionChromaControl.Value = noiseReduction.Chroma;
            NoiseReductionDarkToneControl.Value = noiseReduction.DarkTone;
            NoiseReductionDetailControl.Value = noiseReduction.Detail;
            NoiseReductionGrainProtectControl.Value = noiseReduction.GrainProtect;
            GrainControl.Value = texture.Grain;
            SharpnessControl.Value = texture.Sharpness;
            ClarityControl.Value = texture.Clarity;
            HalationControl.Value = texture.Halation;
            VignetteControl.Value = texture.Vignette;
        }
        finally
        {
            isSynchronizing = false;
        }
    }

    public void SetEnabled(bool enabled)
    {
        foreach (InspectorSlider slider in new[]
                 {
                     NoiseReductionStrengthControl,
                     NoiseReductionLumaControl,
                     NoiseReductionChromaControl,
                     NoiseReductionDarkToneControl,
                     NoiseReductionDetailControl,
                     NoiseReductionGrainProtectControl,
                     GrainControl,
                     SharpnessControl,
                     ClarityControl,
                     HalationControl,
                     VignetteControl,
                 })
        {
            slider.IsEnabled = enabled;
        }
        NoiseReductionToggle.IsEnabled = enabled;
    }

    public void ApplyExpanded(bool expanded) =>
        DevelopInspectorSectionChrome.Apply(
            DetailAndEffectsHeaderButton, DetailAndEffectsChevron, DetailAndEffectsControls, expanded);

    private void OnNoiseReductionToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizing)
        {
            return;
        }
        if (panel.SetNoiseReductionEnabled(NoiseReductionToggle.IsOn) == LibraryFrameError.None)
        {
            RefreshRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnNoiseReductionChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizing)
        {
            return;
        }
        if (panel.SetNoiseReduction(new NoiseReductionRecipe(
                NoiseReductionStrengthControl.Value,
                NoiseReductionLumaControl.Value,
                NoiseReductionChromaControl.Value,
                NoiseReductionDarkToneControl.Value,
                NoiseReductionDetailControl.Value,
                NoiseReductionGrainProtectControl.Value)) == LibraryFrameError.None)
        {
            PreviewRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnTextureChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizing)
        {
            return;
        }
        if (panel.SetTexture(new TextureRecipe(
                GrainControl.Value,
                SharpnessControl.Value,
                HalationControl.Value,
                ClarityControl.Value,
                VignetteControl.Value)) == LibraryFrameError.None)
        {
            PreviewRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnDetailAndEffectsResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetRequested?.Invoke(this, static state => state.ResetDetailAndEffects());
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
