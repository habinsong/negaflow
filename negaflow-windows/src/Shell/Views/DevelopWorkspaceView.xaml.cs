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

    /// <summary>현상 왼쪽 소스입니다. macOS 의 다섯 탭 중 지금 내용이 있는 셋입니다.</summary>
    private enum DevelopSourceKind
    {
        Library,
        Versions,
        Film,
        Output,
    }

    private void UpdateDevelopSourcePanel()
    {
        LibrarySourcePanel.Visibility = Show(DevelopSourceKind.Library);
        VersionsSourcePanel.Visibility = Show(DevelopSourceKind.Versions);
        FilmSourcePanel.Visibility = Show(DevelopSourceKind.Film);
        OutputSourcePanel.Visibility = Show(DevelopSourceKind.Output);

        (string headerKey, string glyph) = developSource switch
        {
            DevelopSourceKind.Versions => ("developSectionVersions", ""),
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
    }

    private Visibility Show(DevelopSourceKind kind) =>
        developSource == kind ? Visibility.Visible : Visibility.Collapsed;

    private IEnumerable<(Button Button, FontIcon Icon, DevelopSourceKind Kind)> DevelopSourceRailButtons()
    {
        yield return (LibraryRailButton, LibraryRailIcon, DevelopSourceKind.Library);
        yield return (VersionsRailButton, VersionsRailIcon, DevelopSourceKind.Versions);
        yield return (FilmRailButton, FilmRailIcon, DevelopSourceKind.Film);
        yield return (OutputRailButton, OutputRailIcon, DevelopSourceKind.Output);
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
