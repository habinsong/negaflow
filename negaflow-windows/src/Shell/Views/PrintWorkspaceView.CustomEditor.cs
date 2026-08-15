using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Print;

namespace Negaflow.Shell.Views;

/// <summary>
/// 커스텀 배치를 마우스로 놓는 편집기입니다.
/// </summary>
/// <remarks>
/// 끌어 옮기는 동안에도 **자리는 비율로** 다룹니다. 화소로 옮겼다가 마지막에 나누면 용지를
/// 바꾼 뒤 배치가 미세하게 어긋나고, 그 어긋남은 여러 번 옮길수록 쌓입니다.
///
/// 칸은 내용 영역 안에 갇힙니다 — 판 밖으로 나간 칸은 배치 자체를 거절당하므로, 끌다가
/// 나가는 것을 막는 편이 끌고 나서 거절당하는 것보다 낫습니다.
/// </remarks>
public sealed partial class PrintWorkspaceView
{
    /// <summary>손잡이 크기입니다. 이보다 작으면 마우스로 잡기 어렵습니다.</summary>
    private const double CustomHandleSize = 12;

    /// <summary>칸의 최소 크기입니다(비율). 0 이 되면 다시 잡을 수 없습니다.</summary>
    private const double CustomMinimumFraction = 0.05;

    private int draggingCustomItem = -1;
    private bool draggingCustomResize;
    private Windows.Foundation.Point customDragOrigin;
    private PrintRect customDragStartRect;

    /// <summary>편집기가 그린 것들입니다. 판을 다시 그릴 때 함께 지웁니다.</summary>
    private readonly List<FrameworkElement> customEditorParts = [];

    /// <summary>
    /// 커스텀 배치 모드에서 칸 테두리와 손잡이를 얹습니다. 다른 모드에서는 아무것도 하지
    /// 않습니다 — 컨택트 시트의 칸은 행·열이 정하므로 끌 수 없습니다.
    /// </summary>
    private void DrawCustomEditor(PrintPackagePageLayout page, double scale)
    {
        foreach (FrameworkElement part in customEditorParts)
        {
            PageCanvas.Children.Remove(part);
        }
        customEditorParts.Clear();
        if (workspaceState is not { } state ||
            state.Current.Print.LayoutMode != PrintLayoutMode.CustomPackage)
        {
            return;
        }

        for (int index = 0; index < page.Items.Count; ++index)
        {
            PrintRect cell = page.Items[index].CellRect;
            int slot = index;
            Rectangle border = new()
            {
                Width = Math.Max(1, cell.Width * scale),
                Height = Math.Max(1, cell.Height * scale),
                Stroke = new SolidColorBrush(Windows.UI.Color.FromArgb(0xCC, 0x6B, 0x8B, 0xFF)),
                StrokeThickness = 1,
                Fill = new SolidColorBrush(Windows.UI.Color.FromArgb(0x14, 0x6B, 0x8B, 0xFF)),
            };
            Canvas.SetLeft(border, cell.X * scale);
            Canvas.SetTop(border, cell.Y * scale);
            AutomationProperties.SetAutomationId(border, $"negaflow.print.custom.cell.{slot}");
            border.PointerPressed += (sender, args) =>
                BeginCustomDrag(sender, args, slot, resize: false);
            border.PointerMoved += OnCustomDragMoved;
            border.PointerReleased += EndCustomDrag;
            border.PointerCaptureLost += EndCustomDrag;
            PageCanvas.Children.Add(border);
            customEditorParts.Add(border);

            // 오른쪽 아래 손잡이로 크기를 바꿉니다. macOS 도 한 모서리만 씁니다.
            Rectangle handle = new()
            {
                Width = CustomHandleSize,
                Height = CustomHandleSize,
                Fill = new SolidColorBrush(Windows.UI.Color.FromArgb(0xFF, 0x6B, 0x8B, 0xFF)),
            };
            Canvas.SetLeft(handle, (cell.MaxX * scale) - CustomHandleSize);
            Canvas.SetTop(handle, (cell.MaxY * scale) - CustomHandleSize);
            AutomationProperties.SetAutomationId(handle, $"negaflow.print.custom.handle.{slot}");
            handle.PointerPressed += (sender, args) =>
                BeginCustomDrag(sender, args, slot, resize: true);
            handle.PointerMoved += OnCustomDragMoved;
            handle.PointerReleased += EndCustomDrag;
            handle.PointerCaptureLost += EndCustomDrag;
            PageCanvas.Children.Add(handle);
            customEditorParts.Add(handle);
        }
    }

    private void BeginCustomDrag(object sender, PointerRoutedEventArgs args, int slot, bool resize)
    {
        if (workspaceState is not { } state ||
            slot >= state.Current.Print.CustomItems.Count ||
            sender is not UIElement element)
        {
            return;
        }
        draggingCustomItem = slot;
        draggingCustomResize = resize;
        customDragOrigin = args.GetCurrentPoint(PageCanvas).Position;
        customDragStartRect = state.Current.Print.CustomItems[slot].NormalizedRect;
        _ = element.CapturePointer(args.Pointer);
        args.Handled = true;
    }

    private void OnCustomDragMoved(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        if (draggingCustomItem < 0 || workspaceState is not { } state)
        {
            return;
        }
        // 내용 영역의 화면 크기로 나눠 비율 변화를 냅니다.
        if (CustomContentSize() is not { } size || size.Width <= 0 || size.Height <= 0)
        {
            return;
        }
        Windows.Foundation.Point now = args.GetCurrentPoint(PageCanvas).Position;
        double dx = (now.X - customDragOrigin.X) / size.Width;
        double dy = (now.Y - customDragOrigin.Y) / size.Height;

        PrintRect start = customDragStartRect;
        PrintRect updated = draggingCustomResize
            ? new PrintRect(
                start.X,
                start.Y,
                Math.Clamp(start.Width + dx, CustomMinimumFraction, 1 - start.X),
                Math.Clamp(start.Height + dy, CustomMinimumFraction, 1 - start.Y))
            : new PrintRect(
                Math.Clamp(start.X + dx, 0, 1 - start.Width),
                Math.Clamp(start.Y + dy, 0, 1 - start.Height),
                start.Width,
                start.Height);

        int slot = draggingCustomItem;
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
        args.Handled = true;
    }

    private void EndCustomDrag(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        draggingCustomItem = -1;
        draggingCustomResize = false;
    }

    /// <summary>내용 영역이 화면에서 차지하는 크기입니다. 비율을 화소로 옮길 때 씁니다.</summary>
    private Windows.Foundation.Size? CustomContentSize()
    {
        if (workspaceState is not { } state || PrintSources.Count == 0)
        {
            return null;
        }
        PrintSizeMm source = SourcePixelSize(PrintSources[0]);
        PrintCompositionSettings composition = state.Current.Print.Composition(
            source.Height > 0 ? source.Width / source.Height : null);
        if (PrintPackageLayout.Make(
                [.. PrintSources.Select(SourcePixelSize)],
                composition,
                state.Current.Print.Package()) is not { Count: > 0 } pages)
        {
            return null;
        }
        double scale = PreviewScale(pages[0].CanvasSize);
        return new Windows.Foundation.Size(
            pages[0].ContentRect.Width * scale,
            pages[0].ContentRect.Height * scale);
    }

    /// <summary>
    /// 고른 사진마다 칸을 하나씩 놓습니다. 배치가 비어 있으면 커스텀 모드가 아무것도 그리지
    /// 못하므로, 모드를 고른 순간 쓸 수 있는 배치가 있어야 합니다.
    /// </summary>
    private void SeedCustomLayoutIfEmpty()
    {
        if (workspaceState is not { } state ||
            state.Current.Print.LayoutMode != PrintLayoutMode.CustomPackage ||
            state.Current.Print.CustomItems.Count > 0)
        {
            return;
        }
        int count = Math.Max(1, Math.Min(PrintSources.Count, 4));
        List<PrintCustomPackageItem> items = new(count);
        for (int index = 0; index < count; ++index)
        {
            // 2×2 를 시작 자리로 둡니다. 사용자는 여기서부터 끌어 옮깁니다.
            items.Add(new PrintCustomPackageItem(
                index,
                new PrintRect(
                    (index % 2) * 0.5,
                    (index / 2) * 0.5,
                    0.5,
                    0.5)));
        }
        state.UpdatePrint(current => current with { CustomItems = items });
    }

    private void OnCustomAddClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is not { } state || PrintSources.Count == 0)
        {
            return;
        }
        state.UpdatePrint(current =>
        {
            if (current.CustomItems.Count >= PrintPackageSettings.MaximumCustomItems)
            {
                return current;
            }
            List<PrintCustomPackageItem> items = [.. current.CustomItems];
            // 새 칸은 가운데 작게 놓습니다 — 기존 칸을 가리지 않으면서 바로 눈에 띕니다.
            items.Add(new PrintCustomPackageItem(
                items.Count % Math.Max(1, PrintSources.Count),
                new PrintRect(0.3, 0.3, 0.4, 0.4))
            {
                ZIndex = items.Count,
            });
            return current with { CustomItems = items };
        });
        SynchronizePrint();
    }

    private void OnCustomRemoveClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.UpdatePrint(current =>
        {
            if (current.CustomItems.Count <= 1)
            {
                // 마지막 칸은 남깁니다. 빈 배치는 판을 만들지 못해 화면이 빕니다.
                return current;
            }
            List<PrintCustomPackageItem> items = [.. current.CustomItems];
            items.RemoveAt(items.Count - 1);
            return current with { CustomItems = items };
        });
        SynchronizePrint();
    }

    private void LocalizeCustomEditor()
    {
        CustomAddButton.Content = AppResources.Get("printCustomAdd", "Content");
        CustomRemoveButton.Content = AppResources.Get("printCustomRemove", "Content");
        CustomSectionText.Text = AppResources.Get("printModeCustomPackage", "Text");
    }
}
