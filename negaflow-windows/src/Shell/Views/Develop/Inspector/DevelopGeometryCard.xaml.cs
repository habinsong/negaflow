using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>
/// 회전·뒤집기·곧게 펴기와 크롭 비율입니다. 실제 crop 세션은 캔버스가 맡습니다.
/// </summary>
public sealed partial class DevelopGeometryCard : UserControl
{
    private bool isSynchronizing;

    public DevelopGeometryCard() => InitializeComponent();

    public event EventHandler? CropClicked;

    public event EventHandler<Func<DevelopPanelState, LibraryFrameError>>? TransformRequested;

    public event EventHandler<CropAspectOption>? AspectChosen;

    public event EventHandler? AspectLockToggled;

    public void Localize()
    {
        string geometry = AppResources.Get("developGeometry", "Text");
        GeometrySectionTitleText.Text = geometry;
        AutomationProperties.SetName(GeometryControlCard, geometry);
        SetLocalizedNameAndTooltip(RotateLeftButton, AppResources.Get("developRotateLeft", "Text"));
        SetLocalizedNameAndTooltip(RotateRightButton, AppResources.Get("developRotateRight", "Text"));
        SetLocalizedNameAndTooltip(FlipHorizontalButton, AppResources.Get("developFlipHorizontal", "Text"));
        SetLocalizedNameAndTooltip(FlipVerticalButton, AppResources.Get("developFlipVertical", "Text"));
        SetLocalizedNameAndTooltip(CropButton, AppResources.Get("developCrop", "Text"));
        StraightenAngleControl.Label = AppResources.Get("developAngle", "Text");
        CropAspectLabel.Text = AppResources.Get("cropAspectRatio", "Text");
        CropAspectOptions.ItemsSource = CropAspect.Options
            .Select(option => new CropAspectChoice(option, CropAspectText(option.Label)))
            .ToList();
    }

    public void ConfigureRanges()
    {
        StraightenAngleControl.Minimum = -45;
        StraightenAngleControl.Maximum = 45;
    }

    public void Show(DevelopPanelState hostPanel)
    {
        isSynchronizing = true;
        try
        {
            StraightenAngleControl.Value = hostPanel.ImageTransform.StraightenAngle;
            CropAngleDialControl.Angle = hostPanel.ImageTransform.StraightenAngle;
        }
        finally
        {
            isSynchronizing = false;
        }
    }

    public void SetEnabled(bool enabled)
    {
        StraightenAngleControl.IsEnabled = enabled;
        CropAspectButton.IsEnabled = enabled;
        CropAspectLockButton.IsEnabled = enabled;
        RotateLeftButton.IsEnabled = enabled;
        RotateRightButton.IsEnabled = enabled;
        FlipHorizontalButton.IsEnabled = enabled;
        FlipVerticalButton.IsEnabled = enabled;
    }

    public void SetDialVisible(bool visible) =>
        CropAngleDialControl.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;

    public void SetLockGlyph(bool locked) =>
        CropAspectLockIcon.Glyph = locked ? "" : "";

    public void UpdateAspectControls(DevelopPanelState hostPanel, bool locked)
    {
        string label = CropAspect.LabelFor(hostPanel.ImageTransform);
        CropAspectButton.Content = CropAspectText(label);
        AutomationProperties.SetName(CropAspectButton, CropAspectButton.Content.ToString());
        string lockName = AppResources.Get(
            locked ? "cropAspectLocked" : "cropAspectUnlocked",
            "Value");
        AutomationProperties.SetName(CropAspectLockButton, lockName);
        ToolTipService.SetToolTip(CropAspectLockButton, lockName);
    }

    private void OnCropClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        CropClicked?.Invoke(this, EventArgs.Empty);
    }

    private void OnRotateLeftClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        TransformRequested?.Invoke(this, static state => state.Rotate(clockwise: false));
    }

    private void OnRotateRightClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        TransformRequested?.Invoke(this, static state => state.Rotate(clockwise: true));
    }

    private void OnFlipHorizontalClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        TransformRequested?.Invoke(this, static state => state.FlipHorizontally());
    }

    private void OnFlipVerticalClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        TransformRequested?.Invoke(this, static state => state.FlipVertically());
    }

    private void OnStraightenAngleChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        if (isSynchronizing)
        {
            return;
        }
        TransformRequested?.Invoke(this, state => state.SetStraightenAngle(args.Value));
    }

    private void OnCropAngleDialChanged(object? sender, double angle)
    {
        _ = sender;
        if (isSynchronizing)
        {
            return;
        }
        TransformRequested?.Invoke(this, state => state.SetStraightenAngle(angle));
    }

    /// <summary>비율 목록 한 칸입니다. 화면에 나가는 이름만 여기서 만듭니다.</summary>
    private sealed record CropAspectChoice(CropAspectOption Option, string Text);

    private void OnCropAspectClicked(object sender, ItemClickEventArgs args)
    {
        _ = sender;
        if (args.ClickedItem is not CropAspectChoice choice)
        {
            return;
        }
        CropAspectButton.Flyout?.Hide();
        AspectChosen?.Invoke(this, choice.Option);
    }

    private void OnCropAspectLockToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        AspectLockToggled?.Invoke(this, EventArgs.Empty);
    }

    private static string CropAspectText(string label) => label switch
    {
        "original" => AppResources.Get("cropAspectOriginal", "Text"),
        "custom" => AppResources.Get("cropAspectCustom", "Text"),
        _ => label,
    };

    private static void SetLocalizedNameAndTooltip(Button button, string text)
    {
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }
}
