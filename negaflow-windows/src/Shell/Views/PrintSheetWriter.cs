using Microsoft.UI.Xaml.Media.Imaging;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Print;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace Negaflow.Shell.Views;

public enum PrintSheetWriteStatus
{
    Written,
    NoSources,
    LayoutRefused,
    DevelopFailed,
    WriteFailed,
}

public readonly record struct PrintSheetWriteResult(
    PrintSheetWriteStatus Status,
    IReadOnlyList<string> Paths)
{
    public bool IsSuccess => Status == PrintSheetWriteStatus.Written;
}

/// <summary>
/// 인화 판을 파일로 씁니다.
/// </summary>
/// <remarks>
/// **사진은 현상 엔진이 냅니다.** 여기서 하는 일은 그 결과를 <see cref="PrintCompositionLayout"/>
/// 이 정한 자리에 놓는 것뿐입니다 — 인화가 색을 따로 만들면 현상 화면에서 본 것과 다른 사진이
/// 인화됩니다. 미리보기와 이 파일이 같은 layout 을 쓰므로 여백과 배치도 같습니다.
/// </remarks>
public static class PrintSheetWriter
{
    /// <summary>
    /// 판을 만들어 폴더에 씁니다. 여러 판이면 <c>-1</c>, <c>-2</c> 를 붙입니다.
    /// </summary>
    public static async Task<PrintSheetWriteResult> WriteAsync(
        IReadOnlyList<LibraryFrameSnapshot> sources,
        PrintPreferences print,
        string destinationFolder,
        string baseName,
        Microsoft.UI.Xaml.Controls.Panel? textHost = null,
        DevelopExportFormat format = DevelopExportFormat.Png16,
        double jpegQuality = 1.0)
    {
        ArgumentNullException.ThrowIfNull(sources);
        ArgumentNullException.ThrowIfNull(print);
        ArgumentException.ThrowIfNullOrEmpty(destinationFolder);
        if (sources.Count == 0)
        {
            return new PrintSheetWriteResult(PrintSheetWriteStatus.NoSources, []);
        }

        // 현상 결과를 한 번씩만 만듭니다. 같은 사진이 판에 여러 번 올라가도 현상은 한 번입니다.
        string scratch = Path.Combine(
            Path.GetTempPath(),
            "negaflow-print",
            Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(scratch);
        try
        {
            // 현상은 **워커 스레드**에서 합니다. UI 스레드는 STA 라 네이티브 디코더가
            // `com_apartment_mismatch` 로 거절합니다 - 인화뷰 내보내기가 늘 실패하던
            // 원인입니다. 겸사겸사 판을 만드는 동안 화면도 멈추지 않습니다.
            //
            // 동시에 도는 장 수는 현상 배치와 같은 둘입니다
            // (`DevelopExportCoordinator.MaximumConcurrentExports`, macOS
            // `startExportBatch(maximumConcurrent: 2)`). 더 늘리면 한 장이 수백 MB 라
            // 메모리만 밀립니다.
            string[] developedPaths = new string[sources.Count];
            bool developFailed = false;
            // 같은 사진이 판에 두 번 올라갈 수 있으므로 자리 번호로 돕니다 - 사진 자체로
            // 찾으면 같은 것 둘이 한 자리를 덮어씁니다.
            int[] order = [.. Enumerable.Range(0, sources.Count)];
            await ExportBatchScheduler.RunAsync(
                order,
                DevelopExportCoordinator.MaximumConcurrentExports,
                async index =>
                {
                    if (developFailed)
                    {
                        return;
                    }
                    LibraryFrameSnapshot source = sources[index];
                    string path = Path.Combine(scratch, $"{index}.tif");
                    if (await Task.Run(() => Develop(source, path)).ConfigureAwait(true))
                    {
                        developedPaths[index] = path;
                        return;
                    }
                    developFailed = true;
                }).ConfigureAwait(true);
            if (developFailed || developedPaths.Any(string.IsNullOrEmpty))
            {
                return new PrintSheetWriteResult(PrintSheetWriteStatus.DevelopFailed, []);
            }
            List<string> developed = [.. developedPaths];

            PrintSizeMm[] sizes = new PrintSizeMm[developed.Count];
            for (int index = 0; index < developed.Count; ++index)
            {
                if (await PixelSizeAsync(developed[index]) is not { } size)
                {
                    return new PrintSheetWriteResult(PrintSheetWriteStatus.DevelopFailed, []);
                }
                sizes[index] = size;
            }

            PrintCompositionSettings composition = print.Composition(
                sizes[0].Height > 0 ? sizes[0].Width / sizes[0].Height : null);
            List<string> written = [];
            if (PrintPreferences.PackageModeFor(print.LayoutMode) is not null)
            {
                if (PrintPackageLayout.Make(sizes, composition, print.Package())
                    is not { Count: > 0 } pages)
                {
                    return new PrintSheetWriteResult(PrintSheetWriteStatus.LayoutRefused, []);
                }
                foreach (PrintPackagePageLayout page in pages)
                {
                    string path = PagePath(
                        destinationFolder, baseName, page.PageIndex, pages.Count, format);
                    if (!await WritePageAsync(
                            path,
                            page,
                            composition,
                            developed,
                            sources,
                            print.CaptionMode,
                            print.CaptionAlignment,
                            textHost,
                            format,
                            jpegQuality))
                    {
                        return new PrintSheetWriteResult(PrintSheetWriteStatus.WriteFailed, written);
                    }
                    written.Add(path);
                }
                return new PrintSheetWriteResult(PrintSheetWriteStatus.Written, written);
            }

            // 낱장 모드는 사진마다 한 판입니다.
            for (int index = 0; index < developed.Count; ++index)
            {
                PrintCompositionSettings pageSettings = composition with
                {
                    PhotoAspectRatio = sizes[index].Height > 0
                        ? sizes[index].Width / sizes[index].Height
                        : null,
                };
                if (PrintCompositionLayout.Make(sizes[index], pageSettings) is not { } layout)
                {
                    return new PrintSheetWriteResult(PrintSheetWriteStatus.LayoutRefused, []);
                }
                string path = PagePath(
                    destinationFolder, baseName, index, developed.Count, format);
                if (!await WriteSingleAsync(
                        path, layout, pageSettings, developed[index], format, jpegQuality))
                {
                    return new PrintSheetWriteResult(PrintSheetWriteStatus.WriteFailed, written);
                }
                written.Add(path);
            }
            return new PrintSheetWriteResult(PrintSheetWriteStatus.Written, written);
        }
        finally
        {
            try
            {
                Directory.Delete(scratch, recursive: true);
            }
            catch (Exception exception) when (
                exception is IOException or UnauthorizedAccessException)
            {
                // 임시 폴더를 못 지운 것은 결과에 영향을 주지 않습니다.
            }
        }
    }

    private static string PagePath(
        string folder,
        string baseName,
        int index,
        int count,
        DevelopExportFormat format)
    {
        string extension = PrintSheetEncoder.ExtensionFor(format);
        // 이미 있는 파일이면 빈 이름을 찾습니다. 엔진은 덮지 않으므로(`destination_exists`),
        // 같은 인화 시트를 두 번째로 내보내면 언제나 실패했습니다.
        return Negaflow.Shell.Develop.ExportBatchCoordinator.UniquePath(Path.Combine(
            folder,
            count > 1 ? $"{baseName}-{index + 1}{extension}" : $"{baseName}{extension}"));
    }

    /// <summary>
    /// 현상 화면과 <b>같은 요청</b>으로 사진을 냅니다. 인화 전용 경로를 따로 만들면 두 화면의
    /// 색이 갈립니다.
    /// </summary>
    private static bool Develop(LibraryFrameSnapshot frame, string destination)
    {
        // 중간 파일은 **압축 없는 16-bit TIFF** 입니다. 판에 얹으려고 한 번 쓰고 한 번
        // 읽을 뿐인데 16-bit PNG 는 deflate 로 굽느라 쓰기도 읽기도 몇 배 느립니다
        // (실측 1장 기준 8.3s -> 아래 측정 참고). 화질은 둘 다 무손실로 같습니다.
        ExportSettings settings = new()
        {
            Format = DevelopExportFormat.Tiff16,
            TiffCompression = DevelopTiffCompression.None,
        };
        DevelopRequestResult built = DevelopRequestFactory.Create(
            frame,
            destination,
            settings.Format,
            settings.ToEncodingOptions());
        if (built.Request is not { } request)
        {
            PreviewTrace.Write($"print develop: no request refusal={built.Refusal}");
            return false;
        }
        DevelopExportResult result = new NativeDevelopExporterAdapter().Run(request);
        if (!result.Succeeded)
        {
            PreviewTrace.Write(
                $"print develop: run failed stage={result.FailedStage} " +
                $"name={result.FailureName} native=0x{result.NativeErrorCode:X}");
        }
        return result.Succeeded;
    }

    private static async Task<PrintSizeMm?> PixelSizeAsync(string path)
    {
        using IRandomAccessStream stream = await PrintSheetFile.OpenAsync(path, FileAccess.Read);
        BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);
        return decoder.PixelWidth > 0 && decoder.PixelHeight > 0
            ? new PrintSizeMm(decoder.PixelWidth, decoder.PixelHeight)
            : null;
    }

    private static async Task<bool> WriteSingleAsync(
        string destination,
        PrintCompositionLayout layout,
        PrintCompositionSettings composition,
        string developedPath,
        DevelopExportFormat format,
        double jpegQuality)
    {
        int width = (int)layout.CanvasSize.Width;
        int height = (int)layout.CanvasSize.Height;
        byte[] page = PrintPageCanvas.NewPage(width, height, composition.SheetBackground);

        if (layout.FilmRect is { } film)
        {
            // 현상된 컬러 네거티브의 마스크가 남은 비노광 가장자리입니다.
            PrintPageCanvas.Fill(page, width, height, film, 0x0E, 0x2B, 0x70);
        }
        if (!await PrintPageCanvas.BlitAsync(
                page, width, height, developedPath, layout.ImageRect, 0,
                composition.PresentationStyle))
        {
            return false;
        }
        foreach (PrintRect hole in layout.PerforationRects)
        {
            PrintPageCanvas.Fill(page, width, height, hole, 0xFF, 0xFF, 0xFF);
        }
        return await PrintSheetEncoder.EncodeAsync(
            destination, page, width, height, composition.Dpi, format, jpegQuality);
    }

    private static async Task<bool> WritePageAsync(
        string destination,
        PrintPackagePageLayout layout,
        PrintCompositionSettings composition,
        IReadOnlyList<string> developed,
        IReadOnlyList<LibraryFrameSnapshot> sources,
        PrintPackageCaptionMode captionMode,
        PrintPackageCaptionAlignment captionAlignment,
        Microsoft.UI.Xaml.Controls.Panel? textHost,
        DevelopExportFormat format,
        double jpegQuality)
    {
        int width = (int)layout.CanvasSize.Width;
        int height = (int)layout.CanvasSize.Height;
        byte[] page = PrintPageCanvas.NewPage(width, height, composition.SheetBackground);
        foreach (PrintPackageItemLayout item in layout.Items)
        {
            if (!await PrintPageCanvas.BlitAsync(
                    page,
                    width,
                    height,
                    developed[item.SourceIndex],
                    item.ImageRect,
                    item.QuarterTurns,
                    composition.PresentationStyle))
            {
                return false;
            }
        }
        bool light = composition.SheetBackground != PrintSheetBackground.White;
        // 캡션은 사진 위, 재단선 아래입니다.
        if (captionMode != PrintPackageCaptionMode.None && textHost is not null)
        {
            for (int slot = 0; slot < layout.Items.Count; ++slot)
            {
                PrintPackageItemLayout item = layout.Items[slot];
                if (item.CaptionRect is not { } caption ||
                    PrintCaptionFormatter.Caption(
                        sources[item.SourceIndex],
                        captionMode,
                        slot + 1) is not { Length: > 0 } text)
                {
                    continue;
                }
                await PrintPageCanvas.DrawCaptionAsync(page, width, height, textHost, text, caption,
                    captionAlignment, light);
            }
        }
        // 손으로 놓은 문구입니다. macOS 렌더러도 사진 위·재단선 아래에 얹습니다
        // (`for textItem in layout.textItems`).
        if (textHost is not null)
        {
            foreach (PrintPackageTextLayout textItem in layout.TextItems)
            {
                await PrintPageCanvas.DrawCaptionAsync(
                    page, width, height, textHost, textItem.Text, textItem.Rect,
                    textItem.Alignment, light);
            }
        }
        // 재단선은 사진 위에 얹습니다 — 칸 모서리를 가리키는 선이므로 사진 아래로 들어가면
        // 보이지 않습니다.
        foreach (PrintLineSegment segment in layout.CropMarks)
        {
            PrintPageCanvas.DrawLine(page, width, height, segment, light);
        }
        return await PrintSheetEncoder.EncodeAsync(
            destination, page, width, height, composition.Dpi, format, jpegQuality);
    }

}
