using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Controls;

/// <summary>macOS Color Mixer의 HSL/All 전환과 여덟 색상 밴드를 표시합니다.</summary>
public sealed partial class ColorMixerEditor : UserControl
{
    /// <summary>
    /// macOS 와 같은 여덟 밴드입니다. <c>Id</c> 는 automation id 에 쓰는 안정된 이름이고
    /// 화면에 나가는 이름은 리소스에서 옵니다. 색은 Swift 의 `Color(red:green:blue:)` 를
    /// 가장 가까운 바이트로 옮긴 값입니다 — 예를 들어 초록 `0.25, 0.72, 0.34` 는 64, 184, 87.
    /// </summary>
    private static readonly (string Id, string ResourceKey, string Color)[] Bands =
    [
        ("red", "developRed", "#FFE63333"),
        ("orange", "developBandOrange", "#FFED8C2E"),
        ("yellow", "developBandYellow", "#FFE0D133"),
        ("green", "developGreen", "#FF40B857"),
        ("aqua", "developBandAqua", "#FF33C2C7"),
        ("blue", "developBlue", "#FF3D6BE6"),
        ("purple", "developBandPurple", "#FF8C4DDB"),
        ("magenta", "developBandMagenta", "#FFE047A8"),
    ];

    /// <summary>macOS `swatchSlider` 의 `EditableSliderValueText(width: 44)` 입니다.</summary>
    private const double BandValueWidth = 44;

    private ColorMixerProperty property = ColorMixerProperty.Hue;
    private bool isSynchronizing;

    public ColorMixerEditor()
    {
        InitializeComponent();
        LocalizeControls();
        HueButton.IsChecked = true;
        RebuildBands();
    }

    /// <summary>이름은 macOS 와 같은 문자열이며 XAML 에 박아 두지 않습니다.</summary>
    private void LocalizeControls()
    {
        SetPropertyText(HueButton, AppResources.Get("developHue", "Text"));
        SetPropertyText(SaturationButton, AppResources.Get("developSaturation", "Text"));
        SetPropertyText(LuminanceButton, AppResources.Get("developLuminance", "Text"));
        SetPropertyText(AllButton, AppResources.Get("developAll", "Text"));
    }

    private static void SetPropertyText(RadioButton radio, string text)
    {
        radio.Content = text;
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(radio, text);
    }

    public static readonly DependencyProperty MixerProperty = DependencyProperty.Register(
        nameof(Mixer),
        typeof(ColorMixerRecipe),
        typeof(ColorMixerEditor),
        new PropertyMetadata(ColorMixerRecipe.Identity, OnMixerChanged));

    public ColorMixerRecipe Mixer
    {
        get => (ColorMixerRecipe)GetValue(MixerProperty);
        set => SetValue(MixerProperty, value);
    }

    public event EventHandler<ColorMixerChangedEventArgs>? MixerChanged;

    private static void OnMixerChanged(DependencyObject sender, DependencyPropertyChangedEventArgs args)
    {
        _ = args;
        ((ColorMixerEditor)sender).RebuildBands();
    }

    private void OnPropertyChecked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (isSynchronizing)
        {
            return;
        }
        property = ReferenceEquals(sender, HueButton) ? ColorMixerProperty.Hue :
            ReferenceEquals(sender, SaturationButton) ? ColorMixerProperty.Saturation :
            ReferenceEquals(sender, LuminanceButton) ? ColorMixerProperty.Luminance :
            ColorMixerProperty.All;
        RebuildBands();
    }

    /// <summary>
    /// macOS 는 "모두" 일 때만 밴드 이름 줄을 따로 내고 그 아래 H·S·L 촘촘 슬라이더 셋을
    /// 붙입니다. 나머지 세 모드는 색 동그라미와 이름이 슬라이더 자신의 이름 줄에 들어가므로
    /// 이름이 두 번 나오지 않습니다.
    /// </summary>
    private void RebuildBands()
    {
        if (BandsPanel is null)
        {
            return;
        }
        isSynchronizing = true;
        BandsPanel.Children.Clear();
        for (int index = 0; index < ColorMixerRecipe.BandCount; index++)
        {
            BandsPanel.Children.Add(property == ColorMixerProperty.All
                ? BuildAllBand(index)
                : BuildSwatchSlider(index, property));
        }
        isSynchronizing = false;
    }

    /// <summary>macOS `swatchSlider(_:_:)` — 색 동그라미 + 이름 + 값, 그 아래 슬라이더.</summary>
    private InspectorSlider BuildSwatchSlider(int index, ColorMixerProperty channel)
    {
        InspectorSlider slider = CreateSlider(index, channel, BandName(index));
        slider.Swatch = BandBrush(index);
        slider.ValueWidth = BandValueWidth;
        slider.LabelSpacing = 3;
        return slider;
    }

    /// <summary>macOS "모두" 밴드 — `VStack(spacing: 3)` 에 이름 줄과 H·S·L 세 줄.</summary>
    private StackPanel BuildAllBand(int index)
    {
        StackPanel band = new() { Spacing = 3, Margin = new Thickness(0, 0, 0, 2) };
        StackPanel heading = new() { Orientation = Orientation.Horizontal, Spacing = 6 };
        heading.Children.Add(BuildSwatchDot(index));
        heading.Children.Add(new TextBlock
        {
            Text = BandName(index),
            FontSize = 12,
            FontWeight = Microsoft.UI.Text.FontWeights.Medium,
            VerticalAlignment = VerticalAlignment.Center,
        });
        band.Children.Add(heading);

        band.Children.Add(CreateMiniSlider(index, ColorMixerProperty.Hue, "H"));
        band.Children.Add(CreateMiniSlider(index, ColorMixerProperty.Saturation, "S"));
        band.Children.Add(CreateMiniSlider(index, ColorMixerProperty.Luminance, "L"));
        return band;
    }

    /// <summary>macOS `swatch(_:)` — 12pt 원에 흰색 30% 0.5pt 테두리.</summary>
    private static Border BuildSwatchDot(int index) => new()
    {
        Width = 12,
        Height = 12,
        CornerRadius = new CornerRadius(6),
        VerticalAlignment = VerticalAlignment.Center,
        BorderThickness = new Thickness(0.5),
        BorderBrush = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 255, 255, 255)) { Opacity = 0.3 },
        Background = BandBrush(index),
    };

    private static SolidColorBrush BandBrush(int index) => new(
        Windows.UI.Color.FromArgb(
            255,
            Convert.ToByte(Bands[index].Color[3..5], 16),
            Convert.ToByte(Bands[index].Color[5..7], 16),
            Convert.ToByte(Bands[index].Color[7..9], 16)));

    /// <summary>macOS `miniSlider(_:_:)` — 태그·슬라이더·값이 한 줄입니다.</summary>
    private InspectorSlider CreateMiniSlider(int index, ColorMixerProperty channel, string tag)
    {
        InspectorSlider slider = CreateSlider(index, channel, tag);
        slider.Compact = true;
        return slider;
    }

    private InspectorSlider CreateSlider(int index, ColorMixerProperty channel, string label)
    {
        InspectorSlider slider = new()
        {
            Label = label,
            Minimum = -1,
            Maximum = 1,
            ResetValue = 0,
            Value = GetValue(channel, index),
            SliderAutomationId = $"negaflow.develop.color-mixer.{ChannelName(channel)}.{ChannelNameForBand(index)}",
        };
        slider.ValueChanged += (_, args) => OnSliderChanged(index, channel, args.Value);
        return slider;
    }

    private void OnSliderChanged(int index, ColorMixerProperty channel, double value)
    {
        if (isSynchronizing)
        {
            return;
        }
        double[] hue = Mixer.Hue.ToArray();
        double[] saturation = Mixer.Saturation.ToArray();
        double[] luminance = Mixer.Luminance.ToArray();
        switch (channel)
        {
            case ColorMixerProperty.Hue: hue[index] = value; break;
            case ColorMixerProperty.Saturation: saturation[index] = value; break;
            case ColorMixerProperty.Luminance: luminance[index] = value; break;
            default: return;
        }
        Mixer = new ColorMixerRecipe(hue, saturation, luminance);
        MixerChanged?.Invoke(this, new ColorMixerChangedEventArgs(Mixer));
    }

    private double GetValue(ColorMixerProperty channel, int index) => channel switch
    {
        ColorMixerProperty.Hue => Mixer.Hue[index],
        ColorMixerProperty.Saturation => Mixer.Saturation[index],
        ColorMixerProperty.Luminance => Mixer.Luminance[index],
        _ => 0,
    };

    private static string ChannelName(ColorMixerProperty channel) => channel switch
    {
        ColorMixerProperty.Hue => "hue",
        ColorMixerProperty.Saturation => "saturation",
        ColorMixerProperty.Luminance => "luminance",
        _ => "all",
    };

    private static string BandName(int index) => AppResources.Get(Bands[index].ResourceKey, "Text");

    private static string ChannelNameForBand(int index) => Bands[index].Id;

    private enum ColorMixerProperty { Hue, Saturation, Luminance, All }
}

public sealed class ColorMixerChangedEventArgs(ColorMixerRecipe mixer) : EventArgs
{
    public ColorMixerRecipe Mixer { get; } = mixer;
}
