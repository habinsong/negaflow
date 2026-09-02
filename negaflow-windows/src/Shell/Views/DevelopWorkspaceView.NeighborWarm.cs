using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;

namespace Negaflow.Shell.Views;

/// <summary>
/// 지금 보고 있는 사진의 <b>바로 앞뒤 한 장씩</b>을 정착 뒤에 미리 현상해 둡니다.
/// </summary>
/// <remarks>
/// <para>
/// macOS 는 고른 한 장만 현상합니다(<c>AppModel+FrameSelection.handleSelectedFrameChange</c>).
/// 여기 두 장은 그것을 넘는 자리이며, 그렇게 하기로 한 근거는 실측과 사용자 지시입니다 —
/// <c>dev-notes/performance-optimization/02-photo-switching.md</c> 의 "메모리 절감보다 사진
/// 선택 속도를 우선합니다. foreground GPU 풀과 현재·인접 정착 캐시는 유지하며".
/// 필름 한 롤을 훑는 작업은 좌우 이동이 대부분이라 이 두 장이 곧 다음 화면입니다.
/// </para>
/// <para>
/// <b>두 장에서 멈추는 것이 이 파일의 전부입니다.</b> 앞 판은 같은 이름으로 라이브러리
/// <b>전체</b>를 돌았습니다. 실측(2026-09-02, 114장): 정착 한 번마다 6~7분 동안 쉬지 않고
/// 디코딩했고, private 이 천장 8,959MB 를 넘겨 9,890MB 까지 올라가 앞단 raw 예산이
/// 2,910MB → 1,324MB 로 깎였습니다. 그래서 정작 사용자가 고른 사진이 매번 캐시 미스였고,
/// 14회 전환에서 먼 예열이 만든 적중은 <b>0회</b>였습니다. 이득은 이웃 두 장뿐이었는데
/// 비용은 전체였습니다.
/// </para>
/// <para>
/// 그래서 여기서는 <b>거리 1 만</b> 보고, 그것도 <b>설정 · 메모리의 프레임 캐시 한도
/// (자동/수동)가 허락하는 만큼만</b> 채웁니다
/// (<see cref="ThumbnailService.SpareDevelopedSlots"/>). 상주 목록은 macOS
/// <c>trimDeveloped</c> 와 같은 FIFO 라 넘겨 채우면 방금 예열한 것이 앞에서 그대로
/// 나갑니다 — 디코딩만 하고 남는 것이 없습니다. 사진을 옮겨 다니면 오래된 것부터
/// 나가고 새 것이 들어옵니다. 보고 있는 사진은 <c>SelectedFrameId</c> 로 지켜집니다.
/// </para>
/// <para>
/// 디스크에는 아무것도 남기지 않습니다 — 현상 프리뷰 디스크 캐시는 맥에 없는 창작이라
/// 걷어냈습니다(<see cref="StaleCacheFolders"/>). 새 선택이 들어오면 즉시 취소합니다.
/// 사용자가 지금 보려는 화면이 언제나 먼저입니다.
/// </para>
/// </remarks>
public sealed partial class DevelopWorkspaceView
{
    /// <summary>정착 뒤 미리 현상해 둘 이웃까지의 거리입니다. 좌우 각 한 장.</summary>
    private const int NeighborWarmDistance = 1;

    private DevelopRun? neighborWarmRun;
    private Task neighborWarmTask = Task.CompletedTask;

    private void WarmNeighborSettledPreviews(LibraryFrameSnapshot current)
    {
        if (libraryHost is null || thumbnails is null)
        {
            return;
        }
        IReadOnlyList<LibraryFrameSnapshot> all = libraryHost.Frames;
        int index = -1;
        for (int i = 0; i < all.Count; ++i)
        {
            if (string.Equals(all[i].Id, current.Id, StringComparison.Ordinal))
            {
                index = i;
                break;
            }
        }
        if (index < 0)
        {
            return;
        }
        // 설정 · 메모리의 프레임 캐시 한도(자동/수동)가 허락하는 만큼만 채웁니다.
        // 넘겨 채우면 FIFO 가 앞부터 내보내므로 방금 예열한 것이 그대로 나갑니다.
        long bytesPerFrame = thumbnails.TryGetDeveloped(current, out var shown)
            ? (long)shown.Pixels.Length
            : 0L;
        int spare = thumbnails.SpareDevelopedSlots(bytesPerFrame);
        if (spare <= 0)
        {
            PreviewTrace.Write("warm preview skip: no spare developed slot");
            return;
        }
        List<LibraryFrameSnapshot> warmOrder = [];
        for (int distance = 1; distance <= NeighborWarmDistance; ++distance)
        {
            if (index - distance >= 0)
            {
                warmOrder.Add(all[index - distance]);
            }
            if (index + distance < all.Count)
            {
                warmOrder.Add(all[index + distance]);
            }
        }
        if (warmOrder.Count > spare)
        {
            warmOrder.RemoveRange(spare, warmOrder.Count - spare);
        }
        if (warmOrder.Count == 0)
        {
            return;
        }

        uint edge = DevelopPreviewProxy.BufferEdge(DevelopPreviewProxy.FullMaxDimension);
        DevelopRun run = new();
        System.Threading.Interlocked.Exchange(ref neighborWarmRun, run)?.Cancel();
        Task previousWarmTask = neighborWarmTask;
        neighborWarmTask = Task.Run(() =>
        {
            try
            {
                previousWarmTask.GetAwaiter().GetResult();
            }
            catch
            {
                // 앞 예열이 어떻게 끝났든 이번 예열은 그대로 갑니다.
            }
            ThreadPriority previousPriority = Thread.CurrentThread.Priority;
            bool priorityChanged = false;
            try
            {
                try
                {
                    Thread.CurrentThread.Priority = ThreadPriority.BelowNormal;
                    priorityChanged = true;
                }
                catch (Exception error) when (error is ThreadStateException or
                    System.Security.SecurityException)
                {
                }
                int pixelBytes = checked((int)((ulong)edge * edge * 4UL));
                byte[] pixels = new byte[pixelBytes];
                foreach (LibraryFrameSnapshot neighbor in warmOrder)
                {
                    if (run.IsCancelRequested)
                    {
                        break;
                    }
                    WarmSettledPreview(neighbor, edge, pixels, run);
                }
            }
            finally
            {
                if (priorityChanged)
                {
                    try
                    {
                        Thread.CurrentThread.Priority = previousPriority;
                    }
                    catch (Exception error) when (error is ThreadStateException or
                        System.Security.SecurityException)
                    {
                    }
                }
                _ = System.Threading.Interlocked.CompareExchange(
                    ref neighborWarmRun, null, run);
                run.Dispose();
            }
        });
    }

    /// <summary>새 선택이 오면 부릅니다. 기다리지 않고 취소만 겁니다.</summary>
    private void CancelNeighborWarm() =>
        System.Threading.Interlocked.Exchange(ref neighborWarmRun, null)?.Cancel();

    private async Task CancelNeighborWarmAsync()
    {
        CancelNeighborWarm();
        Task running = neighborWarmTask;
        try
        {
            await running;
        }
        catch
        {
            // 종료 중입니다. 예열이 어떻게 끝났는지는 더 볼 것이 없습니다.
        }
        if (ReferenceEquals(neighborWarmTask, running))
        {
            neighborWarmTask = Task.CompletedTask;
        }
    }

    private void WarmSettledPreview(
        LibraryFrameSnapshot? frame,
        uint edge,
        byte[] pixels,
        DevelopRun run)
    {
        if (frame is null || frame.SourcePath is not { Length: > 0 } path)
        {
            return;
        }
        try
        {
            if (thumbnails?.TryGetDeveloped(frame, out var cached) == true && cached.Settled)
            {
                PreviewTrace.Write(
                    "warm preview cache HIT " + cached.Width + "x" + cached.Height + " " + path);
                return;
            }
            // 목적지는 쓰이지 않습니다 — 프리뷰 요청이라 파일을 내보내지 않습니다.
            string unused = Path.ChangeExtension(path, ".warm-decode.png");
            if (DevelopRequestFactory.Create(frame, unused).Request is not { } request)
            {
                return;
            }
            DevelopedPreviewCacheIdentity? identity =
                ThumbnailService.CaptureDevelopedCacheIdentity(frame);
            PreviewTrace.Write("warm preview start edge=" + edge + " " + path);
            NativeDevelopExporterAdapter exporter = new();
            DevelopExportResult result = exporter.Preview(request, edge, edge, pixels, run);
            PreviewTrace.Write(
                "warm preview end ok=" + result.Succeeded +
                " cancel=" + result.Cancelled +
                " fail=" + (result.FailureName ?? ""));
            if (result.Succeeded && result.ImageWidth > 0U && result.ImageHeight > 0U)
            {
                thumbnails?.RememberDeveloped(
                    frame,
                    pixels,
                    (int)result.ImageWidth,
                    (int)result.ImageHeight,
                    settled: true,
                    identity);
            }
        }
        catch (Exception error)
        {
            PreviewTrace.Write("warm preview fault " + error.GetType().Name);
        }
    }
}
