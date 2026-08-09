using System.Globalization;
using System.IO;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media.Imaging;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;
using Negaflow.Shell.Views.Layout;

namespace Negaflow.Shell.Views;

public sealed partial class DevelopWorkspaceView : UserControl
{
    private readonly ThreePaneResizeController resizeController = new();
    private WorkspacePresentationState? workspaceState;
    private DevelopPanelState? panel;
    private LibraryHostService? libraryHost;
    private ToneLimits? toneLimits;
    private Microsoft.UI.WindowId? importWindowId;
    private PreviewCoordinator? previewCoordinator;
    private WriteableBitmap? previewBitmap;
    private bool isSynchronizingInspector;

    public DevelopWorkspaceView()
    {
        InitializeComponent();
        LocalizeControls();
    }

    public void Initialize(
        WorkspacePresentationState state,
        NativeEngineStatus nativeEngineStatus)
    {
        ArgumentNullException.ThrowIfNull(state);
        ArgumentNullException.ThrowIfNull(nativeEngineStatus);
        workspaceState = state;
        state.Changed += OnStateChanged;
        Filmstrip.Initialize(state);
        StatusBar.Initialize(nativeEngineStatus);
        UpdateState(state.Current);
        Unloaded += OnUnloaded;
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
                 })
        {
            slider.Minimum = -panel.MaximumToneControl;
            slider.Maximum = panel.MaximumToneControl;
        }
        foreach (InspectorSlider slider in new[] { BaseRedControl, BaseGreenControl, BaseBlueControl })
        {
            slider.Minimum = panel.MinimumManualDmin;
            slider.Maximum = panel.MaximumManualDmin;
        }
        // Import 버튼은 라이브러리가 비어 있을 때도 보여야 합니다. 안 그러면 첫 사진을 넣을
        // 방법이 없습니다.
        DevelopCard.Visibility = Visibility.Visible;
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
        NoFrameCard.Visibility = hasFrames ? Visibility.Collapsed : Visibility.Visible;
        if (!hasFrames)
        {
            FrameSelector.ItemsSource = null;
            SyncToneControls();
            return;
        }

        FrameSelector.ItemsSource = items;
        FrameSelector.SelectedIndex = 0;
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
        picker.FileTypeFilter.Add(".tif");
        picker.FileTypeFilter.Add(".tiff");

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

        panel.Select(item.Id);
        UpdateSelectedFrameText();
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
        SyncBaseControls();
        SyncToneControls();
        ExportButton.IsEnabled = panel.CanExport;
        ExportStatusText.Text = item.CanDevelop
            ? string.Empty
            : DevelopPanelState.Describe(new DevelopExportOutcome(
                DevelopExportOutcomeKind.Refused,
                null,
                RefusalFor(item.Frame),
                null));
        RequestPreview();
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
        ExportButton.IsEnabled = panel.CanExport;
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

        PreviewImage.Visibility = Visibility.Visible;
        EmptyCanvasPanel.Visibility = Visibility.Collapsed;
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
        ExportButton.IsEnabled = panel.CanExport;
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

    private async void OnExportClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel?.SelectedFrame is not { } frame)
        {
            return;
        }

        // 편집은 메모리에만 있었으므로, 현상하기 전에 저장해 파일과 catalog 가 어긋나지 않게 합니다.
        CatalogStoreError saved = panel.Save();
        if (saved != CatalogStoreError.None)
        {
            ExportStatusText.Text = $"Could not save the catalog: {saved}";
            return;
        }

        string destination = Path.Combine(
            Path.GetDirectoryName(frame.SourcePath) ?? Path.GetTempPath(),
            $"{Path.GetFileNameWithoutExtension(frame.SourcePath)}-negaflow.png");

        ExportButton.IsEnabled = false;
        ExportStatusText.Text = "Developing…";
        bool delivered = await panel.ExportAsync(
            destination,
            DevelopExportFormat.Png16,
            outcome => ExportStatusText.Text = DevelopPanelState.Describe(outcome));
        if (!delivered)
        {
            // 큐가 닫혔다는 뜻이므로 창이 사라지는 중입니다. 컨트롤을 더 건드리지 않습니다.
            return;
        }
        ExportButton.IsEnabled = panel.CanExport;
    }

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
    }

    private static void SetNameAndTooltip(Button button, string resourceKey)
    {
        string text = AppResources.Get(resourceKey, "Value");
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is not null)
        {
            workspaceState.Changed -= OnStateChanged;
        }
    }
}
