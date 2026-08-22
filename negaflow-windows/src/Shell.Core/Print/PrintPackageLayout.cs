namespace Negaflow.Shell.Print;

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
                items.Add(PrintPackageCells.MakeItem(
                    sourceIndices[slot],
                    sourceSizes[sourceIndices[slot]],
                    cell,
                    package,
                    pixelsPerMm));
            }
            pages.Add(new PrintPackagePageLayout(pageIndex, canvas, content, items)
            {
                CropMarks = PrintPackageCells.CropMarks(items, content, package, pixelsPerMm),
                TextItems = PageTextItems(canvas, package),
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
        if (PrintPackageCells.PictureCells(package.PictureTemplate, content, horizontalGap, verticalGap)
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
                items.Add(PrintPackageCells.MakeItem(
                    sourceIndex,
                    sourceSizes[sourceIndex],
                    cells[slot],
                    package,
                    pixelsPerMm));
            }
            pages.Add(new PrintPackagePageLayout(pages.Count, canvas, content, items)
            {
                CropMarks = PrintPackageCells.CropMarks(items, content, package, pixelsPerMm),
                TextItems = PageTextItems(canvas, package),
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
    /// <summary>
    /// 손으로 놓은 문구를 판 좌표로 옮깁니다. macOS <c>pageTextItems(page:package:)</c> 와
    /// 같습니다 — 캡션 방식이 "사용자 문구" 일 때만, 빈 문구는 빼고 냅니다.
    /// </summary>
    private static IReadOnlyList<PrintPackageTextLayout> PageTextItems(
        PrintSizeMm canvas,
        PrintPackageSettings package)
    {
        if (package.CaptionMode != PrintPackageCaptionMode.CustomText)
        {
            return [];
        }
        List<PrintPackageTextLayout> items = [];
        foreach (PrintCustomCaption caption in package.CustomCaptions)
        {
            if (caption.Text.Length == 0)
            {
                continue;
            }
            items.Add(new PrintPackageTextLayout(
                caption.Text,
                new PrintRect(
                    caption.NormalizedRect.X * canvas.Width,
                    caption.NormalizedRect.Y * canvas.Height,
                    caption.NormalizedRect.Width * canvas.Width,
                    caption.NormalizedRect.Height * canvas.Height),
                caption.Alignment));
        }
        return items;
    }
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
                items.Add(PrintPackageCells.MakeItem(
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
                CropMarks = PrintPackageCells.CropMarks(items, content, package, pixelsPerMm),
                TextItems = PageTextItems(canvas, package),
            });
        }
        return pages;
    }
}
