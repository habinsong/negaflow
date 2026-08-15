namespace Negaflow.Shell.Print;

public enum PrintPackageContentMode
{
    Fit,
    Fill,
}

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

    public bool IsValid =>
        ContactRows > 0 && ContactColumns > 0 &&
        ContactRows * ContactColumns <= MaximumCells &&
        double.IsFinite(HorizontalSpacingMm) && HorizontalSpacingMm is >= 0 and <= 50 &&
        double.IsFinite(VerticalSpacingMm) && VerticalSpacingMm is >= 0 and <= 50;
}

/// <summary>판 위의 사진 한 칸입니다.</summary>
public sealed record PrintPackageItemLayout(
    int SourceIndex,
    PrintRect CellRect,
    PrintRect ImageRect,
    int QuarterTurns);

/// <summary>판 한 장입니다.</summary>
public sealed record PrintPackagePageLayout(
    int PageIndex,
    PrintSizeMm CanvasSize,
    PrintRect ContentRect,
    IReadOnlyList<PrintPackageItemLayout> Items);

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
        // 판의 방향은 칸 배치를 따릅니다 — 가로로 넓은 격자에는 가로 용지가 맞습니다.
        PrintSizeMm page = PrintCompositionLayout.PageDimensions(
            composition.PaperDimensionsMm,
            composition.Orientation,
            columns >= rows);
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
                items.Add(MakeItem(sourceIndices[slot], sourceSizes[sourceIndices[slot]], cell, package));
            }
            pages.Add(new PrintPackagePageLayout(pageIndex, canvas, content, items));
        }
        return pages;
    }

    private static PrintPackageItemLayout MakeItem(
        int sourceIndex,
        PrintSizeMm sourceSize,
        PrintRect cell,
        PrintPackageSettings package)
    {
        PrintSizeMm effective = sourceSize;
        int quarterTurns = 0;
        if (package.RotateToFit)
        {
            // 돌렸을 때 칸을 더 많이 채우면 돌립니다. 같으면 돌리지 않습니다 — 이유 없이
            // 돌아간 사진은 사용자가 실수로 본 것으로 읽습니다.
            double upright = FitScale(sourceSize, cell);
            double turned = FitScale(new PrintSizeMm(sourceSize.Height, sourceSize.Width), cell);
            if (turned > upright)
            {
                effective = new PrintSizeMm(sourceSize.Height, sourceSize.Width);
                quarterTurns = 1;
            }
        }
        PrintRect image = package.ContentMode == PrintPackageContentMode.Fill
            ? AspectFill(effective, cell)
            : PrintCompositionLayout.AspectFit(effective, cell);
        return new PrintPackageItemLayout(sourceIndex, cell, image, quarterTurns);
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
