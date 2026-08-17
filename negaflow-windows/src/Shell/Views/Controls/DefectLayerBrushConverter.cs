using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Data;
using Microsoft.UI.Xaml.Media;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// 레이어 줄의 두 단추 색입니다. macOS 는 켜진 레이어를 <c>Color.primary</c>, 꺼진 것을
/// <c>Color.secondary</c> 로 내고, 마스크가 보이는 동안에는 <c>Color.accentColor</c> 로 냅니다.
/// </summary>
/// <remarks>
/// 켜짐 색은 매개변수 없이, 강조 색은 <c>ConverterParameter=Accent</c> 로 고릅니다. 색은 켜짐과
/// 꺼짐이라는 상태의 성질이므로 템플릿이 아니라 여기서 정합니다.
/// </remarks>
public sealed class DefectLayerBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        bool active = value is true;
        bool accent = parameter is string name &&
            string.Equals(name, "Accent", StringComparison.Ordinal);
        string key = active
            ? (accent ? "AccentTextFillColorPrimaryBrush" : "TextFillColorPrimaryBrush")
            : "TextFillColorSecondaryBrush";
        return Application.Current.Resources[key] is Brush brush
            ? brush
            : Application.Current.Resources["TextFillColorSecondaryBrush"];
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language) =>
        throw new NotSupportedException();
}
