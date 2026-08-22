using System.Collections.Concurrent;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Print;

namespace Negaflow.Shell.Library;

/// <summary>
/// BGRA8 픽셀을 썸네일 JPEG 로 만드는 플랫폼 코덱입니다. Shell.Core 는 WIC 를 참조하지 않으므로
/// 여기만 열어 두고 셸이 채웁니다 — 그래야 이 정책이 XAML 없이 시험됩니다.
/// </summary>
public interface IThumbnailCodec
{
    /// <returns>JPEG 바이트, 인코딩하지 못하면 null. 크기 조정은 하지 않습니다.</returns>
    byte[]? EncodeJpeg(byte[] bgra, int width, int height);
}

/// <summary>
/// 라이브러리 그리드와 필름스트립이 쓰는 썸네일입니다. 메모리 → 디스크 → 현상 순으로 찾고,
/// 만든 것은 디스크에 남겨 다음 실행에서 즉시 복원합니다.
/// </summary>
/// <remarks>
/// <para>
/// 그리드는 프레임 수백 장을 한 번에 요청합니다. 전부 동시에 현상하면 엔진과 IO 가 같이 밀려
/// 창 전체가 멎으므로, macOS 와 같은 폭 3 으로 제한합니다. 같은 프레임의 중복 요청은 하나로
/// 합칩니다.
/// </para>
/// <para>
/// 이미 현상된 프레임은 <see cref="Publish"/> 로 정착 픽셀을 그대로 받습니다. 미리보기가 이미
/// 만든 그림을 썸네일 때문에 다시 현상하지 않기 위해서입니다.
/// </para>
/// </remarks>
public sealed class ThumbnailService : IAsyncDisposable
{
    /// <summary>macOS <c>DevelopFrameRenderer.thumbnailMaxDimension</c> 와 같은 값입니다.</summary>
    public const int MaximumDimension = 360;

    private const int MaximumConcurrentRenders = 3;

    private readonly IDevelopExporter exporter;
    private readonly IThumbnailCodec codec;
    private readonly IUiDispatcher dispatcher;
    private readonly ThumbnailDiskCache disk;
    private readonly DevelopedPreviewDiskCache developedDisk;
    private readonly string root;
    private readonly SemaphoreSlim renderSlots = new(MaximumConcurrentRenders, MaximumConcurrentRenders);
    private readonly ConcurrentDictionary<string, byte[]> memory = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, Task> inFlight = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, DevelopedPreview> developed = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, DevelopedPreviewCacheIdentity> developedIdentities =
        new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, Task> developedInFlight = new(StringComparer.Ordinal);

    /// <summary>
    /// macOS <c>FrameCacheManager.residentDevelopedIDs</c>. 이것이 없어서
    /// <see cref="developed"/> 가 한 번 방문한 프레임의 전체 해상도 BGRA 를 <b>영구히</b>
    /// 들고 있었습니다 — 3600×2406 이면 프레임당 34.6MB 라, 사진을 옮겨 다니면 그대로 쌓여
    /// 네이티브 할당이 실패하고 앱이 죽었습니다.
    /// </summary>
    private readonly FrameResidency developedResidency;
    private FrameCachePolicy developedPolicy;
    private long developedByteLimit;

    /// <summary>현상 미리보기 화소입니다. 인화 판은 360 JPEG 가 아니라 이것을 먼저 씁니다.</summary>
    public readonly record struct DevelopedPreview(
        byte[] Pixels,
        int Width,
        int Height,
        bool Settled);

    public ThumbnailService(
        IDevelopExporter exporter,
        IThumbnailCodec codec,
        IUiDispatcher dispatcher,
        string thumbnailRoot,
        string developedPreviewRoot)
    {
        ArgumentNullException.ThrowIfNull(exporter);
        ArgumentNullException.ThrowIfNull(codec);
        ArgumentNullException.ThrowIfNull(dispatcher);
        ArgumentException.ThrowIfNullOrWhiteSpace(thumbnailRoot);
        ArgumentException.ThrowIfNullOrWhiteSpace(developedPreviewRoot);

        this.exporter = exporter;
        this.codec = codec;
        this.dispatcher = dispatcher;
        root = thumbnailRoot;
        disk = new ThumbnailDiskCache();
        developedDisk = new DevelopedPreviewDiskCache(developedPreviewRoot);
        installedMemoryBytes = InstalledMemoryBytes();
        FrameCacheLimits limits = FrameCacheBudget.AutomaticLimits(installedMemoryBytes);
        developedByteLimit = FrameCacheBudget.DevelopedDisplayBudgetBytes(limits);
        developedPolicy = new FrameCachePolicy(limits);
        developedResidency = new FrameResidency(limits.Developed, developedByteLimit);
    }

    private readonly ulong installedMemoryBytes;

    /// <summary>이 기계의 설치 메모리입니다. 설정 화면이 자동 한도를 계산할 때 씁니다.</summary>
    public ulong InstalledMemory => installedMemoryBytes;

    /// <summary>
    /// 설정에서 고른 상주 한도를 적용합니다. macOS <c>FrameCacheResidencyStore.onLimitsChange</c>
    /// 가 <c>FrameCacheManager</c> 에 반영하는 자리와 같습니다.
    /// </summary>
    /// <remarks>
    /// <para>
    /// 캐시가 하는 일은 그대로입니다 — **상한만** 바꿉니다. 한도를 낮추면 다음 축출에서
    /// 오래된 프레임부터 내려놓고, 올리면 그만큼 더 담습니다.
    /// </para>
    /// <para>
    /// 상주 캐시는 여기 하나가 아닙니다. 엔진도 디코드한 원본(macOS <c>cleanedRawImage</c>)과
    /// 프리뷰 raw 프록시(macOS <c>developed</c> 몫)를 들고 있고, 그 둘은 <b>설치 메모리만</b>
    /// 보고 예산을 정하고 있었습니다 — 설정에서 무엇을 골라도 엔진 쪽은 그대로였습니다.
    /// 같은 한도를 그쪽에도 겁니다. macOS 는 <c>FrameCacheManager</c> 하나가 두 몫을 함께
    /// 들고 있어 자리가 하나입니다.
    /// </para>
    /// </remarks>
    public void ApplyResidencySettings(FrameCacheResidencySettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        FrameCacheLimits limits = settings.EffectiveLimits(installedMemoryBytes);
        developedByteLimit = FrameCacheBudget.DevelopedDisplayBudgetBytes(limits);
        developedPolicy = new FrameCachePolicy(limits);
        developedResidency.SetLimits(limits.Developed, developedByteLimit, EvictDeveloped);
        // 엔진을 못 부르는 것은 캐시 상한 하나가 자동으로 남는다는 뜻뿐입니다. 그것 때문에
        // 설정 창이나 시작을 세우지 않습니다 — 대신 걸렸는지를 남겨 진단이 볼 수 있게 합니다.
        NativeResidencyLimitsApplied =
            FrameCacheLimitsBridge.Apply(limits.CleanedRaw, limits.Developed);
    }

    /// <summary>
    /// 엔진 캐시에도 한도를 걸었는지입니다. 엔진을 못 부르면 엔진은 자동 예산으로 계속 돕니다 —
    /// 진단이 "설정이 엔진까지 갔는가" 를 확인할 수 있게 남깁니다.
    /// </summary>
    public bool NativeResidencyLimitsApplied { get; private set; }

    /// <summary>썸네일이 새로 준비됐을 때 UI 스레드에서 불립니다. 인자는 frame id 입니다.</summary>
    public event Action<string>? ThumbnailReady;

    public static DevelopedPreviewCacheIdentity? CaptureDevelopedCacheIdentity(
        LibraryFrameSnapshot frame) =>
        DevelopedPreviewCacheIdentityFactory.TryCreate(frame, out var identity)
            ? identity
            : null;

    /// <summary>이미 들고 있는 썸네일 JPEG 입니다. 없으면 null 이며 렌더를 시작하지 않습니다.</summary>
    public byte[]? TryGet(string frameId) =>
        memory.TryGetValue(frameId, out byte[]? jpeg) ? jpeg : null;

    /// <summary>
    /// 현상 워크스페이스가 그린 미리보기입니다. 인화는 이 화소를 먼저 쓰고, 없으면
    /// 360 JPEG 로 자리를 채웁니다.
    /// </summary>
    public bool TryGetDeveloped(string frameId, out DevelopedPreview preview) =>
        developed.TryGetValue(frameId, out preview);

    /// <summary>원본·레시피·엔진 identity가 현재와 같은 memory/disk 정착본만 돌려줍니다.</summary>
    public bool TryGetDeveloped(LibraryFrameSnapshot frame, out DevelopedPreview preview)
    {
        ArgumentNullException.ThrowIfNull(frame);
        preview = default;
        if (!DevelopedPreviewCacheIdentityFactory.TryCreate(frame, out var expected))
        {
            return false;
        }
        if (developed.TryGetValue(frame.Id, out DevelopedPreview resident) &&
            developedIdentities.TryGetValue(frame.Id, out var residentIdentity) &&
            residentIdentity.Matches(expected))
        {
            preview = resident;
            return true;
        }
        EvictDeveloped(frame.Id);
        developedResidency.Remove(frame.Id);
        if (developedDisk.Load(frame, expected) is not { } restored)
        {
            return false;
        }
        RememberResident(frame.Id, restored, expected);
        preview = restored;
        return true;
    }

    /// <summary>
    /// Background 채움이 기존 정착본을 RAM으로 복원하지 않고 건너뛸 수 있는 검사입니다.
    /// </summary>
    public bool HasSettledDeveloped(LibraryFrameSnapshot frame)
    {
        ArgumentNullException.ThrowIfNull(frame);
        if (!DevelopedPreviewCacheIdentityFactory.TryCreate(frame, out var expected))
        {
            return false;
        }
        if (developed.TryGetValue(frame.Id, out DevelopedPreview resident) &&
            resident.Settled &&
            developedIdentities.TryGetValue(frame.Id, out var residentIdentity) &&
            residentIdentity.Matches(expected))
        {
            return true;
        }
        return developedDisk.Contains(frame, expected);
    }

    /// <summary>
    /// macOS <c>ScanFrame.developedImage</c> 자리입니다. 미리보기 버퍼는 다음 렌더가
    /// 덮어쓰므로 여기서 복사합니다.
    /// </summary>
    public void RememberDeveloped(
        string frameId,
        ReadOnlySpan<byte> bgra,
        int width,
        int height,
        bool settled)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        long required = (long)width * height * 4;
        if (width <= 0 || height <= 0 || required > int.MaxValue || bgra.Length < required)
        {
            return;
        }
        int bytes = (int)required;

        developed[frameId] = new DevelopedPreview(
            bgra[..bytes].ToArray(),
            width,
            height,
            settled);
        developedIdentities.TryRemove(frameId, out _);
        // macOS `markDevelopedResident` — FIFO 재등록 뒤 한도 초과분을 내려놓습니다.
        developedResidency.MarkResident(frameId, bytes, EvictDeveloped);
    }

    public void RememberDeveloped(
        LibraryFrameSnapshot frame,
        ReadOnlySpan<byte> bgra,
        int width,
        int height,
        bool settled,
        DevelopedPreviewCacheIdentity? renderedIdentity)
    {
        ArgumentNullException.ThrowIfNull(frame);
        long required = (long)width * height * 4;
        if (width <= 0 || height <= 0 || required > int.MaxValue || bgra.Length < required)
        {
            return;
        }
        int bytes = (int)required;

        DevelopedPreview preview = new(bgra[..bytes].ToArray(), width, height, settled);
        if (renderedIdentity is not null &&
            DevelopedPreviewCacheIdentityFactory.TryCreate(frame, out var current) &&
            renderedIdentity.Matches(current))
        {
            RememberResident(frame.Id, preview, renderedIdentity);
            if (settled)
            {
                developedDisk.Store(
                    frame,
                    renderedIdentity,
                    preview.Pixels,
                    width,
                    height);
            }
        }
        else
        {
            developed[frame.Id] = preview;
            developedIdentities.TryRemove(frame.Id, out _);
            developedResidency.MarkResident(frame.Id, bytes, EvictDeveloped);
        }
    }

    /// <summary>
    /// 먼 background 프레임은 lossless disk 결과만 보존합니다. managed resident와 native
    /// raw를 함께 늘리지 않기 위한 경계이며, 호출자가 재사용하는 버퍼는 여기서 복사합니다.
    /// </summary>
    public void StoreDevelopedOnDisk(
        LibraryFrameSnapshot frame,
        ReadOnlySpan<byte> bgra,
        int width,
        int height,
        DevelopedPreviewCacheIdentity? renderedIdentity)
    {
        ArgumentNullException.ThrowIfNull(frame);
        long required = (long)width * height * 4;
        if (renderedIdentity is null ||
            width <= 0 || height <= 0 || required > int.MaxValue || bgra.Length < required ||
            !DevelopedPreviewCacheIdentityFactory.TryCreate(frame, out var current) ||
            !renderedIdentity.Matches(current))
        {
            return;
        }
        developedDisk.Store(
            frame,
            renderedIdentity,
            bgra[..(int)required].ToArray(),
            width,
            height);
    }

    /// <summary>macOS <c>selectedFrameID</c> — 보고 있는 사진은 축출하지 않습니다.</summary>
    public string? SelectedFrameId
    {
        get => developedResidency.SelectedFrameId;
        set => developedResidency.SelectedFrameId = value;
    }

    /// <summary>지금 상주 중인 현상본 화소 바이트입니다. 시험이 축출을 확인하는 자리입니다.</summary>
    public long DevelopedResidentBytes()
    {
        long total = 0;
        foreach (DevelopedPreview preview in developed.Values)
        {
            total += preview.Pixels.LongLength;
        }
        return total;
    }

    /// <summary>Windows 메모리 압력 알림을 실제 developed FIFO 한도에 반영합니다.</summary>
    public void ApplyMemoryPressure(FrameCachePressureLevel pressure)
    {
        FrameCacheLimits limits = developedPolicy.LimitsFor(pressure);
        developedResidency.SetLimits(limits.Developed, developedByteLimit, EvictDeveloped);
        // 엔진 안의 두 캐시에도 같은 한도를 겁니다. 여기서 멈추면 설정에서 고른 값이
        // 표시본 캐시에만 걸리고 엔진은 계속 설치 메모리만 보고 예산을 잡습니다 -
        // macOS `FrameCacheResidencyStore.onLimitsChange` 는 둘 다 겁니다.
        _ = Negaflow.Interop.FrameCacheLimitsBridge.Apply(limits.CleanedRaw, limits.Developed);
    }

    /// <summary>
    /// <see cref="RememberDeveloped"/> 가 이미 만든 <b>사본</b>에서 썸네일을 만듭니다.
    /// </summary>
    /// <remarks>
    /// <see cref="Publish"/> 는 호출자(UI 스레드)의 공유 버퍼를 읽어야 해서 866만 화소
    /// 축소를 UI 스레드에서 했습니다. 사본은 우리 것이므로 축소까지 워커로 넘길 수 있습니다.
    /// </remarks>
    public void PublishFromDeveloped(string frameId)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        if (!developed.TryGetValue(frameId, out DevelopedPreview preview))
        {
            return;
        }
        _ = Task.Run(() =>
        {
            byte[] reduced = ThumbnailScaler.Reduce(
                preview.Pixels,
                preview.Width,
                preview.Height,
                MaximumDimension,
                out int reducedWidth,
                out int reducedHeight);
            if (codec.EncodeJpeg(reduced, reducedWidth, reducedHeight) is not { } jpeg)
            {
                return;
            }
            Store(frameId, jpeg);
            RaiseReady(frameId);
        });
    }

    private void EvictDeveloped(string frameId)
    {
        developed.TryRemove(frameId, out _);
        developedIdentities.TryRemove(frameId, out _);
    }

    private void RememberResident(
        string frameId,
        DevelopedPreview preview,
        DevelopedPreviewCacheIdentity identity)
    {
        developed[frameId] = preview;
        developedIdentities[frameId] = identity;
        developedResidency.MarkResident(frameId, preview.Pixels.LongLength, EvictDeveloped);
    }

    private static ulong InstalledMemoryBytes()
    {
        long installed = GC.GetGCMemoryInfo().TotalAvailableMemoryBytes;
        return installed > 0 ? (ulong)installed : 0UL;
    }

    /// <summary>
    /// macOS <c>preparePrintPackageDisplayPreview</c> — 칸이 현재 래스터보다 크면
    /// 표시 크기로 현상본을 올립니다. 360 썸네일을 확대해 깨지지 않게 하려는 것입니다.
    /// </summary>
    public void RequestDeveloped(LibraryFrameSnapshot frame, int maxDimension)
    {
        ArgumentNullException.ThrowIfNull(frame);
        if (maxDimension <= 0)
        {
            return;
        }
        if (TryGetDeveloped(frame, out DevelopedPreview existing) &&
            !PrintPreviewResolution.NeedsUpgrade(
                (int)PrintPreviewResolution.PixelDimension(existing.Width, existing.Height),
                maxDimension))
        {
            return;
        }
        string frameId = frame.Id;
        if (developedInFlight.ContainsKey(frameId))
        {
            return;
        }
        Task job = Task.Run(() => ProduceDevelopedAsync(frame, maxDimension));
        if (!developedInFlight.TryAdd(frameId, job))
        {
            return;
        }
        _ = job.ContinueWith(
            _ => developedInFlight.TryRemove(frameId, out Task? _),
            CancellationToken.None,
            TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default);
    }

    /// <summary>
    /// 썸네일을 확보합니다. 이미 있으면 아무 일도 하지 않고, 없으면 디스크를 거쳐 현상까지
    /// 갑니다. 준비되면 <see cref="ThumbnailReady"/> 가 UI 스레드에서 불립니다.
    /// </summary>
    public void Request(LibraryFrameSnapshot frame)
    {
        ArgumentNullException.ThrowIfNull(frame);
        if (memory.ContainsKey(frame.Id) || inFlight.ContainsKey(frame.Id))
        {
            return;
        }
        string frameId = frame.Id;
        Task job = Task.Run(() => ProduceAsync(frame));
        if (!inFlight.TryAdd(frameId, job))
        {
            return;
        }
        _ = job.ContinueWith(
            _ => inFlight.TryRemove(frameId, out Task? _),
            CancellationToken.None,
            TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default);
    }

    /// <summary>
    /// 미리보기가 정착한 픽셀을 그대로 썸네일로 삼습니다. 같은 그림을 다시 현상하지 않으려는
    /// 것이고, 라이브러리 카드가 현상 결과를 곧바로 따라가게 하는 자리이기도 합니다.
    /// </summary>
    public void Publish(string frameId, ReadOnlySpan<byte> bgra, int width, int height)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        if (width <= 0 || height <= 0 || bgra.Length < (long)width * height * 4)
        {
            return;
        }
        // 줄이는 것만 여기서 합니다. 호출자는 UI 스레드이고 원본 버퍼는 재사용되므로, 압축까지
        // 기다리게 하지 않고 작아진 복사본만 워커로 넘깁니다.
        byte[] reduced = ThumbnailScaler.Reduce(
            bgra, width, height, MaximumDimension, out int reducedWidth, out int reducedHeight);
        _ = Task.Run(() =>
        {
            if (codec.EncodeJpeg(reduced, reducedWidth, reducedHeight) is not { } jpeg)
            {
                return;
            }
            Store(frameId, jpeg);
            RaiseReady(frameId);
        });
    }

    /// <summary>
    /// macOS <c>developFrame(frame, preserveThumbnail: false)</c> — 현상 설정이 바뀐 프레임을
    /// 다시 현상해 썸네일을 갈아 끼웁니다.
    /// </summary>
    /// <remarks>
    /// <para>
    /// <see cref="Request"/> 와 다른 점이 둘입니다. 첫째, 이미 들고 있어도 그냥 지나가지 않고
    /// <b>반드시</b> 다시 그립니다 — 폴더 일괄 적용 뒤에도 썸네일이 옛 그림 그대로였던 원인이
    /// 여기였습니다. 둘째, 디스크에 남은 예전 정착본을 <b>읽지 않습니다.</b> 그것도 옛 설정으로
    /// 만든 그림이기 때문입니다.
    /// </para>
    /// <para>
    /// 메모리에 있는 옛 썸네일은 새 것이 나올 때까지 그대로 둡니다. macOS 도 카드를 비우지 않고
    /// 결과가 오면 덮어씁니다. 다 만든 뒤 <see cref="Store"/> 가 메모리와 디스크를 함께 갈아
    /// 끼우므로 디스크 큐에서도 지우기·쓰기가 순서대로 처리됩니다.
    /// </para>
    /// <para>
    /// 기다릴 수 있게 열어 둔 이유는 폴더 일괄 적용이 macOS 처럼 <b>실제 현상</b>에 맞춰 진행률을
    /// 내야 하기 때문입니다. 동시 개수는 <see cref="MaximumConcurrentRenders"/> 로 묶여 있어
    /// macOS <c>maxConcurrentDevelopments</c> 와 같습니다.
    /// </para>
    /// </remarks>
    public async Task RerenderAsync(
        LibraryFrameSnapshot frame,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(frame);
        // 전체 해상도 현상본은 옛 설정으로 만든 것이라 인화 미리보기가 다시 뜨게 버립니다.
        developed.TryRemove(frame.Id, out _);
        developedIdentities.TryRemove(frame.Id, out _);
        developedResidency.Remove(frame.Id);
        if (!frame.CanDevelop)
        {
            return;
        }

        await renderSlots.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            // **네이티브 디코더는 MTA 를 요구합니다.** `wic_tiff_decoder` 는
            // `CoInitializeEx(nullptr, COINIT_MULTITHREADED)` 를 걸고, 실패하면
            // `com_apartment_mismatch` 로 디코드를 거부합니다. WinUI UI 스레드는 STA 라
            // 거기서 부르면 **모든 프레임이 1ms 만에 실패합니다.**
            //
            // 이 메서드는 다른 렌더 경로와 달리 호출자가 `await` 로 직접 부릅니다
            // (폴더 일괄 적용). 세마포어에 빈 자리가 있으면 `WaitAsync` 가 동기로 끝나
            // `Render` 가 **호출자 스레드에서 그대로** 돌았고, 그 호출자가 UI 스레드였습니다.
            // 자리가 막혔을 때만 이어지는 프레임이 스레드풀로 넘어가 성공했으므로,
            // 한 폴더 안에서 몇 장만 바뀌는 것처럼 보였습니다(실측 로그 확인).
            //
            // `Request` 는 `Task.Run(() => ProduceAsync(frame))` 으로 이미 풀에서만 돌고,
            // `DevelopExportCoordinator` 도 `Task.Run(() => exporter.Run(...))` 입니다.
            // 여기만 예외였습니다.
            byte[]? jpeg = await Task.Run(() => Render(frame), cancellationToken)
                .ConfigureAwait(false);
            if (jpeg is null)
            {
                ThumbnailTrace.Write(
                    $"rerender FAILED {frame.Id} {Path.GetFileName(frame.SourcePath)}");
                return;
            }
            Store(frame.Id, jpeg);
            ThumbnailTrace.Write(
                $"rerender stored {frame.Id} {Path.GetFileName(frame.SourcePath)} {jpeg.Length}B");
            RaiseReady(frame.Id);
        }
        finally
        {
            renderSlots.Release();
        }
    }

    /// <summary>프레임이 라이브러리에서 사라질 때 메모리와 디스크 양쪽에서 지웁니다.</summary>
    public void Invalidate(string frameId)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        memory.TryRemove(frameId, out _);
        developed.TryRemove(frameId, out _);
        developedIdentities.TryRemove(frameId, out _);
        // macOS `removeDevelopedResident`.
        developedResidency.Remove(frameId);
        disk.Remove(frameId, PathFor(frameId));
        developedDisk.Remove(frameId);
    }

    /// <summary>디스크 캐시를 통째로 지웁니다. 메모리에 올라온 것은 그대로 쓰입니다.</summary>
    public async Task ClearDiskCacheAsync()
    {
        await Task.WhenAll(disk.ClearAsync(root), developedDisk.ClearAsync()).ConfigureAwait(false);
    }

    public long DiskCacheSizeBytes() =>
        ThumbnailDiskCache.DirectorySize(root) + developedDisk.SizeBytes();

    public async Task WaitUntilIdleAsync()
    {
        await Task.WhenAll(disk.WaitUntilIdleAsync(), developedDisk.WaitUntilIdleAsync())
            .ConfigureAwait(false);
    }

    public async ValueTask DisposeAsync()
    {
        await disk.DisposeAsync().ConfigureAwait(false);
        await developedDisk.DisposeAsync().ConfigureAwait(false);
        renderSlots.Dispose();
    }

    private async Task ProduceAsync(LibraryFrameSnapshot frame)
    {
        // 디스크에 남은 것은 이전 실행의 정착본입니다. 슬롯을 잡기 전에 먼저 봅니다 — 재실행
        // 직후 그리드가 회색으로 남아 있지 않게 하는 것이 여기서 가장 중요합니다.
        if (ThumbnailDiskCache.Load(PathFor(frame.Id)) is { Length: > 0 } cached)
        {
            memory[frame.Id] = cached;
            RaiseReady(frame.Id);
            return;
        }
        if (!frame.CanDevelop)
        {
            return;
        }

        await renderSlots.WaitAsync().ConfigureAwait(false);
        try
        {
            if (Render(frame) is not { } jpeg)
            {
                return;
            }
            Store(frame.Id, jpeg);
            RaiseReady(frame.Id);
        }
        finally
        {
            renderSlots.Release();
        }
    }

    private async Task ProduceDevelopedAsync(LibraryFrameSnapshot frame, int maxDimension)
    {
        if (!frame.CanDevelop)
        {
            return;
        }

        await renderSlots.WaitAsync().ConfigureAwait(false);
        try
        {
            if (TryGetDeveloped(frame, out DevelopedPreview existing) &&
                !PrintPreviewResolution.NeedsUpgrade(
                    (int)PrintPreviewResolution.PixelDimension(existing.Width, existing.Height),
                    maxDimension))
            {
                return;
            }

            string unusedDestination = Path.ChangeExtension(frame.SourcePath, ".print-preview.png");
            if (DevelopRequestFactory.Create(frame, unusedDestination).Request is not { } request)
            {
                return;
            }

            uint edge = DevelopPreviewProxy.BufferEdge(maxDimension);
            byte[] pixels = new byte[(long)edge * edge * 4];
            DevelopedPreviewCacheIdentity? identity =
                DevelopedPreviewCacheIdentityFactory.TryCreate(frame, out var created)
                    ? created
                    : null;
            DevelopExportResult result = exporter.Preview(request, edge, edge, pixels);
            if (!result.Succeeded || result.ImageWidth == 0U || result.ImageHeight == 0U)
            {
                return;
            }

            RememberDeveloped(
                frame,
                pixels,
                (int)result.ImageWidth,
                (int)result.ImageHeight,
                settled: false,
                identity);
            RaiseReady(frame.Id);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            _ = error;
        }
        finally
        {
            renderSlots.Release();
        }
    }

    private byte[]? Render(LibraryFrameSnapshot frame)
    {
        // 회귀 감시. 네이티브 디코더는 STA 에서 `com_apartment_mismatch` 로 거부하므로,
        // 여기로 STA 스레드가 들어오면 그 자체가 결함입니다.
        if (ThumbnailTrace.IsEnabled &&
            Thread.CurrentThread.GetApartmentState() == ApartmentState.STA)
        {
            ThumbnailTrace.Write(
                $"render STA-THREAD {Path.GetFileName(frame.SourcePath)} " +
                "— 네이티브 디코더는 MTA 를 요구합니다");
        }
        // 미리보기는 파일을 쓰지 않지만 요청 팩토리는 목적지를 요구합니다. 네이티브가 무시합니다.
        string unusedDestination = Path.ChangeExtension(frame.SourcePath, ".thumbnail.png");
        DevelopRequestResult built = DevelopRequestFactory.Create(frame, unusedDestination);
        if (built.Request is not { } request)
        {
            ThumbnailTrace.Write(
                $"render REFUSED {built.Refusal} {Path.GetFileName(frame.SourcePath)} " +
                $"signal={frame.Route.SourceSignalKind} film={frame.Route.FilmType} " +
                $"look={frame.Route.FilmLookSource} baseMode={frame.Base.Mode} " +
                $"stock={frame.Base.FilmStockDminId ?? "-"} manual={(frame.ManualBase is null ? "none" : "set")}");
            return null;
        }

        byte[] pixels = new byte[MaximumDimension * MaximumDimension * 4];
        try
        {
            DevelopExportResult result = exporter.Preview(
                request,
                MaximumDimension,
                MaximumDimension,
                pixels);
            if (!result.Succeeded || result.ImageWidth == 0U || result.ImageHeight == 0U)
            {
                ThumbnailTrace.Write(
                    $"render NATIVE-FAIL {Path.GetFileName(frame.SourcePath)} " +
                    $"stage={result.FailedStage} {result.FailureName} " +
                    $"{result.ImageWidth}x{result.ImageHeight} cancelled={result.Cancelled}");
                return null;
            }
            return codec.EncodeJpeg(pixels, (int)result.ImageWidth, (int)result.ImageHeight);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            // 한 장이 실패해도 그리드 전체가 멈추지는 않습니다. 카드는 자리표시자로 남습니다.
            return null;
        }
    }

    private void Store(string frameId, byte[] jpeg)
    {
        memory[frameId] = jpeg;
        disk.Store(frameId, PathFor(frameId), jpeg);
    }

    private void RaiseReady(string frameId)
    {
        if (ThumbnailReady is null)
        {
            ThumbnailTrace.Write($"ready NO-SUBSCRIBER {frameId}");
            return;
        }
        if (dispatcher.HasThreadAccess)
        {
            ThumbnailReady.Invoke(frameId);
            return;
        }
        // 큐가 닫혔다는 것은 창이 사라지는 중이라는 뜻이므로, 배달 실패는 그대로 둡니다.
        bool queued = dispatcher.TryEnqueue(() => ThumbnailReady?.Invoke(frameId));
        ThumbnailTrace.Write($"ready queued={queued} {frameId}");
    }

    /// <summary>
    /// <c>&lt;root&gt;/&lt;앞 두 글자&gt;/&lt;id&gt;.jpg</c>. 한 폴더에 수만 개가 쌓이면 탐색기와
    /// 열거가 같이 느려지므로 앞 두 글자로 흩습니다.
    /// </summary>
    private string PathFor(string frameId)
    {
        string safe = Sanitize(frameId);
        string shard = safe.Length >= 2 ? safe[..2] : "__";
        return Path.Combine(root, shard, safe + ".jpg");
    }

    private static string Sanitize(string value)
    {
        Span<char> buffer = value.Length <= 128 ? stackalloc char[value.Length] : new char[value.Length];
        for (int index = 0; index < value.Length; ++index)
        {
            char character = value[index];
            buffer[index] = char.IsAsciiLetterOrDigit(character) || character is '-' or '_'
                ? character
                : '_';
        }
        return new string(buffer);
    }
}
