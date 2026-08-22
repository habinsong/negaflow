using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Negaflow.Catalog;
using Negaflow.Shell.Library;
using Negaflow.Shell.Localization;
using Windows.UI;

namespace Negaflow.Shell.Views.Library.Host;

/// <summary>
/// "원본 파일을 휴지통으로 이동" 명령입니다. 라이브러리 카드와 현상·인화 필름스트립이
/// 같이 씁니다.
/// </summary>
/// <remarks>
/// macOS <c>LibraryFrameContextMenu</c> 의 마지막 항목이며 <c>role: .destructive</c> 라
/// <b>빨간 글자</b>로 납니다. 누르면 바로 지우지 않고 확인 대화상자를 띄웁니다 — 파일
/// 삭제는 카탈로그 되돌리기로 되살릴 수 없기 때문입니다.
/// </remarks>
internal static class SourceTrashCommand
{
    /// <summary>macOS 의 destructive 색입니다. 시스템 빨강을 쓰되 없으면 표준 빨강입니다.</summary>
    private static Brush DestructiveBrush =>
        Application.Current.Resources.TryGetValue("SystemFillColorCriticalBrush", out object? found)
            && found is Brush brush
            ? brush
            : new SolidColorBrush(Color.FromArgb(255, 196, 43, 28));

    /// <summary>
    /// 메뉴 맨 아래에 구분선과 빨간 항목을 붙입니다. 지울 원본이 없으면(가상 사본만
    /// 골랐으면) 아무 것도 붙이지 않습니다 — 눌러도 아무 일이 없는 항목을 두지 않습니다.
    /// </summary>
    internal static void Append(
        MenuFlyout menu,
        LibraryHostService library,
        IReadOnlyList<LibraryFrameSnapshot> targets,
        XamlRoot? xamlRoot,
        Action? afterDeleted = null)
    {
        ArgumentNullException.ThrowIfNull(menu);
        ArgumentNullException.ThrowIfNull(library);
        ArgumentNullException.ThrowIfNull(targets);
        if (SourceDeletionPlan.For(targets, library.Frames) is not { } plan)
        {
            return;
        }

        menu.Items.Add(new MenuFlyoutSeparator());
        MenuFlyoutItem item = new()
        {
            Text = AppResources.Get("libraryMoveSourceToTrash", "Content"),
            Foreground = DestructiveBrush,
        };
        item.Click += async (_, _) => await ConfirmAndRunAsync(library, plan, xamlRoot, afterDeleted);
        menu.Items.Add(item);
    }

    /// <summary>확인을 받고 실행합니다. 무엇이 몇 개 사라지는지 먼저 말합니다.</summary>
    private static async Task ConfirmAndRunAsync(
        LibraryHostService library,
        SourceDeletionPlan plan,
        XamlRoot? xamlRoot,
        Action? afterDeleted)
    {
        if (xamlRoot is null)
        {
            return;
        }
        ContentDialog dialog = new()
        {
            XamlRoot = xamlRoot,
            Title = AppResources.Get("deleteSourceConfirmationTitle", "Text"),
            Content = new TextBlock
            {
                // "카탈로그 항목 %d개가 원본 파일 %d개를 공유합니다 ... %s" — 숫자 둘을
                // 차례로 채운 뒤 경로를 넣습니다. 경로는 줄이지 않습니다.
                Text = AppResources
                    .FormatIntegers(
                        "deleteSourceConfirmationMessageFormat",
                        "Text",
                        plan.FrameCount,
                        plan.SourceCount)
                    .Replace("%s", plan.FirstSourcePath, StringComparison.Ordinal),
                TextWrapping = TextWrapping.Wrap,
            },
            PrimaryButtonText = AppResources.Get("libraryMoveSourceToTrash", "Content"),
            CloseButtonText = AppResources.Get("commonCancel", "Content"),
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }

        SourceTrashResult result = SourceDeletionCoordinator.Run(library, plan);
        if (result.IsSuccess)
        {
            afterDeleted?.Invoke();
        }
    }
}
