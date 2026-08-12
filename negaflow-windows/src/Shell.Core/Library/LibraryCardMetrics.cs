namespace Negaflow.Shell.Library;

/// <summary>
/// 라이브러리 격자 카드의 치수입니다. macOS <c>LibraryGridCardLayout</c> 과
/// <c>LibraryWorkspaceView.cardSize</c> 의 규칙을 그대로 씁니다.
/// </summary>
public static class LibraryCardMetrics
{
    public const double BaseWidth = 190.0;
    public const double ThumbnailAspectRatio = 3.0 / 2.0;
    public const double ThumbnailTitleSpacing = 3.0;
    public const double RatingControlHeight = 14.0;
    public const double CardPadding = 8.0;
    public const double TitleHeight = 15.0;

    public const double MinimumScale = 0.72;
    public const double MaximumScale = 1.42;
    public const double ScaleStep = 0.08;

    private static double scale = 1.0;

    /// <summary>헤더의 − % + 가 바꾸는 배율입니다. macOS 의 <c>cardScale</c> 과 같습니다.</summary>
    public static double Scale
    {
        get => scale;
        set => scale = Math.Clamp(value, MinimumScale, MaximumScale);
    }

    public static double Width => BaseWidth * Scale;

    /// <summary>macOS 는 배율을 줄여도 10pt 아래로는 좁히지 않습니다.</summary>
    public static double Spacing => Math.Max(10.0, 14.0 * Scale);

    public static double ThumbnailHeight => (Width - (CardPadding * 2.0)) / ThumbnailAspectRatio;

    public static double Height =>
        ThumbnailHeight + TitleHeight + ThumbnailTitleSpacing + RatingControlHeight + (CardPadding * 2.0);
}
