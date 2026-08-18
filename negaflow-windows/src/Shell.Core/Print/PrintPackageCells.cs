namespace Negaflow.Shell.Print;

/// <summary>
/// 판 안의 칸 기하입니다. 몇 장을 어떻게 나눌지는 <see cref="PrintPackageLayout"/> 가
/// 정하고, 여기서는 주어진 영역을 칸으로 자르고 그 칸에 사진을 앉히는 셈만 합니다.
/// </summary>
internal static class PrintPackageCells
{
    /// <summary>
    /// 템플릿의 칸입니다. macOS <c>pictureCells</c> 와 같은 비율 — 큰 칸이 가로의 2/3 를
    /// 가지고, 작은 두 칸이 나머지를 위아래로 나눕니다.
    /// </summary>
    internal static IReadOnlyList<PrintRect>? PictureCells(
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
    internal static IReadOnlyList<PrintLineSegment> CropMarks(
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

    internal static void Add(
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

    internal static PrintPackageItemLayout MakeItem(
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

    internal static double FitScale(PrintSizeMm size, PrintRect bounds) =>
        Math.Min(bounds.Width / size.Width, bounds.Height / size.Height);

    /// <summary>칸을 가득 채웁니다. 넘치는 부분은 잘립니다.</summary>
    internal static PrintRect AspectFill(PrintSizeMm size, PrintRect bounds)
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
