namespace Negaflow.Shell.Library;

/// <summary>
/// 필름스트립 카드 치수입니다. macOS <c>FilmstripSizing</c> 의 산술을 그대로 씁니다 — 여기서
/// 어긋나면 같은 높이에서 카드 크기와 줄 수가 macOS 와 달라집니다.
/// </summary>
public static class FilmstripMetrics
{
    public const double NominalItemHeight = 152.0;
    public const double MaximumAutoItemHeight = 156.0;
    public const double DefaultRowFill = 0.92;
    public const double ThumbnailAspectRatio = 3.0 / 2.0;
    public const double MaximumRowCount = 3.0;
    public const double RowSpacing = 10.0;

    /// <summary>썸네일 높이에서 카드 폭을 냅니다. 112 아래는 macOS 와 같이 compact 여백입니다.</summary>
    public static double CardWidth(double itemHeight)
    {
        bool isCompact = itemHeight < 112.0;
        double horizontalPadding = isCompact ? 10.0 : 16.0;
        double chromeHeight = isCompact ? 43.0 : 57.0;
        double thumbnailHeight = Math.Max(24.0, itemHeight - chromeHeight);
        return Math.Max(96.0, (thumbnailHeight * ThumbnailAspectRatio) + horizontalPadding);
    }

    /// <summary>스트립 높이가 허락하는 만큼으로 줄인 배율입니다.</summary>
    public static double EffectiveItemScale(double itemScale, double filmstripHeight)
    {
        double clampedScale = Math.Clamp(
            itemScale,
            ShellLayoutMetrics.FilmstripMinimumItemScale,
            ShellLayoutMetrics.FilmstripMaximumItemScale);
        double fittedRowHeight = FittedRowHeight(clampedScale, filmstripHeight);
        double autoItemHeight = AutoItemHeight(fittedRowHeight);
        double maximumEffectiveScale = Math.Min(
            ShellLayoutMetrics.FilmstripMaximumItemScale,
            Math.Max(ShellLayoutMetrics.FilmstripMinimumItemScale, fittedRowHeight / autoItemHeight));
        return Math.Min(clampedScale, maximumEffectiveScale);
    }

    /// <summary>
    /// 스트립 높이가 허락하는 최대 배율입니다. macOS <c>maximumEffectiveItemScale</c> 자리이며,
    /// 하단바의 <c>+</c> 를 언제 잠글지가 이 값에서 나옵니다.
    /// </summary>
    public static double MaximumEffectiveItemScale(double itemScale, double filmstripHeight)
    {
        double effective = EffectiveItemScale(itemScale, filmstripHeight);
        return Math.Min(
            ShellLayoutMetrics.FilmstripMaximumItemScale,
            Math.Max(
                effective,
                EffectiveItemScale(
                    ShellLayoutMetrics.FilmstripMaximumItemScale, filmstripHeight)));
    }

    /// <summary>지금 높이에서 카드 하나가 차지할 실제 높이입니다.</summary>
    /// <remarks>
    /// macOS <c>itemSize.height</c> 그대로입니다 — <c>min(autoItemHeight × 실효배율,
    /// fittedRowHeight)</c>. 앞 판은 줄 높이를 <b>실효 배율</b>로 다시 재고 마지막 <c>min</c>
    /// 도 없어서, 배율을 올리면 카드가 줄 칸보다 커질 수 있었습니다. 줄 수와 줄 높이는
    /// macOS 와 같이 <b>고른 배율</b>에서 한 번만 나옵니다.
    /// </remarks>
    public static double ItemHeight(double itemScale, double filmstripHeight)
    {
        double clampedScale = Math.Clamp(
            itemScale,
            ShellLayoutMetrics.FilmstripMinimumItemScale,
            ShellLayoutMetrics.FilmstripMaximumItemScale);
        double fittedRowHeight = FittedRowHeight(clampedScale, filmstripHeight);
        double autoItemHeight = AutoItemHeight(fittedRowHeight);
        double effectiveScale = Math.Min(
            clampedScale,
            Math.Min(
                ShellLayoutMetrics.FilmstripMaximumItemScale,
                Math.Max(
                    ShellLayoutMetrics.FilmstripMinimumItemScale,
                    fittedRowHeight / autoItemHeight)));
        return Math.Min(autoItemHeight * effectiveScale, fittedRowHeight);
    }

    private static double FittedRowHeight(double scale, double filmstripHeight)
    {
        double contentHeight = Math.Max(72.0, filmstripHeight - ShellLayoutMetrics.FilmstripResizeHandleHeight);
        double availableGridHeight = Math.Max(72.0, contentHeight - 20.0);
        double nominalHeight = NominalItemHeight * scale;
        double rowCount = Math.Min(
            MaximumRowCount,
            Math.Max(1.0, Math.Floor((availableGridHeight + RowSpacing) / (nominalHeight + RowSpacing))));
        return Math.Max(
            64.0,
            (availableGridHeight - ((rowCount - 1.0) * RowSpacing)) / rowCount);
    }

    private static double AutoItemHeight(double fittedRowHeight) =>
        Math.Min(MaximumAutoItemHeight, Math.Max(58.0, fittedRowHeight * DefaultRowFill));
}
