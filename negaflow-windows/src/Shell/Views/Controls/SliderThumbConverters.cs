using System.Globalization;
using Microsoft.UI.Xaml.Data;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// 슬라이더 썸을 끌 때 뜨는 값 툴팁의 문구입니다.
/// </summary>
/// <remarks>
/// <para>
/// 붙이지 않으면 WinUI 가 값을 <b>소수점 네 자리</b>로 적습니다(<c>0.3600</c>, <c>85.0000</c>).
/// 화면의 값 글자는 그 옆에서 <c>+0.36</c>·<c>85%</c>·<c>10 mm</c> 로 나오므로, 한 칸이 두 가지로
/// 읽힙니다. 그래서 <b>툴팁은 그 슬라이더의 값 글자와 같은 규칙</b>으로 적습니다.
/// </para>
/// <para>
/// XAML 속성(<c>ThumbToolTipValueConverter="{StaticResource …}"</c>)으로는 걸리지 않습니다 —
/// 파싱도 통과하고 앱도 뜨지만 툴팁은 계속 기본 서식이었습니다(실측). 반드시 코드비하인드에서
/// <c>Slider.ThumbToolTipValueConverter</c> 에 넣으십시오.
/// </para>
/// </remarks>
file static class ThumbToolTip
{
    internal static object Text(object value, Func<double, string> format) =>
        value is double number && double.IsFinite(number) ? format(number) : string.Empty;
}

/// <summary>인스펙터 보정 슬라이더 — macOS <c>sliderInputText</c> 와 같은 두 자리입니다.</summary>
public sealed partial class InspectorSliderValueConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language) =>
        value is double number ? InspectorSliderValue.InputText(number) : string.Empty;

    public object ConvertBack(object value, Type targetType, object parameter, string language) =>
        throw new NotSupportedException();
}

/// <summary>
/// 부분 보정(양·페더·크기) — 값 글자가 0…1 을 퍼센트 정수로 적습니다(<c>35</c>).
/// </summary>
public sealed partial class UnitPercentThumbConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language) =>
        ThumbToolTip.Text(
            value,
            unit => Math.Round(unit * 100.0).ToString("0", CultureInfo.CurrentCulture));

    public object ConvertBack(object value, Type targetType, object parameter, string language) =>
        throw new NotSupportedException();
}

/// <summary>
/// 내보내기 품질·출력 선명도 — 슬라이더가 이미 0…100 이고 값 글자는 <c>85%</c> 입니다.
/// </summary>
public sealed partial class PercentSuffixThumbConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language) =>
        ThumbToolTip.Text(
            value,
            percent => Math.Round(percent).ToString("0", CultureInfo.CurrentCulture) + "%");

    public object ConvertBack(object value, Type targetType, object parameter, string language) =>
        throw new NotSupportedException();
}

/// <summary>인화 여백·간격 — 값 글자가 <c>10 mm</c> 입니다.</summary>
public sealed partial class MillimetreThumbConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language) =>
        ThumbToolTip.Text(
            value,
            millimetres => Math.Round(millimetres).ToString("0", CultureInfo.CurrentCulture) + " mm");

    public object ConvertBack(object value, Type targetType, object parameter, string language) =>
        throw new NotSupportedException();
}
