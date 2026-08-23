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

    public DevelopGeometryCard()
    {
        InitializeComponent();
        // 아이콘 색은 코드에서 칠합니다. `{ThemeResource}` 는 스타일이나 템플릿이 <b>걸릴
        // 때 한 번</b> 풀리고 테마를 바꿔도 다시 풀리지 않습니다 — 실측: 어둡게로 시작하면
        // 흰색, 밝게로 시작하면 검정이지만, 켜 둔 채로 바꾸면 그대로였습니다.
        ApplyToolIconColor();
        ActualThemeChanged += (_, _) => ApplyToolIconColor();
    }

    /// <summary>
    /// 다섯 단추의 아이콘과 알약 바탕 색입니다. 아이콘은 라이트에서 <b>순검정</b>,
    /// 다크에서 <b>순백</b>이고, 알약은 <b>기본 음영</b>(라이트 6% 검정 · 다크 9% 흰색)입니다.
    /// </summary>
    private void ApplyToolIconColor()
    {
        Microsoft.UI.Xaml.Media.Brush icon = new Microsoft.UI.Xaml.Media.SolidColorBrush(
            ActualTheme == ElementTheme.Dark
                ? Microsoft.UI.Colors.White
                : Microsoft.UI.Colors.Black);
        // 단추의 <c>Foreground</c> 를 바꾸는 것만으로는 아이콘이 따라오지 않습니다 —
        // 실측: 테마를 바꾸면 이 메서드는 돌지만(로그 확인) 아이콘 색은 그대로였습니다.
        // 그림에 직접 칠합니다.
        foreach (VectorIcon glyph in new[]
        {
            CropIcon,
            RotateLeftIcon,
            RotateRightIcon,
            FlipHorizontalIcon,
            FlipVerticalIcon,
        })
        {
            glyph.Foreground = icon;
        }

        // 알약 바탕은 <b>기본 음영</b>입니다 — App.xaml 의 `NegaflowSubtleFillBrush` 와
        // 같은 값(라이트 6% 검정 · 다크 9% 흰색)이며, 테마가 바뀌면 여기서 다시 칠합니다.
        Microsoft.UI.Xaml.Media.Brush pill = new Microsoft.UI.Xaml.Media.SolidColorBrush(
            ActualTheme == ElementTheme.Dark
                ? Windows.UI.Color.FromArgb(0x16, 0xFF, 0xFF, 0xFF)
                : Windows.UI.Color.FromArgb(0x10, 0x00, 0x00, 0x00));
        foreach (Button button in new[]
        {
            CropButton,
            RotateLeftButton,
            RotateRightButton,
            FlipHorizontalButton,
            FlipVerticalButton,
        })
        {
            button.Background = pill;
        }
    }

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
            // macOS 는 머리줄 오른쪽에 지금 걸린 회전·뒤집기를 그대로 적습니다.
            GeometryTransformText.Text = hostPanel.ImageTransform.DisplayName;
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
