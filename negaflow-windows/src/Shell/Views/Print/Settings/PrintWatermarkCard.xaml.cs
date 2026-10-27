using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media.Imaging;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Print;
using Negaflow.Shell.Views.Controls;
using Windows.Storage.Streams;

namespace Negaflow.Shell.Views.Print.Settings;

/// <summary>
/// 인화 레이아웃 탭의 워터마크(촬영 정보 띠) 카드입니다. macOS <c>PrintWatermarkInspectorControls</c>.
/// </summary>
/// <remarks>
/// 값은 <see cref="Value"/> 하나로 들고, 컨트롤이 바뀌면 <see cref="Changed"/> 를 올립니다. 로고 파일
/// 고르기는 창 손잡이가 필요해 화면(<c>PrintWorkspaceView</c>)이 <see cref="PickLogo"/> 로 맡습니다.
/// </remarks>
public sealed partial class PrintWatermarkCard : UserControl
{
    private bool isSynchronizing;

    public PrintWatermarkCard()
    {
        InitializeComponent();
        foreach (NegaflowSegmentedPicker picker in new[]
                 {
                     EnabledSelector, BackgroundSelector, TextInkSelector, TopBandSelector,
                     LogoSelector, HistogramSelector, HistogramInkSelector,
                 })
        {
            picker.SelectionChanged += (_, _) => Commit();
        }
        HistogramPlacementSelector.SelectionChanged += (_, _) => Commit();
        UserNamePlacementSelector.SelectionChanged += (_, _) => Commit();
        BandHeightSlider.ThumbToolTipValueConverter = new PercentSuffixThumbConverter();
    }

    /// <summary>사용자가 값을 바꿨습니다.</summary>
    public event EventHandler? Changed;

    /// <summary>로고 파일을 골라 그 경로를 돌려줍니다(그림으로 열리는 것만). 취소하면 null 입니다.</summary>
    public Func<Task<string?>>? PickLogo { get; set; }

    public PrintWatermarkSettings Value { get; private set; } = new();

    public void Localize()
    {
        SectionText.Text = Text("printWatermarkSection");
        EnabledField.Label = Text("printWatermarkSection");
        BackgroundField.Label = Text("printWatermarkBackground");
        TextInkField.Label = Text("printWatermarkTextColor");
        TopBandField.Label = Text("printWatermarkTopBand");
        BandHeightText.Text = Text("printWatermarkBandHeight");
        CameraField.Label = Text("printWatermarkCamera");
        LensField.Label = Text("printWatermarkLens");
        LogoField.Label = Text("printWatermarkLogo");
        LogoFileField.Label = Text("printWatermarkLogoFile");
        ChooseLogoButton.Content = Text("printWatermarkChooseLogo");
        AutomationProperties.SetName(RemoveLogoButton, AppResources.Get("printWatermarkRemoveLogo", "Text"));
        ToolTipService.SetToolTip(RemoveLogoButton, AppResources.Get("printWatermarkRemoveLogo", "Text"));
        FocalField.Label = Text("printWatermarkFocalLength");
        ApertureField.Label = Text("printWatermarkAperture");
        ShutterField.Label = Text("printWatermarkShutter");
        IsoField.Label = Text("printWatermarkIso");
        DateField.Label = Text("printWatermarkCaptureDate");
        AutoFillHintText.Text = Text("printWatermarkAutoFillHint");
        HistogramField.Label = Text("printWatermarkHistogram");
        HistogramInkField.Label = Text("printWatermarkHistogramColor");
        HistogramPlacementField.Label = Text("printWatermarkPlacement");
        UserNameField.Label = Text("printWatermarkUserName");
        UserNamePlacementField.Label = Text("printWatermarkPlacement");

        IReadOnlyList<SegmentOption> booleans =
        [
            new(false, AppResources.Get("printToggleOff", "Text")),
            new(true, AppResources.Get("printToggleOn", "Text")),
        ];
        IReadOnlyList<SegmentOption> inks =
        [
            new(PrintWatermarkInk.Black, Text("printWatermarkBlack")),
            new(PrintWatermarkInk.White, Text("printWatermarkWhite")),
        ];
        // 자리는 넷이라 분할 버튼이 비좁습니다. 팝업으로 고릅니다(macOS 와 같다).
        IReadOnlyList<PopupPickerOption> placements =
        [
            new(Text("printWatermarkBottomCenter"), PrintWatermarkPlacement.BottomCenter),
            new(Text("printWatermarkTopLeading"), PrintWatermarkPlacement.TopLeading),
            new(Text("printWatermarkTopCenter"), PrintWatermarkPlacement.TopCenter),
            new(Text("printWatermarkTopTrailing"), PrintWatermarkPlacement.TopTrailing),
        ];
        isSynchronizing = true;
        try
        {
            EnabledSelector.SetOptions(booleans, Value.IsEnabled);
            BackgroundSelector.SetOptions(
            [
                new(PrintWatermarkBackground.White, Text("printWatermarkWhite")),
                new(PrintWatermarkBackground.Black, Text("printWatermarkBlack")),
                new(PrintWatermarkBackground.Blur, Text("printWatermarkBlur")),
            ], Value.Background);
            TextInkSelector.SetOptions(inks, Value.BlurTextInk);
            TopBandSelector.SetOptions(booleans, Value.AddsTopBand);
            LogoSelector.SetOptions(booleans, Value.ShowsLogo);
            HistogramSelector.SetOptions(booleans, Value.ShowsHistogram);
            HistogramInkSelector.SetOptions(inks, Value.BlurHistogramInk);
            HistogramPlacementSelector.SetOptions(placements);
            HistogramPlacementSelector.SelectByTag(Value.HistogramPlacement);
            UserNamePlacementSelector.SetOptions(placements);
            UserNamePlacementSelector.SelectByTag(Value.UserNamePlacement);
        }
        finally
        {
            isSynchronizing = false;
        }
    }

    /// <summary>
    /// 값을 컨트롤에 되비춥니다. 비워 둔 카메라·렌즈·노출 칸에는 그 사진의 촬영 기록을 흐린 글자로
    /// 보여 줍니다 — 내보낼 때 그 값으로 채워집니다.
    /// </summary>
    public void Apply(PrintWatermarkSettings value, FilmShotMetadata? shot)
    {
        ArgumentNullException.ThrowIfNull(value);
        isSynchronizing = true;
        try
        {
            Value = value;
            EnabledSelector.SetSelected(value.IsEnabled);
            BackgroundSelector.SetSelected(value.Background);
            TextInkSelector.SetSelected(value.BlurTextInk);
            TopBandSelector.SetSelected(value.AddsTopBand);
            LogoSelector.SetSelected(value.ShowsLogo);
            HistogramSelector.SetSelected(value.ShowsHistogram);
            HistogramInkSelector.SetSelected(value.BlurHistogramInk);
            HistogramPlacementSelector.SelectByTag(value.HistogramPlacement);
            UserNamePlacementSelector.SelectByTag(value.UserNamePlacement);
            BandHeightSlider.Value = Math.Round(value.BandHeightRatio * 100);
            SetText(CameraBox, value.CameraName);
            SetText(LensBox, value.LensName);
            SetText(FocalBox, value.FocalLength);
            SetText(ApertureBox, value.Aperture);
            SetText(ShutterBox, value.ShutterSpeed);
            SetText(IsoBox, value.Iso);
            SetText(DateBox, value.CaptureDate);
            SetText(UserNameBox, value.UserName);
            PrintWatermarkSettings auto = new PrintWatermarkSettings().FillingFrom(shot);
            CameraBox.PlaceholderText = Placeholder(auto.CameraName, Text("printWatermarkCamera"));
            LensBox.PlaceholderText = Placeholder(auto.LensName, Text("printWatermarkLens"));
            FocalBox.PlaceholderText = Placeholder(auto.FocalLength, "50");
            ApertureBox.PlaceholderText = Placeholder(auto.Aperture, "2.8");
            ShutterBox.PlaceholderText = Placeholder(auto.ShutterSpeed, "1/125");
            IsoBox.PlaceholderText = Placeholder(auto.Iso, "400");
            _ = ShowLogoAsync(value);
            UpdateVisibility();
        }
        finally
        {
            isSynchronizing = false;
        }
    }

    private void UpdateVisibility()
    {
        PrintWatermarkSettings value = Value;
        DetailPanel.Visibility = Visible(value.IsEnabled);
        bool blur = value.Background == PrintWatermarkBackground.Blur;
        TextInkField.Visibility = Visible(blur);
        HistogramInkField.Visibility = Visible(blur && value.ShowsHistogram);
        // 위 여백이 없으면 위쪽 자리는 쓸 수 없으므로(아래 가운데로 내려옴) 위치 줄을 감춥니다.
        HistogramPlacementField.Visibility = Visible(value.AddsTopBand && value.ShowsHistogram);
        UserNamePlacementField.Visibility = Visible(
            value.AddsTopBand && !string.IsNullOrWhiteSpace(value.UserName));
        LogoFileField.Visibility = Visible(value.ShowsLogo);
        RemoveLogoButton.Visibility = Visible(value.LogoSourcePath.Length > 0);
        // 경로가 비면 negaflow 로고입니다.
        LogoFileText.Text = value.LogoSourcePath.Length > 0
            ? System.IO.Path.GetFileName(value.LogoSourcePath)
            : "negaflow";
        ToolTipService.SetToolTip(LogoFileText, value.LogoSourcePath.Length > 0 ? value.LogoSourcePath : null);
        BandHeightValueText.Text = Math.Round(value.BandHeightRatio * 100)
            .ToString("0", System.Globalization.CultureInfo.CurrentCulture) + "%";
    }

    private void Commit()
    {
        if (isSynchronizing)
        {
            return;
        }
        Value = Value with
        {
            IsEnabled = Chosen(EnabledSelector, Value.IsEnabled),
            Background = Chosen(BackgroundSelector, Value.Background),
            BlurTextInk = Chosen(TextInkSelector, Value.BlurTextInk),
            AddsTopBand = Chosen(TopBandSelector, Value.AddsTopBand),
            ShowsLogo = Chosen(LogoSelector, Value.ShowsLogo),
            BandHeightRatio = Math.Clamp(
                BandHeightSlider.Value / 100,
                PrintWatermarkSettings.MinimumBandHeightRatio,
                PrintWatermarkSettings.MaximumBandHeightRatio),
            CameraName = CameraBox.Text,
            LensName = LensBox.Text,
            FocalLength = FocalBox.Text,
            Aperture = ApertureBox.Text,
            ShutterSpeed = ShutterBox.Text,
            Iso = IsoBox.Text,
            CaptureDate = DateBox.Text,
            ShowsHistogram = Chosen(HistogramSelector, Value.ShowsHistogram),
            BlurHistogramInk = Chosen(HistogramInkSelector, Value.BlurHistogramInk),
            HistogramPlacement = HistogramPlacementSelector.SelectedTag is PrintWatermarkPlacement histogramPlacement
                ? histogramPlacement
                : Value.HistogramPlacement,
            UserName = UserNameBox.Text,
            UserNamePlacement = UserNamePlacementSelector.SelectedTag is PrintWatermarkPlacement namePlacement
                ? namePlacement
                : Value.UserNamePlacement,
        };
        UpdateVisibility();
        _ = ShowLogoAsync(Value);
        Changed?.Invoke(this, EventArgs.Empty);
    }

    private void OnTextChanged(object sender, TextChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        Commit();
    }

    private void OnSliderChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        Commit();
    }

    private async void OnChooseLogoClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (PickLogo is null || await PickLogo() is not { } path)
        {
            return;
        }
        // 설정·템플릿에는 경로를 담고, 그릴 때마다 그 경로에서 읽습니다.
        Value = Value with { LogoSourcePath = path };
        await ShowLogoAsync(Value);
        UpdateVisibility();
        Changed?.Invoke(this, EventArgs.Empty);
    }

    private void OnRemoveLogoClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        // 고른 파일을 빼면 negaflow 로고로 돌아갑니다.
        Value = Value with { LogoSourcePath = string.Empty };
        _ = ShowLogoAsync(Value);
        UpdateVisibility();
        Changed?.Invoke(this, EventArgs.Empty);
    }

    private async Task ShowLogoAsync(PrintWatermarkSettings value)
    {
        if (await PrintWatermarkLogo.LoadAsync(value) is not { Length: > 0 } png)
        {
            LogoImage.Source = null;
            return;
        }
        BitmapImage image = new();
        using InMemoryRandomAccessStream stream = new();
        await stream.WriteAsync(png.AsBuffer());
        stream.Seek(0);
        await image.SetSourceAsync(stream);
        LogoImage.Source = image;
    }

    private static void SetText(TextBox box, string value)
    {
        if (box.Text != value)
        {
            box.Text = value;
        }
    }

    private static string Placeholder(string automatic, string sample) =>
        string.IsNullOrWhiteSpace(automatic) ? sample : automatic;

    private static T Chosen<T>(NegaflowSegmentedPicker picker, T fallback) =>
        picker.SelectedValue is T value ? value : fallback;

    private static Visibility Visible(bool value) => value ? Visibility.Visible : Visibility.Collapsed;

    private static string Text(string key) => AppResources.Get(key, "Text");
}
