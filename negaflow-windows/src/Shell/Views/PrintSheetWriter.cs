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
        string baseName)
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
                    if (!await WritePageAsync(path, page, composition, developed))
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
        using IRandomAccessStream stream = await OpenAsync(path, FileAccess.Read);
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
        byte[] page = NewPage(width, height, composition.SheetBackground);

        if (layout.FilmRect is { } film)
        {
            // 현상된 컬러 네거티브의 마스크가 남은 비노광 가장자리입니다.
            Fill(page, width, height, film, 0x0E, 0x2B, 0x70);
        }
        if (!await BlitAsync(page, width, height, developedPath, layout.ImageRect, 0))
        {
            return false;
        }
        foreach (PrintRect hole in layout.PerforationRects)
        {
            Fill(page, width, height, hole, 0xFF, 0xFF, 0xFF);
        }
        return await EncodeAsync(destination, page, width, height, composition.Dpi);
    }

    private static async Task<bool> WritePageAsync(
        string destination,
        PrintPackagePageLayout layout,
        PrintCompositionSettings composition,
        IReadOnlyList<string> developed)
    {
        int width = (int)layout.CanvasSize.Width;
        int height = (int)layout.CanvasSize.Height;
        byte[] page = NewPage(width, height, composition.SheetBackground);
        foreach (PrintPackageItemLayout item in layout.Items)
        {
            if (!await BlitAsync(
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
        // 재단선은 사진 위에 얹습니다 — 칸 모서리를 가리키는 선이므로 사진 아래로 들어가면
        // 보이지 않습니다.
        bool light = composition.SheetBackground != PrintSheetBackground.White;
        foreach (PrintLineSegment segment in layout.CropMarks)
        {
            DrawLine(page, width, height, segment, light);
        }
        return await EncodeAsync(destination, page, width, height, composition.Dpi);
    }

    /// <summary>
    /// 재단선 한 줄입니다. 가로나 세로로만 놓이므로 기울어진 선을 그릴 일이 없습니다 — macOS 도
    /// 칸 모서리에서 수평·수직으로만 뻗습니다.
    /// </summary>
    private static void DrawLine(
        byte[] page,
        int width,
        int height,
        PrintLineSegment segment,
        bool light)
    {
        byte level = light ? (byte)0xFF : (byte)0x00;
        int x0 = (int)Math.Round(Math.Min(segment.StartX, segment.EndX));
        int x1 = (int)Math.Round(Math.Max(segment.StartX, segment.EndX));
        int y0 = (int)Math.Round(Math.Min(segment.StartY, segment.EndY));
        int y1 = (int)Math.Round(Math.Max(segment.StartY, segment.EndY));
        // 한 화소 선은 눈에 잘 띄지 않습니다. macOS 와 같이 얇게 두되 최소 한 화소는 채웁니다.
        Fill(
            page,
            width,
            height,
            new PrintRect(x0, y0, Math.Max(1, x1 - x0), Math.Max(1, y1 - y0)),
            level,
            level,
            level);
    }

    /// <summary>BGRA8 한 장입니다. 종이 색으로 채워 시작합니다.</summary>
    private static byte[] NewPage(int width, int height, PrintSheetBackground background)
    {
        byte level = background switch
        {
            PrintSheetBackground.Black => 0x00,
            PrintSheetBackground.Gray => 0x80,
            _ => 0xFF,
        };
        byte[] page = new byte[checked(width * height * 4)];
        for (int index = 0; index < page.Length; index += 4)
        {
            page[index] = level;
            page[index + 1] = level;
            page[index + 2] = level;
            page[index + 3] = 0xFF;
        }
        return page;
    }

    private static void Fill(
        byte[] page,
        int width,
        int height,
        PrintRect rect,
        byte blue,
        byte green,
        byte red)
    {
        int left = Math.Max(0, (int)Math.Round(rect.X));
        int top = Math.Max(0, (int)Math.Round(rect.Y));
        int right = Math.Min(width, (int)Math.Round(rect.MaxX));
        int bottom = Math.Min(height, (int)Math.Round(rect.MaxY));
        for (int y = top; y < bottom; ++y)
        {
            int row = y * width * 4;
            for (int x = left; x < right; ++x)
            {
                int at = row + (x * 4);
                page[at] = blue;
                page[at + 1] = green;
                page[at + 2] = red;
                page[at + 3] = 0xFF;
            }
        }
    }

    /// <summary>
    /// 현상된 사진을 그 자리에 놓습니다. 크기 맞추기는 <b>WIC 가</b> 합니다 — 직접 재표본화하면
    /// 내보내기의 긴 변 축소와 다른 결과가 나옵니다.
    /// </summary>
    private static async Task<bool> BlitAsync(
        byte[] page,
        int pageWidth,
        int pageHeight,
        string sourcePath,
        PrintRect rect,
        int quarterTurns)
    {
        int width = Math.Max(1, (int)Math.Round(rect.Width));
        int height = Math.Max(1, (int)Math.Round(rect.Height));
        // 돌려 놓을 자리라면 원본을 돌린 뒤의 크기로 뽑아야 합니다.
        bool turned = quarterTurns % 2 != 0;
        BitmapTransform transform = new()
        {
            ScaledWidth = (uint)(turned ? height : width),
            ScaledHeight = (uint)(turned ? width : height),
            InterpolationMode = BitmapInterpolationMode.Fant,
            Rotation = (quarterTurns % 4) switch
            {
                1 => BitmapRotation.Clockwise90Degrees,
                2 => BitmapRotation.Clockwise180Degrees,
                3 => BitmapRotation.Clockwise270Degrees,
                _ => BitmapRotation.None,
            },
        };

        using IRandomAccessStream stream = await OpenAsync(sourcePath, FileAccess.Read);
        BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);
        PixelDataProvider pixels = await decoder.GetPixelDataAsync(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Ignore,
            transform,
            ExifOrientationMode.IgnoreExifOrientation,
            ColorManagementMode.DoNotColorManage);
        byte[] tile = pixels.DetachPixelData();
        if (tile.Length < width * height * 4)
        {
            return false;
        }

        int left = (int)Math.Round(rect.X);
        int top = (int)Math.Round(rect.Y);
        for (int y = 0; y < height; ++y)
        {
            int pageY = top + y;
            if (pageY < 0 || pageY >= pageHeight)
            {
                continue;
            }
            int sourceRow = y * width * 4;
            int pageRow = pageY * pageWidth * 4;
            for (int x = 0; x < width; ++x)
            {
                int pageX = left + x;
                if (pageX < 0 || pageX >= pageWidth)
                {
                    continue;
                }
                int from = sourceRow + (x * 4);
                int to = pageRow + (pageX * 4);
                page[to] = tile[from];
                page[to + 1] = tile[from + 1];
                page[to + 2] = tile[from + 2];
                page[to + 3] = 0xFF;
            }
        }
        return true;
    }

    /// <summary>
    /// 판을 PNG 로 씁니다. **해상도를 파일에 적습니다** — 인화소는 그 값으로 실제 크기를
    /// 정하므로, 빠뜨리면 300dpi 로 짠 판이 72dpi 로 인쇄됩니다.
    /// </summary>
    private static async Task<bool> EncodeAsync(
        string destination,
        byte[] page,
        int width,
        int height,
        int dpi)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(destination) ?? ".");
            using IRandomAccessStream stream = await OpenAsync(destination, FileAccess.ReadWrite);
            stream.Size = 0;
            BitmapEncoder encoder = await BitmapEncoder.CreateAsync(
                BitmapEncoder.PngEncoderId,
                stream);
            encoder.SetPixelData(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Ignore,
                (uint)width,
                (uint)height,
                dpi,
                dpi,
                page);
            await encoder.FlushAsync();
            return true;
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    private static async Task<IRandomAccessStream> OpenAsync(string path, FileAccess access)
    {
        FileStream file = new(
            path,
            access == FileAccess.Read ? FileMode.Open : FileMode.OpenOrCreate,
            access,
            FileShare.Read);
        return await Task.FromResult(file.AsRandomAccessStream());
    }
}
