using Microsoft.UI.Xaml.Data;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// 필름 종류를 사용자 언어 문자열로 바꿉니다. 이름을 한 곳에서만 만들어야 카드·필터·정보 패널이
/// 서로 다른 말을 쓰지 않습니다.
/// </summary>
public sealed partial class FilmTypeNameConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        _ = targetType;
        _ = parameter;
        _ = language;
        return value is FilmType filmType ? Name(filmType) : string.Empty;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language) =>
        throw new NotSupportedException();

    public static string Name(FilmType filmType) => AppResources.Get(
        filmType switch
        {
            FilmType.ColorNegative => "filmTypeColorNegative",
            FilmType.ColorPositive => "filmTypeColorPositive",
            FilmType.BlackAndWhiteNegative => "filmTypeBlackAndWhiteNegative",
            FilmType.BlackAndWhitePositive => "filmTypeBlackAndWhitePositive",
            _ => "filmTypeColorNegative",
        },
        "Text");
}
