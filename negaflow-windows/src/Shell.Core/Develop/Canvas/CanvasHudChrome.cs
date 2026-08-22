namespace Negaflow.Shell.Develop;

/// <summary>macOS <c>CanvasBackground</c>.</summary>
public enum CanvasBackgroundKind
{
    Black,
    Gray,
    White,
}

/// <summary>
/// 캔버스 바탕색입니다. macOS <c>CanvasBackground.color</c> 와 같은 값입니다 —
/// 검정 0.07 · 회색 0.5 · 흰색 0.97.
/// </summary>
public static class CanvasBackgroundColors
{
    public static double White(CanvasBackgroundKind background) => background switch
    {
        CanvasBackgroundKind.Gray => 0.5,
        CanvasBackgroundKind.White => 0.97,
        _ => 0.07,
    };

    public static byte Byte(CanvasBackgroundKind background) =>
        (byte)Math.Round(255 * White(background), MidpointRounding.AwayFromZero);
}

/// <summary>macOS <c>CanvasBackground.hudContentColor</c> / <c>hudSurfaceColor</c>.</summary>
public readonly record struct CanvasHudChrome(double ContentWhite, double SurfaceWhite)
{
    /// <summary>macOS stroke <c>hudContentColor.opacity(0.22)</c>.</summary>
    public const double StrokeOpacity = 0.22;

    public static CanvasHudChrome For(CanvasBackgroundKind background) =>
        background switch
        {
            CanvasBackgroundKind.Black => new(0.97, 0.20),
            CanvasBackgroundKind.Gray => new(0.97, 0.30),
            CanvasBackgroundKind.White => new(0.12, 0.86),
            _ => new(0.97, 0.20),
        };

    public byte ContentByte => ToByte(ContentWhite);

    public byte SurfaceByte => ToByte(SurfaceWhite);

    public byte StrokeAlpha => (byte)Math.Round(255 * StrokeOpacity, MidpointRounding.AwayFromZero);

    private static byte ToByte(double white) =>
        (byte)Math.Round(Math.Min(Math.Max(white, 0), 1) * 255, MidpointRounding.AwayFromZero);
}
