using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Negaflow.Shell.Print;

namespace Negaflow.Shell.Views.Print.Preview;

/// <summary>
/// 인화지 표면을 판 위에 덮습니다. macOS <c>PrintPaperSurfaceOverlay</c> 를 그대로 옮긴
/// 것입니다.
/// </summary>
/// <remarks>
/// 수치는 macOS 그대로입니다.
/// <list type="bullet">
/// <item>유광: 좌상 → 우하 기울기, 흰색 0.02 → 흰색 0.18 → 투명 → 검정 0.025.</item>
/// <item>무광: 아무것도 덮지 않습니다.</item>
/// <item>러스터: 한 방향 빗금, 간격 5, 흰색 0.10, 굵기 0.45.</item>
/// <item>실크: 교차 빗금, 간격 7, 같은 색·굵기.</item>
/// </list>
/// 포인터는 받지 않습니다 — 칸을 끌 때 이 겹이 가로채면 사진이 안 끌립니다.
/// </remarks>
internal static class PrintPaperSurfaceOverlay
{
    /// <summary>표면 겹을 만듭니다. 무광이면 <see langword="null"/> 입니다.</summary>
    internal static FrameworkElement? Make(PrintPaperSurface surface, double width, double height)
    {
        if (width <= 0 || height <= 0)
        {
            return null;
        }
        return surface switch
        {
            PrintPaperSurface.Glossy => Glossy(width, height),
            PrintPaperSurface.Lustre => Lines(width, height, crossed: false, spacing: 5),
            PrintPaperSurface.Silk => Lines(width, height, crossed: true, spacing: 7),
            _ => null,
        };
    }

    private static FrameworkElement Glossy(double width, double height)
    {
        LinearGradientBrush brush = new()
        {
            StartPoint = new Windows.Foundation.Point(0, 0),
            EndPoint = new Windows.Foundation.Point(1, 1),
            GradientStops =
            {
                new GradientStop { Offset = 0, Color = White(0.02) },
                new GradientStop { Offset = 0.333, Color = White(0.18) },
                new GradientStop { Offset = 0.667, Color = Windows.UI.Color.FromArgb(0, 0, 0, 0) },
                new GradientStop { Offset = 1, Color = Black(0.025) },
            },
        };
        return new Rectangle
        {
            Width = width,
            Height = height,
            Fill = brush,
            IsHitTestVisible = false,
        };
    }

    private static FrameworkElement Lines(
        double width,
        double height,
        bool crossed,
        double spacing)
    {
        Canvas host = new()
        {
            Width = width,
            Height = height,
            IsHitTestVisible = false,
        };
        SolidColorBrush stroke = new(White(0.10));
        // macOS: `for offset in stride(from: -size.height, through: size.width, by: spacing)`
        for (double offset = -height; offset <= width; offset += spacing)
        {
            host.Children.Add(Segment(offset, height, offset + height, 0, stroke));
        }
        if (crossed)
        {
            for (double offset = 0; offset <= width + height; offset += spacing)
            {
                host.Children.Add(Segment(offset, 0, offset - height, height, stroke));
            }
        }
        // 판 밖으로 나간 빗금은 잘라 냅니다(macOS `.clipped()`). WinUI 에는 ClipToBounds 가
        // 없어 사각형을 직접 물립니다.
        host.Clip = new RectangleGeometry
        {
            Rect = new Windows.Foundation.Rect(0, 0, width, height),
        };
        return host;
    }

    private static Line Segment(double x1, double y1, double x2, double y2, Brush stroke) =>
        new()
        {
            X1 = x1,
            Y1 = y1,
            X2 = x2,
            Y2 = y2,
            Stroke = stroke,
            StrokeThickness = 0.45,
            IsHitTestVisible = false,
        };

    private static Windows.UI.Color White(double opacity) =>
        Windows.UI.Color.FromArgb((byte)Math.Round(opacity * 255), 0xFF, 0xFF, 0xFF);

    private static Windows.UI.Color Black(double opacity) =>
        Windows.UI.Color.FromArgb((byte)Math.Round(opacity * 255), 0x00, 0x00, 0x00);
}
