using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI;
using Negaflow.Catalog;
using Microsoft.UI.Xaml.Automation;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Print;
using Negaflow.Shell.Views.Print.Export;
using Negaflow.Shell.Views.Print.Preview;
using Negaflow.Shell.Views.Print.Settings;
using Negaflow.Shell.Views.Print.Sources;

namespace Negaflow.Shell.Views;

/// <summary>
/// 인화 화면의 소스·검사기·미리보기·게시를 실제 타입에 넘기는 배선입니다.
/// </summary>
public sealed partial class PrintWorkspaceView
{
    private PrintSourceController? printSources;
    private PrintInspectorBinder? printInspector;
    private PrintPreviewRenderer? printPreview;
    /// <summary>ICC 고르개가 어느 창에 붙을지입니다.</summary>
    private Microsoft.UI.WindowId? printWindowId;

    private Print.Export.PrintSheetExportRunner? printSheetExport;

    /// <summary>인화의 "파일" 탭입니다. 라이브러리와 같은 컨트롤이며 셸이 ✕ 를 잇습니다.</summary>
    internal Library.Sources.LibraryFilesSourceTree FilesTab => PrintFilesSourceTree;

    private void BindPrintComposition()
    {
        printSources = new PrintSourceController(
            new PrintSourceSurface
            {
                FilesTree = PrintFilesSourceTree,
                LeftHeader = NoFrameLeftHeaderText,
                RightHeader = NoFrameRightHeaderText,
                NoFrameLeftPanel = NoFrameLeftPanel,
                Filmstrip = Filmstrip,
                ApplySourcePane = frames =>
                {
                    hasPrintFrames = frames;
                    ShowPrintSource(printSourceIsExport);
                },
                Presentation = () => workspaceState,
            },
            SynchronizePrint);
        // 인화 캔버스의 확대·이동과 줌 캡슐입니다(macOS `PrintCanvasView`).
        HookPrintViewport();
        PrintFilesSourceTree.TraceName = "print";
        // 새 현상본·썸네일이 도착하면 풀어 둔 그림을 버립니다. 이 신호를 아무도 받지 않아
        // 현상뷰에서 자동 레벨·자동 색상을 바꿔도 인화 판은 <b>옛 그림</b>을 계속 다시
        // 걸었습니다 — 두 화면의 사진이 달라 보이던 원인입니다.
        printSources.PreviewImageArrived += (_, _) => printPreview?.InvalidateTiles();
        PrintFilesSourceTree.FrameInvoked += (sender, invocation) =>
            printSources?.HandleTreeInvoked(sender, invocation);
        printInspector = new PrintInspectorBinder(
            new PrintInspectorSurface
            {
                // 레이아웃 탭
                LayoutModeField = LayoutTab.LayoutModeField,
                LayoutModeSelector = LayoutTab.LayoutModeSelector,
                PaperSizeField = LayoutTab.PaperSizeField,
                PaperSizeSelector = LayoutTab.PaperSizeSelector,
                OrientationField = LayoutTab.OrientationField,
                OrientationSelector = LayoutTab.OrientationSelector,
                MarginText = LayoutTab.MarginText,
                MarginValueText = LayoutTab.MarginValueText,
                MarginSlider = LayoutTab.MarginSlider,
                RulerField = LayoutTab.RulerField,
                RulerSelector = LayoutTab.RulerSelector,
                RulerUnitField = LayoutTab.RulerUnitField,
                RulerUnitSelector = LayoutTab.RulerUnitSelector,
                SheetColorField = LayoutTab.SheetColorField,
                SheetBackgroundSelector = LayoutTab.SheetBackgroundSelector,
                SurfaceField = LayoutTab.SurfaceField,
                SurfaceSelector = LayoutTab.SurfaceSelector,

                // 패키지 배치
                PackageLayoutCard = LayoutTab.PackageLayoutCard,
                PackageLayoutIcon = LayoutTab.PackageLayoutIcon,
                PackageLayoutTitle = LayoutTab.PackageLayoutTitle,
                GridSizeRow = LayoutTab.GridSizeRow,
                RowsField = LayoutTab.RowsField,
                RowsBox = LayoutTab.RowsBox,
                ColumnsField = LayoutTab.ColumnsField,
                ColumnsBox = LayoutTab.ColumnsBox,
                TemplateField = LayoutTab.TemplateField,
                TemplateSelector = LayoutTab.TemplateSelector,
                SpacingText = LayoutTab.SpacingText,
                SpacingValueText = LayoutTab.SpacingValueText,
                SpacingSlider = LayoutTab.SpacingSlider,
                SpacingGroup = LayoutTab.SpacingGroup,
                VerticalSpacingText = LayoutTab.VerticalSpacingText,
                VerticalSpacingValueText = LayoutTab.VerticalSpacingValueText,
                VerticalSpacingSlider = LayoutTab.VerticalSpacingSlider,
                NormalizeOrientationField = LayoutTab.NormalizeOrientationField,
                NormalizeOrientationSelector = LayoutTab.NormalizeOrientationSelector,
                CustomPanel = LayoutTab.CustomPanel,
                CustomItemsHost = LayoutTab.CustomItemsHost,
                CustomAddButton = LayoutTab.CustomAddButton,

                // 콘텐츠 탭
                ContentFitGroup = ContentTab.ContentFitGroup,
                ContentFitField = ContentTab.ContentFitField,
                ContentFitSelector = ContentTab.ContentFitSelector,
                RotateToFitField = ContentTab.RotateToFitField,
                RotateToFitSelector = ContentTab.RotateToFitSelector,
                RepeatField = LayoutTab.RepeatField,
                RepeatSelector = LayoutTab.RepeatSelector,
                CaptionFontField = ContentTab.CaptionFontField,
                CaptionFontSelector = ContentTab.CaptionFontSelector,
                CaptionDetailGroup = ContentTab.CaptionDetailGroup,
                CaptionAlignmentGroup = ContentTab.CaptionAlignmentGroup,
                CustomCaptionGroup = ContentTab.CustomCaptionGroup,
                CustomCaptionsHost = ContentTab.CustomCaptionsHost,
                AddCaptionButton = ContentTab.AddCaptionButton,
                ContentCropMarksField = ContentTab.ContentCropMarksField,
                ContentCropMarksSelector = ContentTab.ContentCropMarksSelector,
                ContentSectionText = ContentTab.ContentSectionText,
                CaptionField = ContentTab.CaptionField,
                CaptionSelector = ContentTab.CaptionSelector,
                CaptionAlignmentField = ContentTab.CaptionAlignmentField,
                CaptionAlignmentSelector = ContentTab.CaptionAlignmentSelector,

                // 출력 탭
                OutputProcessField = OutputTab.OutputProcessField,
                OutputProcessSelector = OutputTab.OutputProcessSelector,
                CprintLabField = OutputTab.CprintLabField,
                CprintLabBox = OutputTab.CprintLabBox,
                CprintPaperField = OutputTab.CprintPaperField,
                CprintPaperBox = OutputTab.CprintPaperBox,
                ProofProfileField = OutputTab.ProofProfileField,
                ProofPreviewField = OutputTab.ProofPreviewField,
                PrintProofPreviewSelector = OutputTab.PrintProofPreviewSelector,
                OutputSectionText = OutputTab.OutputSectionText,
                AdvancedProofText = OutputTab.AdvancedProofText,
                DeliveryColorSpaceRow = OutputTab.DeliveryColorSpaceRow,
                DeliveryColorSpaceValue = OutputTab.DeliveryColorSpaceValue,
                PaperSimulationField = OutputTab.PaperSimulationField,
                PaperSimulationSelector = OutputTab.PaperSimulationSelector,
                GamutWarningField = OutputTab.GamutWarningField,
                GamutWarningSelector = OutputTab.GamutWarningSelector,
            });
        printPreview = new PrintPreviewRenderer(
            new PrintPreviewSurface
            {
                CanvasHost = CanvasHost,
                PageBorder = PageBorder,
                PageCanvas = PageCanvas,
                RulerCanvas = RulerCanvas,
                NoFramePanel = NoFramePanel,
                PageCountText = PageCountText,
            },
            () => PrintSources,
            () => printSources?.Thumbnails,
            () => workspaceState,
            DrawCustomEditor);

        // 좌측 내보내기 탭의 두 단추는 판 합성본을 씁니다. macOS
        // `ExportSection(onExport:onQuickExport:)` 이 인화뷰에서만 따로 꽂아 주는 자리입니다.
        printSheetExport = new Print.Export.PrintSheetExportRunner(
            () => PrintSources,
            () => workspaceState,
            TextRasterHost,
            PrintExportPanel.SetOutputStatus);
        PrintExportPanel.UsesPaperLayout = true;
        // 나올 **파일 수**를 단추에 답니다. macOS `printExportOutputCount` 와 같은 계산이며,
        // 낱장 배치는 사진마다 한 판이고 콘택트 시트·사진 패키지·사용자 패키지는 한 판에
        // 여러 장을 얹습니다 — 사진 수를 적으면 실제로 나올 파일 수와 어긋납니다.
        PrintExportPanel.PaperOutputCount = () => PrintExportOutputCount;
        PrintExportPanel.RunExport = () =>
            printSheetExport.RunExportAsync(PrintExportPanel.Settings);
        PrintExportPanel.RunQuickExport = () =>
            printSheetExport.RunQuickExportAsync(PrintExportPanel.QuickSettings);
    }

    /// <summary>
    /// 지금 설정으로 나올 판(파일) 수입니다. macOS <c>printExportOutputCount</c> 그대로입니다 —
    /// 패키지 배치가 아니면 사진 수이고, 패키지 배치이면 <c>ExpectedPageCount</c> 입니다.
    /// 셀 수 없으면 사진 수로 물러납니다.
    /// </summary>
    internal int PrintExportOutputCount
    {
        get
        {
            int sourceCount = PrintSources.Count;
            if (workspaceState?.Current.Print is not { } print ||
                PrintPreferences.PackageModeFor(print.LayoutMode) is null)
            {
                return sourceCount;
            }
            return PrintPackageLayout.ExpectedPageCount(sourceCount, print.Package())
                ?? sourceCount;
        }
    }

    /// <summary>
    /// 인화할 사진들입니다. 라이브러리에서 고른 것을 그대로 씁니다 — macOS 도 같은 선택을
    /// 봅니다.
    /// </summary>
    private IReadOnlyList<LibraryFrameSnapshot> PrintSources =>
        printSources?.Sources ?? [];

    public void AttachThumbnails(Negaflow.Shell.Library.ThumbnailService service) =>
        printSources?.AttachThumbnails(service);

    public void ShowLibrary(LibraryHostService host) => printSources?.ShowLibrary(host);

    /// <summary>
    /// 별·깃발·제외가 바뀌었습니다. 하단 필름스트립의 표시만 맞춥니다.
    /// </summary>
    internal void RefreshFrameMarks(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        Filmstrip.RefreshFrames(host.Frames);
    }

    public void AttachWindow(Microsoft.UI.WindowId windowId) =>
        printWindowId = windowId;



    private void OnPrintFilmstripFrameSelected(object? sender, LibraryFrameListItem item) =>
        printSources?.HandleFilmstripSelected(sender, item);

    private void LocalizePrintInspector()
    {
        printInspector?.Localize();
        LocalizeCprint();
        LocalizeLayoutTemplates();
    }

    /// <summary>
    /// 세그먼트는 XAML 에서 `SelectionChanged` 를 걸 수 없어(이벤트가 컨트롤 것이라) 여기서
    /// 겁니다. 안 걸면 눌러도 값이 안 바뀌는 가짜가 됩니다.
    /// </summary>
    private void HookPrintSegments()
    {
        foreach (Controls.NegaflowSegmentedPicker picker in new[]
        {
            LayoutTab.OrientationSelector,
            LayoutTab.RulerSelector,
            LayoutTab.RulerUnitSelector,
            LayoutTab.SheetBackgroundSelector,
            LayoutTab.RepeatSelector,
            LayoutTab.NormalizeOrientationSelector,
            ContentTab.ContentFitSelector,
            ContentTab.RotateToFitSelector,
            ContentTab.CaptionAlignmentSelector,
            ContentTab.ContentCropMarksSelector,
            OutputTab.OutputProcessSelector,
            OutputTab.PrintProofPreviewSelector,
            OutputTab.PaperSimulationSelector,
            OutputTab.GamutWarningSelector,
        })
        {
            picker.SelectionChanged += OnPrintSegmentChanged;
        }
    }

    /// <summary>
    /// C-print 를 골랐을 때만 인화소·인화지·인화 프로파일이 나옵니다. macOS 도 일반 출력에서는
    /// 그 카드들을 내리므로, 여기서도 같은 자리에서 감춥니다.
    /// </summary>
    internal void ApplyCprintVisibility(PrintPreferences print)
    {
        ArgumentNullException.ThrowIfNull(print);
        bool cprint = print.OutputProcess == PrintOutputProcess.CPrint;
        OutputTab.CprintCard.Visibility = cprint ? Visibility.Visible : Visibility.Collapsed;
        OutputTab.PrintProofCard.Visibility = OutputTab.CprintCard.Visibility;
        bool hasProfile = !string.IsNullOrWhiteSpace(print.CPrintProofProfilePath);
        // macOS 는 프로파일이 없으면 이름 자리에 긴 대시를 둡니다.
        OutputTab.PrintProofProfileText.Text = hasProfile
            ? print.CPrintProofProfileName
            : "—";
        // 지우기는 담아 둔 프로파일이 있을 때만 나옵니다(macOS `if ... != nil`).
        OutputTab.PrintProofClearButton.Visibility = hasProfile
            ? Visibility.Visible
            : Visibility.Collapsed;
        // 프로파일이 없으면 미리보기를 켤 수 없습니다 — 흉내 낼 대상이 없습니다.
        OutputTab.PrintProofPreviewSelector.IsEnabled = hasProfile;
        OutputTab.ProofProfileWarning.Visibility = cprint && !hasProfile
            ? Visibility.Visible
            : Visibility.Collapsed;
        if (cprint && !hasProfile)
        {
            OutputTab.ProofProfileWarningText.Text =
                AppResources.Get("printPreviewProfileRequired", "Text");
        }
        // 전달 색 공간은 보여 주기만 합니다(macOS `model.exportColorSpace.uiLabel`).
        if (workspaceState is { } current)
        {
            // 색 공간 이름은 한곳에서만 정합니다 — `enum.ToString()` 을 쓰면 "Srgb" 같은
            // 코드 이름이 화면으로 새어 나옵니다(macOS `ExportColorSpace.uiLabel`).
            OutputTab.DeliveryColorSpaceValue.Text = Negaflow.Shell.Develop.ExportColorSpaceLabel
                .For(current.Current.Export.EffectiveColorSpace);
            // 여기서 세그먼트를 고르면 그 알림이 다시 이 동기화를 부릅니다. 값을 넣는 동안은
            // 담기를 막습니다 — 다른 컨트롤이 `printInspector.IsSynchronizing` 으로 하는 것과
            // 같은 처리입니다.
            suppressPrintCommit = true;
            try
            {
                OutputTab.GamutWarningSelector.SetSelected(
                    current.Current.SoftProof.GamutWarningEnabled);
            }
            finally
            {
                suppressPrintCommit = false;
            }
        }
        ApplyInspectorTabAvailability(print);
    }

    /// <summary>
    /// macOS <c>PrintLayoutTemplateStore</c> 자리입니다. 앱 데이터 폴더에 한 파일로 삽니다 —
    /// macOS 도 `Application Support/negaflow/print-layout-templates.json` 한 장입니다.
    /// </summary>
    private PrintLayoutTemplateStore? layoutTemplates;

    private PrintLayoutTemplateStore Templates => layoutTemplates ??= new PrintLayoutTemplateStore(
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Negaflow",
            "print-layout-templates.json"));

    internal void LocalizeLayoutTemplates()
    {
        LayoutTab.LayoutTemplateSectionText.Text = AppResources.Get("printLayoutTemplateSection", "Text");
        LayoutTab.LayoutTemplateNameLabel.Text = AppResources.Get("printLayoutTemplateName", "Text");
        LayoutTab.LayoutTemplateNameBox.PlaceholderText = LayoutTab.LayoutTemplateNameLabel.Text;
        AutomationProperties.SetName(LayoutTab.LayoutTemplateNameBox, LayoutTab.LayoutTemplateNameLabel.Text);
        LayoutTab.LayoutTemplateSaveButton.Content = AppResources.Get("printLayoutTemplateSave", "Content");
        LayoutTab.LayoutTemplateApplyButton.Content = AppResources.Get("printLayoutTemplateApply", "Content");
        LayoutTab.LayoutTemplateDeleteButton.Content = AppResources.Get("printLayoutTemplateDelete", "Content");
        RefreshLayoutTemplates();
    }

    private void RefreshLayoutTemplates()
    {
        // 담아 둔 판형 목록입니다. macOS 도 여기서 `PrintInspectorPopupPicker` 를 씁니다 —
        // WinUI 기본 ComboBox 의 네모 상자를 인스펙터에 두지 않습니다.
        LayoutTab.LayoutTemplateSelector.SetOptions(
            [.. Templates.Templates.Select(
                template => new Views.Controls.PopupPickerOption(template.Name, template.Id))]);
        bool hasTemplates = Templates.Templates.Count > 0;
        LayoutTab.LayoutTemplateAppliedRow.Visibility =
            hasTemplates ? Visibility.Visible : Visibility.Collapsed;
        if (hasTemplates && LayoutTab.LayoutTemplateSelector.SelectedIndex < 0)
        {
            LayoutTab.LayoutTemplateSelector.SelectSilently(0);
        }
        LayoutTab.LayoutTemplateSaveButton.IsEnabled = Templates.CanModify &&
            !string.IsNullOrWhiteSpace(LayoutTab.LayoutTemplateNameBox.Text) &&
            Templates.Templates.Count < PrintLayoutTemplateStore.MaximumTemplateCount;
        LayoutTab.LayoutTemplateStatusText.Text = Templates.CanModify
            ? string.Empty
            : AppResources.Get("printLayoutTemplateLocked", "Text");
    }

    internal void OnLayoutTemplateNameChanged(object sender, TextChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        LayoutTab.LayoutTemplateSaveButton.IsEnabled = Templates.CanModify &&
            !string.IsNullOrWhiteSpace(LayoutTab.LayoutTemplateNameBox.Text) &&
            Templates.Templates.Count < PrintLayoutTemplateStore.MaximumTemplateCount;
    }

    internal void OnLayoutTemplateSaveClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is not { } state)
        {
            return;
        }
        if (Templates.Templates.Count >= PrintLayoutTemplateStore.MaximumTemplateCount)
        {
            LayoutTab.LayoutTemplateStatusText.Text = AppResources.Get("printLayoutTemplateFull", "Text");
            return;
        }
        if (Templates.Add(
                LayoutTab.LayoutTemplateNameBox.Text,
                PrintLayoutTemplateSettings.From(state.Current.Print)) is null)
        {
            LayoutTab.LayoutTemplateStatusText.Text = Templates.CanModify
                ? AppResources.Get("printLayoutTemplateDuplicate", "Text")
                : AppResources.Get("printLayoutTemplateLocked", "Text");
            return;
        }
        LayoutTab.LayoutTemplateNameBox.Text = string.Empty;
        RefreshLayoutTemplates();
    }

    /// <summary>고른 판형입니다. 팝업 단추는 값으로 <c>Id</c> 를 듭니다.</summary>
    private PrintLayoutTemplate? SelectedLayoutTemplate() =>
        LayoutTab.LayoutTemplateSelector.SelectedTag is Guid id
            ? Templates.Templates.FirstOrDefault(template => template.Id == id)
            : null;

    internal void OnLayoutTemplateApplyClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is null || SelectedLayoutTemplate() is not { } template)
        {
            return;
        }
        workspaceState.UpdatePrint(current => template.Settings.ApplyTo(current));
    }

    internal void OnLayoutTemplateDeleteClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (SelectedLayoutTemplate() is { } template && Templates.Delete(template.Id))
        {
            RefreshLayoutTemplates();
        }
    }

    internal void OnCprintTextChanged(object sender, TextChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        CommitPrintSettings();
    }

    /// <summary>
    /// 인화소가 준 ICC 를 고릅니다. macOS <c>selectCPrintProofICCProfile</c> — 고르면 미리보기가
    /// 함께 켜집니다.
    /// </summary>
    internal async void OnPrintProofChooseClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        PreviewTrace.Write(System.FormattableString.Invariant(
            $"proof.choose state={workspaceState is not null} window={printWindowId is not null}"));
        if (workspaceState is null || printWindowId is not { } windowId)
        {
            return;
        }
        Windows.Storage.Pickers.FileOpenPicker picker = new();
        picker.FileTypeFilter.Add(".icc");
        picker.FileTypeFilter.Add(".icm");
        WinRT.Interop.InitializeWithWindow.Initialize(
            picker,
            Win32Interop.GetWindowFromWindowId(windowId));
        Windows.Storage.StorageFile? file = await picker.PickSingleFileAsync();
        PreviewTrace.Write("proof.picked " + (file?.Path ?? "<none>"));
        if (file is null)
        {
            return;
        }
        // macOS `SoftProof.rgbOutputColorSpace(fromICCData:)` 와 같은 판정입니다 — 데이터
        // 공간이 RGB 이고 목적지로 쓸 수 있는 종류인가만 봅니다. 매체 흰색·검정을 읽어 보는
        // 것으로 대신하면 인화소가 주는 표 기반 프로파일이 통째로 거절됩니다.
        bool usable = PrintIccProfile.IsRgbOutput(file.Path);
        PreviewTrace.Write(System.FormattableString.Invariant($"proof.usable {usable}"));
        if (!usable)
        {
            // macOS: `model.statusMessage = model.text(.softProofInvalidICC)` — 담지 않습니다.
            OutputTab.ProofProfileWarning.Visibility = Visibility.Visible;
            OutputTab.ProofProfileWarningText.Text =
                AppResources.Get("softProofInvalidICC", "Text");
            return;
        }
        workspaceState.UpdatePrint(current => current with
        {
            CPrintProofProfilePath = file.Path,
            CPrintProofProfileName = Path.GetFileNameWithoutExtension(file.Path),
            CPrintPreviewEnabled = true,
        });
        ApplyCprintSoftProof();
        // 이름 글자와 지우기 단추는 `ApplyCprintVisibility` 가 채웁니다. 여기서 부르지 않으면
        // 프로파일을 새로 골라도 이름 자리가 "—" 로 남습니다.
        SynchronizePrint();
    }

    /// <summary>
    /// C-print 프루프를 실제 화면 색에 겁니다. macOS
    /// <c>advanceSoftProofConfiguration()</c> 자리입니다 — 값만 담아 두면 프로파일을 골라도
    /// 화면과 인화물의 색이 하나도 바뀌지 않습니다.
    /// </summary>
    /// <remarks>
    /// 목적지는 <see cref="Negaflow.Shell.Develop.SoftProofPreferences.PrinterProfilePath"/>
    /// 입니다. 인화 대상으로 현상할 때 프루프가 그 종이를 향하게 하는 자리이며, 화면을 보는
    /// 프루프 프로파일과 따로 둡니다 — macOS 도 둘을 나눠 둡니다.
    /// </remarks>
    private void ApplyCprintSoftProof()
    {
        if (workspaceState is not { } state)
        {
            return;
        }
        PrintPreferences print = state.Current.Print;
        bool active = print.OutputProcess == PrintOutputProcess.CPrint &&
            print.CPrintPreviewEnabled &&
            print.CPrintProofProfilePath.Length > 0;
        string wanted = active ? print.CPrintProofProfilePath : string.Empty;
        Negaflow.Interop.SoftProofSimulation simulation =
            active && print.CPrintPaperSimulationEnabled
                ? Negaflow.Interop.SoftProofSimulation.PaperAndBlackInk
                : state.Current.SoftProof.Simulation;
        // 우리가 켠 것만 우리가 끕니다. 설정에서 사용자가 켜 둔 프루프는 건드리지 않습니다.
        bool enabled = active || (state.Current.SoftProof.IsEnabled && !printTurnedProofOn);
        printTurnedProofOn = active;
        // 색영역 경고는 맥에서도 프루프와 별개의 스위치입니다
        // (`model.destinationGamutWarningEnabled`). 사람이 만졌을 때 그대로 담습니다.
        bool gamut = OutputTab.GamutWarningSelector.SelectedValue as bool? ??
            state.Current.SoftProof.GamutWarningEnabled;
        // <b>달라질 때만</b> 씁니다. 값이 같은데도 쓰면 설정 변경 알림이 다시 동기화를 부르고,
        // 그 동기화가 또 여기로 들어와 UI 스레드가 멈춥니다.
        if (string.Equals(state.Current.SoftProof.PrinterProfilePath, wanted, StringComparison.Ordinal) &&
            state.Current.SoftProof.Simulation == simulation &&
            state.Current.SoftProof.IsEnabled == enabled &&
            state.Current.SoftProof.GamutWarningEnabled == gamut)
        {
            return;
        }
        // 현상본이 이 프로파일로 나오게 합니다 — 사진에 프로파일이 걸리는 자리이고,
        // 색영역 경고도 여기서 ICM 이 판정합니다.
        if (printSources?.Thumbnails is { } cache &&
            cache.SetPrintProof(PrintSoftProofFilter.Preview(print, gamut)))
        {
            printPreview?.InvalidateForRecipeChange();
            printPreview?.Draw();
        }
        state.UpdateSoftProof(value => value with
        {
            PrinterProfilePath = wanted,
            IsEnabled = enabled,
            // 용지·잉크까지 흉내 낼지는 인화 설정이 정합니다(macOS `cPrintPaperSimulationEnabled`).
            Simulation = simulation,
            GamutWarningEnabled = gamut,
        });
    }

    /// <summary>macOS <c>clearCPrintProofICCProfile</c> — 지우면 미리보기도 함께 꺼집니다.</summary>
    internal void OnPrintProofClearClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.UpdatePrint(current => current with
        {
            CPrintProofProfilePath = string.Empty,
            CPrintProofProfileName = string.Empty,
            CPrintPreviewEnabled = false,
        });
        // 지우면 화면 색도 함께 돌아와야 합니다(macOS `clearCPrintProofICCProfile`).
        ApplyCprintSoftProof();
        SynchronizePrint();
    }

    private void OnPrintSegmentChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        CommitPrintSettings();
    }

    internal void OnPrintSettingChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        CommitPrintSettings();
    }

    internal void OnPrintSliderChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        CommitPrintSettings();
    }

    internal void OnPrintNumberChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        CommitPrintSettings();
    }

    internal void OnPrintToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        CommitPrintSettings();
    }

    /// <summary>
    /// 값을 화면에 넣는 동안 담기를 막습니다. 넣는 것이 다시 담기를 부르면 그 담기가 또
    /// 넣기를 불러 화면이 멈춥니다.
    /// </summary>
    private bool suppressPrintCommit;

    /// <summary>인화 미리보기 때문에 소프트 프루프를 켠 것인지입니다.</summary>
    private bool printTurnedProofOn;

    private void CommitPrintSettings()
    {
        if (printInspector is null ||
            printInspector.IsSynchronizing ||
            suppressPrintCommit ||
            workspaceState is not { } state)
        {
            return;
        }
        printInspector.Commit(state);
        // 색영역 경고와 프루프 목적지는 `PrintPreferences` 가 아니라 소프트 프루프 설정에
        // 삽니다. 사람이 세그먼트를 만졌을 때 여기서 담지 않으면 아무 데도 기록되지 않아
        // 켬 단추가 눌리지 않는 것처럼 보입니다. 되먹임은 값이 달라질 때만 쓰는 것과
        // `suppressPrintCommit` 으로 막습니다.
        ApplyCprintSoftProof();
        SynchronizePrint();
    }

    /// <summary>설정과 선택을 화면에 맞춥니다.</summary>
    private void SynchronizePrint()
    {
        if (printInspector is null || workspaceState is not { } state)
        {
            return;
        }
        printInspector.Apply(state.Current.Print);
        ApplyCprintVisibility(state.Current.Print);
        SynchronizeExportSelection();
        SeedCustomLayoutIfEmpty();
        // 셀·문구 목록은 개수가 바뀌면 통째로 다시 그립니다. 목록 안 컨트롤이 값을 바꿀
        // 때마다 다시 그리면 손잡이를 놓치므로 개수가 같으면 그대로 둡니다.
        RebuildPrintCellListsIfNeeded(state.Current.Print);
        printPreview?.Draw();
    }

    private void OnCanvasHostSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        // 확대한 판이 위 막대와 좌우 패널 위로 넘치지 않게 잘라 냅니다. WinUI 에는
        // ClipToBounds 가 없어 크기가 바뀔 때마다 사각형을 다시 잡습니다 - 현상뷰
        // 캔버스와 같은 처리입니다.
        CanvasHost.Clip = new Microsoft.UI.Xaml.Media.RectangleGeometry
        {
            Rect = new Windows.Foundation.Rect(
                0, 0, Math.Max(0, args.NewSize.Width), Math.Max(0, args.NewSize.Height)),
        };
        printPreview?.Draw();
    }

    internal void OnPrintExportClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ExportFromMenu();
    }

    /// <summary>macOS 인화 모듈의 <c>exportSelectionToFolder(for:)</c> 입니다.</summary>
    /// <summary>
    /// 메뉴의 인화 내보내기입니다. 좌측 내보내기 탭의 단추와 <b>같은 하나</b>를 부릅니다 —
    /// 두 길이 갈라지면 메뉴와 단추가 서로 다른 파일을 냅니다.
    /// </summary>
    /// <summary>
    /// 사용자 패키지의 셀 목록과 손으로 놓은 문구 목록을 만드는 자리입니다.
    /// </summary>
    private Print.Settings.PrintCellEditor? cellEditor;

    private Print.Settings.PrintCellEditor CellEditor => cellEditor ??= new(
        () => workspaceState?.Current.Print ?? new PrintPreferences(),
        update =>
        {
            workspaceState?.UpdatePrint(update);
            SynchronizePrint();
        },
        () => [.. PrintSources.Select(LibraryFrameNaming.DisplayName)]);

    private int builtCellCount = -1;

    private int builtCaptionCount = -1;

    /// <summary>목록을 지을 때 쓴 사진들입니다. 선택이 바뀌면 "사진" 팝업도 다시 짓습니다.</summary>
    private string builtSourceSignature = string.Empty;

    /// <summary>개수가 달라졌을 때만 목록을 다시 만듭니다.</summary>
    private void RebuildPrintCellListsIfNeeded(PrintPreferences print)
    {
        // 칸의 "사진" 팝업에 들어가는 목록은 **고른 사진들**입니다. 여러 장을 골랐다 말았다
        // 하면 그 목록이 달라지므로, 칸 수가 그대로여도 다시 지어야 합니다 — 그러지 않으면
        // 새로 고른 사진이 팝업에 나오지 않고 예전 목록이 그대로 남습니다.
        string sourceSignature = string.Join('', PrintSources.Select(frame => frame.Id));
        if (builtCellCount == print.CustomItems.Count &&
            builtCaptionCount == print.CustomCaptions.Count &&
            string.Equals(builtSourceSignature, sourceSignature, StringComparison.Ordinal))
        {
            return;
        }
        builtCellCount = print.CustomItems.Count;
        builtCaptionCount = print.CustomCaptions.Count;
        builtSourceSignature = sourceSignature;
        RebuildPrintCellLists();
    }

    /// <summary>목록을 지금 설정에 맞춰 다시 그립니다.</summary>
    internal void RebuildPrintCellLists()
    {
        CellEditor.BuildCells(LayoutTab.CustomItemsHost);
        CellEditor.BuildCaptions(ContentTab.CustomCaptionsHost);
    }

    internal void OnAddCustomCaptionClicked()
    {
        CellEditor.AddCaption();
        SynchronizePrint();
    }

    /// <summary>인스펙터 어디서든 값이 바뀌면 담고 다시 그립니다.</summary>
    internal void OnPrintInspectorChanged() => CommitPrintSettings();

    internal void ExportFromMenu()
    {
        if (printSheetExport is { } runner)
        {
            _ = runner.RunExportAsync(PrintExportPanel.Settings);
        }
    }

    /// <summary>하단바가 범위·차례를 바꿨습니다. 필름스트립을 다시 냅니다.</summary>
    internal void RefreshSources()
    {
        if (printExportHost is { } host)
        {
            printSources?.ShowLibrary(host);
        }
    }

    private static PrintSizeMm SourcePixelSize(LibraryFrameSnapshot frame) =>
        PrintPreviewRenderer.SourcePixelSize(frame);

    private double PreviewScale(PrintSizeMm canvas) =>
        printPreview?.PreviewScale(canvas) ?? 1;
}
