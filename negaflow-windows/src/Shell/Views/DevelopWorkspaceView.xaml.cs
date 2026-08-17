using System.Globalization;
using System.Text.Json.Nodes;
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
using Negaflow.Shell.Views.Develop.Export;
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
    private SoftProofPreferences softProofPreferences = new();
    private AutoAdjustCoordinator? autoAdjustCoordinator;
    private WriteableBitmap? previewBitmap;
    private bool isSynchronizingInspector;
    private bool isSynchronizingFrameSelection;
    private bool isSynchronizingInspectorPresentation;
    private bool isInspectorPresentationReady;
    private Negaflow.Shell.Library.ThumbnailService? thumbnails;
    private WorkflowSidebarTab developSource = WorkflowSidebarTab.Library;
    private GrainMendDetectCoordinator? grainMendDetectCoordinator;
    private bool isSynchronizingMetadata;
    private string engineVersion = "unknown";
    private readonly CropWorkspaceState crop = new();
    private CropDisplayPoint guidedDefectDragStart;
    private CropDisplayPoint guidedDefectDragCurrent;
    private bool guidedDefectDragging;
    private readonly GrainMendWorkspaceState grainMend = new();

    public DevelopWorkspaceView()
    {
        InitializeComponent();
        isInspectorPresentationReady = true;
        DefectLayers.Command += OnDefectLayerCommand;
        ApplyInspectorPresentation();
        LocalizeControls();
    }

    public event EventHandler? QuickExportAvailabilityChanged;

    /// <summary>macOS의 스캐너 가져오기 명령을 공유 Library 소스에 요청합니다.</summary>
    public event EventHandler? ScannerSetupRequested;

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
        ExportPanel.Attach(state);
        ExportPanel.RunQuickExport = QuickExportAsync;
        StatusBar.Initialize(nativeEngineStatus);
        engineVersion = nativeEngineStatus.BuildInfo?.AbiVersion.ToString() ?? "unknown";
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

        if (libraryHost is not null)
        {
            libraryHost.SelectionChanged -= OnLibrarySelectionChanged;
        }
        libraryHost = host;
        // 격자에서 고른 장수가 바뀌면 내보내기 단추의 이름도 따라갑니다.
        host.SelectionChanged += OnLibrarySelectionChanged;
        toneLimits = limits;
        panel = new DevelopPanelState(host, limits, negativeLimits);
        ExportPanel.Bind(panel, host, windowId, engineVersion);
        // 사용자 프리셋은 카탈로그가 아니라 앱 설정 옆에 삽니다. macOS 의 UserDefaults 자리입니다.
        panel.OpenUserPresets(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Negaflow",
            "Development",
            "user-presets.json"));
        FilmStockSelector.ItemsSource = BundledFilmBaseOptions.FilmStocks;
        LightSourceSelector.ItemsSource = BundledFilmBaseOptions.LightSources;
        ScannerProfileSelector.ItemsSource = ScannerProfileChoices();
        ExposureControl.Minimum = -panel.Tone.MaximumExposureStops;
        ExposureControl.Maximum = panel.Tone.MaximumExposureStops;
        HistogramView.ConfigureRanges(panel.Tone.MaximumExposureStops, panel.Tone.MaximumToneControl);
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
            slider.Minimum = -panel.Tone.MaximumToneControl;
            slider.Maximum = panel.Tone.MaximumToneControl;
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
            string noFrame = AppResources.Get("noFrame", "Text");
            NoFrameHeaderText.Text = noFrame;
            ToolTipService.SetToolTip(NoFrameHeaderText, noFrame);
            FrameSelector.ItemsSource = null;
            Filmstrip.ShowFrames([], -1);
            HistogramView.Clear();
            RebuildDevelopLibraryTree();
            SyncToneControls();
            NotifyQuickExportAvailabilityChanged();
            return;
        }

        int selectedIndex = IndexOf(items, libraryHost.ActiveFrameId);
        if (selectedIndex < 0)
        {
            selectedIndex = 0;
        }
        isSynchronizingFrameSelection = true;
        try
        {
            FrameSelector.ItemsSource = items;
            FrameSelector.SelectedIndex = selectedIndex;
            // 필름스트립과 왼쪽 목록은 같은 항목을 봅니다. 썸네일이 도착하면 둘 다 채워집니다.
            RebuildDevelopLibraryTree();
            Filmstrip.ShowFrames(items, selectedIndex);
        }
        finally
        {
            isSynchronizingFrameSelection = false;
        }
        ActivateFrame(items[selectedIndex], selectedIndex, publishSelection: false);
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
        // 레이어 목록은 GrainMend 카드와 한 탭에 삽니다. macOS 도 같은 인스펙터에 붙습니다.
        DefectLayers.Visibility = GrainMendCard.Visibility;
        if (inspectorPresentation.SelectedTab != DevelopInspectorTab.Defects)
        {
            // 탭을 떠나면 도구도 놓습니다. 보이지 않는 도구가 캔버스를 잡고 있으면
            // 크롭이나 확대가 먹지 않는 것처럼 보입니다.
            SetGrainMendTool(GrainMendTool.None);
        }
        UpdateInfoCard();
        UpdateAppMetadataCards();
        UpdateRollRecordCard();
        UpdateGrainMendCard();
        UpdateDefectLayers();
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
            CommitButtonText = AppResources.Get("importSection", "Value"),
        };
        foreach (string extension in ImageSourcePaths.SupportedImportExtensions)
        {
            picker.FileTypeFilter.Add(extension);
        }

        SetImportActionsEnabled(false);
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
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            ImportStatusText.Text = AppResources.Get("libraryImportFailed", "Text");
        }
        finally
        {
            SetImportActionsEnabled(true);
        }
    }

    private async void OnImportFolderClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (libraryHost is null || importWindowId is null)
        {
            return;
        }

        Microsoft.Windows.Storage.Pickers.FolderPicker picker = new(importWindowId.Value)
        {
            CommitButtonText = AppResources.Get("importFolder", "Content"),
        };
        SetImportActionsEnabled(false);
        ImportStatusText.Text = string.Empty;
        try
        {
            Microsoft.Windows.Storage.Pickers.PickFolderResult? picked =
                await picker.PickSingleFolderAsync();
            if (picked is null)
            {
                return;
            }
            FolderImportResult imported = libraryHost.ImportFolders(
                [picked.Path],
                DevelopmentProcess.C41);
            ImportStatusText.Text = imported.IsSuccess
                ? AppResources.FormatIntegers(
                    "libraryFolderImportResult",
                    "Text",
                    imported.AddedFrameCount,
                    imported.AddedFolderCount)
                : AppResources.Get("libraryImportFailed", "Text");
            RefreshFrames();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            ImportStatusText.Text = AppResources.Get("libraryImportFailed", "Text");
        }
        finally
        {
            SetImportActionsEnabled(true);
        }
    }

    private void OnImportScannerClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ScannerSetupRequested?.Invoke(this, EventArgs.Empty);
    }

    private void SetImportActionsEnabled(bool enabled)
    {
        ImportButton.IsEnabled = enabled;
        ImportFolderButton.IsEnabled = enabled;
        ImportScannerButton.IsEnabled = enabled;
    }

    private void OnFrameSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingFrameSelection || panel is null ||
            FrameSelector.SelectedItem is not LibraryFrameListItem item)
        {
            return;
        }

        ActivateFrame(item, FrameSelector.SelectedIndex, publishSelection: true);
    }

    private void ActivateFrame(
        LibraryFrameListItem item,
        int selectedIndex,
        bool publishSelection)
    {
        if (panel is null)
        {
            return;
        }

        CancelCrop();
        if (publishSelection)
        {
            libraryHost?.SetSelection([item.Id], item.Id);
        }
        panel.Select(item.Id);
        Filmstrip.SynchronizeSelection(selectedIndex);
        NoFrameHeaderText.Text = item.DisplayName;
        ToolTipService.SetToolTip(NoFrameHeaderText, item.DisplayName);
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

    private static int IndexOf(IReadOnlyList<LibraryFrameListItem> items, string? frameId)
    {
        if (frameId is null)
        {
            return -1;
        }
        for (int index = 0; index < items.Count; ++index)
        {
            if (string.Equals(items[index].Id, frameId, StringComparison.Ordinal))
            {
                return index;
            }
        }
        return -1;
    }

    private void SynchronizeInspectorValues()
    {
        if (panel is null)
        {
            return;
        }

        isSynchronizingInspector = true;
        ExposureControl.Value = panel.Tone.Exposure;
        ContrastControl.Value = panel.Tone.Contrast;
        HighlightsControl.Value = panel.Tone.Highlights;
        ShadowsControl.Value = panel.Tone.Shadows;
        WhitesControl.Value = panel.Tone.Whites;
        BlacksControl.Value = panel.Tone.Blacks;
        DensityControl.Value = panel.Tone.Density;
        CurveHighlightsControl.Value = panel.Tone.CurveHighlights;
        CurveLightsControl.Value = panel.Tone.CurveLights;
        CurveDarksControl.Value = panel.Tone.CurveDarks;
        CurveShadowsControl.Value = panel.Tone.CurveShadows;
        PointCurveEditor.Curves = panel.Color.PointCurves;
        ColorMixerEditor.Mixer = panel.Color.ColorMixer;
        ColorGradingEditor.Grading = panel.Color.ColorGrading;
        ColorModelRecipe colorModel = panel.Color.ColorModel;
        WarmthControl.Value = colorModel.Warmth;
        TintControl.Value = colorModel.Tint;
        VibranceControl.Value = colorModel.Vibrance;
        SaturationControl.Value = colorModel.Saturation;
        ColorDepthControl.Value = colorModel.ColorDepth;
        BwToningRecipe bwToning = panel.Color.BwToning;
        // macOS 는 흑백 필름에서만 이 섹션을 냅니다.
        BwToningSection.Visibility = panel.Color.ShowsBwToning
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
        PrimaryCalibrationRecipe calibration = panel.Color.PrimaryCalibration;
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
            panel.Tone.Shadows,
            panel.Tone.Density,
            panel.Tone.Exposure,
            panel.Tone.Highlights);
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
        // 레이어 강도를 끄는 동안에는 아직 저장하지 않은 값을 얹은 사본을 그립니다 — 저장은
        // 원본 파일 전체를 다시 해싱하므로 드래그 중에 하면 슬라이더가 멈춥니다.
        if (previewCoordinator is null || panel?.DefectLayers.PreviewFrame is not { } frame)
        {
            return;
        }
        _ = previewCoordinator.RequestAsync(frame, ShowPreview);
    }

    private void ShowPreview(PreviewOutcome outcome)
    {
        // 샘플러가 읽을 버퍼는 화면에 그린 것과 같아야 합니다 — 다른 것을 읽으면 보이는 색과
        // 적히는 수가 갈립니다.
        KeepPreviewPixels(outcome.Pixels, outcome.Width, outcome.Height);
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
        crop.MarkPreviewReady();
        RenderCropOverlay();
    }

    private void OnCropClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (crop.IsActive)
        {
            CancelCrop();
            return;
        }
        if (panel is null || panel.SelectedFrame is null || PreviewImage.Visibility != Visibility.Visible)
        {
            return;
        }

        // macOS와 같이 crop을 먼저 해제해 전체 프레임에서 새 선택을 만들게 합니다. 드래그 중
        // catalog를 쓰지 않고 Apply/Cancel에서 한 번만 저장합니다.
        if (panel.SetCrop(null) != LibraryFrameError.None)
        {
            return;
        }
        crop.Begin(panel.ImageTransform.Crop, LockedNormalizedAspectRatio());
        CropAngleDialControl.Visibility = Visibility.Visible;
        CanvasHost.Focus(FocusState.Programmatic);
        RequestPreview();
    }

    private void OnCropApplyClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (!crop.IsActive || panel is null)
        {
            return;
        }
        if (panel.SetCrop(crop.Apply()) != LibraryFrameError.None)
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
        if (!crop.Full())
        {
            return;
        }
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
        if (!crop.IsActive)
        {
            return;
        }
        ImageCropRect? restore = crop.Cancel();
        if (panel?.SetCrop(restore) != LibraryFrameError.None)
        {
            return;
        }
        EndCropSession();
        RequestPreview();
    }

    private void EndCropSession()
    {
        crop.End();
        CropOverlay.Visibility = Visibility.Collapsed;
        CropAngleDialControl.Visibility = Visibility.Collapsed;
    }

    private void OnCanvasSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        RenderCropOverlay();
        RenderGuidedDefectSelection();
    }

    private void OnCanvasPointerPressed(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (TryTogglePendingDefectComponent(args))
        {
            args.Handled = true;
            return;
        }
        if (TryBeginGuidedDefectSelection(args))
        {
            args.Handled = true;
            return;
        }
        if (TryBeginGrainMendStroke(args))
        {
            args.Handled = true;
            return;
        }
        if (!TryCanvasUnitPoint(args, out CropDisplayPoint point) || !crop.TryBeginDrag(point))
        {
            return;
        }
        CanvasHost.CapturePointer(args.Pointer);
        args.Handled = true;
    }

    private void OnCanvasPointerMoved(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        // 샘플러는 다른 도구를 막지 않습니다 — 값을 읽기만 하므로 크롭이나 브러시와 함께
        // 돌아도 서로 방해하지 않습니다.
        UpdatePixelSampler(args);
        if (TryContinueGuidedDefectSelection(args))
        {
            args.Handled = true;
            return;
        }
        if (TryContinueGrainMendStroke(args))
        {
            args.Handled = true;
            return;
        }
        if (!TryCanvasUnitPoint(args, out CropDisplayPoint point) || !crop.TryContinueDrag(point))
        {
            return;
        }
        RenderCropOverlay();
        args.Handled = true;
    }

    private void OnCanvasPointerReleased(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (TryFinishGuidedDefectSelection(args))
        {
            args.Handled = true;
            return;
        }
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
        EndGuidedDefectSelection(args);
        EndCropDrag(args);
    }

    private void OnCanvasPointerCaptureLost(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        EndGuidedDefectSelection(args);
        EndCropDrag(args);
    }

    private void EndCropDrag(PointerRoutedEventArgs args)
    {
        if (!crop.EndDrag())
        {
            return;
        }
        CanvasHost.ReleasePointerCapture(args.Pointer);
        args.Handled = true;
    }

    private bool TryBeginGuidedDefectSelection(PointerRoutedEventArgs args)
    {
        if (grainMend.Strokes.Tool != GrainMendTool.Guided || grainMend.IsDetecting ||
            panel?.SelectedFrame is null ||
            !TryCanvasUnitPoint(args, out CropDisplayPoint point))
        {
            return false;
        }
        guidedDefectDragStart = point;
        guidedDefectDragCurrent = point;
        guidedDefectDragging = true;
        RenderGuidedDefectSelection();
        CanvasHost.CapturePointer(args.Pointer);
        return true;
    }

    /// <summary>
    /// 보류 중인 자동/가이드 마스크의 연결 성분을 클릭하면 포함과 제외를 바꿉니다. 이 단계는
    /// recipe를 건드리지 않으며, Enter 또는 제거 단추를 눌러야만 sidecar로 갑니다.
    /// </summary>
    private bool TryTogglePendingDefectComponent(PointerRoutedEventArgs args)
    {
        if (grainMend.PendingReview is null || grainMend.PendingEdit is null ||
            panel?.SelectedFrame is not { SourceMetadata: { } metadata } frame ||
            !TryCanvasUnitPoint(args, out CropDisplayPoint displayPoint) ||
            !DevelopDisplayGeometry.TryMapDisplayToRaw(
                frame.ImageTransform,
                metadata.PixelWidth,
                metadata.PixelHeight,
                displayPoint.X,
                displayPoint.Y,
                out double rawX,
                out double rawY) ||
            !grainMend.ToggleReviewAtRaw(new DefectPoint(rawX, rawY)))
        {
            return false;
        }

        ExportStatusText.Text = AppResources.FormatIntegers(
            "developGrainMendFoundFormat",
            "Value",
            grainMend.IncludedCount);
        ShowDefectOverlay(grainMend.PendingEdit);
        UpdateGrainMendCard();
        return true;
    }

    private bool TryContinueGuidedDefectSelection(PointerRoutedEventArgs args)
    {
        if (!guidedDefectDragging || !TryCanvasUnitPoint(args, out CropDisplayPoint point))
        {
            return false;
        }
        guidedDefectDragCurrent = point;
        RenderGuidedDefectSelection();
        return true;
    }

    private bool TryFinishGuidedDefectSelection(PointerRoutedEventArgs args)
    {
        if (!guidedDefectDragging)
        {
            return false;
        }
        if (TryCanvasUnitPoint(args, out CropDisplayPoint point))
        {
            guidedDefectDragCurrent = point;
        }
        CanvasHost.ReleasePointerCapture(args.Pointer);
        guidedDefectDragging = false;
        GuidedDefectOverlay.Visibility = Visibility.Collapsed;

        double width = Math.Abs(guidedDefectDragCurrent.X - guidedDefectDragStart.X);
        double height = Math.Abs(guidedDefectDragCurrent.Y - guidedDefectDragStart.Y);
        if (width <= 0.012 || height <= 0.012 || panel is null)
        {
            return true;
        }
        DefectRect displayRoi = new(
            Math.Min(guidedDefectDragStart.X, guidedDefectDragCurrent.X),
            Math.Min(guidedDefectDragStart.Y, guidedDefectDragCurrent.Y),
            width,
            height);
        if (panel.TryMapDisplayRectToRaw(displayRoi, out DefectRect rawRoi))
        {
            _ = DetectGrainMendAsync(rawRoi);
        }
        return true;
    }

    private void EndGuidedDefectSelection(PointerRoutedEventArgs args)
    {
        if (!guidedDefectDragging)
        {
            return;
        }
        CanvasHost.ReleasePointerCapture(args.Pointer);
        guidedDefectDragging = false;
        GuidedDefectOverlay.Visibility = Visibility.Collapsed;
    }

    private void RenderGuidedDefectSelection()
    {
        if (!guidedDefectDragging || !TryGetPreviewFrame(out PreviewFrame frame))
        {
            GuidedDefectOverlay.Visibility = Visibility.Collapsed;
            return;
        }
        double x = Math.Min(guidedDefectDragStart.X, guidedDefectDragCurrent.X);
        double y = Math.Min(guidedDefectDragStart.Y, guidedDefectDragCurrent.Y);
        double selectionWidth = Math.Abs(guidedDefectDragCurrent.X - guidedDefectDragStart.X);
        double selectionHeight = Math.Abs(guidedDefectDragCurrent.Y - guidedDefectDragStart.Y);
        Place(
            GuidedDefectSelection,
            frame.Left + x * frame.Width,
            frame.Top + y * frame.Height,
            selectionWidth * frame.Width,
            selectionHeight * frame.Height);
        GuidedDefectOverlay.Visibility = Visibility.Visible;
    }

    private void OnCanvasKeyDown(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        // 검토 중인 검출이 있으면 그것이 먼저입니다. 도움말이 안내하는 대로 Enter 가 받아들이고
        // Esc 가 버립니다.
        if (grainMend.PendingEdit is not null)
        {
            if (args.Key == VirtualKey.Enter)
            {
                AcceptPendingDefectEdit();
                args.Handled = true;
                return;
            }
            if (args.Key == VirtualKey.Escape)
            {
                CancelPendingDefectEdit();
                args.Handled = true;
                return;
            }
        }
        if (args.Key == VirtualKey.Escape && grainMend.Strokes.Tool == GrainMendTool.Guided)
        {
            SetGrainMendTool(GrainMendTool.None);
            args.Handled = true;
        }
        if (!crop.IsActive)
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
                crop.TryMove(-step, 0.0);
                break;
            case VirtualKey.Right:
                crop.TryMove(step, 0.0);
                break;
            case VirtualKey.Up:
                crop.TryMove(0.0, -step);
                break;
            case VirtualKey.Down:
                crop.TryMove(0.0, step);
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
        if (!TryGetPreviewFrame(out PreviewFrame frame))
        {
            point = default;
            return false;
        }
        return frame.TryMapPoint(position.X, position.Y, out point);
    }

    private bool TryGetPreviewFrame(out PreviewFrame frame)
    {
        if (previewBitmap is null)
        {
            frame = default;
            return false;
        }
        return PreviewFrame.TryFrom(
            CanvasHost.ActualWidth,
            CanvasHost.ActualHeight,
            previewBitmap.PixelWidth,
            previewBitmap.PixelHeight,
            out frame);
    }

    private void RenderCropOverlay()
    {
        if (crop.Session is not { } session || crop.AwaitingPreview ||
            !TryGetPreviewFrame(out PreviewFrame frame))
        {
            CropOverlay.Visibility = Visibility.Collapsed;
            return;
        }

        // 기하는 CropInteraction 이 계산합니다. 뷰는 계산된 자리에 요소를 놓기만 합니다.
        CropOverlayLayout layout = CropInteraction.Layout(
            frame,
            session.Selection,
            CropActionBar.ActualHeight);
        CropOverlay.Visibility = Visibility.Visible;
        Place(CropDimTop, layout.DimTop);
        Place(CropDimBottom, layout.DimBottom);
        Place(CropDimLeft, layout.DimLeft);
        Place(CropDimRight, layout.DimRight);
        Place(CropSelection, layout.Selection);
        Place(CropThirdVerticalFirst, layout.ThirdVerticalFirst);
        Place(CropThirdVerticalSecond, layout.ThirdVerticalSecond);
        Place(CropThirdHorizontalFirst, layout.ThirdHorizontalFirst);
        Place(CropThirdHorizontalSecond, layout.ThirdHorizontalSecond);
        Place(CropHandleTopLeft, layout.HandleTopLeft);
        Place(CropHandleTop, layout.HandleTop);
        Place(CropHandleTopRight, layout.HandleTopRight);
        Place(CropHandleRight, layout.HandleRight);
        Place(CropHandleBottomRight, layout.HandleBottomRight);
        Place(CropHandleBottom, layout.HandleBottom);
        Place(CropHandleBottomLeft, layout.HandleBottomLeft);
        Place(CropHandleLeft, layout.HandleLeft);
        Canvas.SetLeft(CropActionBar, layout.ActionBarLeft);
        Canvas.SetTop(CropActionBar, layout.ActionBarTop);
    }

    private static void Place(FrameworkElement element, double left, double top, double width, double height)
    {
        element.Width = width;
        element.Height = height;
        Canvas.SetLeft(element, left);
        Canvas.SetTop(element, top);
    }

    private static void Place(FrameworkElement element, CropOverlayPlacement placement) =>
        Place(element, placement.Left, placement.Top, placement.Width, placement.Height);

    private static void Place(
        Microsoft.UI.Xaml.Shapes.Line line,
        (double X1, double Y1, double X2, double Y2) segment)
    {
        line.X1 = segment.X1;
        line.Y1 = segment.Y1;
        line.X2 = segment.X2;
        line.Y2 = segment.Y2;
    }

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
        ScannerProfileSelector.SelectedItem = ScannerProfileSelector.Items
            .OfType<ScannerProfileChoice>()
            .FirstOrDefault(choice => choice.Id == panel.SelectedFrame?.Base.ScannerProfileId);
        isSynchronizingInspector = false;
        FilmBaseControls.Visibility = canEdit && panel.BaseMode == BaseEstimationMode.Preset
            ? Visibility.Visible
            : Visibility.Collapsed;
        FilmStockSelector.IsEnabled = canEdit && panel.BaseMode == BaseEstimationMode.Preset;
        LightSourceSelector.IsEnabled = canEdit && panel.BaseMode == BaseEstimationMode.Preset;
        ScannerProfileSelector.IsEnabled = canEdit && panel.BaseMode == BaseEstimationMode.Preset;
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
                    ? panel.Tone.ApplyAutoTone(outcome.Settings)
                    : panel.Tone.ApplyAutoWhiteBalance(outcome.Settings);
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

    /// <summary>
    /// 프로파일 목록입니다. macOS 처럼 이름 뒤에 검증 상태를 붙입니다 — 같은 스캐너의 프로파일이
    /// 여럿일 때 무엇으로 만들어진 것인지가 고르는 근거입니다.
    /// </summary>
    private static IReadOnlyList<ScannerProfileChoice> ScannerProfileChoices()
    {
        List<ScannerProfileChoice> choices =
        [
            new(null, AppResources.Get("developScannerProfileNone", "Text")),
        ];
        foreach (ScannerProfileOption option in BundledFilmBaseOptions.ScannerProfiles)
        {
            choices.Add(new ScannerProfileChoice(
                option.Id,
                $"{option.DisplayName} · {StatusLabel(option.Status)}"));
        }
        return choices;
    }

    private static string StatusLabel(ScannerProfileValidationStatus status) =>
        AppResources.Get(status switch
        {
            ScannerProfileValidationStatus.Draft => "developProfileStatusDraft",
            ScannerProfileValidationStatus.PairedSmoke => "developProfileStatusPairedSmoke",
            ScannerProfileValidationStatus.PairedValidated =>
                "developProfileStatusPairedValidated",
            _ => "developProfileStatusRealOnly",
        }, "Text");

    private void OnScannerProfileSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizingInspector ||
            panel.SetScannerProfile(
                (ScannerProfileSelector.SelectedItem as ScannerProfileChoice)?.Id) !=
                LibraryFrameError.None)
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
            DevelopHistogramRegion.Shadow => panel.Tone.SetShadows(args.Value),
            DevelopHistogramRegion.Density => panel.Tone.SetDensity(args.Value),
            DevelopHistogramRegion.Exposure => panel.Tone.SetExposure(args.Value),
            DevelopHistogramRegion.Highlight => panel.Tone.SetHighlights(args.Value),
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
        panel.Tone.SetExposure(args.Value);
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
                panel.Tone.SetContrast(args.Value),
            InspectorSlider control when ReferenceEquals(control, HighlightsControl) =>
                panel.Tone.SetHighlights(args.Value),
            InspectorSlider control when ReferenceEquals(control, ShadowsControl) =>
                panel.Tone.SetShadows(args.Value),
            InspectorSlider control when ReferenceEquals(control, WhitesControl) =>
                panel.Tone.SetWhites(args.Value),
            InspectorSlider control when ReferenceEquals(control, BlacksControl) =>
                panel.Tone.SetBlacks(args.Value),
            InspectorSlider control when ReferenceEquals(control, DensityControl) =>
                panel.Tone.SetDensity(args.Value),
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
                panel.Tone.SetCurveHighlights(args.Value),
            InspectorSlider control when ReferenceEquals(control, CurveLightsControl) =>
                panel.Tone.SetCurveLights(args.Value),
            InspectorSlider control when ReferenceEquals(control, CurveDarksControl) =>
                panel.Tone.SetCurveDarks(args.Value),
            InspectorSlider control when ReferenceEquals(control, CurveShadowsControl) =>
                panel.Tone.SetCurveShadows(args.Value),
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
        if (panel.Color.SetPointCurves(args.Curves) == LibraryFrameError.None)
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
        if (panel.Color.SetColorMixer(args.Mixer) == LibraryFrameError.None)
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
        if (panel.Color.SetColorGrading(args.Grading) == LibraryFrameError.None)
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
        if (panel.Color.SetColorModel(panel.Color.ColorModel with
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
        if (panel.Color.SetBwToningMode(mode) == LibraryFrameError.None)
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
        if (panel.Color.SetBwToning(panel.Color.BwToning with
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
        if (panel is null || panel.Color.ResetBwToning() != LibraryFrameError.None)
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
        if (panel.Color.SetPrimaryCalibration(new PrimaryCalibrationRecipe(
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

    /// <summary>macOS <c>WorkflowSidebarTab</c>과 같은 현상 왼쪽 소스를 바꿉니다.</summary>
    private void OnDevelopSourceRailClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not Button { Tag: string tag } ||
            !Enum.TryParse(tag, out WorkflowSidebarTab kind))
        {
            return;
        }
        developSource = kind;
        workspaceState?.SelectDevelopSidebarTab(kind);
        UpdateDevelopSourcePanel();
    }

    private void UpdateDevelopSourcePanel()
    {
        LibrarySourcePanel.Visibility = Show(WorkflowSidebarTab.Library);
        if (developSource == WorkflowSidebarTab.Library)
        {
            RebuildDevelopLibraryTree();
        }
        DevelopFilesSourceTree.Visibility = Show(WorkflowSidebarTab.Files);
        if (developSource == WorkflowSidebarTab.Files)
        {
            RebuildDevelopFilesTree();
        }
        VersionsSourcePanel.Visibility = Show(WorkflowSidebarTab.Versions);
        PresetsSourcePanel.Visibility = Show(WorkflowSidebarTab.Presets);
        FilmSourcePanel.Visibility = Show(WorkflowSidebarTab.Film);
        ExportPanel.Visibility = Show(WorkflowSidebarTab.Output);

        (string headerKey, string glyph) = developSource switch
        {
            WorkflowSidebarTab.Files => ("sidebarFiles", ""),
            WorkflowSidebarTab.Versions => ("developSectionVersions", ""),
            WorkflowSidebarTab.Presets => ("developSectionPresets", "\uE9E9"),
            WorkflowSidebarTab.Film => ("developSectionFilm", ""),
            WorkflowSidebarTab.Output => ("developSectionOutput", ""),
            _ => ("developLibrary", ""),
        };
        LibraryHeaderText.Text = AppResources.Get(headerKey, "Text");
        DevelopSourceIcon.Glyph = glyph;

        var accent = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["AccentTextFillColorPrimaryBrush"];
        var normal = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorPrimaryBrush"];
        var selection = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["NegaflowSelectionBrush"];
        foreach ((Button button, FontIcon icon, WorkflowSidebarTab kind) in DevelopSourceRailButtons())
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
        ExportPanel.RefreshPreview();
        UpdateFilmLookControls();
        UpdatePresetControls();
    }

    /// <summary>
    /// 라이브러리와 같은 폴더 트리입니다. 같은 투영을 쓰므로 두 화면이 서로 다른 폴더 목록을
    /// 보여 주지 않습니다.
    /// </summary>
    private void RebuildDevelopFilesTree()
    {
        DevelopFilesSourceTree.RootNodes.Clear();
        if (libraryHost is null)
        {
            return;
        }
        LibraryBrowserProjection projection = LibraryBrowserProjector.Create(
            LibraryFrameListItems.From(
                libraryHost.Frames,
                libraryHost.SourceAvailabilityByFrameId),
            libraryHost.Folders,
            libraryHost.FolderAvailabilityById,
            LibraryBrowserViewMode.Folders);
        AddDevelopFolderNodes(DevelopFilesSourceTree, projection.FolderSections);
    }

    /// <summary>
    /// macOS combined Library 탭처럼 현재 frame이 든 폴더만 보입니다. Files 탭은 전체 폴더를
    /// 보이므로 두 탭의 역할을 섞지 않습니다.
    /// </summary>
    private void RebuildDevelopLibraryTree()
    {
        DevelopLibrarySourceTree.RootNodes.Clear();
        if (libraryHost?.ActiveFrameId is not { } activeFrameId)
        {
            return;
        }
        LibraryBrowserProjection projection = LibraryBrowserProjector.Create(
            LibraryFrameListItems.From(
                libraryHost.Frames,
                libraryHost.SourceAvailabilityByFrameId),
            libraryHost.Folders,
            libraryHost.FolderAvailabilityById,
            LibraryBrowserViewMode.Folders);
        AddDevelopFolderNodes(
            DevelopLibrarySourceTree,
            projection.FolderSections.Where(section =>
                section.Items.Any(item => string.Equals(
                    item.Id,
                    activeFrameId,
                    StringComparison.Ordinal))));
    }

    private static void AddDevelopFolderNodes(
        TreeView tree,
        IEnumerable<LibraryBrowserFolderSection> sections)
    {
        foreach (LibraryBrowserFolderSection section in sections)
        {
            var folder = new TreeViewNode
            {
                Content = LibrarySourceNode.Folder(
                    section.Title,
                    AppResources.FormatIntegers("libraryFolderFrameCount", "Text", section.Count)),
            };
            foreach (LibraryFrameListItem item in section.Items)
            {
                folder.Children.Add(new TreeViewNode
                {
                    Content = LibrarySourceNode.Frame(item.DisplayName, item.Id),
                });
            }
            tree.RootNodes.Add(folder);
        }
    }

    /// <summary>트리에서 frame 을 누르면 그 장을 현상 대상으로 잡습니다.</summary>
    private void OnDevelopFilesTreeItemInvoked(TreeView sender, TreeViewItemInvokedEventArgs args)
    {
        SelectDevelopTreeFrame(args);
    }

    private void OnDevelopLibraryTreeItemInvoked(TreeView sender, TreeViewItemInvokedEventArgs args)
    {
        SelectDevelopTreeFrame(args);
    }

    private void SelectDevelopTreeFrame(TreeViewItemInvokedEventArgs args)
    {
        if (args.InvokedItem is not TreeViewNode { Content: LibrarySourceNode node } ||
            node.FrameId is not { } frameId ||
            panel is null)
        {
            return;
        }
        panel.Select(frameId);
        SynchronizeInspectorValues();
        RequestPreview();
        RebuildDevelopLibraryTree();
    }

    private Visibility Show(WorkflowSidebarTab kind) =>
        developSource == kind ? Visibility.Visible : Visibility.Collapsed;

    private IEnumerable<(Button Button, FontIcon Icon, WorkflowSidebarTab Kind)> DevelopSourceRailButtons()
    {
        yield return (LibraryRailButton, LibraryRailIcon, WorkflowSidebarTab.Library);
        yield return (FilesRailButton, FilesRailIcon, WorkflowSidebarTab.Files);
        yield return (VersionsRailButton, VersionsRailIcon, WorkflowSidebarTab.Versions);
        yield return (PresetsRailButton, PresetsRailIcon, WorkflowSidebarTab.Presets);
        yield return (FilmRailButton, FilmRailIcon, WorkflowSidebarTab.Film);
        yield return (OutputRailButton, OutputRailIcon, WorkflowSidebarTab.Output);
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

    private static string DescribePasteScope(DevelopSettingsPasteScope scope) =>
        PasteScopeSummary.Describe(
            scope,
            new PasteScopeText(
                AppResources.Get("developPasteScopeAll", "Text"),
                AppResources.Get("developPasteScopeNone", "Text"),
                AppResources.Get("developScopeBase", "Text"),
                AppResources.Get("developScopeTone", "Text"),
                AppResources.Get("developScopeColor", "Text"),
                AppResources.Get("developScopeDetail", "Text"),
                AppResources.Get("developScopeGeometry", "Text")));

    private bool updatingGrainMendSensitivity;
    private bool updatingGrainMendMicroSpecks;

    private async void OnGrainMendAutoClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetGrainMendTool(GrainMendTool.None);
        await DetectGrainMendAsync(new DefectRect(0.0, 0.0, 1.0, 1.0));
    }

    private void OnGrainMendGuidedClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ClearPendingDefectEdit();
        SetGrainMendTool(grainMend.Strokes.Tool == GrainMendTool.Guided
            ? GrainMendTool.None
            : GrainMendTool.Guided);
        if (grainMend.Strokes.Tool == GrainMendTool.Guided)
        {
            _ = CanvasHost.Focus(FocusState.Programmatic);
        }
    }

    private async Task DetectGrainMendAsync(DefectRect rawRoi)
    {
        if (panel?.SelectedFrame is not { } frame || grainMendDetectCoordinator is null ||
            grainMend.IsDetecting)
        {
            return;
        }
        grainMend.BeginDetection();
        HideDefectOverlay();
        ExportStatusText.Text = AppResources.Get("developGrainMendDetecting", "Text");
        UpdateGrainMendCard();
        try
        {
            bool automatic = IsWholeFrameGrainMendRoi(rawRoi);
            GrainMendDetectionOptions options = GrainMendSensitivity.ToDetectionOptions(
                GetGrainMendSensitivity(automatic),
                automatic,
                GetGrainMendMicroSpecks(automatic));
            await grainMendDetectCoordinator.RunAsync(
                frame,
                rawRoi,
                options,
                outcome => ShowDetectedDefects(outcome, rawRoi));
        }
        finally
        {
            grainMend.EndDetection();
            UpdateGrainMendCard();
        }
    }

    private void ShowDetectedDefects(GrainMendDetectOutcome outcome, DefectRect rawRoi)
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

        if (!grainMend.SetDetectedEdit(edit, rawRoi))
        {
            ExportStatusText.Text = AppResources.Get("developGrainMendFoundNothing", "Text");
            return;
        }
        ExportStatusText.Text = AppResources.FormatIntegers(
            "developGrainMendFoundFormat",
            "Value",
            grainMend.IncludedCount);
        ShowDefectOverlay(edit);
        UpdateGrainMendCard();
        // Enter 와 Esc 를 받으려면 캔버스가 초점을 가져야 합니다.
        _ = CanvasHost.Focus(FocusState.Programmatic);
    }

    /// <summary>
    /// 마스크를 미리보기 위에 얹습니다. 표시된 화소만 칠하고 나머지는 완전히 투명하게 둡니다 —
    /// 반투명한 판을 통째로 덮으면 사진이 아니라 판을 보게 됩니다.
    /// </summary>
    private void ShowDefectOverlay(DefectEditItem edit)
    {
        if (panel?.SelectedFrame is not { } frame || previewBitmap is null)
        {
            return;
        }

        int width = previewBitmap.PixelWidth;
        int height = previewBitmap.PixelHeight;
        if (GrainMendOverlayRenderer.Render(
                frame,
                width,
                height,
                edit,
                grainMend.PendingReview) is not { } bgra)
        {
            return;
        }
        WriteableBitmap bitmap = new(width, height);
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
        grainMend.ClearPending();
        HideDefectOverlay();
    }

    private void HideDefectOverlay()
    {
        DefectOverlayImage.Source = null;
        DefectOverlayImage.Visibility = Visibility.Collapsed;
    }

    private static bool IsWholeFrameGrainMendRoi(DefectRect roi) =>
        roi.X == 0.0 && roi.Y == 0.0 && roi.Width == 1.0 && roi.Height == 1.0;

    private double GetGrainMendSensitivity(bool automatic)
    {
        return panel?.SelectedFrame is { } frame
            ? grainMend.Sensitivity(frame.Id, automatic)
            : GrainMendSensitivity.Default;
    }

    private void SetGrainMendSensitivity(bool automatic, double value)
    {
        if (panel?.SelectedFrame is not { } frame)
        {
            return;
        }
        grainMend.SetSensitivity(frame.Id, automatic, value);
    }

    private bool GetGrainMendMicroSpecks(bool automatic)
    {
        return panel?.SelectedFrame is { } frame
            ? grainMend.MicroSpecks(
                frame.Id,
                automatic,
                MicroSpeckDefault(automatic: true),
                MicroSpeckDefault(automatic: false))
            : MicroSpeckDefault(automatic);
    }

    /// <summary>설정에 담긴 기본값입니다. 설정을 못 읽으면 macOS 기본인 켬입니다.</summary>
    private bool MicroSpeckDefault(bool automatic) =>
        workspaceState?.Current is { } preferences
            ? automatic
                ? preferences.AutoDefectDetectsMicroSpecks
                : preferences.GuidedDefectDetectsMicroSpecks
            : true;

    private void SetGrainMendMicroSpecks(bool automatic, bool enabled)
    {
        if (panel?.SelectedFrame is not { } frame)
        {
            return;
        }
        grainMend.SetMicroSpecks(
            frame.Id,
            automatic,
            enabled,
            MicroSpeckDefault(automatic: true),
            MicroSpeckDefault(automatic: false));
    }

    private void OnGrainMendSensitivityValueChanged(
        object sender,
        RangeBaseValueChangedEventArgs args)
    {
        _ = sender;
        if (updatingGrainMendSensitivity || grainMend.PendingEdit is null)
        {
            return;
        }
        SetGrainMendSensitivity(
            grainMend.PendingEdit.Label.Kind == DefectEditLabelKind.Automatic,
            args.NewValue);
    }

    private async void OnGrainMendSensitivityPointerReleased(
        object sender,
        PointerRoutedEventArgs args)
    {
        _ = sender;
        args.Handled = true;
        await RedetectGrainMendForSensitivityAsync();
    }

    private async void OnGrainMendSensitivityKeyUp(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        await RedetectGrainMendForSensitivityAsync();
    }

    private async Task RedetectGrainMendForSensitivityAsync()
    {
        if (grainMend.TakeSensitivityRedetectionRoi() is not { } rawRoi)
        {
            return;
        }
        await DetectGrainMendAsync(rawRoi);
    }

    private async void OnGrainMendMicroSpecksToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (updatingGrainMendMicroSpecks || grainMend.PendingEdit is null ||
            grainMend.PendingRawRoi is not { } rawRoi || grainMend.IsDetecting)
        {
            return;
        }
        bool automatic = grainMend.PendingEdit.Label.Kind == DefectEditLabelKind.Automatic;
        SetGrainMendMicroSpecks(automatic, GrainMendMicroSpecksToggle.IsOn);
        await DetectGrainMendAsync(rawRoi);
    }

    /// <summary>검토 중인 검출을 받아들여 recipe 에 담습니다.</summary>
    private void AcceptPendingDefectEdit()
    {
        if (panel is null || grainMend.PendingEdit is null)
        {
            return;
        }
        DefectEditItem? edit = grainMend.BuildAcceptedEdit();
        if (edit is null)
        {
            CancelPendingDefectEdit();
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

    private void CancelPendingDefectEdit()
    {
        ClearPendingDefectEdit();
        ExportStatusText.Text = string.Empty;
        UpdateGrainMendCard();
    }

    private void OnGrainMendRemoveClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        AcceptPendingDefectEdit();
    }

    private void OnGrainMendCancelClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        CancelPendingDefectEdit();
    }

    private void OnGrainMendBrushClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetGrainMendTool(grainMend.Strokes.Tool == GrainMendTool.Brush
            ? GrainMendTool.None
            : GrainMendTool.Brush);
    }

    private void OnGrainMendCloneClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetGrainMendTool(grainMend.Strokes.Tool == GrainMendTool.Clone
            ? GrainMendTool.None
            : GrainMendTool.Clone);
    }

    private void OnGrainMendAutoResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ClearPendingDefectEdit();
        RemoveGrainMendEdits(DefectEditLabelKind.Automatic);
    }

    private void OnGrainMendGuidedResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ClearPendingDefectEdit();
        RemoveGrainMendEdits(DefectEditLabelKind.Guided);
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

    private void RemoveGrainMendEdits(DefectEditLabelKind label)
    {
        if (panel is null)
        {
            return;
        }
        SetGrainMendTool(GrainMendTool.None);
        if (panel.RemoveDefectEdits(label) != LibraryFrameError.None)
        {
            return;
        }
        UpdateGrainMendCard();
        RequestPreview();
    }

    private void SetGrainMendTool(GrainMendTool tool)
    {
        if (grainMend.Strokes.Tool == tool)
        {
            return;
        }
        grainMend.Strokes.Select(tool);
        if (tool != GrainMendTool.Guided)
        {
            guidedDefectDragging = false;
            GuidedDefectOverlay.Visibility = Visibility.Collapsed;
        }
        if (tool != GrainMendTool.None && crop.IsActive)
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
        GrainMendAutoText.Text = AppResources.Get("developGrainMendAuto", "Content");
        GrainMendGuidedText.Text = AppResources.Get("developGrainMendGuided", "Content");
        GrainMendBrushText.Text = AppResources.Get("developGrainMendBrush", "Content");
        GrainMendCloneText.Text = AppResources.Get("developGrainMendClone", "Content");
        GrainMendRemoveButton.Content = AppResources.Get("developGrainMendRemove", "Content");
        GrainMendCancelButton.Content = AppResources.Get("developCropCancel", "Text");
        GrainMendSensitivityLabel.Text = AppResources.Get("developGrainMendSensitivity", "Text");
        SetLocalizedNameAndTooltip(
            GrainMendBrushButton, AppResources.Get("developGrainMendBrushHelp", "Value"));
        SetLocalizedNameAndTooltip(
            GrainMendCloneButton, AppResources.Get("developGrainMendCloneHelp", "Value"));
        SetLocalizedNameAndTooltip(
            GrainMendAutoButton, AppResources.Get("developGrainMendAutoHelp", "Value"));
        SetLocalizedNameAndTooltip(
            GrainMendGuidedButton,
            AppResources.Get("developGrainMendGuidedHelp", "Value"));
        SetLocalizedNameAndTooltip(
            GrainMendRemoveButton, AppResources.Get("developGrainMendRemove", "Content"));
        SetLocalizedNameAndTooltip(
            GrainMendCancelButton, AppResources.Get("developCropCancel", "Text"));
        string grainMendSensitivity = AppResources.Get("developGrainMendSensitivity", "Text");
        AutomationProperties.SetName(GrainMendSensitivitySlider, grainMendSensitivity);
        ToolTipService.SetToolTip(GrainMendSensitivitySlider, grainMendSensitivity);
        string grainMendMicroSpecks = AppResources.Get("developGrainMendMicroSpecks", "Text");
        GrainMendMicroSpecksToggle.OnContent = grainMendMicroSpecks;
        GrainMendMicroSpecksToggle.OffContent = grainMendMicroSpecks;
        AutomationProperties.SetName(GrainMendMicroSpecksToggle, grainMendMicroSpecks);
        ToolTipService.SetToolTip(GrainMendMicroSpecksToggle, grainMendMicroSpecks);
        GrainMendCardState card = GrainMendCardProjection.Create(
            panel?.SelectedFrame is not null,
            grainMend.IsDetecting,
            grainMend.PendingEdit?.Label.Kind,
            grainMend.PendingReview?.IncludedCount,
            grainMend.Strokes.Tool,
            panel?.HasDefectEdits(DefectEditLabelKind.Automatic) == true,
            panel?.HasDefectEdits(DefectEditLabelKind.Guided) == true,
            panel?.HasDefectEdits(DefectEditKind.Brush) == true,
            panel?.HasDefectEdits(DefectEditKind.Clone) == true);
        GrainMendAutoButton.IsEnabled = card.AutoEnabled;
        GrainMendAutoResetButton.IsEnabled = card.AutoResetEnabled;
        GrainMendGuidedButton.IsEnabled = card.GuidedEnabled;
        GrainMendGuidedResetButton.IsEnabled = card.GuidedResetEnabled;
        GrainMendReviewTuning.Visibility = card.Reviewing ? Visibility.Visible : Visibility.Collapsed;
        GrainMendReviewActions.Visibility = card.Reviewing ? Visibility.Visible : Visibility.Collapsed;
        GrainMendSensitivitySlider.IsEnabled = card.SensitivityEnabled;
        GrainMendMicroSpecksToggle.IsEnabled = card.MicroSpecksEnabled;
        if (card.Reviewing)
        {
            updatingGrainMendSensitivity = true;
            GrainMendSensitivitySlider.Value = GetGrainMendSensitivity(card.ReviewingAutomatic);
            updatingGrainMendSensitivity = false;
            updatingGrainMendMicroSpecks = true;
            GrainMendMicroSpecksToggle.IsOn = GetGrainMendMicroSpecks(card.ReviewingAutomatic);
            updatingGrainMendMicroSpecks = false;
        }
        GrainMendRemoveButton.IsEnabled = card.RemoveEnabled;
        GrainMendCancelButton.IsEnabled = card.CancelEnabled;

        string reset = AppResources.Get("developGrainMendReset", "Value");
        SetLocalizedNameAndTooltip(GrainMendAutoResetButton, reset);
        SetLocalizedNameAndTooltip(GrainMendGuidedResetButton, reset);
        SetLocalizedNameAndTooltip(GrainMendBrushResetButton, reset);
        SetLocalizedNameAndTooltip(GrainMendCloneResetButton, reset);

        GrainMendBrushButton.IsEnabled = card.BrushEnabled;
        GrainMendCloneButton.IsEnabled = card.CloneEnabled;
        GrainMendBrushResetButton.IsEnabled = card.BrushResetEnabled;
        GrainMendCloneResetButton.IsEnabled = card.CloneResetEnabled;

        ApplyGrainMendPill(GrainMendAutoPill, GrainMendAutoButton, card.AutoActive);
        ApplyGrainMendPill(GrainMendGuidedPill, GrainMendGuidedButton, card.GuidedActive);
        ApplyGrainMendPill(GrainMendBrushPill, GrainMendBrushButton, card.BrushActive);
        ApplyGrainMendPill(GrainMendClonePill, GrainMendCloneButton, card.CloneActive);
        // 카드가 바뀌는 모든 자리는 목록도 바뀌는 자리입니다. 열두 군데를 따로 부르면
        // 언젠가 한 군데가 빠지고 목록만 옛 값을 붙듭니다.
        UpdateDefectLayers();
    }

    /// <summary>
    /// macOS InspectorActionPill 의 켜짐 표시입니다. 캡슐 바탕과 낭독기 상태가 함께 바뀌어야
    /// 눈으로 보는 것과 읽어 주는 것이 어긋나지 않습니다.
    /// </summary>
    private static void ApplyGrainMendPill(Border pill, Button action, bool isActive)
    {
        pill.Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources[
            isActive ? "NegaflowSelectionBrush" : "NegaflowSubtleFillBrush"];
        AutomationProperties.SetItemStatus(
            action,
            AppResources.Get(isActive ? "selected" : "notSelected", "Value"));
    }

    /// <summary>
    /// 도구가 잡고 있으면 포인터를 가로챕니다. 크롭 세션과 같은 이벤트를 쓰므로 어느 쪽이
    /// 먼저인지가 분명해야 합니다 — 도구가 켜져 있으면 크롭은 이미 꺼져 있습니다.
    /// </summary>
    private bool TryBeginGrainMendStroke(PointerRoutedEventArgs args)
    {
        if (panel?.SelectedFrame is null ||
            !TryCanvasUnitPoint(args, out CropDisplayPoint point))
        {
            return false;
        }

        bool alt = InputKeyboardSource
            .GetKeyStateForCurrentThread(Windows.System.VirtualKey.Menu)
            .HasFlag(CoreVirtualKeyStates.Down);
        bool handled = grainMend.Strokes.Begin(
            new DefectPoint(point.X, point.Y),
            alt);
        if (grainMend.Strokes.IsDragging)
        {
            CanvasHost.CapturePointer(args.Pointer);
        }
        return handled;
    }

    private bool TryContinueGrainMendStroke(PointerRoutedEventArgs args)
    {
        if (!TryCanvasUnitPoint(args, out CropDisplayPoint point))
        {
            return false;
        }
        return grainMend.Strokes.Continue(new DefectPoint(point.X, point.Y));
    }

    private bool TryFinishGrainMendStroke(PointerRoutedEventArgs args)
    {
        if (!grainMend.Strokes.IsDragging)
        {
            return false;
        }
        CanvasHost.ReleasePointerCapture(args.Pointer);
        if (panel is null)
        {
            grainMend.Strokes.CancelStroke();
            return true;
        }
        if (!grainMend.Strokes.Finish(panel, out LibraryFrameError error))
        {
            return false;
        }
        if (error == LibraryFrameError.None)
        {
            UpdateGrainMendCard();
            RequestPreview();
        }
        return true;
    }

    /// <summary>정보 카드 한 줄입니다.</summary>
    /// <summary>
    /// macOS 정보 카드의 여섯 줄입니다. 원본과 Sidecar 는 지금 알 수 있는 사실이고, 카메라·날짜·
    /// 제목·키워드는 아직 EXIF/IPTC 를 읽지 않으므로 macOS 의 빈 상태와 같은 "— · —" 입니다.
    /// 읽지 않은 값을 추측해서 채우지 않습니다.
    /// </summary>
    /// <summary>
    /// 적어 둔 메타데이터를 컨트롤에 되비춥니다. 값이 없으면 빈 칸이고, placeholder 가 무엇을
    /// 적는 자리인지 말합니다 — macOS 도 라벨 대신 placeholder 를 씁니다.
    /// </summary>
    private void UpdateAppMetadataCards()
    {
        if (AppMetadataTitleBox is null)
        {
            return;
        }
        bool onInfoTab = inspectorPresentation.SelectedTab == DevelopInspectorTab.Info;
        bool hasFrame = panel?.SelectedFrame is not null;
        AppMetadataCard.Visibility = onInfoTab && hasFrame
            ? Visibility.Visible
            : Visibility.Collapsed;
        FilmShotCard.Visibility = AppMetadataCard.Visibility;
        if (panel?.SelectedFrame is not { } frame)
        {
            return;
        }

        AppMetadataOverlay overlay = frame.AppMetadata ?? new AppMetadataOverlay();
        FilmShotMetadata shot = overlay.FilmShot ?? new FilmShotMetadata();
        isSynchronizingMetadata = true;
        try
        {
            AppMetadataTitleBox.Text = overlay.Title ?? string.Empty;
            AppMetadataCaptionBox.Text = overlay.Caption ?? string.Empty;
            AppMetadataKeywordsBox.Text = string.Join(", ", overlay.Keywords);
            AppMetadataCopyrightBox.Text = overlay.Copyright ?? string.Empty;
            FilmShotCameraMakeBox.Text = shot.CameraMake ?? string.Empty;
            FilmShotCameraModelBox.Text = shot.CameraModel ?? string.Empty;
            FilmShotLensModelBox.Text = shot.LensModel ?? string.Empty;
            FilmShotFilmStockBox.Text = shot.FilmStock ?? string.Empty;
            FilmShotIsoSpeedBox.Text = shot.IsoSpeed?.ToString(CultureInfo.CurrentCulture)
                ?? string.Empty;
            FilmShotShutterBox.Text = DevelopMetadataFields.FormatShutter(shot.ExposureTimeSeconds);
            FilmShotApertureBox.Text = shot.FNumber?.ToString("0.##", CultureInfo.CurrentCulture)
                ?? string.Empty;
            FilmShotFocalLengthBox.Text =
                shot.FocalLengthMm?.ToString("0.##", CultureInfo.CurrentCulture) ?? string.Empty;
        }
        finally
        {
            isSynchronizingMetadata = false;
        }
        AppMetadataSavedText.Text = overlay.IsEmpty
            ? string.Empty
            : AppResources.Get("developAppMetadataSaved", "Text");
    }

    /// <summary>
    /// 칸을 떠날 때 한 번만 씁니다. 글자마다 카탈로그를 건드리면 5만 행짜리 저장이 타이핑마다
    /// 돕니다.
    /// </summary>
    private void OnAppMetadataCommitted(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingMetadata || panel is null)
        {
            return;
        }
        FilmShotMetadata shot = new(
            FilmShotCameraMakeBox.Text,
            FilmShotCameraModelBox.Text,
            FilmShotLensModelBox.Text,
            FilmShotFilmStockBox.Text,
            DevelopMetadataFields.ParseInteger(FilmShotIsoSpeedBox.Text),
            DevelopMetadataFields.ParseShutter(FilmShotShutterBox.Text),
            DevelopMetadataFields.ParseNumber(FilmShotApertureBox.Text),
            DevelopMetadataFields.ParseNumber(FilmShotFocalLengthBox.Text));
        AppMetadataOverlay next = new()
        {
            Title = AppMetadataTitleBox.Text,
            Caption = AppMetadataCaptionBox.Text,
            Keywords = DevelopMetadataFields.SplitKeywords(AppMetadataKeywordsBox.Text),
            Copyright = AppMetadataCopyrightBox.Text,
            FilmShot = shot.Normalized().IsEmpty ? null : shot.Normalized(),
        };
        AppMetadataOverlay stored = panel.SelectedFrame?.AppMetadata ?? new AppMetadataOverlay();
        // 같은 값을 다시 쓰면 revision 만 오르고 카탈로그가 매번 더러워집니다.
        if (DevelopMetadataFields.Equivalent(stored, next))
        {
            return;
        }
        _ = panel.SetAppMetadata(_ => next);
        UpdateAppMetadataCards();
        UpdateInfoCard();
    }

    private void LocalizeAppMetadataCards()
    {
        string card = AppResources.Get("developAppMetadataCard", "Text");
        AppMetadataCardTitleText.Text = card;
        AutomationProperties.SetName(AppMetadataCard, card);
        string shotCard = AppResources.Get("developFilmShotCard", "Text");
        FilmShotCardTitleText.Text = shotCard;
        AutomationProperties.SetName(FilmShotCard, shotCard);
        LocalizeMetadataBox(AppMetadataTitleBox, "developAppMetadataTitle");
        LocalizeMetadataBox(AppMetadataCaptionBox, "developAppMetadataCaption");
        LocalizeMetadataBox(AppMetadataKeywordsBox, "developAppMetadataKeywords");
        LocalizeMetadataBox(AppMetadataCopyrightBox, "developAppMetadataCopyright");
        LocalizeMetadataBox(FilmShotCameraMakeBox, "developFilmShotCameraMake");
        LocalizeMetadataBox(FilmShotCameraModelBox, "developFilmShotCameraModel");
        LocalizeMetadataBox(FilmShotLensModelBox, "developFilmShotLensModel");
        LocalizeMetadataBox(FilmShotFilmStockBox, "developFilmShotFilmStock");
        LocalizeMetadataBox(FilmShotIsoSpeedBox, "developFilmShotIsoSpeed");
        LocalizeMetadataBox(FilmShotShutterBox, "developFilmShotShutter");
        LocalizeMetadataBox(FilmShotApertureBox, "developFilmShotAperture");
        LocalizeMetadataBox(FilmShotFocalLengthBox, "developFilmShotFocalLength");
    }

    private static void LocalizeMetadataBox(TextBox box, string resourceKey)
    {
        string text = AppResources.Get(resourceKey, "Text");
        box.PlaceholderText = text;
        AutomationProperties.SetName(box, text);
    }

    /// <summary>
    /// 롤 기록 카드입니다. 이 frame 이 롤에 속해 있을 때만 칸이 나오고, 아니면 macOS 와 같이
    /// 아직 롤에 속해 있지 않다고 알립니다.
    /// </summary>
    private void UpdateRollRecordCard()
    {
        if (RollCodeBox is null)
        {
            return;
        }
        bool onInfoTab = inspectorPresentation.SelectedTab == DevelopInspectorTab.Info;
        RollRecordCard.Visibility = onInfoTab && panel?.SelectedFrame is not null
            ? Visibility.Visible
            : Visibility.Collapsed;
        if (panel?.SelectedFrame is not { } frame || libraryHost is null)
        {
            return;
        }

        LibraryRollSnapshot? roll = libraryHost.RollFor(frame.Id);
        RollNameText.Text = roll?.Name ?? string.Empty;
        RollMissingText.Visibility = roll is null ? Visibility.Visible : Visibility.Collapsed;
        RollCreateButton.Visibility = RollMissingText.Visibility;
        RollRecordFields.Visibility = roll is null ? Visibility.Collapsed : Visibility.Visible;
        if (roll is null)
        {
            return;
        }

        RollRecord record = roll.Record ?? new RollRecord();
        FilmShotMetadata shot = record.Shot ?? new FilmShotMetadata();
        isSynchronizingMetadata = true;
        try
        {
            RollCodeBox.Text = record.Code ?? string.Empty;
            RollNotesBox.Text = record.Notes ?? string.Empty;
            RollCameraMakeBox.Text = shot.CameraMake ?? string.Empty;
            RollCameraModelBox.Text = shot.CameraModel ?? string.Empty;
            RollLensModelBox.Text = shot.LensModel ?? string.Empty;
            RollFilmStockBox.Text = shot.FilmStock ?? string.Empty;
        }
        finally
        {
            isSynchronizingMetadata = false;
        }
    }

    /// <summary>
    /// 고른 사진으로 롤을 만듭니다. macOS 의 "선택 항목으로 롤 만들기" 와 같으며, 라이브러리에서
    /// 고른 것이 없으면 지금 보고 있는 한 장으로 만듭니다.
    /// </summary>
    private void OnCreateRollClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (libraryHost is null || panel?.SelectedFrame is not { } frame)
        {
            return;
        }
        IReadOnlyList<LibraryFrameSnapshot> selected = libraryHost.SelectedFrames;
        IReadOnlyList<LibraryFrameSnapshot> selection =
            selected.Count > 1 ? selected : [frame];
        // 이름은 원본이 들어 있는 폴더에서 옵니다. 사용자가 필름 봉투에 적은 이름이 대개
        // 그 폴더 이름이며, 없으면 macOS 의 "무제 필름" 자리를 씁니다.
        string name = Path.GetFileName(Path.GetDirectoryName(frame.SourcePath) ?? string.Empty);
        if (string.IsNullOrWhiteSpace(name))
        {
            name = AppResources.Get("scanUntitledFilm", "Text");
        }
        string? rollId = libraryHost.CreateRoll(
            name,
            frame.Route.FilmType,
            selection.Select(item => item.Id));
        if (rollId is not null)
        {
            // 새로 만든 롤이 곧 지금 스캔 중인 롤입니다 — macOS 도 만든 롤을 활성으로 둡니다.
            _ = libraryHost.SetActiveRoll(rollId);
        }
        UpdateRollRecordCard();
    }

    private void OnRollRecordCommitted(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingMetadata ||
            libraryHost is null ||
            panel?.SelectedFrame is not { } frame ||
            libraryHost.RollFor(frame.Id) is not { } roll)
        {
            return;
        }
        RollRecord next = new(
            RollCodeBox.Text,
            new FilmShotMetadata(
                RollCameraMakeBox.Text,
                RollCameraModelBox.Text,
                RollLensModelBox.Text,
                RollFilmStockBox.Text),
            RollNotesBox.Text);
        if (next.Normalized() == (roll.Record ?? new RollRecord()).Normalized())
        {
            return;
        }
        _ = libraryHost.SetRollRecord(roll.Id, next);
        UpdateRollRecordCard();
    }

    private void LocalizeRollRecordCard()
    {
        string card = AppResources.Get("developRollRecordCard", "Text");
        RollRecordCardTitleText.Text = card;
        AutomationProperties.SetName(RollRecordCard, card);
        RollMissingText.Text = AppResources.Get("developRollMissing", "Text");
        RollFillHintText.Text = AppResources.Get("developRollFillHint", "Text");
        LocalizeMetadataBox(RollCodeBox, "developRollCode");
        LocalizeMetadataBox(RollCameraMakeBox, "developFilmShotCameraMake");
        LocalizeMetadataBox(RollCameraModelBox, "developFilmShotCameraModel");
        LocalizeMetadataBox(RollLensModelBox, "developFilmShotLensModel");
        LocalizeMetadataBox(RollFilmStockBox, "developFilmShotFilmStock");
        LocalizeMetadataBox(RollNotesBox, "developRollNotes");
        SetButtonText(
            RollCreateButton,
            AppResources.Get("developRollCreateFromSelection", "Content"));
    }

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
        InfoRows.ItemsSource = DevelopInfoCardProjection.Rows(
            panel?.SelectedFrame,
            InfoCardText(),
            File.Exists);
    }

    private static DevelopInfoCardText InfoCardText() => new(
        AppResources.Get("developInfoSource", "Text"),
        AppResources.Get("developInfoSidecar", "Text"),
        AppResources.Get("developInfoCamera", "Text"),
        AppResources.Get("developInfoDate", "Text"),
        AppResources.Get("developInfoTitle", "Text"),
        AppResources.Get("developInfoKeywords", "Text"),
        AppResources.Get("developInfoNotAvailable", "Text"),
        AppResources.Get("developInfoOriginScan", "Text"),
        AppResources.Get("developInfoOriginImport", "Text"),
        AppResources.Get("developInfoUnknown", "Text"),
        AppResources.Get("developInfoSidecarNotFound", "Text"));

    /// <summary>버전 목록 한 줄입니다. 표시 문구를 XAML 이 짓지 않도록 여기서 만듭니다.</summary>
    private void UpdateVersionControls()
    {
        if (VersionsList is null)
        {
            return;
        }
        IReadOnlyList<VersionRow> rows = VersionListProjection.Rows(
            panel?.Versions ?? [],
            AppResources.Get("developVersionRestore", "Content"),
            AppResources.Get("developVersionDelete", "Content"));
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

        FilmLookGroups.ItemsSource = FilmLookMenuProjection.Groups(
            frame.Route.FilmType,
            panel.FilmEmulation,
            AppResources.Get("developFilmLookNone", "Text"),
            FilmGroupTitle);
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

    private static string FilmGroupTitle(FilmEmulationKind kind) =>
        AppResources.Get(FilmLookMenuProjection.GroupTitleKey(kind), "Text");

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


    private void OnLibrarySelectionChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (libraryHost?.ActiveFrameId is { } activeFrameId &&
            (FrameSelector.ItemsSource is not IReadOnlyList<LibraryFrameListItem> items ||
             IndexOf(items, activeFrameId) < 0))
        {
            RefreshFrames();
        }
        else
        {
            SynchronizeSharedSelection();
        }
        RebuildDevelopLibraryTree();
        ExportPanel.RefreshPreview();
    }

    private void SynchronizeSharedSelection()
    {
        if (libraryHost?.ActiveFrameId is not { } activeFrameId ||
            FrameSelector.ItemsSource is not IReadOnlyList<LibraryFrameListItem> items)
        {
            return;
        }
        int index = IndexOf(items, activeFrameId);
        if (index < 0 || index == FrameSelector.SelectedIndex)
        {
            return;
        }
        isSynchronizingFrameSelection = true;
        try
        {
            FrameSelector.SelectedIndex = index;
        }
        finally
        {
            isSynchronizingFrameSelection = false;
        }
        ActivateFrame(items[index], index, publishSelection: false);
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
        if (panel?.SelectedFrame is not { SourceMetadata: { } metadata })
        {
            return null;
        }
        return CropInteraction.LockedNormalizedAspectRatio(
            crop.IsAspectLocked,
            panel.ImageTransform.CropAspect,
            metadata.PixelWidth,
            metadata.PixelHeight,
            panel.ImageTransform.Rotation);
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
        bool nextLocked = crop.ToggleAspectLock();
        // 잠금은 catalog 가 아니라 다음 crop 드래그의 동작만 바꿉니다.
        CropAspectLockIcon.Glyph = nextLocked ? "" : "";
        crop.SyncLockedAspect(LockedNormalizedAspectRatio());
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
        bool locked = crop.IsAspectLocked;
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
        ResetInspectorSection(static state => state.Tone.ResetBasicTone());
    }

    private void OnToneCurveResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetInspectorSection(static state => state.Tone.ResetToneCurve());
    }

    private void OnColorMixerResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetInspectorSection(static state => state.Color.ResetColorMixer());
    }

    private void OnColorResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetInspectorSection(static state => state.Color.ResetColor());
    }

    private void OnColorGradingResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetInspectorSection(static state => state.Color.ResetColorGrading());
    }

    private void OnCalibrationResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetInspectorSection(static state => state.Color.ResetPrimaryCalibration());
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

        ExportStatusText.Text = AppResources.Get("developExportRunning", "Text");
        Task<bool> exportTask = panel.ExportAsync(
            ExportPanel.QuickSettings.Destination.PathFor(frame.SourcePath),
            ExportPanel.QuickSettings.Format,
            outcome => ExportStatusText.Text = DevelopPanelState.Describe(outcome),
            ExportPanel.QuickSettings.Encoding);
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
        if (developSource != preferences.SelectedDevelopSidebarTab)
        {
            developSource = preferences.SelectedDevelopSidebarTab;
            UpdateDevelopSourcePanel();
        }
        if (ExportPanel.Settings != preferences.Export ||
            ExportPanel.QuickSettings != preferences.QuickExport ||
            ExportPanel.Recipes != preferences.ExportRecipes)
        {
            ExportPanel.ApplyPreferences(
                preferences.Export,
                preferences.QuickExport,
                preferences.ExportRecipes);
        }

        // 프루프는 보기용이므로 미리보기에만 겁니다. 게시하는 파일은 그대로입니다.
        if (softProofPreferences != preferences.SoftProof)
        {
            softProofPreferences = preferences.SoftProof;
            ApplySoftProof();
        }
    }

    /// <summary>
    /// 고른 프로파일의 용지 흰색과 잉크 검정을 미리보기에 겁니다.
    /// </summary>
    /// <remarks>
    /// 목적지는 현상 대상이 정합니다 — PRINT 로 현상할 때는 프린터 출력 프로파일이 목적지이며,
    /// 그래야 프루프가 화면이 아니라 인화될 종이를 보여 줍니다. 프로파일을 읽지 못하면 용지·
    /// 잉크를 흉내 내지 않습니다: 없는 값을 지어내느니 프로파일만 보는 쪽이 정직합니다.
    /// </remarks>
    private void ApplySoftProof()
    {
        if (previewCoordinator is not { } coordinator)
        {
            return;
        }
        DevelopTarget target = panel?.SelectedFrame?.DevelopTarget ?? DevelopTarget.Main;
        coordinator.SoftProof = softProofPreferences.ToSettings(
            SoftProofProfileReader.Read(softProofPreferences.DestinationProfilePath(target)));
        RequestPreview();
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
        bool compact = LeftPanel.Width < ShellLayoutMetrics.SidebarCompactThreshold;
        LeftRailColumn.Width = new GridLength(compact
            ? ShellLayoutMetrics.SidebarCompactRailWidth
            : ShellLayoutMetrics.SidebarRegularRailWidth);
        DevelopSourceRail.Padding = compact
            ? new Thickness(8, 10, 8, 0)
            : new Thickness(22, 10, 22, 0);
        DevelopSourceHeader.Padding = compact
            ? new Thickness(8, 0, 8, 0)
            : new Thickness(12, 0, 12, 0);
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
        LibraryImportSectionText.Text = AppResources.Get("importSection", "Text");
        ImportImageText.Text = AppResources.Get("libraryImportImageShort", "Content");
        ImportFolderText.Text = AppResources.Get("libraryImportFolderShort", "Content");
        ImportScannerText.Text = AppResources.Get("libraryScannerLabel", "Content");
        AutomationProperties.SetName(ImportButton, ImportImageText.Text);
        AutomationProperties.SetName(ImportFolderButton, ImportFolderText.Text);
        AutomationProperties.SetName(ImportScannerButton, ImportScannerText.Text);
        ExportPanel.Localize();
        LocalizeAppMetadataCards();
        LocalizeRollRecordCard();
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
        ScannerProfileLabel.Text = AppResources.Get("developScannerProfile", "Text");
        AutomationProperties.SetName(ScannerProfileSelector, ScannerProfileLabel.Text);
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
