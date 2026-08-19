using Microsoft.UI.Xaml;
using Negaflow.Shell.Localization;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;

namespace Negaflow.Shell.Views.Library.Browser;

/// <summary>
/// 격자 한 칸입니다. 썸네일·이름·별점만 그립니다. 고르기 메뉴와 격자 오케스트레이션은 부모가
/// 맡습니다.
/// </summary>
public sealed partial class LibraryFrameCard : UserControl
{
    public LibraryFrameCard()
    {
        InitializeComponent();
        Localize();
    }

    /// <summary>x:Uid 대신 코드에서 겁니다 — 언어를 바꾸면 카드가 다시 만들어집니다.</summary>
    public void Localize() =>
        LibraryLocateOriginalLocalized.Content =
            AppResources.Get("libraryLocateOriginal", "Content");

    public event RightTappedEventHandler? CardRightTapped;

    public event RoutedEventHandler? LocateOriginalClicked;

    public event EventHandler<int>? RatingCommitted;

    private void OnCardRightTapped(object sender, RightTappedRoutedEventArgs args)
    {
        _ = sender;
        CardRightTapped?.Invoke(this, args);
    }

    private void OnLocateOriginalClicked(object sender, RoutedEventArgs args) =>
        LocateOriginalClicked?.Invoke(sender, args);

    private void OnRatingCommitted(object? sender, int rating) =>
        RatingCommitted?.Invoke(sender, rating);
}
