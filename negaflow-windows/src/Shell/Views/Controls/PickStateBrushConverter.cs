using Microsoft.UI.Xaml.Data;
using Microsoft.UI.Xaml.Media;
using Negaflow.Catalog;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// 깃발 색입니다. macOS <c>FramePickState.tint</c> 와 같이 선택은 초록, 제외는 빨강입니다.
/// 색을 문자열로 넘겨 XAML 에서 파싱하지 않고 여기서 정하는 것은, 색이 상태의 성질이지
/// 표시의 성질이 아니기 때문입니다.
/// </summary>
public sealed class PickStateBrushConverter : IValueConverter
{
    private static readonly SolidColorBrush Picked =
        new(Windows.UI.Color.FromArgb(0xFF, 0x30, 0xA4, 0x6C));

    private static readonly SolidColorBrush Rejected =
        new(Windows.UI.Color.FromArgb(0xFF, 0xE5, 0x48, 0x4D));

    public object Convert(object value, Type targetType, object parameter, string language) =>
        value is FramePickState.Rejected ? Rejected : Picked;

    public object ConvertBack(object value, Type targetType, object parameter, string language) =>
        throw new NotSupportedException();
}
