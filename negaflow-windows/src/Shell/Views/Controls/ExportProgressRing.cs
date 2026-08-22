using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Negaflow.Shell.Develop;
using Windows.Foundation;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// 위 막대에 잠깐 나오는 원형 진행 표시입니다. 옆에 "3/8" 과 퍼센트가 붙습니다.
/// </summary>
/// <remarks>
/// 내보내는 동안에만 나오고 끝나면 사라집니다. 위 막대는 제목 표시줄이라 자리가 좁으므로
/// 지름 16 짜리 고리 하나와 글자 두 개만 둡니다 — 진행의 자세한 내역은 좌측 출력 탭의
/// 알약이 들고 있습니다.
/// </remarks>
public sealed class ExportProgressRing : UserControl, IThemedSettingsControl
{
    private const double Diameter = 16;
    private const double Thickness = 2;

    private readonly Ellipse track = new()
    {
        Width = Diameter,
        Height = Diameter,
        StrokeThickness = Thickness,
    };

    private readonly Microsoft.UI.Xaml.Shapes.Path arc = new()
    {
        StrokeThickness = Thickness,
        StrokeStartLineCap = PenLineCap.Round,
        StrokeEndLineCap = PenLineCap.Round,
    };

    private readonly TextBlock countText = new()
    {
        FontSize = 11,
        FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        VerticalAlignment = VerticalAlignment.Center,
    };

    private readonly TextBlock percentText = new()
    {
        FontSize = 11,
        VerticalAlignment = VerticalAlignment.Center,
    };

    private ExportProgress progress = ExportProgress.Idle;

    public ExportProgressRing()
    {
        Visibility = Visibility.Collapsed;
        VerticalAlignment = VerticalAlignment.Center;

        Grid ring = new() { Width = Diameter, Height = Diameter };
        ring.Children.Add(track);
        ring.Children.Add(arc);

        StackPanel row = new()
        {
            Orientation = Orientation.Horizontal,
            Spacing = 5,
            VerticalAlignment = VerticalAlignment.Center,
        };
        row.Children.Add(ring);
        row.Children.Add(countText);
        row.Children.Add(percentText);
        Content = row;
    }

    /// <summary>
    /// 몇 장 중 몇 장인지입니다. <see cref="ExportProgress.Idle"/> 이면 통째로 사라집니다.
    /// </summary>
    public ExportProgress Progress
    {
        get => progress;
        set
        {
            progress = value;
            Visibility = value.IsRunning ? Visibility.Visible : Visibility.Collapsed;
            if (!value.IsRunning)
            {
                return;
            }
            countText.Text = value.CountText;
            percentText.Text = string.Create(
                System.Globalization.CultureInfo.CurrentCulture,
                $"{value.Percent}%");
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(this, value.DisplayText);
            arc.Data = ArcFor(value.Fraction);
        }
    }

    public void ApplyBrushes()
    {
        track.Stroke = SettingsBrushes.GetStrokeBrush(this) ??
            SettingsBrushes.GetHoverBrush(this);
        arc.Stroke = SettingsBrushes.GetAccentBrush(this);
        countText.Foreground = SettingsBrushes.GetPrimaryForeground(this) ?? countText.Foreground;
        percentText.Foreground =
            SettingsBrushes.GetSecondaryForeground(this) ?? percentText.Foreground;
    }

    /// <summary>12시에서 시계 방향으로 <paramref name="fraction"/> 만큼 그린 호입니다.</summary>
    private static Geometry ArcFor(double fraction)
    {
        double radius = (Diameter - Thickness) / 2;
        double centre = Diameter / 2;
        double swept = Math.Clamp(fraction, 0.0, 0.999_9) * 2 * Math.PI;
        Point start = new(centre, centre - radius);
        Point end = new(
            centre + (radius * Math.Sin(swept)),
            centre - (radius * Math.Cos(swept)));
        PathFigure figure = new() { StartPoint = start, IsClosed = false, IsFilled = false };
        figure.Segments.Add(new ArcSegment
        {
            Point = end,
            Size = new Size(radius, radius),
            SweepDirection = SweepDirection.Clockwise,
            IsLargeArc = swept > Math.PI,
        });
        PathGeometry geometry = new();
        geometry.Figures.Add(figure);
        return geometry;
    }
}
