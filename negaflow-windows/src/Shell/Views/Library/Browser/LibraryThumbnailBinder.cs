using Negaflow.Shell.Library;

namespace Negaflow.Shell.Views.Library.Browser;

/// <summary>
/// 목록 항목에 썸네일을 채우는 한 곳입니다. 라이브러리 격자·현상 필름스트립·인화 필름스트립이
/// 모두 같은 캐시를 보므로 채우는 규칙도 하나여야 합니다.
/// </summary>
/// <remarks>
/// <b>캐시에 이미 있으면 그 자리에서 넣어야 합니다.</b> <see cref="ThumbnailService.Request"/>
/// 는 이미 들고 있는 프레임을 그냥 지나가므로 <c>ThumbnailReady</c> 가 오지 않습니다. 목록을
/// 다시 만들 때 요청만 하고 채우지 않으면, <b>캐시가 채워져 있을수록 화면이 비어 보이는</b>
/// 거꾸로 된 동작이 됩니다 — 현상뷰 하단 필름스트립이 폴더 일괄 적용 뒤에 통째로 비던 것이
/// 정확히 이 경우였습니다(적용이 모든 프레임을 캐시에 넣어 두므로 요청이 전부 조기 반환).
/// </remarks>
internal static class LibraryThumbnailBinder
{
    /// <summary>
    /// 캐시에 있으면 지금 채우고, 없으면 렌더를 청합니다. 돌려주는 것은 그 자리에서 채운 수입니다.
    /// </summary>
    internal static int Hydrate(
        ThumbnailService? thumbnails,
        IReadOnlyList<LibraryFrameListItem> items,
        string trace)
    {
        ArgumentNullException.ThrowIfNull(items);
        int filled = 0;
        int requested = 0;
        foreach (LibraryFrameListItem item in items)
        {
            if (Hydrate(thumbnails, item))
            {
                ++filled;
            }
            else
            {
                ++requested;
            }
        }
        ThumbnailTrace.Write(
            $"{trace,-9} hydrate items={items.Count} filled={filled} requested={requested}");
        return filled;
    }

    /// <summary><see langword="true"/> 면 그 자리에서 채웠고, 아니면 렌더를 청했습니다.</summary>
    internal static bool Hydrate(ThumbnailService? thumbnails, LibraryFrameListItem item)
    {
        ArgumentNullException.ThrowIfNull(item);
        if (thumbnails is null)
        {
            return false;
        }
        if (thumbnails.TryGetOrLoad(item.Id) is { } jpeg)
        {
            item.Thumbnail = LibraryThumbnails.Decode(jpeg);
            return true;
        }
        item.Thumbnail = null;
        thumbnails.Request(item.Frame);
        return false;
    }
}
