namespace Negaflow.Shell.Develop;

/// <summary>macOS <c>CanvasBackground</c>.</summary>
public enum CanvasBackgroundKind
{
    Black,
    Gray,
    White,
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
