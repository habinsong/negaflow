using Negaflow.Catalog;

namespace Negaflow.Shell.Library;

public sealed partial class ThumbnailService
{
    /// <summary>
    /// 이 사진들의 캐시 식별을 백그라운드에서 미리 만듭니다. 목록은 호출한 스레드에서 복사하므로
    /// 라이브러리가 그 뒤에 바뀌어도 됩니다.
    /// </summary>
    public Task PrepareIdentitiesAsync(IReadOnlyList<LibraryFrameSnapshot> frames)
    {
        ArgumentNullException.ThrowIfNull(frames);
        LibraryFrameSnapshot[] copy = [.. frames];
        return Task.Run(() => ThumbnailCacheIdentity.Prepare(copy));
    }
}
