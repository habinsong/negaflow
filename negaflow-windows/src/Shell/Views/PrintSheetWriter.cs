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
        Microsoft.UI.Xaml.Controls.Panel? textHost = null)
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
            List<string> developed = new(sources.Count);
            for (int index = 0; index < sources.Count; ++index)
            {
                string path = Path.Combine(scratch, $"{index}.png");
                if (!Develop(sources[index], path))
                {
                    return new PrintSheetWriteResult(PrintSheetWriteStatus.DevelopFailed, []);
                }
                developed.Add(path);
            }

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
                    string path = PagePath(destinationFolder, baseName, page.PageIndex, pages.Count);
                    if (!await WritePageAsync(
                            path,
                            page,
                            composition,
                            developed,
                            sources,
                            print.CaptionMode,
                            print.CaptionAlignment,
                            textHost))
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
                string path = PagePath(destinationFolder, baseName, index, developed.Count);
                if (!await WriteSingleAsync(path, layout, pageSettings, developed[index]))
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

    private static string PagePath(string folder, string baseName, int index, int count) =>
        Path.Combine(folder, count > 1 ? $"{baseName}-{index + 1}.png" : $"{baseName}.png");

    /// <summary>
    /// 현상 화면과 <b>같은 요청</b>으로 사진을 냅니다. 인화 전용 경로를 따로 만들면 두 화면의
    /// 색이 갈립니다.
    /// </summary>
    private static bool Develop(LibraryFrameSnapshot frame, string destination)
    {
        ExportSettings settings = new() { Format = DevelopExportFormat.Png16 };
        DevelopRequestResult built = DevelopRequestFactory.Create(
            frame,
            destination,
            settings.Format,
            settings.ToEncodingOptions());
        return built.Request is { } request &&
            new NativeDevelopExporterAdapter().Run(request).Succeeded;
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
        string developedPath)
    {
        int width = (int)layout.CanvasSize.Width;
        int height = (int)layout.CanvasSize.Height;
        byte[] page = PrintPageCanvas.NewPage(width, height, composition.SheetBackground);

        if (layout.FilmRect is { } film)
        {
            // 현상된 컬러 네거티브의 마스크가 남은 비노광 가장자리입니다.
            PrintPageCanvas.Fill(page, width, height, film, 0x0E, 0x2B, 0x70);
        }
        if (!await PrintPageCanvas.BlitAsync(page, width, height, developedPath, layout.ImageRect, 0))
        {
            return false;
        }
        foreach (PrintRect hole in layout.PerforationRects)
        {
            PrintPageCanvas.Fill(page, width, height, hole, 0xFF, 0xFF, 0xFF);
        }
        return await PrintSheetEncoder.EncodeAsync(destination, page, width, height, composition.Dpi);
    }

    private static async Task<bool> WritePageAsync(
        string destination,
        PrintPackagePageLayout layout,
        PrintCompositionSettings composition,
        IReadOnlyList<string> developed,
        IReadOnlyList<LibraryFrameSnapshot> sources,
        PrintPackageCaptionMode captionMode,
        PrintPackageCaptionAlignment captionAlignment,
        Microsoft.UI.Xaml.Controls.Panel? textHost)
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
                    item.QuarterTurns))
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
        // 재단선은 사진 위에 얹습니다 — 칸 모서리를 가리키는 선이므로 사진 아래로 들어가면
        // 보이지 않습니다.
        foreach (PrintLineSegment segment in layout.CropMarks)
        {
            PrintPageCanvas.DrawLine(page, width, height, segment, light);
        }
        return await PrintSheetEncoder.EncodeAsync(destination, page, width, height, composition.Dpi);
    }

}
