namespace Negaflow.Shell.Print;

public enum PrintPackageContentMode
{
    Fit,
    Fill,
}

/// <summary>픽처 패키지의 칸 배치입니다. macOS <c>PrintPicturePackageTemplate</c> 과 같습니다.</summary>
public enum PrintPicturePackageTemplate
{
    OneLargeTwoSmall,
    TwoUp,
    FourUp,
}

/// <summary>칸 아래에 무엇을 적을지입니다. macOS <c>PrintPackageCaptionMode</c> 와 같습니다.</summary>
public enum PrintPackageCaptionMode
{
    None,
    FileName,
    FrameNumber,
    SequenceNumber,
    Rating,
}

public enum PrintPackageCaptionAlignment
{
    Leading,
    Center,
    Trailing,
}

/// <summary>
/// 사용자가 손으로 놓은 칸 하나입니다. macOS <c>PrintCustomPackageItem</c> 과 같습니다.
/// </summary>
/// <remarks>
/// 자리는 <b>내용 영역에 대한 0…1 비율</b>입니다. 화소로 담으면 용지나 해상도를 바꾼 순간
/// 배치가 통째로 어긋납니다.
/// </remarks>
public sealed record PrintCustomPackageItem(
    int SourceIndex,
    PrintRect NormalizedRect)
{
    public int PageIndex { get; init; }

    public PrintPackageContentMode ContentMode { get; init; } = PrintPackageContentMode.Fit;

    public bool RotateToFit { get; init; }

    /// <summary>겹칠 때 위로 오는 차례입니다. 같으면 목록 차례를 따릅니다.</summary>
    public int ZIndex { get; init; }

    /// <summary>판 밖으로 나가거나 넓이가 없는 칸은 놓지 않습니다.</summary>
    public bool IsValid =>
        SourceIndex >= 0 &&
        PageIndex >= 0 &&
        double.IsFinite(NormalizedRect.X) && double.IsFinite(NormalizedRect.Y) &&
        double.IsFinite(NormalizedRect.Width) && double.IsFinite(NormalizedRect.Height) &&
        NormalizedRect.Width > 0 && NormalizedRect.Height > 0 &&
        NormalizedRect.X >= 0 && NormalizedRect.Y >= 0 &&
        NormalizedRect.MaxX <= 1.0001 && NormalizedRect.MaxY <= 1.0001;
}

/// <summary>크롭마크 선분 하나입니다.</summary>
public readonly record struct PrintLineSegment(
    double StartX,
    double StartY,
    double EndX,
    double EndY);

/// <summary>여러 장을 한 판에 놓는 방식입니다. macOS <c>PrintPackageLayoutMode</c> 와 같습니다.</summary>
public enum PrintPackageMode
{
    ContactSheet,
    PicturePackage,
    CustomPackage,
}

/// <summary>
/// 인화 판을 채우는 값입니다. macOS <c>PrintPackageSettings</c> 중 Windows 가 지금 내는 것들입니다.
/// </summary>
public sealed record PrintPackageSettings
{
    public const int MaximumPageCount = 32;

    /// <summary>한 판에 놓을 수 있는 칸 수의 한계입니다. 넘으면 칸이 화소보다 작아집니다.</summary>
    public const int MaximumCells = 400;

    public PrintPackageMode Mode { get; init; } = PrintPackageMode.ContactSheet;

    public int ContactRows { get; init; } = 7;

    public int ContactColumns { get; init; } = 6;

    public double HorizontalSpacingMm { get; init; } = 4;

    public double VerticalSpacingMm { get; init; } = 4;

    public PrintPackageContentMode ContentMode { get; init; } = PrintPackageContentMode.Fit;

    /// <summary>칸에 더 잘 맞으면 90도 돌려 놓습니다. 프레임 자체는 건드리지 않습니다.</summary>
    public bool RotateToFit { get; init; }

    /// <summary>한 판에 한 사진을 가득 반복합니다 — 증명사진처럼 같은 컷을 여러 장 뽑을 때입니다.</summary>
    public bool RepeatOnePhotoPerPage { get; init; }

    public PrintSheetBackground SheetBackground { get; init; } = PrintSheetBackground.White;

    public PrintPicturePackageTemplate PictureTemplate { get; init; } =
        PrintPicturePackageTemplate.OneLargeTwoSmall;

    public PrintPackageCaptionMode CaptionMode { get; init; } = PrintPackageCaptionMode.None;

    public PrintPackageCaptionAlignment CaptionAlignment { get; init; } =
        PrintPackageCaptionAlignment.Center;

    /// <summary>캡션이 차지하는 높이입니다. 사진은 그만큼 위로 물러납니다.</summary>
    public double CaptionHeightMm { get; init; } = 6;

    public bool ShowsCropMarks { get; init; }

    public double CropMarkLengthMm { get; init; } = 4;

    /// <summary>커스텀 배치의 칸들입니다. 그 모드가 아니면 쓰이지 않습니다.</summary>
    public IReadOnlyList<PrintCustomPackageItem> CustomItems { get; init; } = [];

    /// <summary>손으로 놓을 수 있는 칸 수의 한계입니다. macOS 와 같은 128 입니다.</summary>
    public const int MaximumCustomItems = 128;

    public bool IsValid =>
        ContactRows > 0 && ContactColumns > 0 &&
        ContactRows * ContactColumns <= MaximumCells &&
        double.IsFinite(HorizontalSpacingMm) && HorizontalSpacingMm is >= 0 and <= 50 &&
        double.IsFinite(VerticalSpacingMm) && VerticalSpacingMm is >= 0 and <= 50 &&
        double.IsFinite(CaptionHeightMm) && CaptionHeightMm is >= 0 and <= 40 &&
        double.IsFinite(CropMarkLengthMm) && CropMarkLengthMm is >= 0 and <= 30 &&
        CustomItems.Count <= MaximumCustomItems;
}

/// <summary>판 위의 사진 한 칸입니다.</summary>
public sealed record PrintPackageItemLayout(
    int SourceIndex,
    PrintRect CellRect,
    PrintRect ImageRect,
    int QuarterTurns)
{
    /// <summary>캡션이 놓이는 자리입니다. 캡션이 없으면 null 입니다.</summary>
    public PrintRect? CaptionRect { get; init; }
}

/// <summary>판 한 장입니다.</summary>
public sealed record PrintPackagePageLayout(
    int PageIndex,
    PrintSizeMm CanvasSize,
    PrintRect ContentRect,
    IReadOnlyList<PrintPackageItemLayout> Items)
{
    /// <summary>재단선입니다. 켜지 않았으면 빕니다.</summary>
    public IReadOnlyList<PrintLineSegment> CropMarks { get; init; } = [];
}

public static class PrintPackageLayout
{
    /// <summary>
    /// 판을 계산합니다. 사진이 한 판에 다 안 들어가면 판을 여러 장 냅니다.
    /// </summary>
    /// <remarks>
    /// 칸 차례는 <b>왼쪽 위부터 오른쪽으로</b>이고, 좌표는 화면과 같은 위에서 아래 방향입니다 —
    /// macOS 는 아래에서 위인 좌표계라 같은 자리를 다른 수로 적지만, 놓이는 차례는 같습니다.
    /// </remarks>
    public static IReadOnlyList<PrintPackagePageLayout>? Make(
        IReadOnlyList<PrintSizeMm> sourceSizes,
        PrintCompositionSettings composition,
        PrintPackageSettings package)
    {
        ArgumentNullException.ThrowIfNull(sourceSizes);
        ArgumentNullException.ThrowIfNull(composition);
        ArgumentNullException.ThrowIfNull(package);
        if (!composition.IsValid || !package.IsValid ||
            sourceSizes.Any(size =>
                size.Width <= 0 || size.Height <= 0 ||
                !double.IsFinite(size.Width) || !double.IsFinite(size.Height)))
        {
            return null;
        }
        if (sourceSizes.Count == 0)
        {
            return [];
        }

        int rows = package.ContactRows;
        int columns = package.ContactColumns;
        bool picturePackage = package.Mode == PrintPackageMode.PicturePackage;
        // 판의 방향은 칸 배치를 따릅니다 — 가로로 넓은 격자에는 가로 용지가 맞습니다.
        // 픽처 패키지는 칸이 정해져 있으므로 첫 사진의 방향을 따릅니다.
        PrintSizeMm page = PrintCompositionLayout.PageDimensions(
            composition.PaperDimensionsMm,
            composition.Orientation,
            picturePackage
                ? sourceSizes[0].Width >= sourceSizes[0].Height
                : columns >= rows);
        double pixelsPerMm = composition.Dpi / 25.4;
        PrintSizeMm canvas = new(
            Math.Max(1, Math.Round(page.Width * pixelsPerMm)),
            Math.Max(1, Math.Round(page.Height * pixelsPerMm)));
        PrintRect content = new PrintRect(0, 0, canvas.Width, canvas.Height)
            .Inset(composition.MarginMm * pixelsPerMm);
        if (content.Width <= 1 || content.Height <= 1)
        {
            return null;
        }

        double horizontalGap = package.HorizontalSpacingMm * pixelsPerMm;
        double verticalGap = package.VerticalSpacingMm * pixelsPerMm;
        if (package.Mode == PrintPackageMode.CustomPackage)
        {
            return CustomPackagePages(sourceSizes, package, canvas, content, pixelsPerMm);
        }
        if (picturePackage)
        {
            return PicturePackagePages(
                sourceSizes,
                package,
                canvas,
                content,
                horizontalGap,
                verticalGap,
                pixelsPerMm);
        }
        double availableWidth = content.Width - ((columns - 1) * horizontalGap);
        double availableHeight = content.Height - ((rows - 1) * verticalGap);
        if (availableWidth <= 1 || availableHeight <= 1)
        {
            return null;
        }
        double cellWidth = availableWidth / columns;
        double cellHeight = availableHeight / rows;

        int capacity = rows * columns;
        List<int[]> assignments = [];
        if (package.RepeatOnePhotoPerPage)
        {
            foreach (int index in Enumerable.Range(0, sourceSizes.Count))
            {
                assignments.Add([.. Enumerable.Repeat(index, capacity)]);
            }
        }
        else
        {
            for (int start = 0; start < sourceSizes.Count; start += capacity)
            {
                assignments.Add([.. Enumerable.Range(
                    start,
                    Math.Min(capacity, sourceSizes.Count - start))]);
            }
        }
        if (assignments.Count > PrintPackageSettings.MaximumPageCount)
        {
            return null;
        }

        List<PrintPackagePageLayout> pages = new(assignments.Count);
        for (int pageIndex = 0; pageIndex < assignments.Count; ++pageIndex)
        {
            int[] sourceIndices = assignments[pageIndex];
            List<PrintPackageItemLayout> items = new(sourceIndices.Length);
            for (int slot = 0; slot < sourceIndices.Length; ++slot)
            {
                int row = slot / columns;
                int column = slot % columns;
                PrintRect cell = new(
                    content.MinX + (column * (cellWidth + horizontalGap)),
                    content.MinY + (row * (cellHeight + verticalGap)),
                    cellWidth,
                    cellHeight);
                items.Add(MakeItem(
                    sourceIndices[slot],
                    sourceSizes[sourceIndices[slot]],
                    cell,
                    package,
                    pixelsPerMm));
            }
            pages.Add(new PrintPackagePageLayout(pageIndex, canvas, content, items)
            {
                CropMarks = CropMarks(items, content, package, pixelsPerMm),
            });
        }
        return pages;
    }

    /// <summary>
    /// 픽처 패키지 한 판씩입니다. 칸 수가 템플릿에 매여 있어, 사진이 칸보다 적으면 앞에서부터
    /// 다시 씁니다 — macOS 도 <c>slot % sourceIndices.count</c> 로 돌려 씁니다.
    /// </summary>
    private static IReadOnlyList<PrintPackagePageLayout>? PicturePackagePages(
        IReadOnlyList<PrintSizeMm> sourceSizes,
        PrintPackageSettings package,
        PrintSizeMm canvas,
        PrintRect content,
        double horizontalGap,
        double verticalGap,
        double pixelsPerMm)
    {
        int capacity = package.PictureTemplate switch
        {
            PrintPicturePackageTemplate.TwoUp => 2,
            PrintPicturePackageTemplate.FourUp => 4,
            _ => 3,
        };
        if (PictureCells(package.PictureTemplate, content, horizontalGap, verticalGap)
            is not { } cells)
        {
            return null;
        }
        List<PrintPackagePageLayout> pages = [];
        for (int start = 0; start < sourceSizes.Count; start += capacity)
        {
            int[] sourceIndices = [.. Enumerable.Range(
                start,
                Math.Min(capacity, sourceSizes.Count - start))];
            List<PrintPackageItemLayout> items = new(cells.Count);
            for (int slot = 0; slot < cells.Count; ++slot)
            {
                int sourceIndex = sourceIndices[slot % sourceIndices.Length];
                items.Add(MakeItem(
                    sourceIndex,
                    sourceSizes[sourceIndex],
                    cells[slot],
                    package,
                    pixelsPerMm));
            }
            pages.Add(new PrintPackagePageLayout(pages.Count, canvas, content, items)
            {
                CropMarks = CropMarks(items, content, package, pixelsPerMm),
            });
            if (pages.Count > PrintPackageSettings.MaximumPageCount)
            {
                return null;
            }
        }
        return pages;
    }

    /// <summary>
    /// 손으로 놓은 배치입니다. 칸이 겹칠 수 있으므로 <c>ZIndex</c> 차례로 쌓습니다 — 같으면
    /// 목록에 적힌 차례입니다.
    /// </summary>
    /// <remarks>
    /// 판 번호는 <b>0 부터 빈 곳 없이</b> 이어져야 합니다. 1번 판만 있고 0번이 없으면 첫 장이
    /// 빈 채로 인쇄되므로, 그런 배치는 아예 만들지 않습니다 — macOS 도 같은 조건입니다.
    /// </remarks>
    private static IReadOnlyList<PrintPackagePageLayout>? CustomPackagePages(
        IReadOnlyList<PrintSizeMm> sourceSizes,
        PrintPackageSettings package,
        PrintSizeMm canvas,
        PrintRect content,
        double pixelsPerMm)
    {
        if (package.CustomItems.Count == 0 ||
            package.CustomItems.Any(item =>
                !item.IsValid || item.SourceIndex >= sourceSizes.Count))
        {
            return null;
        }
        int highestPage = package.CustomItems.Max(item => item.PageIndex);
        if (highestPage + 1 > PrintPackageSettings.MaximumPageCount)
        {
            return null;
        }
        var usedPages = package.CustomItems.Select(item => item.PageIndex).ToHashSet();
        for (int pageIndex = 0; pageIndex <= highestPage; ++pageIndex)
        {
            if (!usedPages.Contains(pageIndex))
            {
                return null;
            }
        }

        List<PrintPackagePageLayout> pages = new(highestPage + 1);
        for (int pageIndex = 0; pageIndex <= highestPage; ++pageIndex)
        {
            List<PrintPackageItemLayout> items = [];
            IEnumerable<PrintCustomPackageItem> ordered = package.CustomItems
                .Select((item, order) => (item, order))
                .Where(pair => pair.item.PageIndex == pageIndex)
                .OrderBy(pair => pair.item.ZIndex)
                .ThenBy(pair => pair.order)
                .Select(pair => pair.item);
            foreach (PrintCustomPackageItem definition in ordered)
            {
                PrintRect cell = new(
                    content.MinX + (definition.NormalizedRect.X * content.Width),
                    content.MinY + (definition.NormalizedRect.Y * content.Height),
                    definition.NormalizedRect.Width * content.Width,
                    definition.NormalizedRect.Height * content.Height);
                items.Add(MakeItem(
                    definition.SourceIndex,
                    sourceSizes[definition.SourceIndex],
                    cell,
                    // 칸마다 맞추기·돌리기를 따로 고를 수 있습니다.
                    package with
                    {
                        ContentMode = definition.ContentMode,
                        RotateToFit = definition.RotateToFit,
                    },
                    pixelsPerMm));
            }
            pages.Add(new PrintPackagePageLayout(pageIndex, canvas, content, items)
            {
                CropMarks = CropMarks(items, content, package, pixelsPerMm),
            });
        }
        return pages;
    }

    /// <summary>
    /// 템플릿의 칸입니다. macOS <c>pictureCells</c> 와 같은 비율 — 큰 칸이 가로의 2/3 를
    /// 가지고, 작은 두 칸이 나머지를 위아래로 나눕니다.
    /// </summary>
    private static IReadOnlyList<PrintRect>? PictureCells(
        PrintPicturePackageTemplate template,
        PrintRect content,
        double horizontalGap,
        double verticalGap)
    {
        switch (template)
        {
            case PrintPicturePackageTemplate.TwoUp:
            {
                double width = (content.Width - horizontalGap) / 2;
                return width <= 1
                    ? null
                    : new PrintRect[]
                    {
                        new(content.MinX, content.MinY, width, content.Height),
                        new(content.MinX + width + horizontalGap, content.MinY, width,
                            content.Height),
                    };
            }

            case PrintPicturePackageTemplate.FourUp:
            {
                double width = (content.Width - horizontalGap) / 2;
                double height = (content.Height - verticalGap) / 2;
                if (width <= 1 || height <= 1)
                {
                    return null;
                }
                List<PrintRect> quad = new(4);
                for (int slot = 0; slot < 4; ++slot)
                {
                    quad.Add(new PrintRect(
                        content.MinX + ((slot % 2) * (width + horizontalGap)),
                        content.MinY + ((slot / 2) * (height + verticalGap)),
                        width,
                        height));
                }
                return quad;
            }

            default:
            {
                double availableWidth = content.Width - horizontalGap;
                double availableHeight = content.Height - verticalGap;
                if (availableWidth <= 2 || availableHeight <= 2)
                {
                    return null;
                }
                double largeWidth = availableWidth * 2 / 3;
                double smallWidth = availableWidth - largeWidth;
                double smallHeight = availableHeight / 2;
                double smallX = content.MinX + largeWidth + horizontalGap;
                return new PrintRect[]
                {
                    new(content.MinX, content.MinY, largeWidth, content.Height),
                    new(smallX, content.MinY, smallWidth, smallHeight),
                    new(smallX, content.MinY + smallHeight + verticalGap, smallWidth, smallHeight),
                };
            }
        }
    }

    /// <summary>
    /// 재단선입니다. macOS 와 같이 칸 모서리 밖으로 뻗되 **판을 넘지 않습니다** — 넘은 선은
    /// 잘려 나가 인쇄물에 반쪽만 남습니다.
    /// </summary>
    private static IReadOnlyList<PrintLineSegment> CropMarks(
        IReadOnlyList<PrintPackageItemLayout> items,
        PrintRect content,
        PrintPackageSettings package,
        double pixelsPerMm)
    {
        if (!package.ShowsCropMarks || package.CropMarkLengthMm <= 0)
        {
            return [];
        }
        double length = package.CropMarkLengthMm * pixelsPerMm;
        List<PrintLineSegment> segments = new(items.Count * 8);
        foreach (PrintPackageItemLayout item in items)
        {
            PrintRect cell = item.CellRect;
            double left = Math.Max(content.MinX, cell.MinX - length);
            double right = Math.Min(content.MaxX, cell.MaxX + length);
            double top = Math.Max(content.MinY, cell.MinY - length);
            double bottom = Math.Min(content.MaxY, cell.MaxY + length);
            Add(segments, left, cell.MinY, cell.MinX, cell.MinY);
            Add(segments, left, cell.MaxY, cell.MinX, cell.MaxY);
            Add(segments, cell.MaxX, cell.MinY, right, cell.MinY);
            Add(segments, cell.MaxX, cell.MaxY, right, cell.MaxY);
            Add(segments, cell.MinX, top, cell.MinX, cell.MinY);
            Add(segments, cell.MaxX, top, cell.MaxX, cell.MinY);
            Add(segments, cell.MinX, cell.MaxY, cell.MinX, bottom);
            Add(segments, cell.MaxX, cell.MaxY, cell.MaxX, bottom);
        }
        return segments;
    }

    private static void Add(
        List<PrintLineSegment> segments,
        double startX,
        double startY,
        double endX,
        double endY)
    {
        // 길이 0 인 선은 그리지 않습니다 — 칸이 판 가장자리에 붙으면 그런 선이 생깁니다.
        if (Math.Abs(startX - endX) < 0.001 && Math.Abs(startY - endY) < 0.001)
        {
            return;
        }
        segments.Add(new PrintLineSegment(startX, startY, endX, endY));
    }

    private static PrintPackageItemLayout MakeItem(
        int sourceIndex,
        PrintSizeMm sourceSize,
        PrintRect cell,
        PrintPackageSettings package,
        double pixelsPerMm)
    {
        // 캡션은 칸 아래를 차지하고, 사진은 남은 자리에 듭니다.
        double captionHeight = package.CaptionMode == PrintPackageCaptionMode.None
            ? 0
            : Math.Min(package.CaptionHeightMm * pixelsPerMm, cell.Height / 2);
        PrintRect? caption = captionHeight > 0
            ? new PrintRect(cell.X, cell.MaxY - captionHeight, cell.Width, captionHeight)
            : null;
        PrintRect imageCell = captionHeight > 0
            ? new PrintRect(cell.X, cell.Y, cell.Width, cell.Height - captionHeight)
            : cell;

        PrintSizeMm effective = sourceSize;
        int quarterTurns = 0;
        if (package.RotateToFit)
        {
            // 돌렸을 때 칸을 더 많이 채우면 돌립니다. 같으면 돌리지 않습니다 — 이유 없이
            // 돌아간 사진은 사용자가 실수로 본 것으로 읽습니다.
            double upright = FitScale(sourceSize, imageCell);
            double turned = FitScale(
                new PrintSizeMm(sourceSize.Height, sourceSize.Width),
                imageCell);
            if (turned > upright)
            {
                effective = new PrintSizeMm(sourceSize.Height, sourceSize.Width);
                quarterTurns = 1;
            }
        }
        PrintRect image = package.ContentMode == PrintPackageContentMode.Fill
            ? AspectFill(effective, imageCell)
            : PrintCompositionLayout.AspectFit(effective, imageCell);
        return new PrintPackageItemLayout(sourceIndex, cell, image, quarterTurns)
        {
            CaptionRect = caption,
        };
    }

    private static double FitScale(PrintSizeMm size, PrintRect bounds) =>
        Math.Min(bounds.Width / size.Width, bounds.Height / size.Height);

    /// <summary>칸을 가득 채웁니다. 넘치는 부분은 잘립니다.</summary>
    private static PrintRect AspectFill(PrintSizeMm size, PrintRect bounds)
    {
        double scale = Math.Max(bounds.Width / size.Width, bounds.Height / size.Height);
        double width = size.Width * scale;
        double height = size.Height * scale;
        return new PrintRect(
            bounds.MidX - (width / 2),
            bounds.MidY - (height / 2),
            width,
            height);
    }
}
