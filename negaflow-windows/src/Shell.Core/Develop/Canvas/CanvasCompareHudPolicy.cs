namespace Negaflow.Shell.Develop;

/// <summary>macOS <c>CanvasCompareOrientation</c>.</summary>
public enum CanvasCompareOrientation
{
    Vertical,
    Horizontal,
}

/// <summary>macOS <c>CanvasCompareToggle</c> 수치.</summary>
public static class CanvasCompareHudPolicy
{
    /// <summary>macOS <c>HStack(spacing: 2)</c>.</summary>
    public const double ItemSpacing = 2;

    /// <summary>macOS <c>.padding(2)</c>.</summary>
    public const double SurfacePadding = 2;

    /// <summary>macOS <c>canvasControlSurface(..., cornerRadius: 10)</c>.</summary>
    public const double SurfaceCornerRadius = 10;

    /// <summary>macOS text <c>.padding(.horizontal, 9)</c>.</summary>
    public const double TextHorizontalPadding = 9;

    /// <summary>macOS text/icon <c>.frame(height: 24)</c>.</summary>
    public const double ButtonHeight = 24;

    /// <summary>macOS icon <c>.frame(width: 26, height: 24)</c>.</summary>
    public const double IconButtonWidth = 26;

    /// <summary>macOS icon <c>.font(.system(size: 12, weight: .semibold))</c>.</summary>
    public const double IconSize = 12;

    /// <summary>macOS active background <c>content.opacity(0.16)</c>.</summary>
    public const double ActiveFillOpacity = 0.16;

    /// <summary>macOS inactive <c>content.opacity(0.65)</c>.</summary>
    public const double InactiveContentOpacity = 0.65;

    /// <summary>macOS button <c>RoundedRectangle(cornerRadius: 7)</c>.</summary>
    public const double ButtonCornerRadius = 7;

    public static CanvasCompareOrientation? SplitOrientation(CanvasCompareMode mode) =>
        mode switch
        {
            CanvasCompareMode.SplitVertical => CanvasCompareOrientation.Vertical,
            CanvasCompareMode.SplitHorizontal => CanvasCompareOrientation.Horizontal,
            _ => null,
        };
}
