using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// 테마에 따라 갈리는 색을 컨트롤 바깥에서 받아 오는 자리입니다.
/// </summary>
/// <remarks>
/// <para>
/// <b><c>Application.Current.Resources["..."]</c> 로 브러시를 읽으면 안 됩니다.</b> 그
/// 조회는 <c>ThemeDictionaries</c> 를 <b>요소의 테마로</b> 풀지 않습니다. 그래서 앱을 "밝게"
/// 로 두어도 어두운 사전의 값이 나와, 설정 창의 카드가 검게 칠해지고 그 위 글자가 읽히지
/// 않았습니다(사용자 신고, 밝은 모드 스크린샷).
/// </para>
/// <para>
/// WinUI 에서 테마를 제대로 따라가는 길은 <b>Style 세터의 <c>{ThemeResource}</c></b> 입니다 —
/// 세터는 요소마다 풀리고 테마가 바뀌면 다시 풀립니다. 그래서 색이 필요한 컨트롤마다
/// 의존 속성을 두고, <c>Styles/Settings.xaml</c> 의 암시적 Style 이 그 속성을 채웁니다.
/// </para>
/// </remarks>
public static class SettingsBrushes
{
    /// <summary>카드(둥근 상자)의 바탕입니다.</summary>
    public static readonly DependencyProperty CardBackgroundProperty =
        DependencyProperty.RegisterAttached(
            "CardBackground",
            typeof(Brush),
            typeof(SettingsBrushes),
            new PropertyMetadata(null, OnBrushChanged));

    public static Brush? GetCardBackground(DependencyObject element) =>
        (Brush?)element.GetValue(CardBackgroundProperty);

    public static void SetCardBackground(DependencyObject element, Brush? value) =>
        element.SetValue(CardBackgroundProperty, value);

    /// <summary>행 사이 분리선입니다.</summary>
    public static readonly DependencyProperty DividerBrushProperty =
        DependencyProperty.RegisterAttached(
            "DividerBrush",
            typeof(Brush),
            typeof(SettingsBrushes),
            new PropertyMetadata(null, OnBrushChanged));

    public static Brush? GetDividerBrush(DependencyObject element) =>
        (Brush?)element.GetValue(DividerBrushProperty);

    public static void SetDividerBrush(DependencyObject element, Brush? value) =>
        element.SetValue(DividerBrushProperty, value);

    /// <summary>값·설명문처럼 한 단 흐린 글자색입니다.</summary>
    public static readonly DependencyProperty SecondaryForegroundProperty =
        DependencyProperty.RegisterAttached(
            "SecondaryForeground",
            typeof(Brush),
            typeof(SettingsBrushes),
            new PropertyMetadata(null, OnBrushChanged));

    public static Brush? GetSecondaryForeground(DependencyObject element) =>
        (Brush?)element.GetValue(SecondaryForegroundProperty);

    public static void SetSecondaryForeground(DependencyObject element, Brush? value) =>
        element.SetValue(SecondaryForegroundProperty, value);

    /// <summary>캡슐 트랙의 바탕입니다.</summary>
    public static readonly DependencyProperty TrackBrushProperty =
        DependencyProperty.RegisterAttached(
            "TrackBrush",
            typeof(Brush),
            typeof(SettingsBrushes),
            new PropertyMetadata(null, OnBrushChanged));

    public static Brush? GetTrackBrush(DependencyObject element) =>
        (Brush?)element.GetValue(TrackBrushProperty);

    public static void SetTrackBrush(DependencyObject element, Brush? value) =>
        element.SetValue(TrackBrushProperty, value);

    /// <summary>캡슐에서 고른 칸의 바탕입니다.</summary>
    public static readonly DependencyProperty ThumbBrushProperty =
        DependencyProperty.RegisterAttached(
            "ThumbBrush",
            typeof(Brush),
            typeof(SettingsBrushes),
            new PropertyMetadata(null, OnBrushChanged));

    public static Brush? GetThumbBrush(DependencyObject element) =>
        (Brush?)element.GetValue(ThumbBrushProperty);

    public static void SetThumbBrush(DependencyObject element, Brush? value) =>
        element.SetValue(ThumbBrushProperty, value);

    /// <summary>색이 바뀌면 컨트롤이 자기 안쪽을 다시 칠하게 합니다.</summary>
    private static void OnBrushChanged(
        DependencyObject sender,
        DependencyPropertyChangedEventArgs args)
    {
        _ = args;
        if (sender is IThemedSettingsControl themed)
        {
            themed.ApplyBrushes();
        }
    }
}

/// <summary>테마 색을 받아 안쪽 요소에 바르는 컨트롤입니다.</summary>
public interface IThemedSettingsControl
{
    void ApplyBrushes();
}
