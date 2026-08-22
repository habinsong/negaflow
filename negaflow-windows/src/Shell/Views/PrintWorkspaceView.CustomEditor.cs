using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Negaflow.Shell.Print;

namespace Negaflow.Shell.Views;

/// <summary>
/// 사용자 패키지의 칸을 마우스로 놓는 편집기입니다. macOS
/// <c>PrintCustomPackageCanvasOverlay</c> 를 그대로 옮긴 것입니다.
/// </summary>
/// <remarks>
/// macOS 와 같은 규칙을 지킵니다.
/// <list type="bullet">
/// <item>테두리와 손잡이는 <b>고른 칸에만</b> 나옵니다(<c>isSelected ? .accentColor : .clear</c>).</item>
/// <item>칸은 <c>zIndex</c> 차례로 겹치고, 같으면 목록 차례를 따릅니다.</item>
/// <item>자리는 늘 비율로 다룹니다 — 화소로 옮기면 용지를 바꿀 때 어긋남이 쌓입니다.</item>
/// <item>손잡이는 오른쪽 아래 한 곳뿐입니다.</item>
/// </list>
/// </remarks>
public sealed partial class PrintWorkspaceView
{
    /// <summary>손잡이 한 변입니다. macOS 는 10pt 사각형을 꼭짓점에 <b>중심</b>으로 놓습니다.</summary>
    private const double CustomHandleSize = 10;

    /// <summary>칸의 최소 크기입니다(비율). macOS <c>0.02</c> 와 같습니다.</summary>
    private const double CustomMinimumFraction = 0.02;

    /// <summary>고른 칸입니다. macOS <c>selectedCustomItemIndex</c> 자리입니다.</summary>
    private int selectedCustomItem = -1;

    private int draggingCustomItem = -1;
    private bool draggingCustomResize;
    private Windows.Foundation.Point customDragOrigin;
    private PrintRect customDragStartRect;

    /// <summary>편집기가 그린 것들입니다. 판을 다시 그릴 때 함께 지웁니다.</summary>
    private readonly List<FrameworkElement> customEditorParts = [];

    /// <summary>
    /// 칸과 손잡이가 화면에서 차지하는 자리입니다. 포인터는 <see cref="PageCanvas"/> 가
    /// 받으므로 어느 칸을 눌렀는지는 여기서 찾습니다.
    /// </summary>
    private readonly List<(int Slot,
        Windows.Foundation.Rect Cell,
        Windows.Foundation.Rect Handle)> customHitBoxes = [];

    /// <summary>
    /// 내용 영역이 화면에서 차지하는 크기입니다. macOS <c>contentRectPoints * scale</c> 이며,
    /// 그릴 때 재어 두었다가 끌 때 씁니다 — 끌 때마다 배치를 다시 계산하면 느립니다.
    /// </summary>
    private Windows.Foundation.Size customContentSize;

    private bool customPointerHooked;

    /// <summary>
    /// 커스텀 배치의 포인터를 <see cref="PageCanvas"/> 가 받게 합니다. 판을 다시 그려도
    /// 이 요소는 그대로 있으므로 끌기가 끊기지 않습니다.
    /// </summary>
    private void HookCustomPointer()
    {
        if (customPointerHooked)
        {
            return;
        }
        customPointerHooked = true;
        // 배경이 없으면 자식이 없는 자리는 포인터를 받지 않습니다.
        PageCanvas.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        PageCanvas.PointerPressed += OnCustomPointerPressed;
        PageCanvas.PointerMoved += OnCustomDragMoved;
        PageCanvas.PointerReleased += EndCustomDrag;
        PageCanvas.PointerCaptureLost += EndCustomDrag;
        PageCanvas.PointerCanceled += EndCustomDrag;
    }

    /// <summary>
    /// 누른 자리의 칸을 찾습니다. 손잡이가 칸 밖으로 반쯤 나와 있으므로 손잡이를 먼저 보고,
    /// 겹친 칸은 <b>나중에 그린 것</b>이 위이므로 뒤에서부터 봅니다.
    /// </summary>
    private void OnCustomPointerPressed(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (workspaceState is not { } state ||
            state.Current.Print.LayoutMode != PrintLayoutMode.CustomPackage)
        {
            return;
        }
        Windows.Foundation.Point point = args.GetCurrentPoint(PageCanvas).Position;
        PreviewTrace.Write(System.FormattableString.Invariant(
            $"custom.press ({point.X:F0},{point.Y:F0}) boxes={customHitBoxes.Count}"));
        for (int index = customHitBoxes.Count - 1; index >= 0; --index)
        {
            (int slot, Windows.Foundation.Rect cell, Windows.Foundation.Rect handle) =
                customHitBoxes[index];
            // 손잡이는 macOS 와 같이 고른 칸에만 있습니다.
            if (slot == selectedCustomItem && Contains(handle, point))
            {
                BeginCustomDrag(args, slot, resize: true);
                return;
            }
            if (Contains(cell, point))
            {
                BeginCustomDrag(args, slot, resize: false);
                return;
            }
        }
        // 빈 자리를 누르면 고른 칸을 놓습니다.
        if (selectedCustomItem >= 0)
        {
            selectedCustomItem = -1;
            printPreview?.Draw();
        }
    }

    private static bool Contains(Windows.Foundation.Rect rect, Windows.Foundation.Point point) =>
        point.X >= rect.X && point.X <= rect.X + rect.Width &&
        point.Y >= rect.Y && point.Y <= rect.Y + rect.Height;

    /// <summary>
    /// 사용자 패키지에서 칸 테두리와 손잡이를 얹습니다. 다른 모드에서는 아무것도 하지
    /// 않습니다 — 컨택트 시트의 칸은 행·열이 정하므로 끌 수 없습니다.
    /// </summary>
    private void DrawCustomEditor(PrintPackagePageLayout page, double scale)
    {
        foreach (FrameworkElement part in customEditorParts)
        {
            PageCanvas.Children.Remove(part);
        }
        customEditorParts.Clear();
        customHitBoxes.Clear();
        if (workspaceState is not { } state ||
            state.Current.Print.LayoutMode != PrintLayoutMode.CustomPackage)
        {
            // macOS `onChange(of: layoutMode) { if mode != .customPackage { selected = nil } }`
            selectedCustomItem = -1;
            return;
        }
        HookCustomPointer();
        customContentSize = new Windows.Foundation.Size(
            page.ContentRect.Width * scale,
            page.ContentRect.Height * scale);

        // macOS `customItemIndices`: 이 판의 칸을 zIndex 차례로 세웁니다. 그린 차례와 설정
        // 목록의 차례가 다르므로 둘을 짝지어야 엉뚱한 칸이 끌립니다.
        IReadOnlyList<PrintCustomPackageItem> definitions = state.Current.Print.CustomItems;
        int[] slots =
        [
            .. definitions
                .Select((item, order) => (item, order))
                .Where(pair => pair.item.PageIndex == page.PageIndex)
                .OrderBy(pair => pair.item.ZIndex)
                .ThenBy(pair => pair.order)
                .Select(pair => pair.order),
        ];
        PreviewTrace.Write(System.FormattableString.Invariant(
            $"custom.draw page={page.PageIndex} items={page.Items.Count} slots={slots.Length} scale={scale:F3} selected={selectedCustomItem}"));

        for (int offset = 0; offset < slots.Length && offset < page.Items.Count; ++offset)
        {
            int slot = slots[offset];
            PrintRect cell = page.Items[offset].CellRect;
            Windows.Foundation.Rect screen = new(
                cell.X * scale,
                cell.Y * scale,
                Math.Max(1, cell.Width * scale),
                Math.Max(1, cell.Height * scale));
            customHitBoxes.Add((
                slot,
                screen,
                new Windows.Foundation.Rect(
                    (cell.MaxX * scale) - (CustomHandleSize / 2),
                    (cell.MaxY * scale) - (CustomHandleSize / 2),
                    CustomHandleSize,
                    CustomHandleSize)));
            PreviewTrace.Write(System.FormattableString.Invariant(
                $"custom.box {slot} cell=({screen.X:F0},{screen.Y:F0},{screen.Width:F0},{screen.Height:F0})"));
            if (slot != selectedCustomItem)
            {
                // macOS 는 고르지 않은 칸에 `Color.clear` 를 칠합니다 — 아무 틀도 없습니다.
                continue;
            }

            Rectangle border = new()
            {
                Width = screen.Width,
                Height = screen.Height,
                Stroke = AccentBrush(),
                StrokeThickness = 1.5,
                // macOS `StrokeStyle(lineWidth: 1.5, dash: [5, 3])` — WinUI 의 대시 길이는
                // 선 두께의 배수이므로 나눠 줍니다.
                StrokeDashArray = [5.0 / 1.5, 3.0 / 1.5],
                StrokeDashCap = PenLineCap.Flat,
                IsHitTestVisible = false,
            };
            Canvas.SetLeft(border, screen.X);
            Canvas.SetTop(border, screen.Y);
            AutomationProperties.SetAutomationId(border, $"negaflow.print.custom.cell.{slot}");
            PageCanvas.Children.Add(border);
            customEditorParts.Add(border);

            // macOS 는 10×10 둥근 사각형을 오른쪽 아래 꼭짓점에 **중심**으로 놓습니다.
            //
            // 끄는 동안 판은 계속 다시 그려집니다. 손잡이 자체가 포인터를 잡고 있으면 그
            // 다시 그리기가 잡고 있던 요소를 지워 한 화소 만에 끌기가 끝납니다. 그래서 잡는
            // 자리는 지워지지 않는 `PageCanvas` 이고 여기 있는 것들은 그림일 뿐입니다.
            Rectangle handle = new()
            {
                Width = CustomHandleSize,
                Height = CustomHandleSize,
                RadiusX = 2,
                RadiusY = 2,
                Fill = AccentBrush(),
                IsHitTestVisible = false,
            };
            Canvas.SetLeft(handle, (cell.MaxX * scale) - (CustomHandleSize / 2));
            Canvas.SetTop(handle, (cell.MaxY * scale) - (CustomHandleSize / 2));
            AutomationProperties.SetAutomationId(handle, $"negaflow.print.custom.handle.{slot}");
            PageCanvas.Children.Add(handle);
            customEditorParts.Add(handle);
        }
    }

    private static Brush AccentBrush() =>
        Application.Current.Resources["NegaflowAccentBrush"] as Brush
            ?? new SolidColorBrush(Windows.UI.Color.FromArgb(0xFF, 0x6B, 0x8B, 0xFF));

    private void BeginCustomDrag(PointerRoutedEventArgs args, int slot, bool resize)
    {
        if (workspaceState is not { } state ||
            slot >= state.Current.Print.CustomItems.Count)
        {
            return;
        }
        PreviewTrace.Write(System.FormattableString.Invariant(
            $"custom.begin slot={slot} resize={resize}"));
        bool selectionChanged = selectedCustomItem != slot;
        selectedCustomItem = slot;
        draggingCustomItem = slot;
        draggingCustomResize = resize;
        customDragOrigin = args.GetCurrentPoint(PageCanvas).Position;
        customDragStartRect = state.Current.Print.CustomItems[slot].NormalizedRect;
        _ = PageCanvas.CapturePointer(args.Pointer);
        args.Handled = true;
        if (selectionChanged)
        {
            // 고른 칸이 바뀌면 테두리와 손잡이가 그 칸으로 옮겨 가야 합니다.
            printPreview?.Draw();
        }
    }

    private void OnCustomDragMoved(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (draggingCustomItem < 0 || workspaceState is not { } state)
        {
            return;
        }
        // 내용 영역의 화면 크기로 나눠 비율 변화를 냅니다(macOS `contentRectPoints * scale`).
        if (customContentSize.Width <= 0 || customContentSize.Height <= 0)
        {
            PreviewTrace.Write("custom.move content-size zero");
            return;
        }
        Windows.Foundation.Point now = args.GetCurrentPoint(PageCanvas).Position;
        double dx = (now.X - customDragOrigin.X) / customContentSize.Width;
        double dy = (now.Y - customDragOrigin.Y) / customContentSize.Height;

        PrintRect start = customDragStartRect;
        // macOS 는 아래가 0 인 좌표라 세로 이동을 뒤집지만, 여기 배치는 위가 0 입니다
        // (`PrintPackageLayout.CustomPackagePages` 가 `content.MinY + Y * height`).
        // 화면에서 보이는 움직임은 같습니다.
        PrintRect updated = draggingCustomResize
            ? new PrintRect(
                start.X,
                start.Y,
                // macOS: min(max(start.width + dW, 0.02), 1 - start.minX)
                Math.Clamp(
                    start.Width + dx,
                    CustomMinimumFraction,
                    Math.Max(CustomMinimumFraction, 1 - start.X)),
                // macOS 는 아래 모서리(= 화면의 위)를 붙듭니다. 위가 0 인 좌표에서는 start.Y 가
                // 그대로 남으므로 아래로만 자랍니다.
                Math.Clamp(
                    start.Height + dy,
                    CustomMinimumFraction,
                    Math.Max(CustomMinimumFraction, 1 - start.Y)))
            : new PrintRect(
                Math.Clamp(start.X + dx, 0, Math.Max(0, 1 - start.Width)),
                Math.Clamp(start.Y + dy, 0, Math.Max(0, 1 - start.Height)),
                start.Width,
                start.Height);

        int slot = draggingCustomItem;
        PreviewTrace.Write(System.FormattableString.Invariant(
            $"custom.move slot={slot} d=({dx:F3},{dy:F3}) -> ({updated.X:F3},{updated.Y:F3},{updated.Width:F3},{updated.Height:F3})"));
        state.UpdatePrint(current =>
        {
            if (slot >= current.CustomItems.Count)
            {
                return current;
            }
            List<PrintCustomPackageItem> items = [.. current.CustomItems];
            items[slot] = items[slot] with { NormalizedRect = updated };
            return current with { CustomItems = items };
        });
        // 값만 바꾸면 눈에는 아무 일도 일어나지 않습니다 - 판을 다시 그려야 칸이 따라옵니다.
        // 우측 패널의 가로/세로/너비/높이 숫자도 같은 순간에 따라가야 합니다.
        printInspector?.Apply(state.Current.Print);
        printPreview?.Draw();
        args.Handled = true;
    }

    private void EndCustomDrag(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (draggingCustomItem < 0)
        {
            return;
        }
        draggingCustomItem = -1;
        draggingCustomResize = false;
        // 끌기가 끝나면 저장까지 마칩니다.
        SynchronizePrint();
    }

    /// <summary>
    /// 칸을 하나 더합니다. macOS <c>addCustomItem()</c> 과 같습니다 — 이미 있는 칸 수만큼
    /// 조금씩 어긋나게 놓아 서로 가리지 않고, 맨 위 차례를 받습니다.
    /// </summary>
    internal void OnCustomAddClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is not { } state)
        {
            return;
        }
        int sources = PrintSources.Count;
        state.UpdatePrint(current =>
        {
            if (current.CustomItems.Count >= PrintPackageSettings.MaximumCustomItemCount)
            {
                return current;
            }
            List<PrintCustomPackageItem> items = [.. current.CustomItems];
            int count = items.Count;
            double offset = (count % 5) * 0.05;
            // macOS 는 아래가 0 인 좌표에서 `min(0.55, 0.08 + offset)` 입니다.
            double bottomUpY = Math.Min(0.55, 0.08 + offset);
            items.Add(new PrintCustomPackageItem(
                Math.Min(count, Math.Max(0, sources - 1)),
                new PrintRect(Math.Min(0.55, 0.08 + offset), 1 - bottomUpY - 0.4, 0.4, 0.4))
            {
                ZIndex = items.Count == 0 ? 0 : items.Max(item => item.ZIndex) + 1,
            });
            return current with { CustomItems = items };
        });
        // 새 칸을 바로 고릅니다 — macOS 도 새로 넣은 칸의 서랍을 엽니다.
        selectedCustomItem = state.Current.Print.CustomItems.Count - 1;
        SynchronizePrint();
    }

    /// <summary>
    /// 사용자 패키지를 처음 고른 순간의 배치입니다. macOS
    /// <c>PrintWorkspaceSettingsStore.prepareDefaultCustomPackage(sourceCount:)</c> 와 같습니다.
    /// </summary>
    private void SeedCustomLayoutIfEmpty()
    {
        if (workspaceState is not { } state ||
            state.Current.Print.LayoutMode != PrintLayoutMode.CustomPackage)
        {
            return;
        }
        // 칸이 없는 사진을 가리키면 배치가 통째로 거절돼 판이 사라집니다. 먼저 당깁니다.
        if (PrintCustomPackageSeed.Clamp(
                state.Current.Print.CustomItems,
                PrintSources.Count) is { } clamped)
        {
            PreviewTrace.Write(System.FormattableString.Invariant(
                $"custom.clamp sources={PrintSources.Count} cells={clamped.Count}"));
            state.UpdatePrint(current => current with { CustomItems = clamped });
        }
        if (PrintCustomPackageSeed.Prepare(
                state.Current.Print.CustomItems,
                PrintSources.Count) is not { } items)
        {
            return;
        }
        PreviewTrace.Write(System.FormattableString.Invariant(
            $"custom.seed sources={PrintSources.Count} cells={items.Count}"));
        state.UpdatePrint(current => current with { CustomItems = items });
    }
}
