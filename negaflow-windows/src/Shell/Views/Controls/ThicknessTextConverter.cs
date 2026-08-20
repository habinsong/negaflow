using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Data;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// <c>"6"</c> · <c>"6,22,6,6"</c> 같은 글자를 <see cref="Thickness"/> 로 바꿉니다.
/// </summary>
/// <remarks>
/// XAML 에 직접 적은 여백은 표시 변환기가 알아서 처리하지만, <c>Binding</c> 으로 온 값은 그
/// 변환을 거치지 않습니다. 여백이 데이터에서 오는 자리 — 폴더 머리줄의
/// <c>.padding(.top, isFirst ? 0 : 16)</c> — 에서 이것이 필요합니다. <c>Shell.Core</c> 는
/// WinUI 를 참조하지 않으므로 투영은 글자로 내고 셸이 여기서 바꿉니다.
/// </remarks>
public sealed partial class ThicknessTextConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        _ = targetType;
        _ = parameter;
        _ = language;
        return Parse(value as string);
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language) =>
        throw new NotSupportedException();

    /// <summary>한 값이면 네 변 모두, 네 값이면 왼쪽·위·오른쪽·아래입니다.</summary>
    internal static Thickness Parse(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return default;
        }
        string[] parts = text.Split(',', StringSplitOptions.TrimEntries);
        if (parts.Length == 1 && TryRead(parts[0], out double uniform))
        {
            return new Thickness(uniform);
        }
        if (parts.Length == 4 &&
            TryRead(parts[0], out double left) &&
            TryRead(parts[1], out double top) &&
            TryRead(parts[2], out double right) &&
            TryRead(parts[3], out double bottom))
        {
            return new Thickness(left, top, right, bottom);
        }
        return default;
    }

    private static bool TryRead(string text, out double value) =>
        double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out value);
}
