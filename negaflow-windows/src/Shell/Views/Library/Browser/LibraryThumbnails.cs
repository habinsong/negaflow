using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Negaflow.Shell.Library;

namespace Negaflow.Shell.Views.Library.Browser;

/// <summary>격자 카드 썸네일 디코드입니다. 선택·메뉴와 다른 이유입니다.</summary>
internal sealed class LibraryThumbnails
{
    private readonly LibraryWorkspaceView view;

    internal LibraryThumbnails(LibraryWorkspaceView view) => this.view = view;

    /// <summary>
    /// 카드 크기는 macOS 와 같은 규칙입니다 — 폭 190·배율, 썸네일은 (폭 − 안쪽 여백) / 1.5,
    /// 그 아래 이름·필름 종류·별점이 고정 높이로 붙습니다.
    /// </summary>
    internal void OnContainerChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        _ = sender;
        // 재활용되는 카드의 비트맵은 놓아 줍니다. 놓지 않으면 스크롤한 만큼 디코드된 썸네일이
        // 계속 쌓입니다 — 1,500장에서 1.2GB 를 쓰던 원인이 이것이었습니다.
        if (args.InRecycleQueue)
        {
            if (args.Item is LibraryFrameListItem recycled)
            {
                recycled.Thumbnail = null;
            }
            return;
        }
        if (args.ItemContainer is not GridViewItem container)
        {
            return;
        }
        container.Width = LibraryCardMetrics.Width;
        container.Height = LibraryCardMetrics.Height;
        container.Margin = new Thickness(LibraryCardMetrics.Spacing / 2.0);
        container.Padding = new Thickness(0.0);
        container.CornerRadius = new CornerRadius(9.0);

        if (args.Item is LibraryFrameListItem item)
        {
            // realize 된 카드만 디코드하고, 아직 없는 것만 렌더를 요청합니다.
            Realize(item);
            view.thumbnails?.Request(item.Frame);
        }
    }

    /// <summary>
    /// 카드가 화면에 realize 될 때만 썸네일을 디코드합니다.
    /// </summary>
    /// <remarks>
    /// 예전에는 목록을 다시 만들 때마다 <b>전체</b> 항목을 디코드했습니다. 별점 하나만 바꿔도
    /// 그리드 전부가 다시 디코드됐고, 화면에 없는 카드의 비트맵까지 메모리에 남았습니다.
    /// 200장에서 이미 눈에 띄었으므로 수천 장이면 문제가 됩니다. 지금은 컨테이너가 만들어질 때
    /// 그 한 장만 디코드하고, 이미 디코드된 항목은 그대로 둡니다.
    /// </remarks>
    internal void Realize(LibraryFrameListItem item)
    {
        if (view.thumbnails is null || item.HasThumbnail)
        {
            return;
        }
        if (view.thumbnails.TryGet(item.Id) is { } jpeg)
        {
            item.Thumbnail = Decode(jpeg);
        }
    }

    internal void OnReady(string frameId)
    {
        if (view.thumbnails?.TryGet(frameId) is not { } jpeg)
        {
            ThumbnailTrace.Write($"lib.ready NO-BYTES {frameId}");
            return;
        }
        foreach (LibraryFrameListItem item in view.allItems)
        {
            if (!string.Equals(item.Id, frameId, StringComparison.Ordinal))
            {
                continue;
            }
            item.Thumbnail = Decode(jpeg);
            ThumbnailTrace.Write($"lib.ready applied  {frameId}");
            return;
        }
        ThumbnailTrace.Write($"lib.ready NOT-IN-LIST {frameId} allItems={view.allItems.Count}");
    }

    /// <summary>
    /// JPEG 바이트를 그대로 <c>BitmapImage</c> 에 흘려 넣습니다. 디코드는 WinUI 가 필요할 때
    /// 하므로, 화면 밖 카드까지 미리 펼쳐 두지 않습니다.
    /// </summary>
    internal static BitmapImage? Decode(byte[] jpeg)
    {
        try
        {
            var stream = new Windows.Storage.Streams.InMemoryRandomAccessStream();
            using (var writer = new Windows.Storage.Streams.DataWriter(stream.GetOutputStreamAt(0UL)))
            {
                writer.WriteBytes(jpeg);
                _ = writer.StoreAsync().AsTask().GetAwaiter().GetResult();
            }
            var bitmap = new BitmapImage();
            stream.Seek(0UL);
            bitmap.SetSource(stream);
            return bitmap;
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return null;
        }
    }
}
