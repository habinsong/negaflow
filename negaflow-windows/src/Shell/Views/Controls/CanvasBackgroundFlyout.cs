using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Controls;

/// <summary>
/// 캔버스를 오른쪽 클릭하면 뜨는 배경색 메뉴입니다. macOS <c>CanvasBackgroundMenu</c>
/// 이식본이며, 현상 캔버스와 인화 캔버스가 <b>같은 메뉴</b>를 씁니다.
/// </summary>
/// <remarks>
/// macOS 는 머리글 "배경색" 아래 인라인 Picker 로 세 칸을 냅니다. WinUI 의 같은 모양은
/// 머리글 한 줄 + <see cref="ToggleMenuFlyoutItem"/> 셋이며, 고른 것 하나만 체크가 켜집니다.
/// </remarks>
public static class CanvasBackgroundFlyout
{
    /// <summary>
    /// 메뉴를 만듭니다. <paramref name="current"/> 는 열 때마다 지금 값을 되읽고,
    /// <paramref name="choose"/> 는 고른 값을 저장합니다.
    /// </summary>
    public static MenuFlyout Create(
        Func<CanvasBackgroundKind> current,
        Action<CanvasBackgroundKind> choose)
    {
        ArgumentNullException.ThrowIfNull(current);
        ArgumentNullException.ThrowIfNull(choose);
        MenuFlyout flyout = new();
        MenuFlyoutItem header = new()
        {
            Text = AppResources.Get("canvasBackgroundMenu", "Text"),
            IsEnabled = false,
        };
        flyout.Items.Add(header);
        List<(CanvasBackgroundKind Kind, string Key)> options =
        [
            (CanvasBackgroundKind.Black, "canvasBackgroundBlack"),
            (CanvasBackgroundKind.Gray, "canvasBackgroundGray"),
            (CanvasBackgroundKind.White, "canvasBackgroundWhite"),
        ];
        List<ToggleMenuFlyoutItem> items = [];
        foreach ((CanvasBackgroundKind kind, string key) in options)
        {
            ToggleMenuFlyoutItem item = new()
            {
                Text = AppResources.Get(key, "Content"),
                Tag = kind,
            };
            item.Click += (_, _) =>
            {
                choose(kind);
                Synchronize(items, kind);
            };
            flyout.Items.Add(item);
            items.Add(item);
        }
        // 메뉴를 열 때마다 지금 값에 체크를 맞춥니다 - 설정 창에서 바꾼 값도 그대로 보입니다.
        flyout.Opening += (_, _) => Synchronize(items, current());
        return flyout;
    }

    private static void Synchronize(
        List<ToggleMenuFlyoutItem> items,
        CanvasBackgroundKind selected)
    {
        foreach (ToggleMenuFlyoutItem item in items)
        {
            item.IsChecked = item.Tag is CanvasBackgroundKind kind && kind == selected;
        }
    }
}
