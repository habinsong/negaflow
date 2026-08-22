using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Library;

/// <summary>한 번의 폴더 적용이 어디까지 갔는지입니다. macOS <c>LibraryTaskProgress</c>.</summary>
public readonly record struct LibraryFolderDevelopmentProgress(int CompletedCount, int TotalCount)
{
    public int Percent => TotalCount == 0 ? 0 : (int)Math.Round(100.0 * CompletedCount / TotalCount);
}

/// <summary>
/// macOS <c>AppModel.configureLibraryFolderDevelopment</c> ·
/// <c>applyLibraryFolderDevelopment</c> — 폴더 머리줄에서 고른 프로세스와 타깃을 그 폴더의
/// 모든 사진에 겁니다.
/// </summary>
/// <remarks>
/// <para>
/// Swift 와 같은 차례입니다: ① 프리뷰 스캔은 뺀다 ② 프로세스(필름 종류·디지털 표시)를 쓴다
/// ③ 타깃을 쓰되 스캐너 프로파일은 타깃·필름 종류에 맞을 때만 남긴다 ④ <b>그러고 나서 한
/// 장씩 다시 현상한다.</b>
/// </para>
/// <para>
/// ④ 가 빠져 있어서 적용을 눌러도 썸네일이 옛 그림 그대로였습니다. 카탈로그 값만 바뀌고
/// 그림을 다시 만들지 않으면 <see cref="ThumbnailService"/> 는 이미 들고 있는 JPEG 를 그대로
/// 내놓기 때문입니다. macOS 는 설정을 다 쓴 뒤 <c>developFrame(preserveThumbnail: false)</c>
/// 로 프레임마다 다시 현상합니다.
/// </para>
/// </remarks>
public static class LibraryFolderDevelopment
{
    /// <summary>
    /// macOS 폴더 머리줄 타깃 고르개가 내는 다섯입니다
    /// (<c>LibraryFolderDevelopmentControls.visibleTargets</c>) — PRINT 와 EXPIRED 는 없습니다.
    /// </summary>
    public static IReadOnlyList<DevelopTarget> VisibleTargets { get; } =
    [
        DevelopTarget.Main,
        DevelopTarget.Noritsu,
        DevelopTarget.Sp3000,
        DevelopTarget.F135,
        DevelopTarget.Hr,
    ];

    /// <summary>
    /// macOS <c>configureLibraryFolderDevelopment</c> — 고른 값을 프레임마다 씁니다.
    /// 돌려주는 것은 실제로 바뀐 프레임의 <b>새</b> 스냅샷입니다.
    /// </summary>
    public static IReadOnlyList<LibraryFrameSnapshot> Configure(
        LibraryHostService host,
        IReadOnlyList<LibraryFrameSnapshot> frames,
        DevelopmentProcess process,
        DevelopTarget target)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(frames);

        // 부르는 쪽이 host.Frames 같은 살아 있는 목록을 넘길 수 있습니다. 편집이 그 목록을
        // 다시 만들면 훑던 중에 깨지므로 먼저 사본을 뜹니다.
        LibraryFrameSnapshot[] targets = [.. frames];
        FilmType filmType = DevelopRouteSelection.FromProcess(process).FilmType;
        List<LibraryFrameSnapshot> configured = new(targets.Length);
        foreach (LibraryFrameSnapshot frame in targets)
        {
            // 필름 룩은 프레임마다 다릅니다. `FromProcess(process)` 만 쓰면 기본값
            // `FilmEmulation.None` 이 실려 나가 **폴더 일괄 적용이 사용자의 필름 룩을
            // 통째로 지웁니다.** macOS `configureLibraryFolderDevelopment` 는 filmType ·
            // isDigitalSource · developTarget · scannerProfileID 만 건드리고 룩은 손대지
            // 않습니다. 현상뷰의 `DevelopRouteEditor.SetProcess` 도 프레임의 룩을 그대로
            // 실어 보냅니다 — 같은 규칙이어야 합니다.
            DevelopRouteSelection selection = DevelopRouteSelection.FromProcess(
                process,
                frame.Route.FilmEmulation,
                frame.Route.FilmEmulationIntensity);
            LibraryFrameError routeError = host.EditRoute(frame.Id, selection);
            if (routeError != LibraryFrameError.None)
            {
                ThumbnailTrace.Write($"configure ROUTE-FAIL {routeError} {frame.Id}");
                continue;
            }

            // 프로세스가 필름 종류를 바꿨으므로 프로파일 판정은 새 종류로 합니다.
            LibraryFrameSnapshot current = Latest(host, frame);
            string? profileId = DevelopTargets.ProfileAfterTargetChange(
                target,
                filmType,
                current.Base.ScannerProfileId);
            LibraryFrameError editError = host.Edit(
                current.Id,
                new LibraryFrameEdit(
                    current.Tone,
                    current.ManualBase,
                    current.Base with { ScannerProfileId = profileId },
                    DevelopTarget: target));
            if (editError != LibraryFrameError.None)
            {
                ThumbnailTrace.Write($"configure EDIT-FAIL {editError} {current.Id}");
                continue;
            }

            // 다시 현상할 때 쓸 것은 편집이 끝난 뒤의 값입니다.
            configured.Add(Latest(host, current));
        }

        return configured;
    }

    /// <summary>
    /// 고른 값을 프레임마다 씁니다. 돌려주는 것은 실제로 바뀐 프레임 수입니다.
    /// </summary>
    public static int Apply(
        LibraryHostService host,
        IReadOnlyList<LibraryFrameSnapshot> frames,
        DevelopmentProcess process,
        DevelopTarget target,
        Action<LibraryFolderDevelopmentProgress>? progress = null)
    {
        ArgumentNullException.ThrowIfNull(frames);
        int total = frames.Count;
        progress?.Invoke(new LibraryFolderDevelopmentProgress(0, total));
        IReadOnlyList<LibraryFrameSnapshot> configured = Configure(host, frames, process, target);
        for (int completed = 1; completed <= total; completed++)
        {
            progress?.Invoke(new LibraryFolderDevelopmentProgress(completed, total));
        }
        return configured.Count;
    }

    /// <summary>
    /// macOS <c>applyLibraryFolderDevelopment</c> — 값을 다 쓴 뒤 프레임마다 다시 현상합니다.
    /// 진행률은 <b>현상 한 장이 끝날 때마다</b> 올라갑니다.
    /// </summary>
    /// <remarks>
    /// macOS 는 렌더 슬롯 수(<c>maxConcurrentDevelopments</c> = 3)만큼 동시에 돌리고 하나가
    /// 끝날 때마다 다음을 넣습니다. <see cref="ThumbnailService"/> 가 이미 같은 수로 묶여
    /// 있으므로 여기서는 전부 걸어 두고 끝나는 대로 세면 같은 동작이 됩니다.
    /// </remarks>
    public static async Task<int> ApplyAsync(
        LibraryHostService host,
        IReadOnlyList<LibraryFrameSnapshot> frames,
        DevelopmentProcess process,
        DevelopTarget target,
        ThumbnailService? thumbnails,
        Action<LibraryFolderDevelopmentProgress>? progress = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(frames);
        int total = frames.Count;
        // 사용자가 적용을 누른 시점에 선택을 먼저 기록합니다. 렌더를 기다린 뒤 기록하면 그
        // 사이 현상뷰에서 더 최근에 고른 값을 오래된 폴더 작업이 덮어씁니다.
        IReadOnlyList<LibraryFrameSnapshot> configured = Configure(host, frames, process, target);
        ThumbnailTrace.Write(
            $"apply begin process={process} target={target} " +
            $"configured={configured.Count}/{total}");
        progress?.Invoke(new LibraryFolderDevelopmentProgress(0, total));
        if (thumbnails is null || configured.Count == 0)
        {
            progress?.Invoke(new LibraryFolderDevelopmentProgress(total, total));
            return configured.Count;
        }

        int completed = 0;
        List<Task> renders = new(configured.Count);
        foreach (LibraryFrameSnapshot frame in configured)
        {
            renders.Add(RenderOneAsync(frame));
        }
        await Task.WhenAll(renders).ConfigureAwait(false);
        if (completed < total)
        {
            progress?.Invoke(new LibraryFolderDevelopmentProgress(total, total));
        }
        return configured.Count;

        async Task RenderOneAsync(LibraryFrameSnapshot frame)
        {
            try
            {
                await thumbnails.RerenderAsync(frame, cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                // 취소는 실패가 아닙니다. 남은 장수만 진행률에서 마저 세 줍니다.
            }
            progress?.Invoke(new LibraryFolderDevelopmentProgress(
                Interlocked.Increment(ref completed),
                total));
        }
    }

    private static LibraryFrameSnapshot Latest(LibraryHostService host, LibraryFrameSnapshot frame) =>
        host.Frames.FirstOrDefault(
            candidate => string.Equals(candidate.Id, frame.Id, StringComparison.Ordinal))
        ?? frame;
}
