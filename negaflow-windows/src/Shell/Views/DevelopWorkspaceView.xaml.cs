using System.Globalization;
using System.IO;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Input;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;
using Negaflow.Shell.Views.Layout;
using Windows.System;
using Windows.UI.Core;

namespace Negaflow.Shell.Views;

public sealed partial class DevelopWorkspaceView : UserControl
{
    private readonly ThreePaneResizeController resizeController = new();
    private readonly DevelopInspectorPresentationState inspectorPresentation = new();
    private WorkspacePresentationState? workspaceState;
    private DevelopPanelState? panel;
    private LibraryHostService? libraryHost;
    private ToneLimits? toneLimits;
    private Microsoft.UI.WindowId? importWindowId;
    private PreviewCoordinator? previewCoordinator;
    private AutoAdjustCoordinator? autoAdjustCoordinator;
    private WriteableBitmap? previewBitmap;
    private bool isSynchronizingInspector;
    private bool isSynchronizingInspectorPresentation;
    private bool isInspectorPresentationReady;
    private Negaflow.Shell.Library.ThumbnailService? thumbnails;
    /// <summary>macOS 의 <c>crop.aspectLocked</c> 와 같이 잠긴 상태로 시작합니다.</summary>
    private bool isCropAspectLocked = true;
    private DevelopSourceKind developSource = DevelopSourceKind.Library;
    private GrainMendDetectCoordinator? grainMendDetectCoordinator;
    /// <summary>폴더가 비어 있으면 원본 옆에 씁니다 — 목적지를 고르기 전에도 내보낼 수 있습니다.</summary>
    private ExportDestination exportDestination =
        new(string.Empty, ExportDestination.NameToken, DevelopExportFormat.Tiff16);
    private CropSession? cropSession;
    private CropDragMode cropDragMode;
    private CropDisplayPoint cropDragStart;
    private CropDisplayRect cropDragStartRect;
    private bool cropAwaitingPreview;

    private enum CropDragMode
    {
        None,
        Create,
        Move,
        TopLeft,
        Top,
        TopRight,
        Right,
        BottomRight,
        Bottom,
        BottomLeft,
        Left,
    }

    public DevelopWorkspaceView()
    {
        InitializeComponent();
        isInspectorPresentationReady = true;
        ApplyInspectorPresentation();
        LocalizeControls();
    }

    public event EventHandler? QuickExportAvailabilityChanged;

    public bool CanQuickExport => panel?.CanExport == true;

    public void Initialize(
        WorkspacePresentationState state,
        NativeEngineStatus nativeEngineStatus)
    {
        ArgumentNullException.ThrowIfNull(state);
        ArgumentNullException.ThrowIfNull(nativeEngineStatus);
        workspaceState = state;
        state.Changed += OnStateChanged;
        Filmstrip.Initialize(state);
        Filmstrip.FrameSelected += OnFilmstripFrameSelected;
        StatusBar.Initialize(nativeEngineStatus);
        UpdateState(state.Current);
        Unloaded += OnUnloaded;
    }

    /// <summary>
    /// 정착한 미리보기를 라이브러리 썸네일로 넘겨줄 서비스입니다.
    /// </summary>
    public void AttachThumbnails(Negaflow.Shell.Library.ThumbnailService service)
    {
        ArgumentNullException.ThrowIfNull(service);
        if (thumbnails is not null)
        {
            thumbnails.ThumbnailReady -= OnThumbnailReady;
        }
        thumbnails = service;
        thumbnails.ThumbnailReady += OnThumbnailReady;
    }

    /// <summary>
    /// 라이브러리를 붙입니다. **UI 스레드에서만** 부르십시오. 현상 자체는 워커에서 돌지만
    /// 여기서 만지는 것은 전부 컨트롤입니다.
    /// </summary>
    public void ShowLibrary(
        LibraryHostService host,
        ToneLimits limits,
        NegativeLimits negativeLimits,
        Microsoft.UI.WindowId windowId)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(limits);
        ArgumentNullException.ThrowIfNull(negativeLimits);
        importWindowId = windowId;

        libraryHost = host;
        toneLimits = limits;
        panel = new DevelopPanelState(host, limits, negativeLimits);
        // 사용자 프리셋은 카탈로그가 아니라 앱 설정 옆에 삽니다. macOS 의 UserDefaults 자리입니다.
        panel.OpenUserPresets(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Negaflow",
            "Development",
            "user-presets.json"));
        FilmStockSelector.ItemsSource = BundledFilmBaseOptions.FilmStocks;
        LightSourceSelector.ItemsSource = BundledFilmBaseOptions.LightSources;
        ExposureControl.Minimum = -panel.MaximumExposureStops;
        ExposureControl.Maximum = panel.MaximumExposureStops;
        HistogramView.ConfigureRanges(panel.MaximumExposureStops, panel.MaximumToneControl);
        foreach (InspectorSlider slider in new[]
                 {
                     ContrastControl,
                     HighlightsControl,
                     ShadowsControl,
                     WhitesControl,
                     BlacksControl,
                     DensityControl,
                     CurveHighlightsControl,
                     CurveLightsControl,
                     CurveDarksControl,
                     CurveShadowsControl,
                     RedPrimaryHueControl,
                     RedPrimarySaturationControl,
                     GreenPrimaryHueControl,
                     GreenPrimarySaturationControl,
                     BluePrimaryHueControl,
                     BluePrimarySaturationControl,
                     ClarityControl,
                     VignetteControl,
                 })
        {
            slider.Minimum = -panel.MaximumToneControl;
            slider.Maximum = panel.MaximumToneControl;
        }
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
        foreach (InspectorSlider slider in new[] { BaseRedControl, BaseGreenControl, BaseBlueControl })
        {
            slider.Minimum = panel.MinimumManualDmin;
            slider.Maximum = panel.MaximumManualDmin;
        }
        StraightenAngleControl.Minimum = -45;
        StraightenAngleControl.Maximum = 45;
        // 미리보기는 캔버스에 맞는 크기면 충분합니다. 전체 해상도로 그리면 슬라이더를 끄는
        // 동안 엔진이 밀립니다.
        // 이 메서드는 UI 스레드에서만 불리므로 여기서 dispatcher 를 잡을 수 있습니다.
        if (DispatcherQueueUiDispatcher.CaptureForCurrentThread() is { } uiDispatcher)
        {
            previewCoordinator = new PreviewCoordinator(
                new NativeDevelopExporterAdapter(),
                uiDispatcher,
                1600,
                1200);
            grainMendDetectCoordinator = new GrainMendDetectCoordinator(
                new NativeDevelopExporterAdapter(),
                uiDispatcher);
            autoAdjustCoordinator = new AutoAdjustCoordinator(
                new NativeDevelopExporterAdapter(),
                uiDispatcher);
        }
        RefreshFrames();
    }

    private void RefreshFrames()
    {
        if (libraryHost is null)
        {
            return;
        }

        IReadOnlyList<LibraryFrameListItem> items =
            LibraryFrameListItems.From(libraryHost.Frames);
        bool hasFrames = items.Count > 0;
        FramePanel.Visibility = hasFrames ? Visibility.Visible : Visibility.Collapsed;
        NoFrameLeftPanel.Visibility = hasFrames ? Visibility.Collapsed : Visibility.Visible;
        NoFrameCard.Visibility = hasFrames ? Visibility.Collapsed : Visibility.Visible;
        DevelopInspectorContent.Visibility = hasFrames ? Visibility.Visible : Visibility.Collapsed;
        if (!hasFrames)
        {
            FrameSelector.ItemsSource = null;
            Filmstrip.ShowFrames([], -1);
            HistogramView.Clear();
            SyncToneControls();
            NotifyQuickExportAvailabilityChanged();
            return;
        }

        FrameSelector.ItemsSource = items;
        FrameSelector.SelectedIndex = 0;
        // 필름스트립과 왼쪽 목록은 같은 항목을 봅니다. 썸네일이 도착하면 둘 다 채워집니다.
        Filmstrip.ShowFrames(items, 0);
        foreach (LibraryFrameListItem item in items)
        {
            if (thumbnails?.TryGet(item.Id) is not null)
            {
                continue;
            }
            thumbnails?.Request(item.Frame);
        }
    }

    private void OnFilmstripFrameSelected(object? sender, LibraryFrameListItem item)
    {
        _ = sender;
        SelectFrame(item.Id);
    }

    /// <summary>
    /// 라이브러리에서 넘어온 frame 을 고릅니다. 목록에 없으면 아무 것도 바꾸지 않습니다 —
    /// 방금 지워진 frame 때문에 보고 있던 사진이 바뀌지 않게 합니다.
    /// </summary>
    public void SelectFrame(string frameId)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        if (FrameSelector.ItemsSource is not IReadOnlyList<LibraryFrameListItem> current)
        {
            return;
        }
        for (int index = 0; index < current.Count; ++index)
        {
            if (string.Equals(current[index].Id, frameId, StringComparison.Ordinal))
            {
                FrameSelector.SelectedIndex = index;
                return;
            }
        }
    }

    private void OnThumbnailReady(string frameId)
    {
        if (FrameSelector.ItemsSource is not IReadOnlyList<LibraryFrameListItem> current ||
            thumbnails?.TryGet(frameId) is not { } jpeg)
        {
            return;
        }
        foreach (LibraryFrameListItem item in current)
        {
            if (string.Equals(item.Id, frameId, StringComparison.Ordinal))
            {
                item.Thumbnail = LibraryWorkspaceView.DecodeThumbnail(jpeg);
                return;
            }
        }
    }

    private void OnInspectorTabClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (!isInspectorPresentationReady ||
            isSynchronizingInspectorPresentation ||
            sender is not ToggleButton { Tag: string tag } ||
            !Enum.TryParse(tag, out DevelopInspectorTab tab))
        {
            return;
        }

        if (tab != DevelopInspectorTab.Edit)
        {
            CancelCrop();
        }

        inspectorPresentation.SelectTab(tab);
        ApplyInspectorPresentation();
    }

    private void OnInspectorSectionHeaderClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (!isInspectorPresentationReady ||
            isSynchronizingInspectorPresentation ||
            sender is not Button { Tag: string tag } ||
            !Enum.TryParse(tag, out DevelopInspectorSection section))
        {
            return;
        }

        if (inspectorPresentation.ExpandedSection == section)
        {
            inspectorPresentation.Collapse(section);
        }
        else
        {
            inspectorPresentation.Expand(section);
        }
        ApplyInspectorPresentation();
    }

    private void OnInspectorSectionExpansionRequested(
        object? sender,
        DisclosureExpansionRequestedEventArgs args)
    {
        if (!isInspectorPresentationReady ||
            isSynchronizingInspectorPresentation ||
            sender is not DisclosureButton { Tag: string tag } ||
            !Enum.TryParse(tag, out DevelopInspectorSection section))
        {
            return;
        }

        if (args.IsExpanded)
        {
            inspectorPresentation.Expand(section);
        }
        else
        {
            inspectorPresentation.Collapse(section);
        }
        ApplyInspectorPresentation();
    }

    private void ApplyInspectorPresentation()
    {
        if (!isInspectorPresentationReady)
        {
            return;
        }

        isSynchronizingInspectorPresentation = true;
        BasicTabButton.IsChecked = inspectorPresentation.SelectedTab == DevelopInspectorTab.Basic;
        BaseTabButton.IsChecked = inspectorPresentation.SelectedTab == DevelopInspectorTab.Base;
        EditTabButton.IsChecked = inspectorPresentation.SelectedTab == DevelopInspectorTab.Edit;
        DefectsTabButton.IsChecked = inspectorPresentation.SelectedTab == DevelopInspectorTab.Defects;
        InfoTabButton.IsChecked = inspectorPresentation.SelectedTab == DevelopInspectorTab.Info;
        ResetTabButton.IsChecked = inspectorPresentation.SelectedTab == DevelopInspectorTab.Reset;
        BaseControlCard.Visibility = inspectorPresentation.SelectedTab == DevelopInspectorTab.Base
            ? Visibility.Visible
            : Visibility.Collapsed;
        InfoCard.Visibility = inspectorPresentation.SelectedTab == DevelopInspectorTab.Info
            ? Visibility.Visible
            : Visibility.Collapsed;
        GrainMendCard.Visibility = inspectorPresentation.SelectedTab == DevelopInspectorTab.Defects
            ? Visibility.Visible
            : Visibility.Collapsed;
        if (inspectorPresentation.SelectedTab != DevelopInspectorTab.Defects)
        {
            // 탭을 떠나면 도구도 놓습니다. 보이지 않는 도구가 캔버스를 잡고 있으면
            // 크롭이나 확대가 먹지 않는 것처럼 보입니다.
            SetGrainMendTool(GrainMendTool.None);
        }
        UpdateInfoCard();
        UpdateGrainMendCard();
        GeometryControlCard.Visibility = inspectorPresentation.SelectedTab == DevelopInspectorTab.Edit
            ? Visibility.Visible
            : Visibility.Collapsed;
        CommonAdjustmentStack.Visibility = inspectorPresentation.ShowsAdjustmentSections
            ? Visibility.Visible
            : Visibility.Collapsed;
        ApplyInspectorSectionState(
            DevelopInspectorSection.Tone,
            BasicToneHeaderButton,
            BasicToneChevron,
            BasicToneControls);
        ApplyInspectorSectionState(
            DevelopInspectorSection.ToneCurve,
            ToneCurveHeaderButton,
            ToneCurveChevron,
            ToneCurveControls);
        ApplyInspectorSectionState(
            DevelopInspectorSection.Color,
            ColorHeaderButton,
            ColorChevron,
            ColorControls);
        ApplyInspectorSectionState(
            DevelopInspectorSection.ColorMixer,
            ColorMixerHeaderButton,
            ColorMixerChevron,
            ColorMixerEditor);
        ApplyInspectorSectionState(
            DevelopInspectorSection.ColorGrading,
            ColorGradingHeaderButton,
            ColorGradingChevron,
            ColorGradingEditor);
        ApplyInspectorSectionState(
            DevelopInspectorSection.BlackAndWhiteToning,
            BwToningHeaderButton,
            BwToningChevron,
            BwToningControls);
        ApplyInspectorSectionState(
            DevelopInspectorSection.Calibration,
            CalibrationHeaderButton,
            CalibrationChevron,
            CalibrationControls);
        ApplyInspectorSectionState(
            DevelopInspectorSection.DetailAndEffects,
            DetailAndEffectsHeaderButton,
            DetailAndEffectsChevron,
            DetailAndEffectsControls);
        isSynchronizingInspectorPresentation = false;
    }

    private void ApplyInspectorSectionState(
        DevelopInspectorSection section,
        DisclosureButton header,
        FontIcon chevron,
        FrameworkElement content)
    {
        bool isExpanded = inspectorPresentation.ExpandedSection == section;
        header.IsExpanded = isExpanded;
        chevron.Glyph = isExpanded ? "\uE70D" : "\uE76C";
        content.Visibility = isExpanded ? Visibility.Visible : Visibility.Collapsed;
    }

    private async void OnImportClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (libraryHost is null || importWindowId is null)
        {
            return;
        }

        // Windows App SDK 1.8 의 picker 는 WindowId 를 받으므로 InitializeWithWindow 가
        // 필요 없습니다. 미패키지 구성에서도 그대로 동작합니다.
        Microsoft.Windows.Storage.Pickers.FileOpenPicker picker = new(importWindowId.Value)
        {
            CommitButtonText = "Import",
        };
        foreach (string extension in ImageSourcePaths.SupportedImportExtensions)
        {
            picker.FileTypeFilter.Add(extension);
        }

        ImportButton.IsEnabled = false;
        try
        {
            IReadOnlyList<Microsoft.Windows.Storage.Pickers.PickFileResult> picked =
                await picker.PickMultipleFilesAsync();
            List<string> paths = [];
            foreach (Microsoft.Windows.Storage.Pickers.PickFileResult file in picked)
            {
                paths.Add(file.Path);
            }

            FrameImportPlan plan = libraryHost.Import(paths, DevelopmentProcess.C41);
            ImportStatusText.Text = FrameImport.Describe(plan);
            RefreshFrames();
        }
        catch (Exception error)
        {
            // async void 는 예외를 삼킵니다. 잡지 않으면 버튼을 눌러도 아무 일도 일어나지 않고
            // 이유도 알 수 없습니다.
            ImportStatusText.Text = $"Import failed: {error.GetType().Name}: {error.Message}";
        }
        finally
        {
            ImportButton.IsEnabled = true;
        }
    }

    private void OnFrameSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || FrameSelector.SelectedItem is not LibraryFrameListItem item)
        {
            return;
        }

        CancelCrop();
        panel.Select(item.Id);
        Filmstrip.SynchronizeSelection(FrameSelector.SelectedIndex);
        UpdateSelectedFrameText();
        SynchronizeInspectorValues();
        SyncBaseControls();
        SyncToneControls();
        NotifyQuickExportAvailabilityChanged();
        ExportStatusText.Text = item.CanDevelop
            ? string.Empty
            : DevelopPanelState.Describe(new DevelopExportOutcome(
                DevelopExportOutcomeKind.Refused,
                null,
                RefusalFor(item.Frame),
                null));
        RequestPreview();
    }

    private void SynchronizeInspectorValues()
    {
        if (panel is null)
        {
            return;
        }

        isSynchronizingInspector = true;
        ExposureControl.Value = panel.Exposure;
        ContrastControl.Value = panel.Contrast;
        HighlightsControl.Value = panel.Highlights;
        ShadowsControl.Value = panel.Shadows;
        WhitesControl.Value = panel.Whites;
        BlacksControl.Value = panel.Blacks;
        DensityControl.Value = panel.Density;
        CurveHighlightsControl.Value = panel.CurveHighlights;
        CurveLightsControl.Value = panel.CurveLights;
        CurveDarksControl.Value = panel.CurveDarks;
        CurveShadowsControl.Value = panel.CurveShadows;
        PointCurveEditor.Curves = panel.PointCurves;
        ColorMixerEditor.Mixer = panel.ColorMixer;
        ColorGradingEditor.Grading = panel.ColorGrading;
        ColorModelRecipe colorModel = panel.ColorModel;
        WarmthControl.Value = colorModel.Warmth;
        TintControl.Value = colorModel.Tint;
        VibranceControl.Value = colorModel.Vibrance;
        SaturationControl.Value = colorModel.Saturation;
        ColorDepthControl.Value = colorModel.ColorDepth;
        BwToningRecipe bwToning = panel.BwToning;
        // macOS 는 흑백 필름에서만 이 섹션을 냅니다.
        BwToningSection.Visibility = panel.ShowsBwToning
            ? Visibility.Visible
            : Visibility.Collapsed;
        BwToningModeSelector.SelectedIndex = bwToning.Mode switch
        {
            Catalog.BwToningMode.Selenium => 1,
            Catalog.BwToningMode.Sepia => 2,
            _ => 0,
        };
        // 끈 상태에서는 세기와 색조가 뜻이 없어 macOS 도 자리째 감춥니다.
        BwToningTintControls.Visibility = bwToning.Mode == Catalog.BwToningMode.None
            ? Visibility.Collapsed
            : Visibility.Visible;
        BwToningStrengthControl.Value = bwToning.ClampedStrength;
        BwToningShadowHueControl.Value = bwToning.ShadowHue;
        BwToningHighlightHueControl.Value = bwToning.HighlightHue;
        PrimaryCalibrationRecipe calibration = panel.PrimaryCalibration;
        RedPrimaryHueControl.Value = calibration.RedHue;
        RedPrimarySaturationControl.Value = calibration.RedSaturation;
        GreenPrimaryHueControl.Value = calibration.GreenHue;
        GreenPrimarySaturationControl.Value = calibration.GreenSaturation;
        BluePrimaryHueControl.Value = calibration.BlueHue;
        BluePrimarySaturationControl.Value = calibration.BlueSaturation;
        NoiseReductionRecipe noiseReduction = panel.NoiseReduction;
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
        TextureRecipe texture = panel.Texture;
        GrainControl.Value = texture.Grain;
        SharpnessControl.Value = texture.Sharpness;
        ClarityControl.Value = texture.Clarity;
        HalationControl.Value = texture.Halation;
        VignetteControl.Value = texture.Vignette;
        StraightenAngleControl.Value = panel.ImageTransform.StraightenAngle;
        CropAngleDialControl.Angle = panel.ImageTransform.StraightenAngle;
        // macOS 는 음화에서만 두 토글을 냅니다. 양화에서는 자리째 사라집니다.
        Visibility autoCorrections = panel.ShowsAutoCorrections
            ? Visibility.Visible
            : Visibility.Collapsed;
        AutoColorToggle.Visibility = autoCorrections;
        AutoLevelsToggle.Visibility = autoCorrections;
        AutoColorToggle.IsChecked = panel.AutoNeutralBalance;
        AutoLevelsToggle.IsChecked = panel.AutoLevels;
        UpdateCropAspectControls();
        UpdateFilmLookControls();
        UpdateVersionControls();
        UpdatePresetControls();
        HistogramView.SynchronizeValues(
            panel.Shadows,
            panel.Density,
            panel.Exposure,
            panel.Highlights);
        // Auto에는 수동 base가 없으므로 slider에는 시작 위치만 보입니다. 사용자가 값을 바꾸면
        // manual mode로 전환되며, 그 전까지 preview/export는 native Auto resolver를 사용합니다.
        ManualBaseRgb shown = panel.ManualBase ?? new ManualBaseRgb(
            panel.SuggestedManualDmin,
            panel.SuggestedManualDmin,
            panel.SuggestedManualDmin);
        BaseRedControl.Value = shown.Red;
        BaseGreenControl.Value = shown.Green;
        BaseBlueControl.Value = shown.Blue;
        isSynchronizingInspector = false;
    }

    private void OnManualBaseChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizingInspector)
        {
            return;
        }

        panel.SetManualBase(
            BaseRedControl.Value,
            BaseGreenControl.Value,
            BaseBlueControl.Value);
        SyncBaseControls();
        // slider 변경은 Auto를 Manual로 전환합니다. 선택 행과 export 상태도 즉시 같은 snapshot으로
        // 갱신해야 preview/export의 요청 mode가 화면과 어긋나지 않습니다.
        UpdateSelectedFrameText();
        NotifyQuickExportAvailabilityChanged();
        if (panel.SelectedFrame is { CanDevelop: true })
        {
            ExportStatusText.Text = string.Empty;
        }
        RequestPreview();
    }

    private void UpdateSelectedFrameText()
    {
        if (panel?.SelectedFrame is { } frame)
        {
            SelectedFrameText.Text = new LibraryFrameListItem(frame).Detail;
        }
    }

    /// <summary>
    /// 현재 선택을 미리보기로 그립니다. 겹쳐 들어온 요청은 coordinator 가 합치되 마지막 것은
    /// 반드시 그리므로, 슬라이더를 끌어도 최종 상태가 화면에 남습니다.
    /// </summary>
    private void RequestPreview()
    {
        if (previewCoordinator is null || panel?.SelectedFrame is not { } frame)
        {
            return;
        }
        _ = previewCoordinator.RequestAsync(frame, ShowPreview);
    }

    private void ShowPreview(PreviewOutcome outcome)
    {
        if (outcome.Kind != DevelopExportOutcomeKind.Completed ||
            outcome.Pixels is not { } pixels ||
            outcome.Width == 0U ||
            outcome.Height == 0U)
        {
            PreviewImage.Visibility = Visibility.Collapsed;
            EmptyCanvasPanel.Visibility = Visibility.Visible;
            HistogramView.Clear();
            // 현상이 실패한 것과 사진이 없는 것은 다릅니다. 같은 빈 화면만 내면 사용자는
            // 사진을 넣으라는 말을 다시 읽을 뿐이고, 무엇이 잘못됐는지 알 길이 없습니다.
            string reason = outcome.Kind == DevelopExportOutcomeKind.Completed
                ? $"{outcome.Result?.FailedStage} {outcome.Result?.FailureName}"
                : outcome.Refusal.ToString();
            ExportStatusText.Text =
                $"{AppResources.Get("developPreviewFailed", "Text")} ({reason})";
            return;
        }

        int width = (int)outcome.Width;
        int height = (int)outcome.Height;
        // 크기가 바뀔 때만 새로 만듭니다. 슬라이더를 끄는 동안 매 프레임 할당하지 않기 위해서입니다.
        if (previewBitmap is null ||
            previewBitmap.PixelWidth != width ||
            previewBitmap.PixelHeight != height)
        {
            previewBitmap = new WriteableBitmap(width, height);
            PreviewImage.Source = previewBitmap;
        }

        int written = width * height * 4;
        using (Stream buffer = previewBitmap.PixelBuffer.AsStream())
        {
            buffer.Write(pixels, 0, written);
        }
        previewBitmap.Invalidate();
        HistogramView.UpdatePixels(pixels, width, height);
        // 방금 현상한 그림이 곧 라이브러리 카드의 썸네일입니다. 같은 픽셀을 두 번 만들지
        // 않으려고 여기서 넘깁니다.
        if (panel?.SelectedFrame is { } settled)
        {
            thumbnails?.Publish(settled.Id, pixels, width, height);
        }

        PreviewImage.Visibility = Visibility.Visible;
        EmptyCanvasPanel.Visibility = Visibility.Collapsed;
        if (cropAwaitingPreview)
        {
            cropAwaitingPreview = false;
        }
        RenderCropOverlay();
    }

    private void OnCropClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (cropSession is not null)
        {
            CancelCrop();
            return;
        }
        if (panel is null || panel.SelectedFrame is null || PreviewImage.Visibility != Visibility.Visible)
        {
            return;
        }

        CropSession next = CropSession.Start(panel.ImageTransform.Crop);
        next.LockedNormalizedAspectRatio = LockedNormalizedAspectRatio();
        // macOS와 같이 crop을 먼저 해제해 전체 프레임에서 새 선택을 만들게 합니다. 드래그 중
        // catalog를 쓰지 않고 Apply/Cancel에서 한 번만 저장합니다.
        if (panel.SetCrop(null) != LibraryFrameError.None)
        {
            return;
        }
        cropSession = next;
        CropAngleDialControl.Visibility = Visibility.Visible;
        cropAwaitingPreview = true;
        CanvasHost.Focus(FocusState.Programmatic);
        RequestPreview();
    }

    private void OnCropApplyClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (cropSession is null || panel is null)
        {
            return;
        }
        if (panel.SetCrop(cropSession.Apply()) != LibraryFrameError.None)
        {
            return;
        }
        EndCropSession();
        RequestPreview();
    }

    private void OnCropFullClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (cropSession is null)
        {
            return;
        }
        cropSession.Full();
        RenderCropOverlay();
    }

    private void OnCropCancelClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        CancelCrop();
    }

    private void CancelCrop()
    {
        if (cropSession is null)
        {
            return;
        }
        ImageCropRect? restore = cropSession.Cancel();
        if (panel?.SetCrop(restore) != LibraryFrameError.None)
        {
            return;
        }
        EndCropSession();
        RequestPreview();
    }

    private void EndCropSession()
    {
        cropSession = null;
        cropDragMode = CropDragMode.None;
        cropAwaitingPreview = false;
        CropOverlay.Visibility = Visibility.Collapsed;
        CropAngleDialControl.Visibility = Visibility.Collapsed;
    }

    private void OnCanvasSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        RenderCropOverlay();
    }

    private void OnCanvasPointerPressed(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (TryBeginGrainMendStroke(args))
        {
            args.Handled = true;
            return;
        }
        if (cropSession is null || cropAwaitingPreview || !TryCanvasUnitPoint(args, out CropDisplayPoint point))
        {
            return;
        }

        cropDragStart = point;
        cropDragStartRect = cropSession.Selection;
        cropDragMode = HitCropHandle(point, cropDragStartRect) ??
            (Contains(cropDragStartRect, point) && !cropDragStartRect.IsFull
                ? CropDragMode.Move
                : CropDragMode.Create);
        CanvasHost.CapturePointer(args.Pointer);
        args.Handled = true;
    }

    private void OnCanvasPointerMoved(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (TryContinueGrainMendStroke(args))
        {
            args.Handled = true;
            return;
        }
        if (cropSession is null || cropDragMode == CropDragMode.None ||
            !TryCanvasUnitPoint(args, out CropDisplayPoint point))
        {
            return;
        }

        switch (cropDragMode)
        {
            case CropDragMode.Create:
                cropSession.Select(cropDragStart, point);
                break;
            case CropDragMode.Move:
                cropSession.SetSelection(cropDragStartRect.Move(
                    point.X - cropDragStart.X,
                    point.Y - cropDragStart.Y));
                break;
            default:
                cropSession.SetSelection(cropDragStartRect.Resize(ToCropHandle(cropDragMode), point));
                break;
        }
        RenderCropOverlay();
        args.Handled = true;
    }

    private void OnCanvasPointerReleased(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (TryFinishGrainMendStroke(args))
        {
            args.Handled = true;
            return;
        }
        EndCropDrag(args);
    }

    private void OnCanvasPointerCancelled(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        EndCropDrag(args);
    }

    private void OnCanvasPointerCaptureLost(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        EndCropDrag(args);
    }

    private void EndCropDrag(PointerRoutedEventArgs args)
    {
        if (cropDragMode == CropDragMode.None)
        {
            return;
        }
        CanvasHost.ReleasePointerCapture(args.Pointer);
        cropDragMode = CropDragMode.None;
        args.Handled = true;
    }

    private void OnCanvasKeyDown(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        // 검토 중인 검출이 있으면 그것이 먼저입니다. 도움말이 안내하는 대로 Enter 가 받아들이고
        // Esc 가 버립니다.
        if (pendingDefectEdit is not null)
        {
            if (args.Key == VirtualKey.Enter)
            {
                AcceptPendingDefectEdit();
                args.Handled = true;
                return;
            }
            if (args.Key == VirtualKey.Escape)
            {
                ClearPendingDefectEdit();
                ExportStatusText.Text = string.Empty;
                UpdateGrainMendCard();
                args.Handled = true;
                return;
            }
        }
        if (cropSession is null)
        {
            return;
        }
        if (args.Key == VirtualKey.Escape)
        {
            CancelCrop();
            args.Handled = true;
            return;
        }

        double step = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift)
            .HasFlag(CoreVirtualKeyStates.Down) ? 0.02 : 0.005;
        switch (args.Key)
        {
            case VirtualKey.Left:
                cropSession.Move(-step, 0.0);
                break;
            case VirtualKey.Right:
                cropSession.Move(step, 0.0);
                break;
            case VirtualKey.Up:
                cropSession.Move(0.0, -step);
                break;
            case VirtualKey.Down:
                cropSession.Move(0.0, step);
                break;
            default:
                return;
        }
        RenderCropOverlay();
        args.Handled = true;
    }

    private bool TryCanvasUnitPoint(PointerRoutedEventArgs args, out CropDisplayPoint point)
    {
        Windows.Foundation.Point position = args.GetCurrentPoint(CanvasHost).Position;
        if (!TryGetPreviewFrame(out double left, out double top, out double width, out double height) ||
            position.X < left || position.X > left + width || position.Y < top || position.Y > top + height)
        {
            point = default;
            return false;
        }
        point = new CropDisplayPoint((position.X - left) / width, (position.Y - top) / height).Clamp();
        return true;
    }

    private bool TryGetPreviewFrame(out double left, out double top, out double width, out double height)
    {
        left = top = width = height = 0.0;
        if (previewBitmap is null || CanvasHost.ActualWidth <= 0.0 || CanvasHost.ActualHeight <= 0.0)
        {
            return false;
        }
        double availableWidth = Math.Max(1.0, CanvasHost.ActualWidth - 48.0);
        double availableHeight = Math.Max(1.0, CanvasHost.ActualHeight - 48.0);
        double scale = Math.Min(availableWidth / previewBitmap.PixelWidth, availableHeight / previewBitmap.PixelHeight);
        width = previewBitmap.PixelWidth * scale;
        height = previewBitmap.PixelHeight * scale;
        left = (CanvasHost.ActualWidth - width) / 2.0;
        top = (CanvasHost.ActualHeight - height) / 2.0;
        return width > 0.0 && height > 0.0;
    }

    private void RenderCropOverlay()
    {
        if (cropSession is null || cropAwaitingPreview ||
            !TryGetPreviewFrame(out double left, out double top, out double width, out double height))
        {
            CropOverlay.Visibility = Visibility.Collapsed;
            return;
        }

        CropDisplayRect selection = cropSession.Selection;
        double cropLeft = left + selection.X * width;
        double cropTop = top + selection.Y * height;
        double cropWidth = selection.Width * width;
        double cropHeight = selection.Height * height;
        CropOverlay.Visibility = Visibility.Visible;
        Place(CropDimTop, left, top, width, Math.Max(0.0, cropTop - top));
        Place(CropDimBottom, left, cropTop + cropHeight, width, Math.Max(0.0, top + height - (cropTop + cropHeight)));
        Place(CropDimLeft, left, cropTop, Math.Max(0.0, cropLeft - left), cropHeight);
        Place(CropDimRight, cropLeft + cropWidth, cropTop, Math.Max(0.0, left + width - (cropLeft + cropWidth)), cropHeight);
        Place(CropSelection, cropLeft, cropTop, cropWidth, cropHeight);
        CropThirdVerticalFirst.X1 = CropThirdVerticalFirst.X2 = cropLeft + cropWidth / 3.0;
        CropThirdVerticalFirst.Y1 = cropTop;
        CropThirdVerticalFirst.Y2 = cropTop + cropHeight;
        CropThirdVerticalSecond.X1 = CropThirdVerticalSecond.X2 = cropLeft + cropWidth * 2.0 / 3.0;
        CropThirdVerticalSecond.Y1 = cropTop;
        CropThirdVerticalSecond.Y2 = cropTop + cropHeight;
        CropThirdHorizontalFirst.X1 = cropLeft;
        CropThirdHorizontalFirst.X2 = cropLeft + cropWidth;
        CropThirdHorizontalFirst.Y1 = CropThirdHorizontalFirst.Y2 = cropTop + cropHeight / 3.0;
        CropThirdHorizontalSecond.X1 = cropLeft;
        CropThirdHorizontalSecond.X2 = cropLeft + cropWidth;
        CropThirdHorizontalSecond.Y1 = CropThirdHorizontalSecond.Y2 = cropTop + cropHeight * 2.0 / 3.0;
        PlaceHandle(CropHandleTopLeft, cropLeft, cropTop, false, false);
        PlaceHandle(CropHandleTop, cropLeft + cropWidth / 2.0, cropTop, true, false);
        PlaceHandle(CropHandleTopRight, cropLeft + cropWidth, cropTop, false, false);
        PlaceHandle(CropHandleRight, cropLeft + cropWidth, cropTop + cropHeight / 2.0, false, true);
        PlaceHandle(CropHandleBottomRight, cropLeft + cropWidth, cropTop + cropHeight, false, false);
        PlaceHandle(CropHandleBottom, cropLeft + cropWidth / 2.0, cropTop + cropHeight, true, false);
        PlaceHandle(CropHandleBottomLeft, cropLeft, cropTop + cropHeight, false, false);
        PlaceHandle(CropHandleLeft, cropLeft, cropTop + cropHeight / 2.0, false, true);
        // macOS는 막대 중심을 (crop 하단 + 30)에 두고 이미지 프레임 안쪽 86/28pt로 가둡니다.
        double barHalfHeight = CropActionBar.ActualHeight > 0 ? CropActionBar.ActualHeight / 2.0 : 21.0;
        Canvas.SetLeft(CropActionBar, Math.Clamp(cropLeft + cropWidth / 2.0, left + 86.0, Math.Max(left + 86.0, left + width - 86.0)) - 86.0);
        Canvas.SetTop(CropActionBar, Math.Clamp(cropTop + cropHeight + 30.0, top + 28.0, Math.Max(top + 28.0, top + height - 28.0)) - barHalfHeight);
    }

    private static void Place(FrameworkElement element, double left, double top, double width, double height)
    {
        element.Width = width;
        element.Height = height;
        Canvas.SetLeft(element, left);
        Canvas.SetTop(element, top);
    }

    private static void PlaceHandle(FrameworkElement element, double centerX, double centerY, bool horizontal, bool vertical)
    {
        double width = horizontal ? 24.0 : 14.0;
        double height = vertical ? 24.0 : 14.0;
        Place(element, centerX - width / 2.0, centerY - height / 2.0, width, height);
    }

    private static bool Contains(CropDisplayRect rect, CropDisplayPoint point) =>
        point.X >= rect.X && point.X <= rect.Right && point.Y >= rect.Y && point.Y <= rect.Bottom;

    private static CropDragMode? HitCropHandle(CropDisplayPoint point, CropDisplayRect rect)
    {
        const double radius = 0.025;
        foreach ((CropDragMode mode, double x, double y) candidate in new[]
                 {
                     (CropDragMode.TopLeft, rect.X, rect.Y),
                     (CropDragMode.Top, rect.X + rect.Width / 2.0, rect.Y),
                     (CropDragMode.TopRight, rect.Right, rect.Y),
                     (CropDragMode.Right, rect.Right, rect.Y + rect.Height / 2.0),
                     (CropDragMode.BottomRight, rect.Right, rect.Bottom),
                     (CropDragMode.Bottom, rect.X + rect.Width / 2.0, rect.Bottom),
                     (CropDragMode.BottomLeft, rect.X, rect.Bottom),
                     (CropDragMode.Left, rect.X, rect.Y + rect.Height / 2.0),
                 })
        {
            if (Math.Abs(point.X - candidate.x) <= radius && Math.Abs(point.Y - candidate.y) <= radius)
            {
                return candidate.mode;
            }
        }
        return null;
    }

    private static CropHandle ToCropHandle(CropDragMode mode) => mode switch
    {
        CropDragMode.TopLeft => CropHandle.TopLeft,
        CropDragMode.Top => CropHandle.Top,
        CropDragMode.TopRight => CropHandle.TopRight,
        CropDragMode.Right => CropHandle.Right,
        CropDragMode.BottomRight => CropHandle.BottomRight,
        CropDragMode.Bottom => CropHandle.Bottom,
        CropDragMode.BottomLeft => CropHandle.BottomLeft,
        CropDragMode.Left => CropHandle.Left,
        _ => throw new ArgumentOutOfRangeException(nameof(mode)),
    };

    private void UpdateManualBaseText()
    {
        if (panel?.SelectedFrame?.Base.Mode == BaseEstimationMode.Auto)
        {
            ManualBaseValueText.Text = "Auto";
            return;
        }
        if (panel?.SelectedFrame?.Base.Mode == BaseEstimationMode.Preset)
        {
            FilmStockOption? filmStock = BundledFilmBaseOptions.FilmStocks.FirstOrDefault(
                option => option.Id == panel.SelectedFrame.Base.FilmStockDminId);
            ManualBaseValueText.Text = filmStock?.Id is not null
                ? filmStock.DisplayName
                : panel.SelectedFrame.Base.FilmStockDminId is null
                    ? "Select film stock"
                    : "Film preset unavailable";
            return;
        }
        if (panel?.ManualBase is { } manualBase)
        {
            ManualBaseValueText.Text = string.Create(
                CultureInfo.CurrentCulture,
                $"{manualBase.Red:F3} / {manualBase.Green:F3} / {manualBase.Blue:F3}");
            return;
        }
        ManualBaseValueText.Text = "not set";
    }

    private void SyncBaseControls()
    {
        if (panel is null)
        {
            return;
        }

        bool canEdit = panel.CanEditBase;
        BaseAutoModeButton.IsEnabled = canEdit;
        BaseFilmModeButton.IsEnabled = canEdit;
        BaseManualModeButton.IsEnabled = canEdit;
        isSynchronizingInspector = true;
        BaseAutoModeButton.IsChecked = panel.BaseMode == BaseEstimationMode.Auto;
        BaseFilmModeButton.IsChecked = panel.BaseMode == BaseEstimationMode.Preset;
        BaseManualModeButton.IsChecked = panel.BaseMode == BaseEstimationMode.Manual;
        FilmStockSelector.SelectedItem = BundledFilmBaseOptions.FilmStocks.FirstOrDefault(
            option => option.Id == panel.SelectedFrame?.Base.FilmStockDminId);
        LightSourceSelector.SelectedItem = BundledFilmBaseOptions.LightSources.FirstOrDefault(
            option => option.Id == panel.SelectedFrame?.Base.LightSourceProfileId);
        isSynchronizingInspector = false;
        FilmBaseControls.Visibility = canEdit && panel.BaseMode == BaseEstimationMode.Preset
            ? Visibility.Visible
            : Visibility.Collapsed;
        FilmStockSelector.IsEnabled = canEdit && panel.BaseMode == BaseEstimationMode.Preset;
        LightSourceSelector.IsEnabled = canEdit && panel.BaseMode == BaseEstimationMode.Preset;
        ManualBaseControls.Visibility = canEdit && panel.BaseMode == BaseEstimationMode.Manual
            ? Visibility.Visible
            : Visibility.Collapsed;
        UpdateManualBaseText();
    }

    private void SyncToneControls()
    {
        bool canEdit = panel?.CanEditTone == true;
        foreach (InspectorSlider slider in new[]
                 {
                     ExposureControl,
                     ContrastControl,
                     HighlightsControl,
                     ShadowsControl,
                     WhitesControl,
                     BlacksControl,
                     DensityControl,
                     CurveHighlightsControl,
                     CurveLightsControl,
                     CurveDarksControl,
                     CurveShadowsControl,
                 })
        {
            slider.IsEnabled = canEdit;
        }
        PointCurveEditor.IsEnabled = canEdit;
        ColorMixerEditor.IsEnabled = canEdit;
        ColorGradingEditor.IsEnabled = canEdit;
        foreach (InspectorSlider slider in new[]
                 {
                     RedPrimaryHueControl,
                     RedPrimarySaturationControl,
                     GreenPrimaryHueControl,
                     GreenPrimarySaturationControl,
                     BluePrimaryHueControl,
                     BluePrimarySaturationControl,
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
            slider.IsEnabled = canEdit;
        }
        NoiseReductionToggle.IsEnabled = canEdit;
        StraightenAngleControl.IsEnabled = canEdit;
        CropAspectButton.IsEnabled = canEdit;
        CropAspectLockButton.IsEnabled = canEdit;
        RotateLeftButton.IsEnabled = canEdit;
        RotateRightButton.IsEnabled = canEdit;
        FlipHorizontalButton.IsEnabled = canEdit;
        FlipVerticalButton.IsEnabled = canEdit;
        HistogramView.IsEnabled = canEdit;
        bool canAutoAdjust = panel?.SelectedFrame?.CanDevelop == true &&
                             autoAdjustCoordinator is not null;
        AutoToneButton.IsEnabled = canAutoAdjust;
        AutoWhiteBalanceButton.IsEnabled = canAutoAdjust;
    }

    private void OnAutoColorToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingInspector)
        {
            return;
        }
        UpdateImageTransform(state =>
            state.SetAutoNeutralBalance(AutoColorToggle.IsChecked == true));
    }

    private void OnAutoLevelsToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingInspector)
        {
            return;
        }
        UpdateImageTransform(state => state.SetAutoLevels(AutoLevelsToggle.IsChecked == true));
    }

    private async void OnAutoToneClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        await RunAutoAdjustAsync(AutoAdjustOperation.Tone);
    }

    private async void OnAutoWhiteBalanceClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        await RunAutoAdjustAsync(AutoAdjustOperation.WhiteBalance);
    }

    private async Task RunAutoAdjustAsync(AutoAdjustOperation operation)
    {
        if (autoAdjustCoordinator is null || panel?.SelectedFrame is not { } frame)
        {
            return;
        }

        AutoToneButton.IsEnabled = false;
        AutoWhiteBalanceButton.IsEnabled = false;
        AutoAdjustStatusText.Text = string.Empty;
        Action<AutoAdjustOutcome> completed = outcome =>
        {
            if (outcome.Kind == DevelopExportOutcomeKind.Completed && outcome.Settings is not null &&
                panel?.SelectedFrame == frame)
            {
                LibraryFrameError error = operation == AutoAdjustOperation.Tone
                    ? panel.ApplyAutoTone(outcome.Settings)
                    : panel.ApplyAutoWhiteBalance(outcome.Settings);
                if (error == LibraryFrameError.None)
                {
                    SynchronizeInspectorValues();
                    RequestPreview();
                }
                else
                {
                    AutoAdjustStatusText.Text = AppResources.Get("developAutoAdjustFailed", "Text");
                }
            }
            else if (outcome.Kind != DevelopExportOutcomeKind.Completed)
            {
                AutoAdjustStatusText.Text = AppResources.Get("developAutoAdjustFailed", "Text");
            }
            SyncToneControls();
        };

        bool delivered = operation == AutoAdjustOperation.Tone
            ? await autoAdjustCoordinator.RunToneAsync(frame, completed)
            : await autoAdjustCoordinator.RunWhiteBalanceAsync(frame, completed);
        if (!delivered)
        {
            AutoAdjustStatusText.Text = AppResources.Get("developAutoAdjustFailed", "Text");
            SyncToneControls();
        }
    }

    private void OnBaseAutoModeChecked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetBaseMode(BaseEstimationMode.Auto);
    }

    private void OnBaseManualModeChecked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetBaseMode(BaseEstimationMode.Manual);
    }

    private void OnBaseFilmModeChecked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetBaseMode(BaseEstimationMode.Preset);
    }

    private void OnFilmStockSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizingInspector ||
            panel.SetFilmStock((FilmStockSelector.SelectedItem as FilmStockOption)?.Id) != LibraryFrameError.None)
        {
            return;
        }
        UpdateAfterBaseRecipeChanged();
    }

    private void OnLightSourceSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizingInspector ||
            panel.SetLightSourceProfile((LightSourceSelector.SelectedItem as LightSourceOption)?.Id) != LibraryFrameError.None)
        {
            return;
        }
        UpdateAfterBaseRecipeChanged();
    }

    private void SetBaseMode(BaseEstimationMode mode)
    {
        if (panel is null || isSynchronizingInspector || panel.SetBaseMode(mode) != LibraryFrameError.None)
        {
            return;
        }

        isSynchronizingInspector = true;
        ManualBaseRgb shown = panel.ManualBase ?? new ManualBaseRgb(
            panel.SuggestedManualDmin,
            panel.SuggestedManualDmin,
            panel.SuggestedManualDmin);
        BaseRedControl.Value = shown.Red;
        BaseGreenControl.Value = shown.Green;
        BaseBlueControl.Value = shown.Blue;
        isSynchronizingInspector = false;
        UpdateAfterBaseRecipeChanged();
    }

    private void UpdateAfterBaseRecipeChanged()
    {
        if (panel is null)
        {
            return;
        }

        SyncBaseControls();
        UpdateSelectedFrameText();
        NotifyQuickExportAvailabilityChanged();
        ExportStatusText.Text = string.Empty;
        RequestPreview();
    }

    private static DevelopRequestRefusal RefusalFor(LibraryFrameSnapshot frame)
    {
        if (frame.Route.FilmLookSource != FilmLookSource.FilmScan)
        {
            return DevelopRequestRefusal.UnsupportedDigitalSource;
        }
        if (frame.Route.FilmType is not (FilmType.ColorNegative or FilmType.BlackAndWhiteNegative))
        {
            return DevelopRequestRefusal.UnsupportedPositiveFilm;
        }
        return frame.Base.Mode switch
        {
            BaseEstimationMode.Preset when string.IsNullOrWhiteSpace(frame.Base.FilmStockDminId) =>
                DevelopRequestRefusal.MissingFilmStock,
            BaseEstimationMode.Manual when frame.ManualBase is null => DevelopRequestRefusal.MissingManualBase,
            _ => DevelopRequestRefusal.None,
        };
    }

    private void OnHistogramValueChanged(object? sender, DevelopHistogramValueChangedEventArgs args)
    {
        _ = sender;
        if (panel is null || isSynchronizingInspector)
        {
            return;
        }

        LibraryFrameError error = args.Region switch
        {
            DevelopHistogramRegion.Shadow => panel.SetShadows(args.Value),
            DevelopHistogramRegion.Density => panel.SetDensity(args.Value),
            DevelopHistogramRegion.Exposure => panel.SetExposure(args.Value),
            DevelopHistogramRegion.Highlight => panel.SetHighlights(args.Value),
            _ => LibraryFrameError.InvalidToneValue,
        };
        if (error == LibraryFrameError.None)
        {
            SynchronizeInspectorValues();
            RequestPreview();
        }
    }

    private void OnExposureChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        // 선택을 바꾸며 슬라이더를 맞출 때는 catalog 를 건드리지 않습니다.
        if (panel is null || isSynchronizingInspector)
        {
            return;
        }
        panel.SetExposure(args.Value);
        RequestPreview();
    }

    private void OnBasicToneChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        if (panel is null || isSynchronizingInspector)
        {
            return;
        }

        LibraryFrameError error = sender switch
        {
            InspectorSlider control when ReferenceEquals(control, ContrastControl) =>
                panel.SetContrast(args.Value),
            InspectorSlider control when ReferenceEquals(control, HighlightsControl) =>
                panel.SetHighlights(args.Value),
            InspectorSlider control when ReferenceEquals(control, ShadowsControl) =>
                panel.SetShadows(args.Value),
            InspectorSlider control when ReferenceEquals(control, WhitesControl) =>
                panel.SetWhites(args.Value),
            InspectorSlider control when ReferenceEquals(control, BlacksControl) =>
                panel.SetBlacks(args.Value),
            InspectorSlider control when ReferenceEquals(control, DensityControl) =>
                panel.SetDensity(args.Value),
            _ => LibraryFrameError.InvalidToneValue,
        };
        if (error == LibraryFrameError.None)
        {
            RequestPreview();
        }
    }

    private void OnToneCurveChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        if (panel is null || isSynchronizingInspector)
        {
            return;
        }

        LibraryFrameError error = sender switch
        {
            InspectorSlider control when ReferenceEquals(control, CurveHighlightsControl) =>
                panel.SetCurveHighlights(args.Value),
            InspectorSlider control when ReferenceEquals(control, CurveLightsControl) =>
                panel.SetCurveLights(args.Value),
            InspectorSlider control when ReferenceEquals(control, CurveDarksControl) =>
                panel.SetCurveDarks(args.Value),
            InspectorSlider control when ReferenceEquals(control, CurveShadowsControl) =>
                panel.SetCurveShadows(args.Value),
            _ => LibraryFrameError.InvalidToneValue,
        };
        if (error == LibraryFrameError.None)
        {
            RequestPreview();
        }
    }

    private void OnPointCurvesChanged(object? sender, ToneCurveChangedEventArgs args)
    {
        _ = sender;
        if (panel is null || isSynchronizingInspector)
        {
            return;
        }
        if (panel.SetPointCurves(args.Curves) == LibraryFrameError.None)
        {
            RequestPreview();
        }
    }

    private void OnColorMixerChanged(object? sender, ColorMixerChangedEventArgs args)
    {
        _ = sender;
        if (panel is null || isSynchronizingInspector)
        {
            return;
        }
        if (panel.SetColorMixer(args.Mixer) == LibraryFrameError.None)
        {
            RequestPreview();
        }
    }

    private void OnColorGradingChanged(object? sender, ColorGradingChangedEventArgs args)
    {
        _ = sender;
        if (panel is null || isSynchronizingInspector)
        {
            return;
        }
        if (panel.SetColorGrading(args.Grading) == LibraryFrameError.None)
        {
            RequestPreview();
        }
    }

    /// <summary>
    /// macOS 색상 섹션의 다섯 축입니다. 원색 세 축은 이 섹션에 없으므로 지금 값을 그대로 둡니다.
    /// </summary>
    private void OnColorModelChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizingInspector)
        {
            return;
        }
        if (panel.SetColorModel(panel.ColorModel with
            {
                Warmth = WarmthControl.Value,
                Tint = TintControl.Value,
                Vibrance = VibranceControl.Value,
                Saturation = SaturationControl.Value,
                ColorDepth = ColorDepthControl.Value,
            }) == LibraryFrameError.None)
        {
            RequestPreview();
        }
    }

    private void OnBwToningModeChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizingInspector ||
            BwToningModeSelector.SelectedItem is not ComboBoxItem { Tag: string tag } ||
            !Enum.TryParse(tag, out Catalog.BwToningMode mode))
        {
            return;
        }
        if (panel.SetBwToningMode(mode) == LibraryFrameError.None)
        {
            SynchronizeInspectorValues();
            RequestPreview();
        }
    }

    private void OnBwToningValueChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizingInspector)
        {
            return;
        }
        if (panel.SetBwToning(panel.BwToning with
            {
                Strength = BwToningStrengthControl.Value,
                ShadowHue = BwToningRecipe.NormalizeHue(BwToningShadowHueControl.Value),
                HighlightHue = BwToningRecipe.NormalizeHue(BwToningHighlightHueControl.Value),
            }) == LibraryFrameError.None)
        {
            RequestPreview();
        }
    }

    private void OnBwToningResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || panel.ResetBwToning() != LibraryFrameError.None)
        {
            return;
        }
        SynchronizeInspectorValues();
        RequestPreview();
    }

    private void OnPrimaryCalibrationChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizingInspector)
        {
            return;
        }
        if (panel.SetPrimaryCalibration(new PrimaryCalibrationRecipe(
                RedPrimaryHueControl.Value,
                RedPrimarySaturationControl.Value,
                GreenPrimaryHueControl.Value,
                GreenPrimarySaturationControl.Value,
                BluePrimaryHueControl.Value,
                BluePrimarySaturationControl.Value)) == LibraryFrameError.None)
        {
            RequestPreview();
        }
    }

    private void OnNoiseReductionToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizingInspector)
        {
            return;
        }
        if (panel.SetNoiseReductionEnabled(NoiseReductionToggle.IsOn) == LibraryFrameError.None)
        {
            SynchronizeInspectorValues();
            RequestPreview();
        }
    }

    private void OnNoiseReductionChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizingInspector)
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
            RequestPreview();
        }
    }

    private void OnTextureChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizingInspector)
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
            RequestPreview();
        }
    }

    private void OnRotateLeftClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateImageTransform(static state => state.Rotate(clockwise: false));
    }

    private void OnRotateRightClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateImageTransform(static state => state.Rotate(clockwise: true));
    }

    private void OnFlipHorizontalClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateImageTransform(static state => state.FlipHorizontally());
    }

    private void OnFlipVerticalClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateImageTransform(static state => state.FlipVertically());
    }

    private void OnStraightenAngleChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        if (isSynchronizingInspector)
        {
            return;
        }
        UpdateImageTransform(state => state.SetStraightenAngle(args.Value));
    }

    /// <summary>
    /// 현상 왼쪽 소스를 바꿉니다. 지금은 라이브러리와 출력 둘이며, 나머지 macOS 탭(필름·프리셋·
    /// 버전)은 아직 내용이 없어 막대에만 있습니다.
    /// </summary>
    private void OnDevelopSourceRailClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not Button { Tag: string tag } ||
            !Enum.TryParse(tag, out DevelopSourceKind kind))
        {
            return;
        }
        developSource = kind;
        UpdateDevelopSourcePanel();
    }

    /// <summary>현상 왼쪽 소스입니다. macOS 의 다섯 탭 중 지금 내용이 있는 넷입니다.</summary>
    private enum DevelopSourceKind
    {
        Library,
        Versions,
        Presets,
        Film,
        Output,
    }

    private void UpdateDevelopSourcePanel()
    {
        LibrarySourcePanel.Visibility = Show(DevelopSourceKind.Library);
        VersionsSourcePanel.Visibility = Show(DevelopSourceKind.Versions);
        PresetsSourcePanel.Visibility = Show(DevelopSourceKind.Presets);
        FilmSourcePanel.Visibility = Show(DevelopSourceKind.Film);
        OutputSourcePanel.Visibility = Show(DevelopSourceKind.Output);

        (string headerKey, string glyph) = developSource switch
        {
            DevelopSourceKind.Versions => ("developSectionVersions", ""),
            DevelopSourceKind.Presets => ("developSectionPresets", "\uE9E9"),
            DevelopSourceKind.Film => ("developSectionFilm", ""),
            DevelopSourceKind.Output => ("developSectionOutput", ""),
            _ => ("developLibrary", ""),
        };
        LibraryHeaderText.Text = AppResources.Get(headerKey, "Text");
        DevelopSourceIcon.Glyph = glyph;

        var accent = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["AccentTextFillColorPrimaryBrush"];
        var normal = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorPrimaryBrush"];
        var selection = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["NegaflowSelectionBrush"];
        foreach ((Button button, FontIcon icon, DevelopSourceKind kind) in DevelopSourceRailButtons())
        {
            bool selected = kind == developSource;
            button.Background = selected
                ? selection
                : new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent);
            icon.Foreground = selected ? accent : normal;
            AutomationProperties.SetItemStatus(
                button,
                AppResources.Get(selected ? "selected" : "notSelected", "Value"));
        }
        UpdateExportPreview();
        UpdateFilmLookControls();
        UpdatePresetControls();
    }

    private Visibility Show(DevelopSourceKind kind) =>
        developSource == kind ? Visibility.Visible : Visibility.Collapsed;

    private IEnumerable<(Button Button, FontIcon Icon, DevelopSourceKind Kind)> DevelopSourceRailButtons()
    {
        yield return (LibraryRailButton, LibraryRailIcon, DevelopSourceKind.Library);
        yield return (VersionsRailButton, VersionsRailIcon, DevelopSourceKind.Versions);
        yield return (PresetsRailButton, PresetsRailIcon, DevelopSourceKind.Presets);
        yield return (FilmRailButton, FilmRailIcon, DevelopSourceKind.Film);
        yield return (OutputRailButton, OutputRailIcon, DevelopSourceKind.Output);
    }

    private void OnCopyDevelopSettingsClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel?.CopyDevelopSettings() == true)
        {
            UpdatePresetControls();
        }
    }

    private void OnPasteDevelopSettingsClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || panel.PasteDevelopSettings() != LibraryFrameError.None)
        {
            return;
        }
        _ = panel.Save();
        ReloadAfterRecipeReplaced();
    }

    private void OnPasteScopeAllClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null)
        {
            return;
        }
        panel.PasteScope = DevelopSettingsPasteScope.All;
        UpdatePresetControls();
    }

    private void OnPasteScopeToggled(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (panel is null || sender is not ToggleMenuFlyoutItem { Tag: string group } item)
        {
            return;
        }
        DevelopSettingsPasteScope scope = panel.PasteScope;
        panel.PasteScope = group switch
        {
            "Base" => scope with { Base = item.IsChecked },
            "Tone" => scope with { Tone = item.IsChecked },
            "Color" => scope with { Color = item.IsChecked },
            "Detail" => scope with { Detail = item.IsChecked },
            "Geometry" => scope with { Geometry = item.IsChecked },
            _ => scope,
        };
        UpdatePresetControls();
    }

    private void OnUserPresetSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateUserPresetButtons();
    }

    private void OnSaveUserPresetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null)
        {
            return;
        }
        string name = AppResources.FormatIntegers(
            "developUserPresetNameFormat",
            "Value",
            panel.UserPresets.Count + 1);
        if (panel.SaveUserPreset(name) is not { } saved)
        {
            return;
        }
        // 방금 저장한 것을 고른 상태로 둡니다 — macOS 도 저장 직후 그 프리셋을 가리킵니다.
        UpdatePresetControls(saved.Id);
    }

    private void OnApplyUserPresetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null ||
            SelectedUserPresetId() is not { } id ||
            panel.ApplyUserPreset(id) != LibraryFrameError.None)
        {
            return;
        }
        _ = panel.Save();
        ReloadAfterRecipeReplaced();
    }

    private void OnDeleteUserPresetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || SelectedUserPresetId() is not { } id || !panel.DeleteUserPreset(id))
        {
            return;
        }
        UpdatePresetControls();
    }

    private Guid? SelectedUserPresetId() =>
        UserPresetSelector.SelectedItem is ComboBoxItem { Tag: Guid id } ? id : null;

    /// <summary>
    /// recipe 가 통째로 바뀌었을 때 화면 전체를 다시 맞춥니다. 붙여넣기와 프리셋 적용이 같은
    /// 자리를 쓰므로 한쪽만 갱신되는 일이 없습니다.
    /// </summary>
    private void ReloadAfterRecipeReplaced()
    {
        SynchronizeInspectorValues();
        SyncBaseControls();
        SyncToneControls();
        UpdateFilmLookControls();
        UpdatePresetControls();
        RequestPreview();
    }

    private void UpdatePresetControls(Guid? select = null)
    {
        if (PasteScopeButton is null)
        {
            return;
        }

        CopyPasteSectionText.Text = AppResources.Get("developCopyPaste", "Text");
        UserPresetSectionText.Text = AppResources.Get("developUserPreset", "Text");
        UserPresetLabel.Text = AppResources.Get("developUserPreset", "Text");
        PasteScopeLabel.Text = AppResources.Get("developPasteScope", "Text");
        CopyDevelopSettingsButton.Content = AppResources.Get("developCopy", "Content");
        PasteDevelopSettingsButton.Content = AppResources.Get("developPaste", "Content");
        SaveUserPresetButton.Content = AppResources.Get("developUserPresetSave", "Content");
        ApplyUserPresetButton.Content = AppResources.Get("developUserPresetApply", "Content");
        DeleteUserPresetButton.Content = AppResources.Get("developUserPresetDelete", "Content");
        PasteScopeAllItem.Text = AppResources.Get("developPasteScopeAll", "Text");
        PasteScopeBaseItem.Text = AppResources.Get("developScopeBase", "Text");
        PasteScopeToneItem.Text = AppResources.Get("developScopeTone", "Text");
        PasteScopeColorItem.Text = AppResources.Get("developScopeColor", "Text");
        PasteScopeDetailItem.Text = AppResources.Get("developScopeDetail", "Text");
        PasteScopeGeometryItem.Text = AppResources.Get("developScopeGeometry", "Text");
        AutomationProperties.SetHelpText(
            CopyDevelopSettingsButton, AppResources.Get("developCopyHelp", "Value"));
        AutomationProperties.SetHelpText(
            PasteDevelopSettingsButton, AppResources.Get("developPasteHelp", "Value"));
        AutomationProperties.SetHelpText(
            PasteScopeButton, AppResources.Get("developPasteScopeHelp", "Value"));
        AutomationProperties.SetHelpText(
            SaveUserPresetButton, AppResources.Get("developUserPresetSaveHelp", "Value"));
        AutomationProperties.SetHelpText(
            ApplyUserPresetButton, AppResources.Get("developUserPresetApplyHelp", "Value"));
        AutomationProperties.SetHelpText(
            DeleteUserPresetButton, AppResources.Get("developUserPresetDeleteHelp", "Value"));

        DevelopSettingsPasteScope scope = panel?.PasteScope ?? DevelopSettingsPasteScope.All;
        PasteScopeBaseItem.IsChecked = scope.Base;
        PasteScopeToneItem.IsChecked = scope.Tone;
        PasteScopeColorItem.IsChecked = scope.Color;
        PasteScopeDetailItem.IsChecked = scope.Detail;
        PasteScopeGeometryItem.IsChecked = scope.Geometry;
        PasteScopeButton.Content = DescribePasteScope(scope);

        CopyDevelopSettingsButton.IsEnabled = panel?.SelectedFrame is not null;
        PasteDevelopSettingsButton.IsEnabled =
            panel?.SelectedFrame is not null && panel.CopiedSettings is not null && !scope.IsEmpty;
        SaveUserPresetButton.IsEnabled = panel?.SelectedFrame is not null;

        Guid? keep = select ?? SelectedUserPresetId();
        IReadOnlyList<DevelopUserPreset> presets = panel?.UserPresets ?? [];
        List<ComboBoxItem> items = [];
        foreach (DevelopUserPreset preset in presets)
        {
            items.Add(new ComboBoxItem { Content = preset.Name, Tag = preset.Id });
        }
        UserPresetSelector.ItemsSource = items;
        UserPresetSelector.IsEnabled = items.Count != 0;
        if (items.Count == 0)
        {
            // macOS 는 목록이 비면 자리표시자 한 줄을 보여 주고 고를 수 없게 둡니다.
            UserPresetSelector.PlaceholderText =
                AppResources.Get("developUserPresetEmpty", "Text");
        }
        else
        {
            UserPresetSelector.SelectedItem =
                items.FirstOrDefault(item => (Guid)item.Tag! == keep) ?? items[^1];
        }
        UpdateUserPresetButtons();
    }

    private void UpdateUserPresetButtons()
    {
        bool hasSelection = SelectedUserPresetId() is not null;
        ApplyUserPresetButton.IsEnabled = hasSelection && panel?.SelectedFrame is not null;
        DeleteUserPresetButton.IsEnabled = hasSelection;
    }

    /// <summary>
    /// macOS 와 같은 요약 문구입니다. 전부면 "모든 설정", 하나도 없으면 "없음", 그 사이는 켜진
    /// 묶음 이름을 순서대로 이어 붙입니다.
    /// </summary>
    private static string DescribePasteScope(DevelopSettingsPasteScope scope)
    {
        if (scope.IsFullDevelopScope)
        {
            return AppResources.Get("developPasteScopeAll", "Text");
        }
        List<string> groups = [];
        if (scope.Base)
        {
            groups.Add(AppResources.Get("developScopeBase", "Text"));
        }
        if (scope.Tone)
        {
            groups.Add(AppResources.Get("developScopeTone", "Text"));
        }
        if (scope.Color)
        {
            groups.Add(AppResources.Get("developScopeColor", "Text"));
        }
        if (scope.Detail)
        {
            groups.Add(AppResources.Get("developScopeDetail", "Text"));
        }
        if (scope.Geometry)
        {
            groups.Add(AppResources.Get("developScopeGeometry", "Text"));
        }
        return groups.Count == 0
            ? AppResources.Get("developPasteScopeNone", "Text")
            : string.Join("/", groups);
    }

    /// <summary>지금 캔버스를 잡고 있는 GrainMend 도구입니다.</summary>
    private enum GrainMendTool
    {
        None,
        Brush,
        Clone,
    }

    private GrainMendTool grainMendTool;
    private readonly List<DefectPoint> grainMendStroke = [];
    private DefectPoint? cloneSourceAnchor;
    private bool grainMendDragging;

    /// <summary>
    /// 검출은 됐지만 아직 받아들이지 않은 결과입니다. macOS 와 같이 Enter 를 받아야 사진이
    /// 바뀝니다 — 여기 값이 있는 동안 사진은 그대로입니다.
    /// </summary>
    private DefectEditItem? pendingDefectEdit;

    private async void OnGrainMendAutoClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel?.SelectedFrame is not { } frame || grainMendDetectCoordinator is null)
        {
            return;
        }
        SetGrainMendTool(GrainMendTool.None);
        ClearPendingDefectEdit();
        ExportStatusText.Text = AppResources.Get("developGrainMendDetecting", "Text");
        GrainMendAutoButton.IsEnabled = false;
        try
        {
            // 자동은 프레임 전체입니다. 가이드는 같은 자리에 사용자가 끈 사각형을 넣습니다.
            await grainMendDetectCoordinator.RunAsync(
                frame,
                new DefectRect(0.0, 0.0, 1.0, 1.0),
                ShowDetectedDefects);
        }
        finally
        {
            GrainMendAutoButton.IsEnabled = panel?.SelectedFrame is not null;
        }
    }

    private void ShowDetectedDefects(GrainMendDetectOutcome outcome)
    {
        if (outcome.Kind is DevelopExportOutcomeKind.Refused
            or DevelopExportOutcomeKind.Faulted)
        {
            ExportStatusText.Text = AppResources.Get("developGrainMendDetectFailed", "Text");
            return;
        }
        if (outcome.Edit is not { } edit)
        {
            ExportStatusText.Text = AppResources.Get("developGrainMendFoundNothing", "Text");
            return;
        }

        pendingDefectEdit = edit;
        ExportStatusText.Text = AppResources.FormatIntegers(
            "developGrainMendFoundFormat",
            "Value",
            edit.Label.Value);
        ShowDefectOverlay(edit, outcome.Width, outcome.Height);
        // Enter 와 Esc 를 받으려면 캔버스가 초점을 가져야 합니다.
        _ = CanvasHost.Focus(FocusState.Programmatic);
    }

    /// <summary>
    /// 마스크를 미리보기 위에 얹습니다. 표시된 화소만 칠하고 나머지는 완전히 투명하게 둡니다 —
    /// 반투명한 판을 통째로 덮으면 사진이 아니라 판을 보게 됩니다.
    /// </summary>
    private void ShowDefectOverlay(DefectEditItem edit, uint width, uint height)
    {
        if (edit.RegionMask is not { } mask || width == 0U || height == 0U ||
            !DefectMaskCodec.TryDecodeRgba8(mask, (int)width, (int)height, out byte[] rgba))
        {
            return;
        }

        WriteableBitmap bitmap = new((int)width, (int)height);
        byte[] bgra = new byte[checked((int)width * (int)height * 4)];
        for (int pixel = 0; pixel < bgra.Length; pixel += 4)
        {
            if (rgba[pixel] == 0)
            {
                continue;
            }
            // 붉은 표시입니다. WriteableBitmap 은 미리 곱해진 알파를 쓰므로 세 채널이 알파를
            // 넘지 않아야 합니다.
            bgra[pixel] = 30;
            bgra[pixel + 1] = 30;
            bgra[pixel + 2] = 200;
            bgra[pixel + 3] = 200;
        }
        using (Stream buffer = bitmap.PixelBuffer.AsStream())
        {
            buffer.Write(bgra, 0, bgra.Length);
        }
        bitmap.Invalidate();
        DefectOverlayImage.Source = bitmap;
        DefectOverlayImage.Visibility = Visibility.Visible;
    }

    private void ClearPendingDefectEdit()
    {
        pendingDefectEdit = null;
        DefectOverlayImage.Source = null;
        DefectOverlayImage.Visibility = Visibility.Collapsed;
    }

    /// <summary>검토 중인 검출을 받아들여 recipe 에 담습니다.</summary>
    private void AcceptPendingDefectEdit()
    {
        if (panel is null || pendingDefectEdit is not { } edit)
        {
            return;
        }
        ClearPendingDefectEdit();
        if (panel.AcceptDefectRegion(edit) != LibraryFrameError.None)
        {
            ExportStatusText.Text = AppResources.Get("developGrainMendDetectFailed", "Text");
            return;
        }
        ExportStatusText.Text = string.Empty;
        UpdateGrainMendCard();
        RequestPreview();
    }

    private void OnGrainMendBrushClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetGrainMendTool(grainMendTool == GrainMendTool.Brush
            ? GrainMendTool.None
            : GrainMendTool.Brush);
    }

    private void OnGrainMendCloneClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetGrainMendTool(grainMendTool == GrainMendTool.Clone
            ? GrainMendTool.None
            : GrainMendTool.Clone);
    }

    private void OnGrainMendAutoResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ClearPendingDefectEdit();
        RemoveGrainMendEdits(DefectEditKind.Region);
    }

    private void OnGrainMendBrushResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        RemoveGrainMendEdits(DefectEditKind.Brush);
    }

    private void OnGrainMendCloneResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        RemoveGrainMendEdits(DefectEditKind.Clone);
    }

    private void RemoveGrainMendEdits(DefectEditKind kind)
    {
        if (panel is null)
        {
            return;
        }
        SetGrainMendTool(GrainMendTool.None);
        if (panel.RemoveDefectEdits(kind) != LibraryFrameError.None)
        {
            return;
        }
        UpdateGrainMendCard();
        RequestPreview();
    }

    private void SetGrainMendTool(GrainMendTool tool)
    {
        if (grainMendTool == tool)
        {
            return;
        }
        grainMendTool = tool;
        grainMendStroke.Clear();
        cloneSourceAnchor = null;
        grainMendDragging = false;
        if (tool != GrainMendTool.None && cropSession is not null)
        {
            // 크롭과 결함 도구는 같은 포인터를 두고 다툽니다. macOS 도 서로를 끕니다.
            EndCropSession();
        }
        UpdateGrainMendCard();
    }

    private void UpdateGrainMendCard()
    {
        if (GrainMendAutoButton is null)
        {
            return;
        }
        GrainMendTitleText.Text = AppResources.Get("developGrainMend", "Text");
        GrainMendAutoButton.Content = AppResources.Get("developGrainMendAuto", "Content");
        GrainMendGuidedButton.Content = AppResources.Get("developGrainMendGuided", "Content");
        GrainMendBrushButton.Content = AppResources.Get("developGrainMendBrush", "Content");
        GrainMendCloneButton.Content = AppResources.Get("developGrainMendClone", "Content");
        SetLocalizedNameAndTooltip(
            GrainMendBrushButton, AppResources.Get("developGrainMendBrushHelp", "Value"));
        SetLocalizedNameAndTooltip(
            GrainMendCloneButton, AppResources.Get("developGrainMendCloneHelp", "Value"));
        SetLocalizedNameAndTooltip(
            GrainMendAutoButton, AppResources.Get("developGrainMendAutoHelp", "Value"));
        // 가이드는 아직 영역을 끄는 상호작용이 없습니다. 검출은 자동과 같은 것을 쓰지만 ROI 가
        // 사용자에게서 와야 하므로, 그 자리가 생기기 전에는 이유를 달아 꺼 둡니다.
        SetLocalizedNameAndTooltip(
            GrainMendGuidedButton,
            AppResources.Get("developGrainMendDetectorMissing", "Value"));
        GrainMendGuidedButton.IsEnabled = false;
        GrainMendGuidedResetButton.IsEnabled = false;
        GrainMendAutoButton.IsEnabled =
            panel?.SelectedFrame is not null && pendingDefectEdit is null;
        GrainMendAutoResetButton.IsEnabled =
            panel?.HasDefectEdits(DefectEditKind.Region) == true;

        string reset = AppResources.Get("developGrainMendReset", "Value");
        SetLocalizedNameAndTooltip(GrainMendBrushResetButton, reset);
        SetLocalizedNameAndTooltip(GrainMendCloneResetButton, reset);

        bool hasFrame = panel?.SelectedFrame is not null;
        GrainMendBrushButton.IsEnabled = hasFrame;
        GrainMendCloneButton.IsEnabled = hasFrame;
        GrainMendBrushResetButton.IsEnabled = panel?.HasDefectEdits(DefectEditKind.Brush) == true;
        GrainMendCloneResetButton.IsEnabled = panel?.HasDefectEdits(DefectEditKind.Clone) == true;

        string active = AppResources.Get("selected", "Value");
        string inactive = AppResources.Get("notSelected", "Value");
        AutomationProperties.SetItemStatus(
            GrainMendBrushButton, grainMendTool == GrainMendTool.Brush ? active : inactive);
        AutomationProperties.SetItemStatus(
            GrainMendCloneButton, grainMendTool == GrainMendTool.Clone ? active : inactive);
        var selection = (Microsoft.UI.Xaml.Media.Brush)
            Application.Current.Resources["NegaflowSelectionBrush"];
        GrainMendBrushButton.Background = grainMendTool == GrainMendTool.Brush
            ? selection
            : new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent);
        GrainMendCloneButton.Background = grainMendTool == GrainMendTool.Clone
            ? selection
            : new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent);
    }

    /// <summary>
    /// 도구가 잡고 있으면 포인터를 가로챕니다. 크롭 세션과 같은 이벤트를 쓰므로 어느 쪽이
    /// 먼저인지가 분명해야 합니다 — 도구가 켜져 있으면 크롭은 이미 꺼져 있습니다.
    /// </summary>
    private bool TryBeginGrainMendStroke(PointerRoutedEventArgs args)
    {
        if (grainMendTool == GrainMendTool.None || panel?.SelectedFrame is null ||
            !TryCanvasUnitPoint(args, out CropDisplayPoint point))
        {
            return false;
        }

        bool alt = InputKeyboardSource
            .GetKeyStateForCurrentThread(Windows.System.VirtualKey.Menu)
            .HasFlag(CoreVirtualKeyStates.Down);
        if (grainMendTool == GrainMendTool.Clone && alt)
        {
            // Alt 클릭은 복제 원본을 정합니다. macOS 의 ⌥ 클릭과 같은 뜻입니다.
            cloneSourceAnchor = new DefectPoint(point.X, point.Y);
            return true;
        }
        if (grainMendTool == GrainMendTool.Clone && cloneSourceAnchor is null)
        {
            // 원본을 정하기 전에는 칠할 수 없습니다.
            return true;
        }

        grainMendStroke.Clear();
        grainMendStroke.Add(new DefectPoint(point.X, point.Y));
        grainMendDragging = true;
        CanvasHost.CapturePointer(args.Pointer);
        return true;
    }

    private bool TryContinueGrainMendStroke(PointerRoutedEventArgs args)
    {
        if (!grainMendDragging || !TryCanvasUnitPoint(args, out CropDisplayPoint point))
        {
            return false;
        }
        grainMendStroke.Add(new DefectPoint(point.X, point.Y));
        return true;
    }

    private bool TryFinishGrainMendStroke(PointerRoutedEventArgs args)
    {
        if (!grainMendDragging)
        {
            return false;
        }
        grainMendDragging = false;
        CanvasHost.ReleasePointerCapture(args.Pointer);
        List<DefectPoint> stroke = [.. grainMendStroke];
        grainMendStroke.Clear();
        if (panel is null || stroke.Count == 0)
        {
            return true;
        }

        LibraryFrameError error = grainMendTool == GrainMendTool.Clone
            ? panel.AddCloneStroke(stroke, cloneSourceAnchor ?? stroke[0])
            : panel.AddBrushStroke(stroke);
        if (error == LibraryFrameError.None)
        {
            UpdateGrainMendCard();
            RequestPreview();
        }
        return true;
    }

    /// <summary>정보 카드 한 줄입니다.</summary>
    private sealed record InfoRow(string Label, string Value);

    /// <summary>
    /// macOS 정보 카드의 여섯 줄입니다. 원본과 Sidecar 는 지금 알 수 있는 사실이고, 카메라·날짜·
    /// 제목·키워드는 아직 EXIF/IPTC 를 읽지 않으므로 macOS 의 빈 상태와 같은 "— · —" 입니다.
    /// 읽지 않은 값을 추측해서 채우지 않습니다.
    /// </summary>
    private void UpdateInfoCard()
    {
        if (InfoRows is null)
        {
            return;
        }
        string cardTitle = AppResources.Get("developInfoCard", "Text");
        InfoCardTitleText.Text = cardTitle;
        // 이름이 없는 Border 는 접근성 트리에 나오지 않습니다 — 화면 낭독기도, 검증도 못 봅니다.
        AutomationProperties.SetName(InfoCard, cardTitle);
        if (panel?.SelectedFrame is not { } frame)
        {
            InfoRows.ItemsSource = Array.Empty<InfoRow>();
            return;
        }

        string none = AppResources.Get("developInfoNotAvailable", "Text");
        // 값과 출처를 가운뎃점으로 잇는 macOS 표기입니다. 둘 다 없으면 "— · —" 가 됩니다.
        string empty = none + " · " + none;
        string origin = AppResources.Get(
            frame.Route.SourceTransport == FrameSourceTransport.Scanner
                ? "developInfoOriginScan"
                : "developInfoOriginImport",
            "Text");
        InfoRows.ItemsSource = new List<InfoRow>
        {
            new(AppResources.Get("developInfoSource", "Text"),
                origin + " · " + Path.GetFileName(frame.SourcePath)),
            new(AppResources.Get("developInfoSidecar", "Text"), DescribeSidecar(frame)),
            new(AppResources.Get("developInfoCamera", "Text"), empty),
            new(AppResources.Get("developInfoDate", "Text"), empty),
            new(AppResources.Get("developInfoTitle", "Text"), empty),
            new(AppResources.Get("developInfoKeywords", "Text"), empty),
        };
    }

    /// <summary>
    /// XMP sidecar 는 아직 읽지 않습니다. 옆에 파일이 없다는 것은 확실히 말할 수 있고, 있는
    /// 경우에 "읽음"이라고 하면 읽지 않은 것을 읽었다고 말하는 것이라 "미확인"입니다.
    /// </summary>
    private static string DescribeSidecar(LibraryFrameSnapshot frame)
    {
        string sidecarPath = Path.ChangeExtension(frame.SourcePath, ".xmp");
        try
        {
            return AppResources.Get(
                File.Exists(sidecarPath) ? "developInfoUnknown" : "developInfoSidecarNotFound",
                "Text");
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException)
        {
            return AppResources.Get("developInfoUnknown", "Text");
        }
    }

    /// <summary>버전 목록 한 줄입니다. 표시 문구를 XAML 이 짓지 않도록 여기서 만듭니다.</summary>
    private sealed record VersionRow(
        string Id,
        string Name,
        string CreatedText,
        string RestoreText,
        string DeleteText);

    private void UpdateVersionControls()
    {
        if (VersionsList is null)
        {
            return;
        }
        IReadOnlyList<LibraryVersionSnapshot> versions = panel?.Versions ?? [];
        string restore = AppResources.Get("developVersionRestore", "Content");
        string delete = AppResources.Get("developVersionDelete", "Content");
        List<VersionRow> rows = [];
        foreach (LibraryVersionSnapshot version in versions)
        {
            rows.Add(new VersionRow(
                version.Id,
                version.Name,
                version.CreatedAt is { } created
                    ? created.ToLocalTime().ToString("g", CultureInfo.CurrentCulture)
                    : string.Empty,
                restore,
                delete));
        }
        VersionsList.ItemsSource = rows;
        VersionsEmptyText.Visibility = rows.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        CaptureVersionButton.IsEnabled =
            panel?.SelectedFrame is not null && !string.IsNullOrWhiteSpace(VersionNameBox.Text);
    }

    private void OnVersionNameChanged(object sender, TextChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        CaptureVersionButton.IsEnabled =
            panel?.SelectedFrame is not null && !string.IsNullOrWhiteSpace(VersionNameBox.Text);
    }

    private void OnCaptureVersionClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || panel.CaptureVersion(VersionNameBox.Text) != LibraryFrameError.None)
        {
            return;
        }
        // 담고 나면 이름 칸을 비웁니다 — 같은 이름으로 두 번 담는 실수를 줄입니다.
        VersionNameBox.Text = string.Empty;
        _ = panel.Save();
        UpdateVersionControls();
    }

    private void OnRestoreVersionClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (panel is null || sender is not Button { Tag: string versionId })
        {
            return;
        }
        if (panel.RestoreVersion(versionId) != LibraryFrameError.None)
        {
            return;
        }
        _ = panel.Save();
        // 되돌린 recipe 가 인스펙터와 캔버스에 함께 반영돼야 합니다.
        SynchronizeInspectorValues();
        SyncBaseControls();
        SyncToneControls();
        RequestPreview();
    }

    private void OnDeleteVersionClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (panel is null || sender is not Button { Tag: string versionId })
        {
            return;
        }
        if (panel.DeleteVersion(versionId) != LibraryFrameError.None)
        {
            return;
        }
        _ = panel.Save();
        UpdateVersionControls();
    }

    /// <summary>필름 목록 한 줄과 한 묶음입니다. 화면에 나가는 것만 담습니다.</summary>
    private sealed record FilmLookChoice(FilmEmulation Emulation, string Name, bool IsSelected);

    private sealed record FilmLookGroup(string Title, IReadOnlyList<FilmLookChoice> Films);

    private void UpdateFilmLookControls()
    {
        if (FilmLookGroups is null)
        {
            return;
        }
        bool applies = panel?.AppliesFilmLook == true;
        FilmLookControls.Visibility = applies ? Visibility.Visible : Visibility.Collapsed;
        FilmLookUnavailableText.Visibility = applies ? Visibility.Collapsed : Visibility.Visible;
        if (!applies || panel?.SelectedFrame is not { } frame)
        {
            FilmLookGroups.ItemsSource = null;
            return;
        }

        FilmEmulation current = panel.FilmEmulation;
        List<FilmLookGroup> groups =
        [
            // macOS 와 같이 첫 자리는 룩을 끄는 선택입니다.
            new(
                AppResources.Get("developFilmLookNone", "Text"),
                [new FilmLookChoice(
                    FilmEmulation.None,
                    AppResources.Get("developFilmLookNone", "Text"),
                    current == FilmEmulation.None)]),
        ];
        foreach (FilmEmulationKind kind in FilmEmulationCatalog.KindsFor(frame.Route.FilmType))
        {
            List<FilmLookChoice> films = [];
            foreach (FilmEmulation emulation in FilmEmulationCatalog.Films(kind))
            {
                films.Add(new FilmLookChoice(
                    emulation,
                    FilmEmulationCatalog.DisplayName(emulation),
                    emulation == current));
            }
            groups.Add(new FilmLookGroup(FilmGroupTitle(kind), films));
        }
        FilmLookGroups.ItemsSource = groups;
        isSynchronizingInspector = true;
        try
        {
            FilmLookIntensityControl.Value = panel.FilmEmulationIntensity;
        }
        finally
        {
            isSynchronizingInspector = false;
        }
    }

    private static string FilmGroupTitle(FilmEmulationKind kind) => AppResources.Get(
        kind switch
        {
            FilmEmulationKind.Slide => "filmTypeColorPositive",
            FilmEmulationKind.Negative => "filmTypeColorNegative",
            FilmEmulationKind.MotionPicture => "developFilmGroupMotion",
            FilmEmulationKind.BlackAndWhiteReversal => "developFilmGroupBWSlide",
            _ => "filmTypeBlackAndWhiteNegative",
        },
        "Text");

    private void OnFilmLookChecked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (isSynchronizingInspector ||
            sender is not RadioButton { Tag: FilmEmulation emulation })
        {
            return;
        }
        UpdateImageTransform(state => state.SetFilmEmulation(emulation));
    }

    private void OnFilmLookIntensityChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        if (isSynchronizingInspector)
        {
            return;
        }
        UpdateImageTransform(state => state.SetFilmEmulationIntensity(args.Value));
    }

    private void OnExportFormatChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (ExportFormatSelector.SelectedItem is not ComboBoxItem { Tag: string tag } ||
            !Enum.TryParse(tag, out DevelopExportFormat format))
        {
            return;
        }
        exportDestination = exportDestination with { Format = format };
        UpdateExportPreview();
    }

    private void OnExportNamePatternChanged(object sender, TextChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        exportDestination = exportDestination with { NamePattern = ExportNamePatternBox.Text };
        UpdateExportPreview();
    }

    private async void OnExportFolderClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (importWindowId is not { } windowId)
        {
            return;
        }
        var picker = new Microsoft.Windows.Storage.Pickers.FolderPicker(windowId)
        {
            CommitButtonText = AppResources.Get("developExportFolderChange", "Content"),
        };
        try
        {
            Microsoft.Windows.Storage.Pickers.PickFolderResult? picked =
                await picker.PickSingleFolderAsync();
            if (picked is null)
            {
                return;
            }
            exportDestination = exportDestination with { FolderPath = picked.Path };
            UpdateExportPreview();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            OutputStatusText.Text = AppResources.Get("developExportFolderFailed", "Text");
        }
    }

    private void UpdateExportPreview()
    {
        if (ExportPreviewText is null)
        {
            return;
        }
        ExportFolderPathText.Text = string.IsNullOrWhiteSpace(exportDestination.FolderPath)
            ? AppResources.Get("developExportFolderBesideSource", "Text")
            : exportDestination.FolderPath;
        ExportPreviewText.Text = panel?.SelectedFrame is { } frame
            ? exportDestination.FileNameFor(frame.SourcePath)
            : string.Empty;
        ExportButton.IsEnabled = panel?.CanExport == true;
    }

    /// <summary>
    /// 출력 패널의 내보내기입니다. 빠른 내보내기와 같은 경로를 쓰되 목적지와 형식을 사용자가
    /// 정한 값으로 씁니다.
    /// </summary>
    private async void OnExportClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel?.SelectedFrame is not { } frame)
        {
            return;
        }
        // 편집은 메모리에만 있었으므로, 현상하기 전에 저장해 파일과 catalog 가 어긋나지 않게 합니다.
        if (panel.Save() != CatalogStoreError.None)
        {
            OutputStatusText.Text = AppResources.Get("developExportSaveFailed", "Text");
            return;
        }

        ExportButton.IsEnabled = false;
        OutputStatusText.Text = AppResources.Get("developExportRunning", "Text");
        try
        {
            _ = await panel.ExportAsync(
                exportDestination.PathFor(frame.SourcePath),
                exportDestination.Format,
                outcome => OutputStatusText.Text = DevelopPanelState.Describe(outcome));
        }
        finally
        {
            UpdateExportPreview();
        }
    }

    private void OnCropAngleDialChanged(object? sender, double angle)
    {
        _ = sender;
        if (isSynchronizingInspector)
        {
            return;
        }
        UpdateImageTransform(state => state.SetStraightenAngle(angle));
    }

    /// <summary>비율 목록 한 칸입니다. 화면에 나가는 이름만 여기서 만듭니다.</summary>
    private sealed record CropAspectChoice(CropAspectOption Option, string Text);

    /// <summary>
    /// 드래그를 가둘 정규 비율입니다. 잠금이 꺼져 있거나 비율이 없으면 null 입니다. 화소
    /// 비율을 정규 비율로 바꾸려면 원본의 가로세로가 필요합니다 — 회전이 걸려 있으면 뒤집습니다.
    /// </summary>
    private double? LockedNormalizedAspectRatio()
    {
        if (!isCropAspectLocked ||
            panel?.SelectedFrame is not { SourceMetadata: { } metadata } ||
            panel.ImageTransform.CropAspect is not { } aspect ||
            !double.IsFinite(aspect) || aspect <= 0.0 ||
            metadata.PixelWidth == 0U || metadata.PixelHeight == 0U)
        {
            return null;
        }
        double width = metadata.PixelWidth;
        double height = metadata.PixelHeight;
        if (panel.ImageTransform.Rotation is ImageRotation.Degrees90 or ImageRotation.Degrees270)
        {
            (width, height) = (height, width);
        }
        return aspect * height / width;
    }

    private void OnCropAspectClicked(object sender, ItemClickEventArgs args)
    {
        _ = sender;
        if (args.ClickedItem is not CropAspectChoice choice)
        {
            return;
        }
        CropAspectButton.Flyout?.Hide();
        // 비율이 crop 을 다시 만드는 동안에는 진행 중인 crop session 을 접습니다 — 두 곳이
        // 같은 사각형을 서로 다르게 들고 있으면 Apply 가 어느 쪽을 쓸지 알 수 없습니다.
        CancelCrop();
        UpdateImageTransform(state => state.SetCropAspect(choice.Option));
    }

    private void OnCropAspectLockToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        isCropAspectLocked = !isCropAspectLocked;
        // 잠금은 catalog 가 아니라 다음 crop 드래그의 동작만 바꿉니다.
        CropAspectLockIcon.Glyph = isCropAspectLocked ? "" : "";
        if (cropSession is not null)
        {
            cropSession.LockedNormalizedAspectRatio = LockedNormalizedAspectRatio();
        }
        UpdateCropAspectControls();
    }

    private void UpdateCropAspectControls()
    {
        if (panel is null)
        {
            return;
        }
        string label = CropAspect.LabelFor(panel.ImageTransform);
        CropAspectButton.Content = CropAspectText(label);
        AutomationProperties.SetName(CropAspectButton, CropAspectButton.Content.ToString());
        bool locked = isCropAspectLocked;
        string lockName = AppResources.Get(
            locked ? "cropAspectLocked" : "cropAspectUnlocked",
            "Value");
        AutomationProperties.SetName(CropAspectLockButton, lockName);
        ToolTipService.SetToolTip(CropAspectLockButton, lockName);
    }

    private static string CropAspectText(string label) => label switch
    {
        "original" => AppResources.Get("cropAspectOriginal", "Text"),
        "custom" => AppResources.Get("cropAspectCustom", "Text"),
        _ => label,
    };

    private void UpdateImageTransform(Func<DevelopPanelState, LibraryFrameError> update)
    {
        if (panel is null || isSynchronizingInspector || update(panel) != LibraryFrameError.None)
        {
            return;
        }
        SynchronizeInspectorValues();
        RequestPreview();
    }

    private void OnBasicToneResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetInspectorSection(static state => state.ResetBasicTone());
    }

    private void OnToneCurveResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetInspectorSection(static state => state.ResetToneCurve());
    }

    private void OnColorMixerResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetInspectorSection(static state => state.ResetColorMixer());
    }

    private void OnColorResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetInspectorSection(static state => state.ResetColor());
    }

    private void OnColorGradingResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetInspectorSection(static state => state.ResetColorGrading());
    }

    private void OnCalibrationResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetInspectorSection(static state => state.ResetPrimaryCalibration());
    }

    private void OnDetailAndEffectsResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetInspectorSection(static state => state.ResetDetailAndEffects());
    }

    private void ResetInspectorSection(Func<DevelopPanelState, LibraryFrameError> reset)
    {
        if (panel is null || reset(panel) != LibraryFrameError.None)
        {
            return;
        }

        SynchronizeInspectorValues();
        RequestPreview();
    }

    public async Task QuickExportAsync()
    {
        if (panel?.SelectedFrame is not { } frame)
        {
            return;
        }

        // 편집은 메모리에만 있었으므로, 현상하기 전에 저장해 파일과 catalog 가 어긋나지 않게 합니다.
        CatalogStoreError saved = panel.Save();
        if (saved != CatalogStoreError.None)
        {
            ExportStatusText.Text = AppResources.Get("developExportSaveFailed", "Text");
            return;
        }

        string destination = Path.Combine(
            Path.GetDirectoryName(frame.SourcePath) ?? Path.GetTempPath(),
            $"{Path.GetFileNameWithoutExtension(frame.SourcePath)}-negaflow.png");

        ExportStatusText.Text = AppResources.Get("developExportRunning", "Text");
        Task<bool> exportTask = panel.ExportAsync(
            destination,
            DevelopExportFormat.Png16,
            outcome => ExportStatusText.Text = DevelopPanelState.Describe(outcome));
        NotifyQuickExportAvailabilityChanged();
        bool delivered = await exportTask;
        if (!delivered)
        {
            // 큐가 닫혔다는 뜻이므로 창이 사라지는 중입니다. 컨트롤을 더 건드리지 않습니다.
            return;
        }
        NotifyQuickExportAvailabilityChanged();
    }

    private void NotifyQuickExportAvailabilityChanged() =>
        QuickExportAvailabilityChanged?.Invoke(this, EventArgs.Empty);

    private void OnRootSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is not null)
        {
            SynchronizeWidths(workspaceState.Current);
        }
    }

    private void OnLeftResizeStarted(object sender, DragStartedEventArgs args)
    {
        _ = sender;
        _ = args;
        resizeController.BeginLeft();
    }

    private void OnLeftResizeDelta(object sender, DragDeltaEventArgs args)
    {
        _ = sender;
        LeftPanel.Width = resizeController.UpdateLeft(args.HorizontalChange, Root.ActualWidth);
        UpdateCompactRail();
    }

    private void OnLeftResizeCompleted(object sender, DragCompletedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SetSidebarWidth(resizeController.EndLeft());
    }

    private void OnRightResizeStarted(object sender, DragStartedEventArgs args)
    {
        _ = sender;
        _ = args;
        resizeController.BeginRight();
    }

    private void OnRightResizeDelta(object sender, DragDeltaEventArgs args)
    {
        _ = sender;
        RightPanel.Width = resizeController.UpdateRight(args.HorizontalChange, Root.ActualWidth);
    }

    private void OnRightResizeCompleted(object sender, DragCompletedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SetInspectorWidth(resizeController.EndRight());
    }

    private void OnStateChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        UpdateState(preferences);
    }

    private void UpdateState(ShellPreferences preferences)
    {
        LeftPanel.Visibility = preferences.IsSidebarVisible ? Visibility.Visible : Visibility.Collapsed;
        LeftDivider.Visibility = LeftPanel.Visibility;
        LeftResizeThumb.Visibility = LeftPanel.Visibility;
        RightPanel.Visibility = preferences.IsInspectorVisible ? Visibility.Visible : Visibility.Collapsed;
        RightDivider.Visibility = RightPanel.Visibility;
        RightResizeThumb.Visibility = RightPanel.Visibility;
        Filmstrip.Visibility = preferences.IsFilmstripVisible ? Visibility.Visible : Visibility.Collapsed;
        SynchronizeWidths(preferences);
    }

    private void SynchronizeWidths(ShellPreferences preferences)
    {
        resizeController.Synchronize(
            preferences.SidebarWidth,
            preferences.InspectorWidth,
            Root.ActualWidth);
        LeftPanel.Width = resizeController.LeftWidth;
        RightPanel.Width = resizeController.RightWidth;
        UpdateCompactRail();
    }

    private void UpdateCompactRail()
    {
        LeftRailColumn.Width = new GridLength(
            LeftPanel.Width < ShellLayoutMetrics.SidebarCompactThreshold
                ? ShellLayoutMetrics.SidebarCompactRailWidth
                : ShellLayoutMetrics.SidebarRegularRailWidth);
    }

    private void LocalizeControls()
    {
        SetNameAndTooltip(LibraryRailButton, "sidebarLibrary");
        SetNameAndTooltip(FilesRailButton, "sidebarFiles");
        SetNameAndTooltip(VersionsRailButton, "sidebarVersions");
        SetNameAndTooltip(PresetsRailButton, "sidebarPresets");
        SetNameAndTooltip(FilmRailButton, "sidebarFilm");
        SetNameAndTooltip(OutputRailButton, "sidebarOutput");
        LibraryHeaderText.Text = AppResources.Get("sidebarLibrary", "Text");
        string noFrame = AppResources.Get("noFrame", "Text");
        NoFrameHeaderText.Text = noFrame;
        NoFrameLeftText.Text = noFrame;
        NoFrameInspectorText.Text = noFrame;
        DevelopHeaderText.Text = AppResources.Get("menuDevelop", "Text");
        SetButtonText(ImportButton, AppResources.Get("importImages", "Content"));
        ExportSectionText.Text = AppResources.Get("exportSection", "Text");
        ExportFormatLabel.Text = AppResources.Get("developExportFormat", "Text");
        AutomationProperties.SetName(ExportFormatSelector, ExportFormatLabel.Text);
        ExportFolderLabel.Text = AppResources.Get("developExportFolder", "Text");
        SetButtonText(ExportFolderButton, AppResources.Get("developExportFolderChange", "Content"));
        ExportNamePatternLabel.Text = AppResources.Get("developExportNamePattern", "Text");
        AutomationProperties.SetName(ExportNamePatternBox, ExportNamePatternLabel.Text);
        ExportNamePatternBox.Text = exportDestination.NamePattern;
        SetButtonText(ExportButton, AppResources.Get("exportSection", "Text"));
        ExportFormatSelector.SelectedIndex = 0;
        SetLocalizedNameAndTooltip(LibraryRailButton, AppResources.Get("developLibrary", "Text"));
        SetLocalizedNameAndTooltip(VersionsRailButton, AppResources.Get("developSectionVersions", "Text"));
        SetButtonText(CaptureVersionButton, AppResources.Get("developVersionCapture", "Content"));
        VersionsEmptyText.Text = AppResources.Get("developVersionsEmpty", "Text");
        string versionName = AppResources.Get("developVersionNamePlaceholder", "Text");
        VersionNameBox.PlaceholderText = versionName;
        AutomationProperties.SetName(VersionNameBox, versionName);
        SetLocalizedNameAndTooltip(FilmRailButton, AppResources.Get("developSectionFilm", "Text"));
        SetLocalizedNameAndTooltip(OutputRailButton, AppResources.Get("developSectionOutput", "Text"));
        FilmLookUnavailableText.Text = AppResources.Get("developFilmLookDigitalOnly", "Text");
        FilmLookIntensityControl.Label = AppResources.Get("developFilmLookIntensity", "Text");
        UpdateDevelopSourcePanel();
        SetRadioText(BaseAutoModeButton, AppResources.Get("developBaseModeAuto", "Content"));
        SetRadioText(BaseFilmModeButton, AppResources.Get("developBaseModeFilm", "Content"));
        SetRadioText(BaseManualModeButton, AppResources.Get("developBaseModeManual", "Content"));
        FilmStockLabel.Text = AppResources.Get("developFilmStock", "Text");
        AutomationProperties.SetName(FilmStockSelector, FilmStockLabel.Text);
        LightSourceLabel.Text = AppResources.Get("developLightSource", "Text");
        AutomationProperties.SetName(LightSourceSelector, LightSourceLabel.Text);
        SetToggleText(AutoColorToggle, AppResources.Get("developAutoColor", "Content"));
        SetToggleText(AutoLevelsToggle, AppResources.Get("developAutoLevels", "Content"));
        SetButtonText(AutoToneButton, AppResources.Get("developAutoTone", "Content"));
        SetButtonText(
            AutoWhiteBalanceButton,
            AppResources.Get("developAutoWhiteBalance", "Content"));
        HistogramView.Localize(
            AppResources.Get("developHistogram", "Text"),
            AppResources.Get("developHistogramShadow", "Text"),
            AppResources.Get("developHistogramDensity", "Text"),
            AppResources.Get("developHistogramExposure", "Text"),
            AppResources.Get("developHistogramHighlight", "Text"),
            AppResources.Get("developHistogramRgb", "Text"),
            AppResources.Get("developHistogramClippingFormat", "Value"),
            AppResources.Get("developHistogramRedShort", "Text"),
            AppResources.Get("developHistogramGreenShort", "Text"),
            AppResources.Get("developHistogramBlueShort", "Text"),
            AppResources.Get("developHistogramKeyboardHelp", "Value"));
        string basic = AppResources.Get("developTabBasic", "Value");
        string baseTitle = AppResources.Get("developTabBase", "Value");
        string edit = AppResources.Get("developTabEdit", "Value");
        string defects = AppResources.Get("developTabDefects", "Value");
        string info = AppResources.Get("developTabInfo", "Value");
        string reset = AppResources.Get("developTabReset", "Value");
        SetLocalizedNameAndTooltip(BasicTabButton, basic);
        SetLocalizedNameAndTooltip(BaseTabButton, baseTitle);
        SetLocalizedNameAndTooltip(EditTabButton, edit);
        SetLocalizedNameAndTooltip(DefectsTabButton, defects);
        SetLocalizedNameAndTooltip(InfoTabButton, info);
        SetLocalizedNameAndTooltip(ResetTabButton, reset);
        BaseSectionTitleText.Text = baseTitle;
        AutomationProperties.SetName(BaseControlCard, baseTitle);
        string geometry = AppResources.Get("developGeometry", "Text");
        GeometrySectionTitleText.Text = geometry;
        AutomationProperties.SetName(GeometryControlCard, geometry);
        SetLocalizedNameAndTooltip(RotateLeftButton, AppResources.Get("developRotateLeft", "Text"));
        SetLocalizedNameAndTooltip(RotateRightButton, AppResources.Get("developRotateRight", "Text"));
        SetLocalizedNameAndTooltip(FlipHorizontalButton, AppResources.Get("developFlipHorizontal", "Text"));
        SetLocalizedNameAndTooltip(FlipVerticalButton, AppResources.Get("developFlipVertical", "Text"));
        SetLocalizedNameAndTooltip(CropButton, AppResources.Get("developCrop", "Text"));
        SetButtonText(CropApplyButton, AppResources.Get("developCropApply", "Text"));
        SetButtonText(CropFullButton, AppResources.Get("developCropFull", "Text"));
        SetButtonText(CropCancelButton, AppResources.Get("developCropCancel", "Text"));
        AutomationProperties.SetName(CropSelection, AppResources.Get("developCropArea", "Text"));
        StraightenAngleControl.Label = AppResources.Get("developAngle", "Text");
        // 슬라이더 이름은 macOS 와 같은 문자열이며 XAML 에 박아 두지 않습니다.
        ExposureControl.Label = AppResources.Get("developExposure", "Text");
        ContrastControl.Label = AppResources.Get("developContrast", "Text");
        HighlightsControl.Label = AppResources.Get("developHighlights", "Text");
        ShadowsControl.Label = AppResources.Get("developShadows", "Text");
        WhitesControl.Label = AppResources.Get("developWhites", "Text");
        BlacksControl.Label = AppResources.Get("developBlacks", "Text");
        DensityControl.Label = AppResources.Get("developDensity", "Text");
        // 톤 커브의 네 축은 Basic 과 같은 이름을 쓰되 가운데 둘만 따로 있습니다.
        CurveHighlightsControl.Label = AppResources.Get("developHighlights", "Text");
        CurveLightsControl.Label = AppResources.Get("developLights", "Text");
        CurveDarksControl.Label = AppResources.Get("developDarks", "Text");
        CurveShadowsControl.Label = AppResources.Get("developShadows", "Text");
        BaseRedControl.Label = AppResources.Get("developBaseRed", "Text");
        BaseGreenControl.Label = AppResources.Get("developBaseGreen", "Text");
        BaseBlueControl.Label = AppResources.Get("developBaseBlue", "Text");
        CropAspectLabel.Text = AppResources.Get("cropAspectRatio", "Text");
        CropAspectOptions.ItemsSource = CropAspect.Options
            .Select(option => new CropAspectChoice(option, CropAspectText(option.Label)))
            .ToList();
        UpdateCropAspectControls();
        SetInspectorSectionText(
            BasicToneSection,
            BasicToneHeaderButton,
            BasicToneSectionTitleText,
            BasicToneResetButton,
            AppResources.Get("developSectionBasicTone", "Text"));
        SetInspectorSectionText(
            ToneCurveSection,
            ToneCurveHeaderButton,
            ToneCurveSectionTitleText,
            ToneCurveResetButton,
            AppResources.Get("developSectionToneCurve", "Text"));
        SetInspectorSectionText(
            ColorSection,
            ColorHeaderButton,
            ColorSectionTitleText,
            ColorResetButton,
            AppResources.Get("developSectionColor", "Text"));
        SetInspectorSectionText(
            ColorMixerSection,
            ColorMixerHeaderButton,
            ColorMixerSectionTitleText,
            ColorMixerResetButton,
            AppResources.Get("developSectionColorMixer", "Text"));
        SetInspectorSectionText(
            ColorGradingSection,
            ColorGradingHeaderButton,
            ColorGradingSectionTitleText,
            ColorGradingResetButton,
            AppResources.Get("developSectionColorGrading", "Text"));
        SetInspectorSectionText(
            BwToningSection,
            BwToningHeaderButton,
            BwToningSectionTitleText,
            BwToningResetButton,
            AppResources.Get("developSectionBwToning", "Text"));
        BwToningModeLabel.Text = AppResources.Get("developBwToningMode", "Text");
        BwToningOffItem.Content = AppResources.Get("developBwToningOff", "Content");
        BwToningSeleniumItem.Content = AppResources.Get("developBwToningSelenium", "Content");
        BwToningSepiaItem.Content = AppResources.Get("developBwToningSepia", "Content");
        BwToningStrengthControl.Label = AppResources.Get("developBwToningStrength", "Text");
        BwToningShadowHueControl.Label = AppResources.Get("developBwToningShadowHue", "Text");
        BwToningHighlightHueControl.Label =
            AppResources.Get("developBwToningHighlightHue", "Text");
        SetInspectorSectionText(
            CalibrationSection,
            CalibrationHeaderButton,
            CalibrationSectionTitleText,
            CalibrationResetButton,
            AppResources.Get("developSectionCalibration", "Text"));
        SetInspectorSectionText(
            DetailAndEffectsSection,
            DetailAndEffectsHeaderButton,
            DetailAndEffectsSectionTitleText,
            DetailAndEffectsResetButton,
            AppResources.Get("developSectionDetailAndEffects", "Text"));
        RedPrimaryText.Text = AppResources.Get("developCalibrationRedPrimary", "Text");
        GreenPrimaryText.Text = AppResources.Get("developCalibrationGreenPrimary", "Text");
        BluePrimaryText.Text = AppResources.Get("developCalibrationBluePrimary", "Text");
        string hue = AppResources.Get("developCalibrationHue", "Text");
        string saturation = AppResources.Get("developCalibrationSaturation", "Text");
        RedPrimaryHueControl.Label = hue;
        GreenPrimaryHueControl.Label = hue;
        BluePrimaryHueControl.Label = hue;
        RedPrimarySaturationControl.Label = saturation;
        GreenPrimarySaturationControl.Label = saturation;
        BluePrimarySaturationControl.Label = saturation;
        NoiseReductionLabelText.Text = AppResources.Get("developNoiseReduction", "Text");
        NoiseReductionStrengthControl.Label = AppResources.Get("developNoiseReductionStrength", "Text");
        NoiseReductionLumaControl.Label = AppResources.Get("developNoiseReductionLuminance", "Text");
        NoiseReductionChromaControl.Label = AppResources.Get("developNoiseReductionColor", "Text");
        NoiseReductionDarkToneControl.Label = AppResources.Get("developNoiseReductionDarkTones", "Text");
        NoiseReductionDetailControl.Label = AppResources.Get("developNoiseReductionDetail", "Text");
        NoiseReductionGrainProtectControl.Label = AppResources.Get("developNoiseReductionGrainProtect", "Text");
        WarmthControl.Label = AppResources.Get("developWarmth", "Text");
        TintControl.Label = AppResources.Get("developTint", "Text");
        VibranceControl.Label = AppResources.Get("developVibrance", "Text");
        SaturationControl.Label = AppResources.Get("developSaturation", "Text");
        ColorDepthControl.Label = AppResources.Get("developColorDepth", "Text");
        GrainControl.Label = AppResources.Get("developTextureGrain", "Text");
        SharpnessControl.Label = AppResources.Get("developTextureSharpness", "Text");
        ClarityControl.Label = AppResources.Get("developTextureClarity", "Text");
        HalationControl.Label = AppResources.Get("developTextureHalation", "Text");
        VignetteControl.Label = AppResources.Get("developTextureVignette", "Text");
    }

    private static void SetInspectorSectionText(
        FrameworkElement section,
        ButtonBase headerButton,
        TextBlock titleText,
        Button resetButton,
        string title)
    {
        titleText.Text = title;
        AutomationProperties.SetName(section, title);
        SetLocalizedNameAndTooltip(headerButton, title);
        string resetName = AppResources.Get("developResetSectionFormat", "Value")
            .Replace("%@", title, StringComparison.Ordinal);
        SetLocalizedNameAndTooltip(resetButton, resetName);
    }

    private static void SetNameAndTooltip(ButtonBase button, string resourceKey)
    {
        string text = AppResources.Get(resourceKey, "Value");
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    private static void SetLocalizedNameAndTooltip(ButtonBase button, string text)
    {
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    private static void SetButtonText(Button button, string text)
    {
        button.Content = text;
        SetLocalizedNameAndTooltip(button, text);
    }

    private static void SetToggleText(ToggleButton toggle, string text)
    {
        toggle.Content = text;
        SetLocalizedNameAndTooltip(toggle, text);
    }

    private static void SetRadioText(RadioButton radio, string text)
    {
        radio.Content = text;
        AutomationProperties.SetName(radio, text);
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        CancelCrop();
        if (workspaceState is not null)
        {
            workspaceState.Changed -= OnStateChanged;
        }
    }
}
