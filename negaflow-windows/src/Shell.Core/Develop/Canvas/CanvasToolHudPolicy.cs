using System.Globalization;

namespace Negaflow.Shell.Develop;

/// <summary>macOS <c>CanvasToolHUD</c> 수치·퍼센트 입력.</summary>
public static class CanvasToolHudPolicy
{
    /// <summary>macOS <c>HStack(spacing: 4)</c>.</summary>
    public const double ItemSpacing = 4;

    /// <summary>macOS <c>.padding(3)</c>.</summary>
    public const double SurfacePadding = 3;

    /// <summary>macOS <c>canvasControlSurface(..., cornerRadius: 10)</c>.</summary>
    public const double SurfaceCornerRadius = 10;

    /// <summary>macOS <c>CanvasToolButton</c> <c>.frame(width: 22, height: 22)</c>.</summary>
    public const double ButtonSize = 22;

    /// <summary>macOS icon <c>.font(.system(size: 13, weight: .semibold))</c>.</summary>
    public const double IconSize = 13;

    /// <summary>macOS button background <c>RoundedRectangle(cornerRadius: 7)</c>.</summary>
    public const double ButtonCornerRadius = 7;

    /// <summary>macOS zoom text <c>.frame(width: 46, height: 22)</c>.</summary>
    public const double PercentWidth = 46;

    /// <summary>macOS zoom text <c>.font(.caption2)</c>.</summary>
    public const double PercentFontSize = 11;

    /// <summary>macOS editor <c>HStack(spacing: 8)</c>.</summary>
    public const double EditorSpacing = 8;

    /// <summary>macOS editor <c>.padding(12)</c>.</summary>
    public const double EditorPadding = 12;

    /// <summary>macOS editor <c>.frame(width: 176)</c>.</summary>
    public const double EditorWidth = 176;

    /// <summary>macOS editor field <c>.frame(width: 72)</c>.</summary>
    public const double EditorFieldWidth = 72;

    /// <summary>macOS HUD <c>scale * 1.25</c>.</summary>
    public const double ZoomStep = 1.25;

    /// <summary>macOS <c>onSetZoomPercent(min(max(value, 5), 1600))</c>.</summary>
    public const double MinPercent = 5;

    /// <summary>macOS <c>onSetZoomPercent(min(max(value, 5), 1600))</c>.</summary>
    public const double MaxPercent = 1600;

    /// <summary>macOS <c>applyZoomPercent</c>.</summary>
    public static bool TryParseZoomPercent(string? text, out double percent)
    {
        percent = 0;
        if (text is null)
        {
            return false;
        }

        string normalized = text.Replace("%", string.Empty, StringComparison.Ordinal)
            .Trim();
        if (!double.TryParse(
                normalized,
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out double value) ||
            !double.IsFinite(value))
        {
            return false;
        }

        percent = Math.Min(Math.Max(value, MinPercent), MaxPercent);
        return true;
    }
}
