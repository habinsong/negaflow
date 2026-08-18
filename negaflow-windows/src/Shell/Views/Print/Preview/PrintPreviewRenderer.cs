using System.IO;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Shapes;
using Negaflow.Catalog;
using Negaflow.Shell.Library;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Print;
using Negaflow.Shell.Views;

namespace Negaflow.Shell.Views.Print.Preview;

/// <summary>
/// 판을 화면에 그립니다. 좌표는 layout 이 낸 화소 값을 한 배율로만 줄입니다.
/// </summary>
internal sealed class PrintPreviewRenderer
{
    private readonly PrintPreviewSurface surface;
    private readonly Func<IReadOnlyList<LibraryFrameSnapshot>> sources;
    private readonly Func<ThumbnailService?> thumbnails;
    private readonly Func<WorkspacePresentationState?> state;
    private readonly Action<PrintPackagePageLayout, double> drawCustomEditor;

    internal PrintPreviewRenderer(
        PrintPreviewSurface surface,
        Func<IReadOnlyList<LibraryFrameSnapshot>> sources,
        Func<ThumbnailService?> thumbnails,
        Func<WorkspacePresentationState?> state,
        Action<PrintPackagePageLayout, double> drawCustomEditor)
    {
        this.surface = surface;
        this.sources = sources;
        this.thumbnails = thumbnails;
        this.state = state;
        this.drawCustomEditor = drawCustomEditor;
    }

    /// <summary>
    /// 원본의 화소 크기입니다. 아직 읽지 못했으면 3:2 로 둡니다 — macOS 도 모르는 비율을
    /// 그렇게 다룹니다.
    /// </summary>
    internal static PrintSizeMm SourcePixelSize(LibraryFrameSnapshot frame) =>
        frame.SourceMetadata is { PixelWidth: > 0, PixelHeight: > 0 } metadata
            ? new PrintSizeMm(metadata.PixelWidth, metadata.PixelHeight)
            : new PrintSizeMm(3000, 2000);

    internal double PreviewScale(PrintSizeMm canvas)
    {
        double available = Math.Max(120, Math.Min(
            surface.CanvasHost.ActualWidth - 48,
            surface.CanvasHost.ActualHeight - 48));
        double longest = Math.Max(canvas.Width, canvas.Height);
        return longest > 0 ? available / longest : 1;
    }

    internal void Draw()
    {
        if (surface.PageCanvas is null || state() is not { } workspace)
        {
            return;
        }
        surface.PageCanvas.Children.Clear();
        IReadOnlyList<LibraryFrameSnapshot> currentSources = sources();
        if (currentSources.Count == 0)
        {
            surface.PageBorder.Visibility = Visibility.Collapsed;
            surface.NoFramePanel.Visibility = Visibility.Visible;
            surface.PageCountText.Text = string.Empty;
            surface.PageSizeSummaryText.Text = string.Empty;
            surface.PrintExportButton.IsEnabled = false;
            surface.RulerCanvas.Children.Clear();
            return;
        }
        surface.NoFramePanel.Visibility = Visibility.Collapsed;
        surface.PageBorder.Visibility = Visibility.Visible;
        surface.PrintExportButton.IsEnabled = true;

        PrintPreferences print = workspace.Current.Print;
        PrintSizeMm firstSource = SourcePixelSize(currentSources[0]);
        PrintCompositionSettings composition = print.Composition(
            firstSource.Height > 0 ? firstSource.Width / firstSource.Height : null);

        if (PrintPreferences.PackageModeFor(print.LayoutMode) is not null)
        {
            DrawPackagePreview(currentSources, composition, print);
            return;
        }
        DrawSinglePreview(currentSources[0], firstSource, composition, print);
    }

    private void DrawSinglePreview(
        LibraryFrameSnapshot frame,
        PrintSizeMm sourceSize,
        PrintCompositionSettings composition,
        PrintPreferences print)
    {
        if (PrintCompositionLayout.Make(sourceSize, composition) is not { } layout)
        {
            surface.PageBorder.Visibility = Visibility.Collapsed;
            surface.PageSizeSummaryText.Text = string.Empty;
            return;
        }
        double scale = PreviewScale(layout.CanvasSize);
        SetPageSize(layout.CanvasSize, scale, print.SheetBackground);

        if (layout.FilmRect is { } film)
        {
            // 필름 띠는 현상된 컬러 네거티브의 베이스 색입니다 — macOS
            // PrintFilmStripAppearance 와 같은 뜻입니다.
            surface.PageCanvas.Children.Add(Rect(
                film,
                scale,
                Windows.UI.Color.FromArgb(0xEB, 0x70, 0x2B, 0x0E)));
        }
        surface.PageCanvas.Children.Add(ImageTile(frame, layout.ImageRect, scale, 0));
        foreach (PrintRect hole in layout.PerforationRects)
        {
            surface.PageCanvas.Children.Add(Rect(
                hole,
                scale,
                Windows.UI.Color.FromArgb(0xFF, 0xFF, 0xFF, 0xFF),
                layout.PerforationCornerRadius * scale));
        }
        surface.PageCountText.Text = string.Empty;
        DrawRulers(layout.CanvasSize, scale, composition);
        WritePageSummary(layout.CanvasSize, composition);
    }

    private void DrawPackagePreview(
        IReadOnlyList<LibraryFrameSnapshot> currentSources,
        PrintCompositionSettings composition,
        PrintPreferences print)
    {
        PrintSizeMm[] sizes = [.. currentSources.Select(SourcePixelSize)];
        if (PrintPackageLayout.Make(sizes, composition, print.Package())
            is not { Count: > 0 } pages)
        {
            surface.PageBorder.Visibility = Visibility.Collapsed;
            surface.PageSizeSummaryText.Text = string.Empty;
            return;
        }
        // 첫 판만 그립니다. 나머지는 장수로 알립니다 — 스무 장을 한꺼번에 그리면 설정을
        // 만질 때마다 화면이 멈춥니다.
        PrintPackagePageLayout page = pages[0];
        double scale = PreviewScale(page.CanvasSize);
        SetPageSize(page.CanvasSize, scale, print.SheetBackground);
        foreach (PrintPackageItemLayout item in page.Items)
        {
            surface.PageCanvas.Children.Add(ImageTile(
                currentSources[item.SourceIndex],
                item.ImageRect,
                scale,
                item.QuarterTurns));
        }
        foreach (PrintPackageItemLayout item in page.Items)
        {
            if (item.CaptionRect is not { } caption)
            {
                continue;
            }
            // 캡션 자리를 옅게 표시합니다. 글자는 판을 쓸 때 들어갑니다 — 미리보기에서 자리를
            // 보여야 사용자가 사진이 왜 위로 물러났는지 압니다.
            surface.PageCanvas.Children.Add(Rect(
                caption,
                scale,
                Windows.UI.Color.FromArgb(0x33, 0x80, 0x80, 0x80)));
        }
        foreach (PrintLineSegment segment in page.CropMarks)
        {
            surface.PageCanvas.Children.Add(Line(segment, scale, print.SheetBackground));
        }
        surface.PageCountText.Text = pages.Count > 1
            ? AppResources.FormatIntegers("printPageCountFormat", "Text", pages.Count)
            : string.Empty;
        DrawRulers(page.CanvasSize, scale, composition);
        drawCustomEditor(page, scale);
        WritePageSummary(page.CanvasSize, composition);
    }

    /// <summary>
    /// 판 위와 왼쪽에 눈금자를 답니다. 눈금은 용지의 실제 mm 를 따르므로, 화면에서 잰 길이가
    /// 인화물에서도 같습니다.
    /// </summary>
    private void DrawRulers(PrintSizeMm canvasPixels, double scale, PrintCompositionSettings composition)
    {
        surface.RulerCanvas.Children.Clear();
        if (state() is not { } workspace || !workspace.Current.Print.ShowsRulers)
        {
            return;
        }
        PrintRulerUnit unit = workspace.Current.Print.RulerUnit;
        double pixelsPerMm = composition.Dpi / 25.4;
        double widthMm = canvasPixels.Width / pixelsPerMm;
        double heightMm = canvasPixels.Height / pixelsPerMm;
        double pageWidth = canvasPixels.Width * scale;
        double pageHeight = canvasPixels.Height * scale;
        // 판은 가운데 있습니다. 눈금자는 그 가장자리에 맞춰 놓습니다.
        double pageLeft = (surface.CanvasHost.ActualWidth - pageWidth) / 2;
        double pageTop = (surface.CanvasHost.ActualHeight - pageHeight) / 2;
        const double band = 16;

        foreach (PrintRulerTick tick in PrintRuler.Ticks(widthMm, unit))
        {
            double x = pageLeft + (tick.Position * pageWidth);
            AddRulerLine(x, pageTop - (band * tick.Length), x, pageTop);
            AddRulerLabel(tick.Label, x + 2, pageTop - band);
        }
        foreach (PrintRulerTick tick in PrintRuler.Ticks(heightMm, unit))
        {
            double y = pageTop + (tick.Position * pageHeight);
            AddRulerLine(pageLeft - (band * tick.Length), y, pageLeft, y);
            AddRulerLabel(tick.Label, pageLeft - band, y + 2);
        }
    }

    private void AddRulerLine(double x1, double y1, double x2, double y2)
    {
        Line line = new()
        {
            X1 = x1,
            Y1 = y1,
            X2 = x2,
            Y2 = y2,
            StrokeThickness = 1,
            Stroke = new SolidColorBrush(Windows.UI.Color.FromArgb(0xAA, 0xB4, 0xB4, 0xB4)),
        };
        surface.RulerCanvas.Children.Add(line);
    }

    private void AddRulerLabel(string? text, double left, double top)
    {
        if (text is null)
        {
            return;
        }
        TextBlock label = new()
        {
            Text = text,
            FontSize = 9,
            Foreground = new SolidColorBrush(Windows.UI.Color.FromArgb(0xCC, 0xB4, 0xB4, 0xB4)),
        };
        Canvas.SetLeft(label, left);
        Canvas.SetTop(label, top);
        surface.RulerCanvas.Children.Add(label);
    }

    private void SetPageSize(PrintSizeMm canvas, double scale, PrintSheetBackground background)
    {
        surface.PageBorder.Width = canvas.Width * scale;
        surface.PageBorder.Height = canvas.Height * scale;
        surface.PageCanvas.Width = surface.PageBorder.Width;
        surface.PageCanvas.Height = surface.PageBorder.Height;
        surface.PageBorder.Background = new SolidColorBrush(background switch
        {
            PrintSheetBackground.Black => Windows.UI.Color.FromArgb(0xFF, 0, 0, 0),
            PrintSheetBackground.Gray => Windows.UI.Color.FromArgb(0xFF, 0x80, 0x80, 0x80),
            _ => Windows.UI.Color.FromArgb(0xFF, 0xFF, 0xFF, 0xFF),
        });
    }

    private void WritePageSummary(PrintSizeMm canvas, PrintCompositionSettings composition)
    {
        surface.PageSizeSummaryText.Text = AppResources
            .FormatIntegers("printPageSummaryFormat", "Text", composition.Dpi)
            .Replace("{0}", PrintPaper.Label(composition.PaperSize), StringComparison.Ordinal)
            .Replace("{1}", ((int)canvas.Width).ToString(
                System.Globalization.CultureInfo.CurrentCulture), StringComparison.Ordinal)
            .Replace("{2}", ((int)canvas.Height).ToString(
                System.Globalization.CultureInfo.CurrentCulture), StringComparison.Ordinal);
    }

    /// <summary>
    /// 재단선 하나입니다. 종이가 어두우면 밝게 그립니다 — macOS
    /// <c>prefersLightForeground</c> 와 같은 판단입니다.
    /// </summary>
    private static Line Line(
        PrintLineSegment segment,
        double scale,
        PrintSheetBackground background) => new()
    {
        X1 = segment.StartX * scale,
        Y1 = segment.StartY * scale,
        X2 = segment.EndX * scale,
        Y2 = segment.EndY * scale,
        StrokeThickness = 1,
        Stroke = new SolidColorBrush(background == PrintSheetBackground.White
            ? Windows.UI.Color.FromArgb(0x99, 0x00, 0x00, 0x00)
            : Windows.UI.Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF)),
    };

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
        ThumbnailService? cache = thumbnails();
        // macOS PrintSingleImagePageView: developedImage ?? rawPreviewImage ?? thumbnailImage.
        // 현상본이 있으면 그것을 쓰고, 칸이 더 크면 표시 크기로 올립니다.
        if (cache?.TryGetDeveloped(frame.Id, out ThumbnailService.DevelopedPreview developed) == true)
        {
            image.Source = BgraBitmap(developed);
        }
        else if (cache?.TryGet(frame.Id) is { } jpeg)
        {
            image.Source = LibraryWorkspaceView.DecodeThumbnail(jpeg);
        }
        RequestDevelopedIfNeeded(cache, frame, rect, scale);
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

    private void RequestDevelopedIfNeeded(
        ThumbnailService? cache,
        LibraryFrameSnapshot frame,
        PrintRect rect,
        double scale)
    {
        if (cache is null)
        {
            return;
        }

        double dpi = surface.CanvasHost.XamlRoot?.RasterizationScale ?? 1;
        if (dpi <= 0)
        {
            dpi = 1;
        }

        double displayPixels = Math.Max(rect.Width, rect.Height) * scale * dpi;
        int current = cache.TryGetDeveloped(frame.Id, out ThumbnailService.DevelopedPreview developed)
            ? (int)PrintPreviewResolution.PixelDimension(developed.Width, developed.Height)
            : 0;
        if (!PrintPreviewResolution.NeedsUpgrade(current, displayPixels))
        {
            return;
        }

        double target = PrintPreviewResolution.RenderDimension(displayPixels);
        if (target > 0)
        {
            cache.RequestDeveloped(frame, (int)target);
        }
    }

    private static WriteableBitmap BgraBitmap(ThumbnailService.DevelopedPreview preview)
    {
        WriteableBitmap bitmap = new(preview.Width, preview.Height);
        int written = preview.Width * preview.Height * 4;
        using (Stream buffer = bitmap.PixelBuffer.AsStream())
        {
            buffer.Write(preview.Pixels, 0, written);
        }
        bitmap.Invalidate();
        return bitmap;
    }
}
