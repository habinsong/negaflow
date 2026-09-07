using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Library;

/// <summary>
/// 한 번의 폴더 적용이 어디까지 갔는지입니다. macOS <c>LibraryTaskProgress</c> 그대로 —
/// 센 것과 전체, 둘뿐입니다.
/// </summary>
/// <remarks>
/// 예전에는 <c>FailedCount</c> 도 들고 다녔습니다. macOS 에 없는 Windows 전용이었고, 실패로
/// 세던 것이 실은 <b>밀린 렌더</b>였습니다 — <see cref="ThumbnailService.RerenderAsync"/> 는
/// 그 사이 같은 프레임에 더 새 티켓이 걸리면 자기 결과를 버리고 <c>false</c> 를 냅니다.
/// 실패가 아니라 "곧 새 것이 온다"는 뜻인데, 화면에는 "적용 실패"로 나갔습니다. macOS
/// <c>developLibraryFolderFrame</c> 은 아무것도 돌려주지 않고, 그룹 작업이 끝나면 그저 하나
/// 올립니다 — 여기도 같게 둡니다.
/// </remarks>
public readonly record struct LibraryFolderDevelopmentProgress
{
    public LibraryFolderDevelopmentProgress(int completedCount, int totalCount)
    {
        TotalCount = Math.Max(0, totalCount);
        CompletedCount = Math.Min(Math.Max(0, completedCount), TotalCount);
    }

    public int CompletedCount { get; }

    public int TotalCount { get; }

    /// <summary>macOS <c>fraction</c>.</summary>
    public double Fraction => TotalCount == 0 ? 0.0 : (double)CompletedCount / TotalCount;

    /// <summary>
    /// macOS <c>percent</c> — <c>Int((fraction * 100).rounded())</c> 입니다. Swift 의
    /// <c>rounded()</c> 는 0.5 를 0 에서 <b>먼 쪽</b>으로 올립니다. <c>Math.Round</c> 의 기본은
    /// 짝수로 붙이므로, 여덟 장 중 한 장(12.5%)에서 맥은 13% 여기는 12% 로 갈렸습니다.
    /// </summary>
    public int Percent => (int)Math.Round(Fraction * 100.0, MidpointRounding.AwayFromZero);
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
    /// macOS 폴더 머리줄 타깃 고르개와 같은 기존 5개와 Custom 18개입니다
    /// (<c>LibraryFolderDevelopmentControls.visibleTargets</c>) — PRINT 와 EXPIRED 는 없습니다.
    /// </summary>
    public static IReadOnlyList<DevelopTarget> VisibleTargets { get; } =
    [
        DevelopTarget.Main,
        DevelopTarget.Noritsu,
        DevelopTarget.Sp3000,
        DevelopTarget.F135,
        DevelopTarget.Hr,
        .. DevelopTargets.Custom,
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
        LibraryFrameSnapshot[] targets = [.. frames.Where(frame => !frame.IsPreviewScan)];
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
        // macOS 는 프리뷰 스캔을 <b>먼저 걸러낸 뒤</b> 그 수를 분모로 씁니다
        // (`applyLibraryFolderDevelopment` 의 `frames.count`). 프리뷰까지 세면 폴더에 임시
        // 스캔이 하나 섞여 있을 때 맥은 "2/2" 로 끝나는 자리가 여기서는 "2/3" 이 됩니다.
        int total = frames.Count(frame => !frame.IsPreviewScan);
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
        // macOS 는 프리뷰 스캔을 <b>먼저 걸러낸 뒤</b> 그 수를 분모로 씁니다
        // (`applyLibraryFolderDevelopment` 의 `frames.count`). 프리뷰까지 세면 폴더에 임시
        // 스캔이 하나 섞여 있을 때 맥은 "2/2" 로 끝나는 자리가 여기서는 "2/3" 이 됩니다.
        int total = frames.Count(frame => !frame.IsPreviewScan);
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
        // macOS 는 `while await group.next()` 한 흐름에서 세고 곧바로 알립니다 - 값과 보고가 같은
        // 차례로 나갑니다. 세는 일과 알리는 일을 렌더 작업마다 흩어 놓으면 `Interlocked` 로
        // 값은 맞아도 <b>부르는 차례가 뒤집혀</b>, 막대가 뒤로 가고 마지막이 50% 로 끝납니다.
        Lock gate = new();
        List<Task> renders = new(configured.Count);
        foreach (LibraryFrameSnapshot frame in configured)
        {
            renders.Add(RenderOneAsync(frame));
        }
        await Task.WhenAll(renders).ConfigureAwait(false);
        lock (gate)
        {
            if (completed < total)
            {
                progress?.Invoke(new LibraryFolderDevelopmentProgress(total, total));
            }
        }

        return configured.Count;

        async Task RenderOneAsync(LibraryFrameSnapshot frame)
        {
            // macOS `developLibraryFolderFrame` 은 아무것도 돌려주지 않습니다. 렌더가 밀렸든
            // 실패했든 그룹 작업이 끝나면 하나 올릴 뿐입니다 - 여기도 같습니다.
            try
            {
                _ = await thumbnails.RerenderAsync(frame, cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }

            lock (gate)
            {
                progress?.Invoke(new LibraryFolderDevelopmentProgress(++completed, total));
            }
        }
    }

    private static LibraryFrameSnapshot Latest(LibraryHostService host, LibraryFrameSnapshot frame) =>
        host.Frames.FirstOrDefault(
            candidate => string.Equals(candidate.Id, frame.Id, StringComparison.Ordinal))
        ?? frame;
}
