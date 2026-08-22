using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Library.Browser;

/// <summary>
/// 격자의 폴더 머리줄입니다. macOS <c>folderSectionHeader</c> +
/// <c>LibraryFolderDevelopmentControls</c> 와 같은 구성이며, 판정과 카탈로그 쓰기는 전부
/// 부모(<see cref="LibrarySourceRail"/>)가 맡습니다 — 여기서는 그리고 알리기만 합니다.
/// </summary>
/// <remarks>
/// <b>UserControl 이어야 합니다.</b> 이 머리줄은 예전에 <c>x:Class</c> 없는
/// <c>ResourceDictionary</c> 안의 <c>DataTemplate</c> 이었고, 그래서 XAML 컴파일러가
/// <c>IComponentConnector</c> 를 만들지 않아 <c>Click</c>·<c>SelectionChanged</c> 가
/// <b>한 개도 연결되지 않았습니다.</b> 프로세스·타깃 고르개와 적용 단추가 보이기만 하고
/// 아무 일도 하지 않던 것이 그 때문입니다. <see cref="LibraryFrameCard"/> 와 같은 형태로
/// 두어야 부모 페이지의 커넥터가 이벤트를 실제로 잇습니다.
/// </remarks>
public sealed partial class LibraryFolderHeader : UserControl
{
    public LibraryFolderHeader()
    {
        InitializeComponent();
        Localize();
        DataContextChanged += OnDataContextChanged;
    }

    /// <summary>이 머리줄이 대표하는 폴더입니다.</summary>
    public LibraryBrowserFolderSection? Section =>
        DataContext as LibraryBrowserFolderSection ?? Tag as LibraryBrowserFolderSection;

    /// <summary>지금 고르개에 떠 있는 프로세스입니다. 아직 프레임에 쓰이지 않은 초안입니다.</summary>
    public DevelopProcessChoice? SelectedProcess =>
        ProcessSelector.SelectedItem as DevelopProcessChoice;

    /// <summary>지금 고르개에 떠 있는 타깃입니다.</summary>
    public DevelopTargetChoice? SelectedTarget =>
        TargetSelector.SelectedItem as DevelopTargetChoice;

    public event EventHandler<RoutedEventArgs>? DisclosureClicked;

    public event EventHandler<RoutedEventArgs>? ProcessChanged;

    public event EventHandler<RoutedEventArgs>? TargetChanged;

    public event EventHandler<RoutedEventArgs>? ApplyClicked;

    /// <summary>x:Uid 대신 코드에서 겁니다 — 언어를 바꾸면 머리줄이 다시 만들어집니다.</summary>
    public void Localize() =>
        ApplyButton.Content = AppResources.Get("libraryFolderApply", "Content");

    /// <summary>
    /// macOS <c>LibraryTaskProgressView</c> 자리입니다. 적용이 도는 동안만 보이고,
    /// 끝나면 부모가 <see cref="ClearProgress"/> 로 지웁니다.
    /// </summary>
    public void ShowProgress(LibraryFolderDevelopmentProgress update)
    {
        ProgressPanel.Visibility = Visibility.Visible;
        ProgressBarControl.Value = update.TotalCount == 0
            ? 0.0
            : (double)update.CompletedCount / update.TotalCount;
        ProgressPercentText.Text = string.Create(
            System.Globalization.CultureInfo.CurrentCulture,
            $"{update.Percent}%");
        ProgressCountText.Text = string.Create(
            System.Globalization.CultureInfo.CurrentCulture,
            $"{update.CompletedCount}/{update.TotalCount}");
    }

    public void ClearProgress()
    {
        ProgressPanel.Visibility = Visibility.Collapsed;
        ProgressBarControl.Value = 0.0;
        ProgressPercentText.Text = string.Empty;
        ProgressCountText.Text = string.Empty;
    }

    /// <summary>
    /// 격자가 머리줄 컨테이너를 재활용하면 같은 인스턴스에 다른 폴더가 들어옵니다. 앞 폴더의
    /// 진행률이 남아 있으면 엉뚱한 폴더가 작업 중인 것처럼 보이므로 여기서 지웁니다.
    /// </summary>
    private void OnDataContextChanged(FrameworkElement sender, DataContextChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        Tag = DataContext;
        ClearProgress();
        // macOS `LibraryFolderApplyButton(isDisabled: frames.isEmpty || isApplying)`.
        ApplyButton.IsEnabled = Section is { Items.Count: > 0 };
    }

    /// <summary>
    /// 고르개가 스스로 움직인 것인가, 사람이 고른 것인가.
    ///
    /// <c>SelectedIndex</c> 는 <c>ProcessIndex</c> 에 묶여 있고, 격자가 머리줄 컨테이너를
    /// 재활용하면 새 폴더의 값으로 다시 세팅되면서 <c>SelectionChanged</c> 가 한 번 더
    /// 올라옵니다. 그것을 사람이 고른 것으로 세면 **옆 폴더의 값이 이 폴더의 초안으로
    /// 적힙니다.** 고르개가 이미 폴더의 현재 값과 같은 자리에 있으면 알리지 않습니다 —
    /// 사람이 같은 값을 다시 골라도 바뀌는 것이 없으므로 잃는 것도 없습니다.
    /// </summary>
    private bool IsBindingEcho(int selectedIndex, int sectionIndex) =>
        Section is null || selectedIndex < 0 || selectedIndex == sectionIndex;

    private void OnDisclosureClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        DisclosureClicked?.Invoke(this, args);
    }

    private void OnProcessChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (Section is not { } section ||
            IsBindingEcho(ProcessSelector.SelectedIndex, section.ProcessIndex))
        {
            return;
        }
        ProcessChanged?.Invoke(this, new RoutedEventArgs());
    }

    private void OnTargetChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (Section is not { } section ||
            IsBindingEcho(TargetSelector.SelectedIndex, section.TargetIndex))
        {
            return;
        }
        TargetChanged?.Invoke(this, new RoutedEventArgs());
    }

    private void OnApplyClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        ApplyClicked?.Invoke(this, args);
    }
}
