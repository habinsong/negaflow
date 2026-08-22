namespace Negaflow.Shell.Print;

/// <summary>
/// 시아노타입 · 유리건판 · 젤라틴 실버의 화소 변환입니다.
/// </summary>
/// <remarks>
/// <para>
/// macOS <c>PrintCanvasView.presentedImage(_:)</c> 와 같은 계산입니다.
/// </para>
/// <list type="bullet">
/// <item>시아노타입: 흑백으로 접고 반전한 값을 알파로 삼아 그림자색을 하이라이트색 위에
/// 얹습니다 — 결국 <b>밝기 0 은 그림자색, 1 은 하이라이트색</b>인 두 색 사이 보간입니다.</item>
/// <item>유리건판: 흑백 + 반전(음화).</item>
/// <item>젤라틴 실버: 흑백.</item>
/// </list>
/// <para>
/// 밝기는 Rec.709 입니다. 화면 감마를 되돌리지 않는 것도 macOS <c>.grayscale(1)</c> 과
/// 같습니다 - 표시값 그대로 섞습니다.
/// </para>
/// </remarks>
public static class PrintPresentationFilter
{
    /// <summary>이 방식이 화소를 건드리는지입니다. 표준이면 아무 일도 하지 않습니다.</summary>
    public static bool Transforms(PrintPresentationStyle style) =>
        style != PrintPresentationStyle.Standard;

    /// <summary>
    /// BGRA8 화소 묶음을 그 자리에서 바꿉니다. <paramref name="pixels"/> 는 4 바이트씩
    /// 늘어선 BGRA 입니다.
    /// </summary>
    public static void Apply(Span<byte> pixels, PrintPresentationStyle style)
    {
        if (!Transforms(style))
        {
            return;
        }
        PrintPresentationAppearance appearance = PrintPresentationAppearance.For(style);
        for (int index = 0; index + 3 < pixels.Length; index += 4)
        {
            double blue = pixels[index] / 255.0;
            double green = pixels[index + 1] / 255.0;
            double red = pixels[index + 2] / 255.0;
            double luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue);
            (double r, double g, double b) = style switch
            {
                // 그림자색(밝기 0) - 하이라이트색(밝기 1) 사이를 밝기로 섞습니다.
                PrintPresentationStyle.Cyanotype => (
                    Mix(appearance.ShadowRed, appearance.HighlightRed, luminance),
                    Mix(appearance.ShadowGreen, appearance.HighlightGreen, luminance),
                    Mix(appearance.ShadowBlue, appearance.HighlightBlue, luminance)),
                PrintPresentationStyle.GlassPlate => (
                    1 - luminance, 1 - luminance, 1 - luminance),
                _ => (luminance, luminance, luminance),
            };
            pixels[index] = ToByte(b);
            pixels[index + 1] = ToByte(g);
            pixels[index + 2] = ToByte(r);
        }
    }

    private static double Mix(double shadow, double highlight, double amount) =>
        shadow + ((highlight - shadow) * Math.Clamp(amount, 0.0, 1.0));

    private static byte ToByte(double value) =>
        (byte)Math.Clamp(Math.Round(value * 255.0), 0, 255);
}
