using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// macOS <c>FrameRatingButtons</c> 와 같은 별 다섯 개입니다. 채워진 별은 파랑, 빈 별은 흐린
/// 보조색이며, 이미 그 값이면 다시 눌러 0 으로 되돌립니다.
/// </summary>
public sealed class FrameRatingStars : UserControl
{
    private const int StarCount = 5;
    private const string FilledGlyph = "";
    private const string EmptyGlyph = "";

    public static readonly DependencyProperty RatingProperty = DependencyProperty.Register(
        nameof(Rating),
        typeof(int),
        typeof(FrameRatingStars),
        new PropertyMetadata(0, OnRatingChanged));

    public static readonly DependencyProperty GlyphSizeProperty = DependencyProperty.Register(
        nameof(GlyphSize),
        typeof(double),
        typeof(FrameRatingStars),
        new PropertyMetadata(11.0, OnGlyphSizeChanged));

    private readonly FontIcon[] stars = new FontIcon[StarCount];

    public FrameRatingStars()
    {
        var panel = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 4.0,
            VerticalAlignment = VerticalAlignment.Center,
        };
        for (int index = 0; index < StarCount; ++index)
        {
            var star = new FontIcon
            {
                FontSize = GlyphSize,
                Glyph = EmptyGlyph,
                Tag = index + 1,
            };
            star.PointerPressed += OnStarPressed;
            stars[index] = star;
            panel.Children.Add(star);
        }
        Content = panel;
        IsTabStop = true;
        // 이름("등급")과 도움말이 리소스에서 옵니다 — 언어가 바뀌면 스스로 다시 겁니다.
        LocalizedElement.Track(this, Localize);
    }

    private void Localize()
    {
        AutomationProperties.SetName(this, AppResources.Get("rating", "Value"));
        Render();
    }

    /// <summary>사용자가 별을 눌러 바꾼 값입니다. 저장은 호스트가 합니다.</summary>
    public event EventHandler<int>? RatingCommitted;

    public int Rating
    {
        get => (int)GetValue(RatingProperty);
        set => SetValue(RatingProperty, value);
    }

    public double GlyphSize
    {
        get => (double)GetValue(GlyphSizeProperty);
        set => SetValue(GlyphSizeProperty, value);
    }

    private static void OnRatingChanged(DependencyObject sender, DependencyPropertyChangedEventArgs args)
    {
        _ = args;
        (sender as FrameRatingStars)?.Render();
    }

    private static void OnGlyphSizeChanged(DependencyObject sender, DependencyPropertyChangedEventArgs args)
    {
        _ = args;
        if (sender is not FrameRatingStars control)
        {
            return;
        }
        foreach (FontIcon star in control.stars)
        {
            star.FontSize = control.GlyphSize;
        }
    }

    private void OnStarPressed(object sender, PointerRoutedEventArgs args)
    {
        if (sender is not FontIcon { Tag: int value })
        {
            return;
        }
        // 카드 선택까지 함께 일어나면 별을 누른 것인지 카드를 고른 것인지 알 수 없습니다.
        args.Handled = true;
        // 같은 값을 다시 누르면 지웁니다 — macOS 의 토글과 같습니다.
        int next = Rating == value ? 0 : value;
        Rating = next;
        RatingCommitted?.Invoke(this, next);
    }

    private void Render()
    {
        var filled = (Brush)Application.Current.Resources["NegaflowRatingFilledBrush"];
        var empty = (Brush)Application.Current.Resources["NegaflowRatingEmptyBrush"];
        for (int index = 0; index < StarCount; ++index)
        {
            bool isFilled = index < Rating;
            stars[index].Glyph = isFilled ? FilledGlyph : EmptyGlyph;
            stars[index].Foreground = isFilled ? filled : empty;
        }
        AutomationProperties.SetHelpText(
            this,
            AppResources.FormatIntegers("ratingAccessibility", "Value", Rating));
    }
}
