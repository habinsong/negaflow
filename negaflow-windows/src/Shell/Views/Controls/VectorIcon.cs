using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using ShapePath = Microsoft.UI.Xaml.Shapes.Path;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// 직접 그린 선 아이콘입니다. <c>FontIcon</c> 자리에 그대로 바꿔 넣도록 만들었습니다.
/// </summary>
/// <remarks>
/// <para>
/// 왜 있는가 — Segoe 에 <b>뜻이 맞는 글리프가 없는</b> 자리가 스무 곳 넘습니다. 지금까지는
/// "비슷해 보이는 것"을 골라 넣어 좌우 반전에 압정이, 우측탭 토글에 와이파이가 붙어
/// 있었습니다(<c>docs/audit/08a-icon-inventory.md</c>). SF Symbols 는 라이선스상 쓸 수
/// 없으므로 <b>같은 뜻의 그림을 직접 그립니다.</b>
/// </para>
/// <para>
/// 획 자료는 <see cref="VectorIconPaths"/> 한 곳에만 둡니다. 자리마다 Path 를 인라인으로
/// 쓰면 같은 아이콘이 화면마다 다르게 그려집니다 — `CanvasToolHud.xaml` 이 그렇게 되어
/// 있고, 그래서 줌 아이콘만 이 저장소에서 뜻이 맞습니다.
/// </para>
/// <para>
/// 크기는 <see cref="IconSize"/> 로 줍니다. <c>FontIcon</c> 의 <c>FontSize</c> 와 같은
/// 뜻이라 바꿔 넣을 때 숫자를 그대로 옮기면 됩니다. 색은 부모의 <c>Foreground</c> 를
/// 물려받습니다 — <c>FontIcon</c> 과 같습니다.
/// </para>
/// </remarks>
public sealed class VectorIcon : UserControl
{
    // 24x24 에 그렸습니다. `VectorIconPaths` 의 좌표계와 반드시 같아야 합니다.
    private const double DesignSize = 24.0;

    // 24 기준 획 두께입니다. 16px 로 줄이면 약 1.07px 이 되어 Segoe 선 굵기와 비슷합니다.
    private const double DesignStrokeThickness = 1.6;

    public static readonly DependencyProperty KindProperty = DependencyProperty.Register(
        nameof(Kind),
        typeof(VectorIconKind),
        typeof(VectorIcon),
        new PropertyMetadata(VectorIconKind.RotateRight, OnKindChanged));

    public static readonly DependencyProperty IconSizeProperty = DependencyProperty.Register(
        nameof(IconSize),
        typeof(double),
        typeof(VectorIcon),
        new PropertyMetadata(16.0, OnIconSizeChanged));

    private readonly ShapePath path = new()
    {
        StrokeThickness = DesignStrokeThickness,
        StrokeStartLineCap = PenLineCap.Round,
        StrokeEndLineCap = PenLineCap.Round,
        StrokeLineJoin = PenLineJoin.Round,
        Fill = null,
    };

    private readonly Viewbox viewbox = new()
    {
        Stretch = Stretch.Uniform,
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
    };

    public VectorIcon()
    {
        // 획이 상자를 넘지 않도록 캔버스를 24x24 로 고정합니다. Viewbox 는 자식의
        // **그려진 범위**로 맞추므로, 캔버스를 안 두면 아이콘마다 실제 크기가 달라집니다.
        Canvas canvas = new()
        {
            Width = DesignSize,
            Height = DesignSize,
        };
        canvas.Children.Add(path);
        viewbox.Child = canvas;
        Content = viewbox;
        IsHitTestVisible = false;
        Apply();
        ApplySize();
        // 부모의 Foreground 를 물려받습니다 — `FontIcon` 과 같은 규칙.
        RegisterPropertyChangedCallback(ForegroundProperty, (_, _) => ApplyBrush());
        Loaded += (_, _) => ApplyBrush();
    }

    public VectorIconKind Kind
    {
        get => (VectorIconKind)GetValue(KindProperty);
        set => SetValue(KindProperty, value);
    }

    /// <summary>한 변의 화소입니다. <c>FontIcon.FontSize</c> 와 같은 뜻입니다.</summary>
    public double IconSize
    {
        get => (double)GetValue(IconSizeProperty);
        set => SetValue(IconSizeProperty, value);
    }

    private static void OnKindChanged(DependencyObject sender, DependencyPropertyChangedEventArgs args)
    {
        if (sender is VectorIcon icon)
        {
            icon.Apply();
        }
    }

    private static void OnIconSizeChanged(
        DependencyObject sender,
        DependencyPropertyChangedEventArgs args)
    {
        if (sender is VectorIcon icon)
        {
            icon.ApplySize();
        }
    }

    private void Apply()
    {
        string data = VectorIconPaths.Data(Kind);
        if (data.Length == 0)
        {
            path.Data = null;
            return;
        }
        // 경로 문자열은 XAML 축약 문법이라 그대로 해석시킵니다. 좌표를 손으로 파싱하면
        // 곡선 명령을 하나만 빠뜨려도 조용히 다른 그림이 됩니다.
        path.Data = (Geometry)XamlBindingHelper.ConvertValue(typeof(Geometry), data);
        ApplyBrush();
    }

    private void ApplyBrush() => path.Stroke = Foreground;

    private void ApplySize()
    {
        double size = IconSize > 0 ? IconSize : 16.0;
        viewbox.Width = size;
        viewbox.Height = size;
        Width = size;
        Height = size;
    }
}
