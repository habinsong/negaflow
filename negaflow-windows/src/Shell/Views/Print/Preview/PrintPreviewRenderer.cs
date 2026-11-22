using Windows.Graphics.Imaging;
using Windows.Storage.Streams;
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

    /// <summary>
    /// 풀어 놓은 그림입니다. 같은 사진을 다시 그릴 때 <b>다시 풀지 않습니다</b>.
    /// </summary>
    /// <remarks>
    /// 이것이 없으면 칸을 한 화소 끌 때마다 판에 놓인 사진을 모두 다시 풀었습니다 — JPEG
    /// 디코드와 BGRA 변환이 초당 수십 번 돌아 끌기가 눈에 띄게 끊겼습니다. macOS 도
    /// <c>NSImage</c> 를 들고 있다가 자리만 바꿉니다.
    ///
    /// 새 썸네일이나 현상본이 도착하면 <see cref="InvalidateTiles"/> 로 비웁니다.
    /// </remarks>
    private readonly PrintPreviewTileCache<ImageSource> tileImages = new();
    private (string Lab, string Printer) cachedProofPaths;

    /// <summary>워터마크 띠의 참조 그림·로고를 풀어 둔 자리입니다.</summary>
    private readonly PrintWatermarkPreview watermarkPreview;

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
        watermarkPreview = new PrintWatermarkPreview(() => Draw());
        // 창이 다른 모니터로 가면 화면 색관리 표가 바뀝니다. 담아 둔 타일은 앞 표로 옮긴
        // 화소라 버리고 다시 그립니다. 인화 화면은 앱이 사는 동안 하나뿐입니다.
        Negaflow.Shell.Services.DisplayColorManagement.Changed += (_, _) =>
        {
            tileImages.Clear();
            Draw();
        };
    }

    /// <summary>
    /// 판에 놓일 사진의 화소 크기입니다. 아직 읽지 못했으면 3:2 로 둡니다 — macOS 도 모르는
    /// 비율을 그렇게 다룹니다.
    /// </summary>
    /// <remarks>
    /// <para>
    /// <b>원본 파일의 크기가 아니라 변형을 적용한 뒤의 크기입니다.</b> 앞 판은
    /// <c>SourceMetadata.PixelWidth/PixelHeight</c> 를 그대로 썼습니다. 그래서 가로로 스캔한
    /// 필름을 현상에서 90° 돌려 세로로 만들어도 인화는 여전히 <b>가로 칸</b>을 만들었고,
    /// 그 칸에 세로 사진을 <c>Stretch.Fill</c> 로 끼워 넣어 눌러 버렸습니다.
    /// </para>
    /// <para>
    /// 실제로 판에 쓰이는 <see cref="PrintSheetWriter"/> 는 현상한 PNG 를 열어 그 화소 크기로
    /// 배치합니다. 즉 미리보기만 다른 크기를 쓰고 있었습니다. macOS 는 같은 자리에서
    /// <c>printPackageLayoutSize(for:)</c> → <c>transformedPrintPackageSize(_:transform:)</c>
    /// 로 회전·수평보정·크롭을 반영합니다.
    /// </para>
    /// </remarks>
    internal static PrintSizeMm SourcePixelSize(LibraryFrameSnapshot frame)
    {
        if (frame.SourceMetadata is not { PixelWidth: > 0, PixelHeight: > 0 } metadata)
        {
            return new PrintSizeMm(3000, 2000);
        }
        return DevelopDisplayGeometry.TryDevelopedPixelSize(
            frame.ImageTransform,
            metadata.PixelWidth,
            metadata.PixelHeight,
            out double width,
            out double height)
            ? new PrintSizeMm(width, height)
            : new PrintSizeMm(metadata.PixelWidth, metadata.PixelHeight);
    }

    internal double PreviewScale(PrintSizeMm canvas)
    {
        double available = Math.Max(120, Math.Min(
            surface.CanvasHost.ActualWidth - 48,
            surface.CanvasHost.ActualHeight - 48));
        double longest = Math.Max(canvas.Width, canvas.Height);
        return longest > 0 ? available / longest : 1;
    }

    /// <summary>다시 그리기가 이미 예약되어 있는지입니다.</summary>
    private bool drawScheduled;

    /// <summary>그리는 동안 들어온 요청입니다. 끝난 뒤 한 번만 더 그립니다.</summary>
    private bool drawRequestedWhileDrawing;

    /// <summary>사진마다 마지막으로 청한 현상본의 긴 변입니다.</summary>
    private readonly Dictionary<string, int> requestedEdges = [];

    // 캐시 화소를 화면 색관리로 옮겨 담는 버퍼입니다. 캐시는 다른 화면도 보므로 제자리에서
    // 바꾸지 않습니다.
    private byte[]? displayScratch;

    /// <summary>
    /// 판을 다시 그립니다. 같은 프레임 안에서 여러 번 불려도 <b>한 번만</b> 그립니다.
    /// </summary>
    /// <remarks>
    /// 판은 선택·썸네일 도착·설정 변경 등 여러 길에서 다시 그려집니다. 그 길들이 서로를
    /// 부르면 초당 수십 번씩 다시 그리게 되고, 그동안 UI 스레드가 화면을 합성하지 못해
    /// 창이 검게 멈춥니다. macOS 는 SwiftUI 가 프레임당 한 번으로 묶어 주는 자리입니다 —
    /// 여기서는 그 묶음을 직접 만듭니다.
    /// </remarks>
    internal void Draw([System.Runtime.CompilerServices.CallerMemberName] string caller = "")
    {
        PreviewTrace.Write("print.ask from=" + caller);
        if (surface.PageCanvas is null)
        {
            return;
        }
        if (drawScheduled)
        {
            drawRequestedWhileDrawing = true;
            return;
        }
        drawScheduled = true;
        if (!surface.PageCanvas.DispatcherQueue.TryEnqueue(RunScheduledDraw))
        {
            RunScheduledDraw();
        }
    }

    /// <summary>
    /// 예약된 한 번을 그립니다. <b>그리는 동안 들어온 요청은 한 번으로 접어</b> 뒤에
    /// 다시 그립니다.
    /// </summary>
    /// <remarks>
    /// 앞 판은 <c>drawScheduled</c> 를 <c>DrawNow</c> <b>앞에서</b> 내렸습니다. 그래서 그리는
    /// 도중에 올라온 요청 — 판 크기 바뀜, 썸네일 도착, 설정 되먹임 — 이 모두 새 예약이 되어
    /// 묶임이 이름만 남았습니다. 이 파일이 이미 두 번 겪은 되풀이 그리기(초당 94회 · 230회)와
    /// 같은 모양이며, 판 한 번에 타일마다 <c>WriteableBitmap</c> 을 만드는 자리라 되풀이가
    /// 곧 GPU 표면 폭주입니다.
    /// </remarks>
    private void RunScheduledDraw()
    {
        try
        {
            DrawNow();
        }
        finally
        {
            drawScheduled = false;
        }
        if (!drawRequestedWhileDrawing)
        {
            return;
        }
        drawRequestedWhileDrawing = false;
        Draw();
    }

    private void DrawNow()
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
            surface.RulerCanvas.Children.Clear();
            return;
        }
        surface.NoFramePanel.Visibility = Visibility.Collapsed;
        surface.PageBorder.Visibility = Visibility.Visible;

        PrintPreferences print = workspace.Current.Print;
        var proofPaths = (print.CPrintProofProfilePath, workspace.Current.SoftProof.PrinterProfilePath);
        if (proofPaths != cachedProofPaths)
        {
            cachedProofPaths = proofPaths;
            tileImages.Clear();
        }
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
        // 워터마크 띠까지 더한 한 장으로 판을 잡습니다. 입력하지 않은 값은 비워 둡니다.
        (PrintSizeMm unitSize, PrintWatermarkFrameLayout? watermarkFrame, composition) =
            composition.PlaceUnit(sourceSize);
        if (PrintCompositionLayout.Make(unitSize, composition) is not { } layout)
        {
            surface.PageBorder.Visibility = Visibility.Collapsed;
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
        PrintWatermarkSettings? watermark = watermarkFrame is null ? null : composition.ActiveWatermark;
        PrintWatermarkReference? reference = watermark is null
            ? null
            : watermarkPreview.Reference(frame, sourceSize, watermark, composition.PresentationStyle, thumbnails());
        PrintRect photoRect = layout.ImageRect;
        if (watermarkFrame is { } frameLayout && watermark is not null)
        {
            watermarkPreview.AddBackground(surface.PageCanvas, layout.ImageRect, watermark, reference, scale);
            photoRect = frameLayout.Place(frameLayout.ImageRect, layout.ImageRect);
        }
        surface.PageCanvas.Children.Add(
            ImageTile(frame, photoRect, scale, 0, composition.PresentationStyle));
        if (watermarkFrame is { } bands && watermark is not null)
        {
            watermarkPreview.AddContent(surface.PageCanvas, layout.ImageRect, bands, watermark, reference, scale);
        }
        foreach (PrintRect hole in layout.PerforationRects)
        {
            surface.PageCanvas.Children.Add(Rect(
                hole,
                scale,
                Windows.UI.Color.FromArgb(0xFF, 0xFF, 0xFF, 0xFF),
                layout.PerforationCornerRadius * scale));
        }
        surface.PageCountText.Text = string.Empty;
        DrawPaperSurface(layout.CanvasSize, scale, print.PaperSurface);
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
                item.QuarterTurns,
                composition.PresentationStyle));
        }
        // 캡션은 <b>글자</b>를 그립니다. macOS `PrintPackageCanvasView` 도 자리 표시 상자가
        // 아니라 그 자리에 실제 글자를 놓습니다 — 회색 네모는 Windows 에만 있던 창작입니다.
        for (int slot = 0; slot < page.Items.Count; ++slot)
        {
            PrintPackageItemLayout item = page.Items[slot];
            if (item.CaptionRect is not { } caption ||
                PrintCaptionFormatter.Caption(
                    currentSources[item.SourceIndex],
                    print.CaptionMode,
                    slot + 1) is not { Length: > 0 } text)
            {
                continue;
            }
            surface.PageCanvas.Children.Add(CaptionText(
                new PrintPackageTextLayout(text, caption, print.CaptionAlignment),
                scale,
                print.SheetBackground,
                print.CaptionFontName,
                // macOS: `size: max(7, min(11, height * 0.55))`
                maximumFontSize: 11));
        }
        // 손으로 놓은 문구입니다. 판에 나갈 글자를 화면에서도 같은 자리에 같은 정렬로
        // 보여 줍니다 — macOS `PrintCustomTextOverlay` 자리입니다.
        foreach (PrintPackageTextLayout textItem in page.TextItems)
        {
            // macOS: `size: max(7, min(18, rect.height * 0.55))`
            surface.PageCanvas.Children.Add(CaptionText(
                textItem, scale, print.SheetBackground, print.CaptionFontName, 18));
        }
        foreach (PrintLineSegment segment in page.CropMarks)
        {
            surface.PageCanvas.Children.Add(Line(segment, scale, print.SheetBackground));
        }
        surface.PageCountText.Text = pages.Count > 1
            ? AppResources.FormatIntegers("printPageCountFormat", "Text", pages.Count)
            : string.Empty;
        DrawPaperSurface(page.CanvasSize, scale, print.PaperSurface);
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
            // 흰 종이는 프루프가 계산한 <b>그 인화지의 흰색</b>으로 물듭니다.
            // macOS `PrintCanvasView.paperColor` 자리입니다.
            _ => PaperWhite(),
        });
    }

    /// <summary>인화지 흰색입니다. 프루프가 물들이지 않으면 순백입니다.</summary>
    private Windows.UI.Color PaperWhite()
    {
        if (state() is { } workspace &&
            PrintPaperTint.For(workspace.Current.Print, workspace.Current.SoftProof) is { } tint)
        {
            PreviewTrace.Write(System.FormattableString.Invariant(
                $"print.paper tint=({tint.Red:F3},{tint.Green:F3},{tint.Blue:F3})"));
            // 용지 흰색은 선형 배율입니다. sRGB 로 인코딩해야 사진 속 흰색과 같은 밝기입니다.
            return Windows.UI.Color.FromArgb(
                0xFF,
                PrintSoftProofFilter.EncodeSrgbByte(tint.Red),
                PrintSoftProofFilter.EncodeSrgbByte(tint.Green),
                PrintSoftProofFilter.EncodeSrgbByte(tint.Blue));
        }
        return Windows.UI.Color.FromArgb(0xFF, 0xFF, 0xFF, 0xFF);
    }

    private void WritePageSummary(PrintSizeMm canvas, PrintCompositionSettings composition)
    {
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

    /// <summary>
    /// 손으로 놓은 문구 하나를 판 위에 얹습니다. 글자색은 판 바탕의 반대쪽이며, 내보내기가
    /// 쓰는 <see cref="PrintTextRasterizer"/> 와 같은 규칙입니다.
    /// </summary>
    private static FrameworkElement CaptionText(
        PrintPackageTextLayout item,
        double scale,
        PrintSheetBackground background,
        string fontName,
        double maximumFontSize)
    {
        double height = Math.Max(1, item.Rect.Height * scale);
        TextBlock text = new()
        {
            Text = item.Text,
            Width = Math.Max(1, item.Rect.Width * scale),
            Height = height,
            // macOS `max(7, min(maximum, height * 0.55))`
            FontSize = Math.Max(7, Math.Min(maximumFontSize, height * 0.55)),
            TextWrapping = TextWrapping.NoWrap,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
            TextAlignment = item.Alignment switch
            {
                PrintPackageCaptionAlignment.Center => TextAlignment.Center,
                PrintPackageCaptionAlignment.Trailing => TextAlignment.Right,
                _ => TextAlignment.Left,
            },
            // macOS `foregroundStyle(pageForegroundColor.opacity(0.92))` — 흰 종이는 검정,
            // 그 밖에는 흰색입니다.
            Foreground = new SolidColorBrush(background == PrintSheetBackground.White
                ? Windows.UI.Color.FromArgb(0xEB, 0x00, 0x00, 0x00)
                : Windows.UI.Color.FromArgb(0xEB, 0xFF, 0xFF, 0xFF)),
            IsHitTestVisible = false,
        };
        if (fontName.Length > 0)
        {
            text.FontFamily = new FontFamily(fontName);
        }
        Canvas.SetLeft(text, item.Rect.X * scale);
        Canvas.SetTop(text, item.Rect.Y * scale);
        return text;
    }

    /// <summary>
    /// 인화지 표면을 판 위에 덮습니다. macOS 는 사진 위·편집기 아래에 놓습니다
    /// (<c>PrintPackageCanvasView</c> 의 <c>PrintPaperSurfaceOverlay</c> 자리).
    /// </summary>
    private void DrawPaperSurface(PrintSizeMm canvas, double scale, PrintPaperSurface paper)
    {
        if (PrintPaperSurfaceOverlay.Make(
                paper,
                canvas.Width * scale,
                canvas.Height * scale) is not { } overlay)
        {
            return;
        }
        Canvas.SetLeft(overlay, 0);
        Canvas.SetTop(overlay, 0);
        surface.PageCanvas.Children.Add(overlay);
    }

    private static byte[]? ReadProofProfile(string? path)
    {
        if (path is null)
        {
            return null;
        }
        try
        {
            return File.ReadAllBytes(path);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException)
        {
            return null;
        }
    }

    private static void ApplyTileColor(
        byte[] pixels,
        int width,
        int height,
        PrintPresentationStyle presentation,
        Negaflow.Interop.SoftProofSettings? proof,
        string? profilePath,
        bool warnGamut)
    {
        PrintPresentationFilter.Apply(pixels, presentation);
        byte[]? icc = ReadProofProfile(profilePath);
        // 색역 판정에는 프루프 왕복 전의 색을 씁니다.
        byte[]? judged = warnGamut && icc is not null ? (byte[])pixels.Clone() : null;
        if (icc is not null)
        {
            bool applied = Negaflow.Interop.NativeGamutMask.Proof(pixels, width, height, icc);
            PreviewTrace.Write(System.FormattableString.Invariant($"print.proof applied={applied}"));
        }
        PrintSoftProofFilter.Apply(pixels, proof);
        if (judged is not null && icc is not null)
        {
            MarkOutOfGamut(pixels, judged, width, height, icc);
        }
        Negaflow.Shell.Services.DisplayColorManagement.ApplyInPlace(pixels, width, height);
    }

    private static void MarkOutOfGamut(
        Span<byte> pixels, ReadOnlySpan<byte> judged, int width, int height, ReadOnlySpan<byte> icc)
    {
        long? marked = Negaflow.Interop.NativeGamutMask.Mark(pixels, judged, width, height, icc);
        int firstRow = Negaflow.Interop.NativeGamutMask.FirstMarkedRow;
        int lastRow = Negaflow.Interop.NativeGamutMask.LastMarkedRow;
        int bufferPixels = pixels.Length / 4;
        PreviewTrace.Write(System.FormattableString.Invariant(
            $"print.gamut marked={marked} of {(long)width * height} size={width}x{height} buffer={bufferPixels} rows={firstRow}..{lastRow}"));
    }
    private FrameworkElement ImageTile(
        LibraryFrameSnapshot frame,
        PrintRect rect,
        double scale,
        int quarterTurns,
        PrintPresentationStyle presentation)
    {
        // 인화 화면의 프루프입니다. macOS `displaySoftProofSettings(for:in: .print)` 이
        // 전역이 아니라 C-print 설정을 쓰는 자리와 같습니다.
        ShellPreferences? preferences = state()?.Current;
        var destination = preferences is not null
            ? PrintSoftProofFilter.Destination(preferences.Print, preferences.SoftProof)
            : null;
        Negaflow.Interop.SoftProofSettings? proof = preferences is not null && destination is { PaperSimulation: true }
            ? PrintSoftProofFilter.Settings(preferences.Print, preferences.SoftProof)
            : null;
        string? profilePath = destination?.Path;
        bool warnGamut = profilePath is not null && preferences?.SoftProof.GamutWarningEnabled == true;
        // macOS `packageImage(_:)` — 홀수 번 돌면 그리는 상자의 가로세로가 바뀝니다.
        // `ImageRect` 는 이미 <b>돌린 뒤</b>의 자리이므로, 돌리기 전 상자는 가로세로를 맞바꾼
        // 크기여야 합니다. 그러지 않으면 세로 사진이 가로 상자에 눌려 들어갑니다.
        bool swapsAxes = quarterTurns % 2 != 0;
        double destinationWidth = Math.Max(1, rect.Width * scale);
        double destinationHeight = Math.Max(1, rect.Height * scale);
        double boxWidth = swapsAxes ? destinationHeight : destinationWidth;
        double boxHeight = swapsAxes ? destinationWidth : destinationHeight;
        Image image = new()
        {
            Width = boxWidth,
            Height = boxHeight,
            // macOS `.aspectRatio(contentMode: .fit)`. `ImageRect` 는 원본 비율을 지켜 만든
            // 자리라 여백이 남지 않으며, 아직 썸네일뿐인 칸에서도 비율이 망가지지 않습니다.
            Stretch = Stretch.Uniform,
        };
        ThumbnailService? cache = thumbnails();
        // macOS PrintSingleImagePageView: developedImage ?? rawPreviewImage ?? thumbnailImage.
        // 현상본이 있으면 그것을 쓰고, 칸이 더 크면 표시 크기로 올립니다.
        ThumbnailService.DevelopedPreview developed = default;
        bool hasDeveloped = cache?.TryGetPrintDeveloped(frame, out developed) == true;
        // 프루프가 바뀌면 풀어 둔 그림도 달라집니다 — 열쇠에 함께 넣습니다.
        (string, PrintPresentationStyle, bool, string) key = (
            frame.Id,
            presentation,
            hasDeveloped,
            (PrintSoftProofFilter.Transforms(proof)
                ? System.FormattableString.Invariant(
                    $"{proof!.PaperWhite.Red:F3}/{proof.PaperWhite.Green:F3}/{proof.PaperWhite.Blue:F3}/{proof.BlackInk.Red:F3}")
                : string.Empty) + (warnGamut ? "|gamut" : string.Empty) +
            (profilePath ?? string.Empty));
        if (tileImages.TryGetValue(key, out ImageSource? cached) && cached is not null)
        {
            image.Source = cached;
        }
        else if (hasDeveloped)
        {
            if (PreviewTrace.IsEnabled)
            {
                PreviewTrace.Write(
                    $"shown.print {frame.Id} {developed.Width}x{developed.Height} " +
                    $"settled={developed.Settled} style={presentation} " +
                    Negaflow.Shell.Develop.PreviewPixelStats.Describe(
                        developed.Pixels, developed.Width, developed.Height));
            }
            // 현상본에는 용지·잉크가 이미 적용됐습니다. ICC 왕복과 색역 경고는 여기서 그립니다.
            WriteableBitmap bitmap = BgraBitmap(developed, presentation, profilePath, warnGamut);
            tileImages.Store(key, bitmap);
            image.Source = bitmap;
        }
        else if (cache?.TryGet(frame.Id) is { } jpeg)
        {
            PreviewTrace.Write(
                $"shown.print {frame.Id} THUMBNAIL-FALLBACK jpeg={jpeg.Length} style={presentation}");
            var plainKey = (frame.Id, PrintPresentationStyle.Standard, false, string.Empty);
            if (!tileImages.TryGetValue(plainKey, out ImageSource? decoded))
            {
                decoded = LibraryWorkspaceView.DecodeThumbnail(jpeg);
                if (decoded is not null) { tileImages.Store(plainKey, decoded); }
            }
            image.Source = decoded;
            // 시아노타입 · 유리건판 · 젤라틴 실버는 **화면에서도** 보여야 합니다. 썸네일은
            // JPEG 이라 화소를 바로 만질 수 없으므로 풀어서 다시 겁니다 — 내보내기가 지나는
            // `PrintPresentationFilter` 와 같은 계산입니다.
            if (PrintPresentationFilter.Transforms(presentation) || profilePath is not null ||
                PrintSoftProofFilter.Transforms(proof))
            {
                long revision = tileImages.Revision;
                _ = ApplyPresentationAsync(jpeg, presentation, proof, profilePath, warnGamut, source =>
                {
                    if (tileImages.TryStore(revision, key, source)) { image.Source = source; }
                });
            }
            else if (decoded is not null)
            {
                tileImages.Store(key, decoded);
            }
        }
        PreviewTrace.Write(System.FormattableString.Invariant(
            $"print.tile {frame.Id} box={boxWidth:F0}x{boxHeight:F0} developed={hasDeveloped} source={(image.Source is null ? "NONE" : image.Source.GetType().Name)} cached={tileImages.Count}"));
        RequestDevelopedIfNeeded(cache, frame, rect, scale);
        Border host = new()
        {
            Width = boxWidth,
            Height = boxHeight,
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0x33, 0x80, 0x80, 0x80)),
            Child = image,
        };
        if (quarterTurns % 4 != 0)
        {
            host.RenderTransformOrigin = new Windows.Foundation.Point(0.5, 0.5);
            // macOS `.rotationEffect(.degrees(-90 * turns))` — 반시계입니다. XAML 은 양수가
            // 시계 방향이므로 부호를 뒤집습니다.
            host.RenderTransform = new RotateTransform { Angle = -90 * (quarterTurns % 4) };
        }
        // macOS `.position(x: destination.midX, y: destination.midY)` — 돌린 결과의 가운데를
        // 칸 가운데에 놓습니다. 왼쪽·위를 그대로 두면 돌아간 만큼 칸 밖으로 밀려납니다.
        Canvas.SetLeft(host, ((rect.X + (rect.Width / 2)) * scale) - (boxWidth / 2));
        Canvas.SetTop(host, ((rect.Y + (rect.Height / 2)) * scale) - (boxHeight / 2));
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
        // macOS `printPackageDisplayImage` — developed ∪ packagePreview ∪ thumbnail ∪ raw.
        // 현상본이 없다고 current=0 으로 두면 콘택트 칸(360보다 작음)마다 develop_preview 가
        // 돕니다. 썸네일이 있으면 긴 변 360 으로 칩니다(`ThumbnailService.MaximumDimension`).
        int? developedEdge = cache.TryGetPrintDeveloped(frame, out ThumbnailService.DevelopedPreview developed)
            ? (int)PrintPreviewResolution.PixelDimension(developed.Width, developed.Height)
            : null;
        int? thumbnailEdge = cache.TryGet(frame.Id) is not null
            ? ThumbnailService.MaximumDimension
            : null;
        int current = PrintPreviewResolution.BestLongEdge(developedEdge, null, thumbnailEdge, null) ?? 0;
        if (!PrintPreviewResolution.NeedsUpgrade(current, displayPixels))
        {
            return;
        }

        double target = PrintPreviewResolution.RenderDimension(displayPixels);
        if (target <= 0)
        {
            return;
        }
        // 같은 크기를 두 번 청하지 않습니다.
        //
        // 청한 크기에 못 닿는 사진이면 `NeedsUpgrade` 가 계속 참이라, 판을 그릴 때마다 다시
        // 청하고 그 결과가 다시 판을 그리게 합니다 — 실측 초당 94회가 돌아 창이 검게
        // 멈췄습니다. 이미 청한 크기 이하이면 물러납니다.
        int edge = (int)target;
        if (requestedEdges.TryGetValue(frame.Id, out int already) && edge <= already)
        {
            return;
        }
        requestedEdges[frame.Id] = edge;
        cache.RequestDeveloped(frame, edge);
    }

    private WriteableBitmap BgraBitmap(
        ThumbnailService.DevelopedPreview preview,
        PrintPresentationStyle presentation,
        string? profilePath,
        bool warnGamut)
    {
        WriteableBitmap bitmap = new(preview.Width, preview.Height);
        int written = preview.Width * preview.Height * 4;
        if (PrintPresentationFilter.Transforms(presentation) || profilePath is not null)
        {
            // 캐시의 화소는 다른 화면도 함께 봅니다. 그 자리에서 바꾸면 현상 미리보기까지
            // 파랗게 물들므로 여기서 한 벌 떠서 바꿉니다.
            byte[] tinted = new byte[written];
            Array.Copy(preview.Pixels, tinted, written);
            ApplyTileColor(tinted, preview.Width, preview.Height, presentation, null, profilePath, warnGamut);
            using (Stream buffer = bitmap.PixelBuffer.AsStream())
            {
                buffer.Write(tinted, 0, written);
            }
            bitmap.Invalidate();
            return bitmap;
        }
        byte[] shown = Negaflow.Shell.Services.DisplayColorManagement.ForDisplay(
            preview.Pixels, preview.Width, preview.Height, ref displayScratch);
        using (Stream buffer = bitmap.PixelBuffer.AsStream())
        {
            buffer.Write(shown, 0, written);
        }
        bitmap.Invalidate();
        return bitmap;
    }

    /// <summary>
    /// 썸네일 JPEG 을 풀어 공정 색을 입힌 뒤 다시 겁니다. 화면이 먼저 원본을 보여 주고
    /// 곧 바뀌는 것은 macOS 가 <c>developedImage ?? thumbnailImage</c> 로 채우는 것과 같은
    /// 순서입니다.
    /// </summary>
    private static async Task ApplyPresentationAsync(
        byte[] jpeg,
        PrintPresentationStyle presentation,
        Negaflow.Interop.SoftProofSettings? proof,
        string? profilePath,
        bool warnGamut,
        Action<ImageSource> keep)
    {
        try
        {
            using InMemoryRandomAccessStream stream = new();
            await stream.WriteAsync(jpeg.AsBuffer());
            stream.Seek(0);
            BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);
            PixelDataProvider provider = await decoder.GetPixelDataAsync(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Ignore,
                new BitmapTransform(),
                ExifOrientationMode.IgnoreExifOrientation,
                ColorManagementMode.DoNotColorManage);
            byte[] pixels = provider.DetachPixelData();
            ApplyTileColor(pixels, (int)decoder.PixelWidth, (int)decoder.PixelHeight,
                presentation, proof, profilePath, warnGamut);
            WriteableBitmap bitmap = new((int)decoder.PixelWidth, (int)decoder.PixelHeight);
            using (Stream buffer = bitmap.PixelBuffer.AsStream())
            {
                buffer.Write(pixels, 0, Math.Min(pixels.Length, (int)bitmap.PixelBuffer.Capacity));
            }
            bitmap.Invalidate();
            keep(bitmap);
        }
        catch (Exception error) when (error is IOException or ArgumentException or
            NotSupportedException or System.Runtime.InteropServices.COMException)
        {
            // 썸네일을 못 풀면 원본 그대로 둡니다 — 판이 비는 것보다 낫습니다.
        }
    }

    /// <summary>
    /// 풀어 둔 그림을 버립니다. 새 썸네일이나 현상본이 도착했을 때 부릅니다 — 그때만
    /// 화면에 걸 그림이 실제로 달라집니다.
    /// </summary>
    /// <remarks>
    /// <b>청한 크기는 지웁니다.</b> 청한 크기까지 못 가는 사진이면 <c>NeedsUpgrade</c> 가
    /// 계속 참이라, 도착할 때마다 지우면 청하기 → 도착 → 청하기 가 끝없이 돕니다(실측 초당
    /// 230회). 크기 판정은 레시피가 바뀔 때만 다시 합니다.
    /// </remarks>
    internal void InvalidateTiles()
    {
        tileImages.Clear();
        // 새 썸네일이면 워터마크의 블러·히스토그램 참조도 바뀝니다.
        watermarkPreview.Invalidate();
    }

    /// <summary>
    /// 현상 설정이나 프루프가 바뀌었습니다. 풀어 둔 그림도, 어느 크기까지 청했는지도 모두
    /// 버립니다 — 같은 크기라도 <b>다른 그림</b>을 새로 받아야 합니다.
    /// </summary>
    internal void InvalidateForRecipeChange()
    {
        tileImages.Clear();
        requestedEdges.Clear();
    }
}
