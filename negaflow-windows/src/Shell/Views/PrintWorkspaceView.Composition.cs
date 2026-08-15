using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Shapes;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Print;

namespace Negaflow.Shell.Views;

/// <summary>
/// 인화 화면의 판 짜기입니다. macOS <c>PrintWorkspaceInspector</c> 와 <c>PrintCanvasView</c> 가
/// 하는 일을 합니다.
/// </summary>
/// <remarks>
/// **화면과 파일이 같은 <c>PrintCompositionLayout</c> 을 씁니다.** 미리보기를 따로 계산하면
/// 보이는 여백과 나오는 여백이 갈리고, 그 어긋남은 인화를 마친 뒤에야 드러납니다.
/// </remarks>
public sealed partial class PrintWorkspaceView
{
    private LibraryHostService? libraryHost;
    private bool isSynchronizingPrint;

    /// <summary>고르개 한 줄입니다. 값과 보이는 이름을 함께 듭니다.</summary>
    private sealed record PrintChoice<T>(T Value, string Label);

    /// <summary>
    /// 인화할 사진들입니다. 라이브러리에서 고른 것을 그대로 씁니다 — macOS 도 같은 선택을
    /// 봅니다.
    /// </summary>
    private IReadOnlyList<LibraryFrameSnapshot> PrintSources =>
        libraryHost?.SelectedFrames is { Count: > 0 } selected
            ? selected
            : libraryHost?.Frames is { Count: > 0 } all
                ? [all[0]]
                : [];

    private Negaflow.Shell.Library.ThumbnailService? thumbnails;

    /// <summary>
    /// 썸네일이 도착하면 판을 다시 그립니다. 인화 화면은 라이브러리와 같은 캐시를 봅니다 —
    /// 같은 사진을 두 번 만들 이유가 없습니다.
    /// </summary>
    public void AttachThumbnails(Negaflow.Shell.Library.ThumbnailService service)
    {
        ArgumentNullException.ThrowIfNull(service);
        if (thumbnails is not null)
        {
            thumbnails.ThumbnailReady -= OnPrintThumbnailReady;
        }
        thumbnails = service;
        thumbnails.ThumbnailReady += OnPrintThumbnailReady;
    }

    private void OnPrintThumbnailReady(string frameId)
    {
        _ = frameId;
        DrawPrintPreview();
    }

    public void ShowLibrary(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        libraryHost = host;
        host.SelectionChanged += OnPrintSelectionChanged;
        // 고른 사진의 썸네일이 아직 없을 수 있습니다. 미리보기가 그림 없이 시작하지 않도록
        // 여기서 한 번 청합니다.
        foreach (LibraryFrameSnapshot frame in PrintSources)
        {
            thumbnails?.Request(frame);
        }
        SynchronizePrint();
    }

    private void OnPrintSelectionChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        SynchronizePrint();
    }

    private void LocalizePrintInspector()
    {
        LayoutModeText.Text = AppResources.Get("printLayoutMode", "Text");
        PaperSizeText.Text = AppResources.Get("printPaperSize", "Text");
        OrientationText.Text = AppResources.Get("printOrientation", "Text");
        PerforationText.Text = AppResources.Get("printPerforation", "Text");
        DpiText.Text = AppResources.Get("printResolution", "Text");
        SheetSectionText.Text = AppResources.Get("printSheetSection", "Text");
        RowsText.Text = AppResources.Get("printRows", "Text");
        ColumnsText.Text = AppResources.Get("printColumns", "Text");
        ContentModeText.Text = AppResources.Get("printContentMode", "Text");
        SheetBackgroundText.Text = AppResources.Get("printSheetBackground", "Text");
        OutputSectionText.Text = AppResources.Get("printOutputSection", "Content");
        SetToggleLabel(RotateToFitToggle, AppResources.Get("printRotateToFit", "Text"));
        SetToggleLabel(RepeatToggle, AppResources.Get("printRepeatOnePhoto", "Text"));
        PrintExportButton.Content = AppResources.Get("printExport", "Content");

        LayoutModeSelector.ItemsSource = new[]
        {
            Choice(PrintLayoutMode.SingleImage, "printModeSingle"),
            Choice(PrintLayoutMode.ContactSheet, "printModeContactSheet"),
            Choice(PrintLayoutMode.PicturePackage, "printModePicturePackage"),
            Choice(PrintLayoutMode.Cyanotype, "printModeCyanotype"),
            Choice(PrintLayoutMode.GlassPlate, "printModeGlassPlate"),
            Choice(PrintLayoutMode.Gelatin, "printModeGelatin"),
        };
        PaperSizeSelector.ItemsSource = PrintPaper.All
            .Select(size => new PrintChoice<PrintPaperSize>(size, PrintPaper.Label(size)))
            .ToArray();
        OrientationSelector.ItemsSource = new[]
        {
            Choice(PrintPaperOrientation.Automatic, "printOrientationAuto"),
            Choice(PrintPaperOrientation.Portrait, "printOrientationPortrait"),
            Choice(PrintPaperOrientation.Landscape, "printOrientationLandscape"),
        };
        PerforationSelector.ItemsSource = new[]
        {
            Choice(PrintPerforationStyle.None, "printPerforationNone"),
            Choice(PrintPerforationStyle.ThirtyFiveMillimeter, "printPerforation35mm"),
        };
        // macOS 와 같은 네 단계입니다. 인화소가 받는 값이라 번역하지 않습니다.
        DpiSelector.ItemsSource = new[] { 150, 240, 300, 360, 600 }
            .Select(dpi => new PrintChoice<int>(dpi, $"{dpi} dpi"))
            .ToArray();
        ContentModeSelector.ItemsSource = new[]
        {
            Choice(PrintPackageContentMode.Fit, "printFit"),
            Choice(PrintPackageContentMode.Fill, "printFill"),
        };
        SheetBackgroundSelector.ItemsSource = new[]
        {
            Choice(PrintSheetBackground.White, "printBackgroundWhite"),
            Choice(PrintSheetBackground.Gray, "printBackgroundGray"),
            Choice(PrintSheetBackground.Black, "printBackgroundBlack"),
        };
    }

    private static PrintChoice<T> Choice<T>(T value, string key) =>
        new(value, AppResources.Get(key, "Text"));

    private static void SetToggleLabel(ToggleSwitch toggle, string text)
    {
        toggle.Header = text;
        AutomationProperties.SetName(toggle, text);
    }

    private void OnPrintSettingChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        CommitPrintSettings();
    }

    private void OnPrintSliderChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        CommitPrintSettings();
    }

    private void OnPrintNumberChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        CommitPrintSettings();
    }

    private void OnPrintToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        CommitPrintSettings();
    }

    /// <summary>고른 값을 설정에 담습니다. 담긴 값이 곧 미리보기와 파일을 정합니다.</summary>
    private void CommitPrintSettings()
    {
        if (isSynchronizingPrint || workspaceState is not { } state)
        {
            return;
        }
        state.UpdatePrint(current => current with
        {
            LayoutMode = Selected(LayoutModeSelector, current.LayoutMode),
            PaperSize = Selected(PaperSizeSelector, current.PaperSize),
            Orientation = Selected(OrientationSelector, current.Orientation),
            PerforationStyle = Selected(PerforationSelector, current.PerforationStyle),
            Dpi = Selected(DpiSelector, current.Dpi),
            MarginMm = MarginSlider.Value,
            ContactRows = (int)Math.Round(
                double.IsNaN(RowsBox.Value) ? current.ContactRows : RowsBox.Value),
            ContactColumns = (int)Math.Round(
                double.IsNaN(ColumnsBox.Value) ? current.ContactColumns : ColumnsBox.Value),
            HorizontalSpacingMm = SpacingSlider.Value,
            VerticalSpacingMm = SpacingSlider.Value,
            ContentMode = Selected(ContentModeSelector, current.ContentMode),
            RotateToFit = RotateToFitToggle.IsOn,
            RepeatOnePhotoPerPage = RepeatToggle.IsOn,
            SheetBackground = Selected(SheetBackgroundSelector, current.SheetBackground),
        });
        SynchronizePrint();
    }

    private static T Selected<T>(ComboBox selector, T fallback) =>
        selector.SelectedItem is PrintChoice<T> choice ? choice.Value : fallback;

    /// <summary>설정과 선택을 화면에 맞춥니다.</summary>
    private void SynchronizePrint()
    {
        if (LayoutModeSelector is null || workspaceState is not { } state)
        {
            return;
        }
        PrintPreferences print = state.Current.Print;
        isSynchronizingPrint = true;
        try
        {
            Select(LayoutModeSelector, print.LayoutMode);
            Select(PaperSizeSelector, print.PaperSize);
            Select(OrientationSelector, print.Orientation);
            Select(PerforationSelector, print.PerforationStyle);
            Select(DpiSelector, print.Dpi);
            MarginSlider.Value = print.MarginMm;
            RowsBox.Value = print.ContactRows;
            ColumnsBox.Value = print.ContactColumns;
            SpacingSlider.Value = print.HorizontalSpacingMm;
            Select(ContentModeSelector, print.ContentMode);
            RotateToFitToggle.IsOn = print.RotateToFit;
            RepeatToggle.IsOn = print.RepeatOnePhotoPerPage;
            Select(SheetBackgroundSelector, print.SheetBackground);
        }
        finally
        {
            isSynchronizingPrint = false;
        }

        MarginText.Text = AppResources
            .Get("printMarginFormat", "Text")
            .Replace("{0}", print.MarginMm.ToString("0.#",
                System.Globalization.CultureInfo.CurrentCulture), StringComparison.Ordinal);
        SpacingText.Text = AppResources
            .Get("printSpacingFormat", "Text")
            .Replace("{0}", print.HorizontalSpacingMm.ToString("0.#",
                System.Globalization.CultureInfo.CurrentCulture), StringComparison.Ordinal);
        SheetCard.Visibility = PrintPreferences.PackageModeFor(print.LayoutMode) is null
            ? Visibility.Collapsed
            : Visibility.Visible;
        DrawPrintPreview();
    }

    private static void Select<T>(ComboBox selector, T value)
    {
        foreach (object item in selector.ItemsSource is IEnumerable<object> source
                     ? source
                     : [])
        {
            if (item is PrintChoice<T> choice && EqualityComparer<T>.Default.Equals(
                    choice.Value,
                    value))
            {
                selector.SelectedItem = item;
                return;
            }
        }
    }

    private void OnCanvasHostSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        DrawPrintPreview();
    }

    /// <summary>
    /// 판을 그립니다. 좌표는 layout 이 낸 화소 값을 화면 크기에 맞춰 **한 배율로만** 줄인
    /// 것입니다 — 따로 계산하면 미리보기와 파일이 달라집니다.
    /// </summary>
    private void DrawPrintPreview()
    {
        if (PageCanvas is null || workspaceState is not { } state)
        {
            return;
        }
        PageCanvas.Children.Clear();
        IReadOnlyList<LibraryFrameSnapshot> sources = PrintSources;
        if (sources.Count == 0)
        {
            PageBorder.Visibility = Visibility.Collapsed;
            NoFramePanel.Visibility = Visibility.Visible;
            PageCountText.Text = string.Empty;
            PageSizeSummaryText.Text = string.Empty;
            PrintExportButton.IsEnabled = false;
            return;
        }
        NoFramePanel.Visibility = Visibility.Collapsed;
        PageBorder.Visibility = Visibility.Visible;
        PrintExportButton.IsEnabled = true;

        PrintPreferences print = state.Current.Print;
        PrintSizeMm firstSource = SourcePixelSize(sources[0]);
        PrintCompositionSettings composition = print.Composition(
            firstSource.Height > 0 ? firstSource.Width / firstSource.Height : null);

        if (PrintPreferences.PackageModeFor(print.LayoutMode) is not null)
        {
            DrawPackagePreview(sources, composition, print);
            return;
        }
        DrawSinglePreview(sources[0], firstSource, composition, print);
    }

    private void DrawSinglePreview(
        LibraryFrameSnapshot frame,
        PrintSizeMm sourceSize,
        PrintCompositionSettings composition,
        PrintPreferences print)
    {
        if (PrintCompositionLayout.Make(sourceSize, composition) is not { } layout)
        {
            PageBorder.Visibility = Visibility.Collapsed;
            PageSizeSummaryText.Text = string.Empty;
            return;
        }
        double scale = PreviewScale(layout.CanvasSize);
        SetPageSize(layout.CanvasSize, scale, print.SheetBackground);

        if (layout.FilmRect is { } film)
        {
            // 필름 띠는 현상된 컬러 네거티브의 베이스 색입니다 — macOS
            // PrintFilmStripAppearance 와 같은 뜻입니다.
            PageCanvas.Children.Add(Rect(
                film,
                scale,
                Windows.UI.Color.FromArgb(0xEB, 0x70, 0x2B, 0x0E)));
        }
        PageCanvas.Children.Add(ImageTile(frame, layout.ImageRect, scale, 0));
        foreach (PrintRect hole in layout.PerforationRects)
        {
            PageCanvas.Children.Add(Rect(
                hole,
                scale,
                Windows.UI.Color.FromArgb(0xFF, 0xFF, 0xFF, 0xFF),
                layout.PerforationCornerRadius * scale));
        }
        PageCountText.Text = string.Empty;
        WritePageSummary(layout.CanvasSize, composition);
    }

    private void DrawPackagePreview(
        IReadOnlyList<LibraryFrameSnapshot> sources,
        PrintCompositionSettings composition,
        PrintPreferences print)
    {
        PrintSizeMm[] sizes = [.. sources.Select(SourcePixelSize)];
        if (PrintPackageLayout.Make(sizes, composition, print.Package())
            is not { Count: > 0 } pages)
        {
            PageBorder.Visibility = Visibility.Collapsed;
            PageSizeSummaryText.Text = string.Empty;
            return;
        }
        // 첫 판만 그립니다. 나머지는 장수로 알립니다 — 스무 장을 한꺼번에 그리면 설정을
        // 만질 때마다 화면이 멈춥니다.
        PrintPackagePageLayout page = pages[0];
        double scale = PreviewScale(page.CanvasSize);
        SetPageSize(page.CanvasSize, scale, print.SheetBackground);
        foreach (PrintPackageItemLayout item in page.Items)
        {
            PageCanvas.Children.Add(ImageTile(
                sources[item.SourceIndex],
                item.ImageRect,
                scale,
                item.QuarterTurns));
        }
        PageCountText.Text = pages.Count > 1
            ? AppResources.FormatIntegers("printPageCountFormat", "Text", pages.Count)
            : string.Empty;
        WritePageSummary(page.CanvasSize, composition);
    }

    /// <summary>
    /// 원본의 화소 크기입니다. 아직 읽지 못했으면 3:2 로 둡니다 — macOS 도 모르는 비율을
    /// 그렇게 다룹니다.
    /// </summary>
    private static PrintSizeMm SourcePixelSize(LibraryFrameSnapshot frame) =>
        frame.SourceMetadata is { PixelWidth: > 0, PixelHeight: > 0 } metadata
            ? new PrintSizeMm(metadata.PixelWidth, metadata.PixelHeight)
            : new PrintSizeMm(3000, 2000);

    private double PreviewScale(PrintSizeMm canvas)
    {
        double available = Math.Max(120, Math.Min(
            CanvasHost.ActualWidth - 48,
            CanvasHost.ActualHeight - 48));
        double longest = Math.Max(canvas.Width, canvas.Height);
        return longest > 0 ? available / longest : 1;
    }

    private void SetPageSize(PrintSizeMm canvas, double scale, PrintSheetBackground background)
    {
        PageBorder.Width = canvas.Width * scale;
        PageBorder.Height = canvas.Height * scale;
        PageCanvas.Width = PageBorder.Width;
        PageCanvas.Height = PageBorder.Height;
        PageBorder.Background = new SolidColorBrush(background switch
        {
            PrintSheetBackground.Black => Windows.UI.Color.FromArgb(0xFF, 0, 0, 0),
            PrintSheetBackground.Gray => Windows.UI.Color.FromArgb(0xFF, 0x80, 0x80, 0x80),
            _ => Windows.UI.Color.FromArgb(0xFF, 0xFF, 0xFF, 0xFF),
        });
    }

    private void WritePageSummary(PrintSizeMm canvas, PrintCompositionSettings composition)
    {
        PageSizeSummaryText.Text = AppResources
            .FormatIntegers("printPageSummaryFormat", "Text", composition.Dpi)
            .Replace("{0}", PrintPaper.Label(composition.PaperSize), StringComparison.Ordinal)
            .Replace("{1}", ((int)canvas.Width).ToString(
                System.Globalization.CultureInfo.CurrentCulture), StringComparison.Ordinal)
            .Replace("{2}", ((int)canvas.Height).ToString(
                System.Globalization.CultureInfo.CurrentCulture), StringComparison.Ordinal);
    }

    /// <summary>
    /// 판을 폴더에 씁니다. 폴더는 macOS 처럼 사용자가 고릅니다 — 앱이 자리를 정하면 어디로
    /// 갔는지 찾아 헤매게 됩니다.
    /// </summary>
    private async void OnPrintExportClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is not { } state || printWindowId is not { } windowId)
        {
            return;
        }
        IReadOnlyList<LibraryFrameSnapshot> sources = PrintSources;
        if (sources.Count == 0)
        {
            return;
        }
        Microsoft.Windows.Storage.Pickers.FolderPicker picker = new(windowId);
        if (await picker.PickSingleFolderAsync() is not { } folder)
        {
            return;
        }
        PrintExportButton.IsEnabled = false;
        PrintStatusText.Text = string.Empty;
        try
        {
            PrintSheetWriteResult result = await PrintSheetWriter.WriteAsync(
                sources,
                state.Current.Print,
                folder.Path,
                LibraryFrameNaming.DisplayName(sources[0]));
            PrintStatusText.Text = result.IsSuccess
                ? AppResources
                    .Get("printExportDone", "Text")
                    .Replace("{0}", folder.Path, StringComparison.Ordinal)
                : AppResources.Get("printExportFailed", "Text");
        }
        finally
        {
            PrintExportButton.IsEnabled = true;
        }
    }

    /// <summary>폴더 선택기는 자기가 어느 창에 붙을지 알아야 합니다.</summary>
    private Microsoft.UI.WindowId? printWindowId;

    public void AttachWindow(Microsoft.UI.WindowId windowId) => printWindowId = windowId;

    private static Rectangle Rect(
        PrintRect rect,
        double scale,
        Windows.UI.Color color,
        double cornerRadius = 0)
    {
        Rectangle shape = new()
        {
            Width = Math.Max(0, rect.Width * scale),
            Height = Math.Max(0, rect.Height * scale),
            Fill = new SolidColorBrush(color),
            RadiusX = cornerRadius,
            RadiusY = cornerRadius,
        };
        Canvas.SetLeft(shape, rect.X * scale);
        Canvas.SetTop(shape, rect.Y * scale);
        return shape;
    }

    private FrameworkElement ImageTile(
        LibraryFrameSnapshot frame,
        PrintRect rect,
        double scale,
        int quarterTurns)
    {
        Image image = new()
        {
            Width = Math.Max(1, rect.Width * scale),
            Height = Math.Max(1, rect.Height * scale),
            Stretch = Stretch.Fill,
        };
        // 썸네일이 아직 없으면 회색 자리만 둡니다 — 판의 짜임은 그림 없이도 옳습니다.
        if (thumbnails?.TryGet(frame.Id) is { } jpeg)
        {
            image.Source = LibraryWorkspaceView.DecodeThumbnail(jpeg);
        }
        Border host = new()
        {
            Width = image.Width,
            Height = image.Height,
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0x33, 0x80, 0x80, 0x80)),
            Child = image,
        };
        if (quarterTurns % 4 != 0)
        {
            host.RenderTransformOrigin = new Windows.Foundation.Point(0.5, 0.5);
            host.RenderTransform = new RotateTransform { Angle = 90 * (quarterTurns % 4) };
        }
        Canvas.SetLeft(host, rect.X * scale);
        Canvas.SetTop(host, rect.Y * scale);
        return host;
    }
}
