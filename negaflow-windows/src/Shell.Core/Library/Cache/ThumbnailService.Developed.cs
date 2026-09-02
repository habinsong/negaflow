using System.Collections.Concurrent;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Print;

namespace Negaflow.Shell.Library;

/// <summary>현상 미리보기 화소 몫입니다. 썸네일 JPEG 몫과 같은 서비스가 함께 들고 있습니다.</summary>
public sealed partial class ThumbnailService
{
    public static DevelopedPreviewCacheIdentity? CaptureDevelopedCacheIdentity(
        LibraryFrameSnapshot frame) =>
        DevelopedPreviewCacheIdentityFactory.TryCreate(frame, out var identity)
            ? identity
            : null;

    /// <summary>
    /// 현상 워크스페이스가 그린 미리보기입니다. 인화는 이 화소를 먼저 쓰고, 없으면
    /// 360 JPEG 로 자리를 채웁니다.
    /// </summary>
    public bool TryGetDeveloped(string frameId, out DevelopedPreview preview) =>
        developed.TryGetValue(frameId, out preview);

    /// <summary>원본·레시피·엔진 identity가 현재와 같은 상주 정착본만 돌려줍니다.</summary>
    /// <remarks>
    /// 예전에는 여기서 못 찾으면 디스크 캐시(<c>Cache\DevelopedPreviews</c>)까지 뒤졌습니다.
    /// 그 캐시는 맥에 없는 Windows 창작이라 걷어냈습니다 — macOS 가 디스크에 두는 것은
    /// 썸네일 · Cleaned Raw · Scan Previews 뿐이고, 현상 프리뷰는 <c>ScanFrame.developedImage</c>
    /// 로 <b>메모리에만</b> 삽니다. 여기 남은 것이 그 자리입니다.
    /// </remarks>
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
        return false;
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
        SyncDisplayCacheBudget();
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
        }
        else
        {
            developed[frame.Id] = preview;
            developedIdentities.TryRemove(frame.Id, out _);
            SyncDisplayCacheBudget();
            developedResidency.MarkResident(frame.Id, bytes, EvictDeveloped);
        }
    }

    /// <summary>macOS <c>selectedFrameID</c> — 보고 있는 사진은 축출하지 않습니다.</summary>
    public string? SelectedFrameId
    {
        get => developedResidency.SelectedFrameId;
        set => developedResidency.SelectedFrameId = value;
    }

    /// <summary>
    /// 이 캐시를 엔진의 <b>프로세스 예산</b>에 붙입니다. 지금 상주량을 알리고 쓸 수 있는
    /// 바이트를 받아 FIFO 한도에 겁니다.
    /// </summary>
    /// <remarks>
    /// 이 캐시는 엔진 밖에 있지만 같은 프로세스의 같은 상한을 나눠 씁니다. 붙이지 않으면
    /// 이 몫이 "캐시가 아닌 몫"으로 잡혀 네이티브 캐시만 굶고, 이쪽은 간접비가 늘어도 줄지
    /// 않습니다 — 실측으로 설치 앱이 9.7GB 까지 갔고 그때 이 캐시가 520MB 였습니다.
    ///
    /// 엔진을 못 부르면 <b>손대지 않습니다.</b> 설정에서 고른 장수에서 나온 값이 그대로
    /// 남습니다 — 캐시 상한 하나 때문에 앱을 세우지 않습니다.
    /// </remarks>
    private void SyncDisplayCacheBudget()
    {
        Negaflow.Shell.Diagnostics.MemoryBudgetLog.Sample("developed");
        if (Negaflow.Interop.DisplayCacheBudgetBridge.Sync(DevelopedResidentBytes())
            is not { } budget)
        {
            return;
        }
        long allowed = budget > long.MaxValue ? long.MaxValue : (long)budget;
        if (allowed <= 0L || allowed == developedByteLimit)
        {
            return;
        }
        developedByteLimit = allowed;
        developedResidency.SetLimits(
            developedResidency.Limit, developedByteLimit, EvictDeveloped);
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

    /// <summary>지금 걸린 developed FIFO 한도입니다 - 장수와 바이트 둘 다입니다.</summary>
    public (int Frames, long Bytes) DevelopedLimits()
        => (developedResidency.Limit, developedResidency.ByteLimit);

    /// <summary>FIFO 가 지금 들고 있는 현상본 장수입니다.</summary>
    public int DevelopedResidentCount => developedResidency.Count;

    /// <summary>
    /// 지금 걸린 한도에서 <b>보고 있는 사진 말고</b> 더 들고 있을 수 있는 정착본 장수입니다.
    /// </summary>
    /// <remarks>
    /// <para>
    /// 한도는 설정 · 메모리의 프레임 캐시(자동/수동)에서 옵니다 —
    /// <see cref="FrameCacheResidencySettings.EffectiveLimits"/> 가 정하고
    /// <see cref="ApplyResidencySettings"/> 가 FIFO 에 겁니다. 여기는 그 값을 읽기만 합니다.
    /// </para>
    /// <para>
    /// 이웃 예열이 이 수를 넘겨 채우면 <b>자기가 넣은 것을 자기가 밀어냅니다.</b> FIFO 는
    /// 앞(가장 오래된)부터 내보내므로, 한도가 3인데 이웃 4장을 밀어 넣으면 먼저 넣은 이웃이
    /// 그대로 나가고 디코딩만 두 번 한 셈이 됩니다. 그래서 예열은 이 수만큼만 갑니다.
    /// </para>
    /// <para>
    /// 장수와 바이트 두 한도를 함께 봅니다 — 68MP 스캔 한 장의 표시본이 35MB 라
    /// 장수는 남아도 바이트가 먼저 차는 기계가 있습니다. <paramref name="bytesPerFrame"/>
    /// 은 지금 보고 있는 사진의 표시본 크기를 넘겨받아 이웃도 그만하다고 봅니다 — 같은
    /// 상자로 현상하므로 실제로 비슷합니다. 0 이면 장수만 봅니다.
    /// </para>
    /// </remarks>
    public int SpareDevelopedSlots(long bytesPerFrame)
    {
        (int frames, long bytes) = DevelopedLimits();
        // 보고 있는 사진이 한 자리를 씁니다. macOS `trimDeveloped` 도 그 자리는
        // `selectedFrameID` 로 지켜 주므로 나머지가 이웃 몫입니다.
        int slots = frames - 1;
        if (slots <= 0)
        {
            return 0;
        }
        if (bytesPerFrame <= 0L)
        {
            return slots;
        }
        long spareBytes = bytes - bytesPerFrame;
        if (spareBytes < bytesPerFrame)
        {
            return 0;
        }
        return (int)Math.Min(slots, spareBytes / bytesPerFrame);
    }

    /// <summary>Windows 메모리 압력 알림을 실제 developed FIFO 한도에 반영합니다.</summary>
    public void ApplyMemoryPressure(FrameCachePressureLevel pressure)
    {
        FrameCacheLimits limits = developedPolicy.LimitsFor(pressure);
        developedResidency.SetLimits(limits.Developed, developedByteLimit, EvictDeveloped);
        // 엔진 안의 두 캐시에도 같은 한도를 겁니다. 여기서 멈추면 설정에서 고른 값이
        // 표시본 캐시에만 걸리고 엔진은 계속 설치 메모리만 보고 예산을 잡습니다 -
        // macOS `FrameCacheResidencyStore.onLimitsChange` 는 둘 다 겁니다.
        //
        // 압력이 없을 때는 **자동이면 0** 을 겁니다(`ApplyEngineLimits` 주석 참고).
        // 압력이 올라갔을 때만 줄인 장수를 걸어 자동값보다 낮춥니다.
        _ = ApplyEngineLimits(
            residencyMode,
            limits,
            clampedByPressure: pressure != FrameCachePressureLevel.Normal);
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
    /// <summary>
    /// 인화 미리보기가 걸어 둔 프루프입니다. macOS 는 인화 작업공간에서만
    /// <c>cPrintSoftProofSettings</c> 를 씁니다 — 여기 값이 있으면 현상본이 그 프로파일로
    /// 나오고, 색영역 경고도 ICM 이 판정해 표시합니다.
    /// </summary>
    public SoftProofSettings? PrintProof { get; private set; }

    /// <summary>
    /// 프루프를 갈아 끼웁니다. 값이 달라지면 현상본을 버려 다음 그리기에서 다시 만듭니다.
    /// </summary>
    public bool SetPrintProof(SoftProofSettings? proof)
    {
        if (Same(PrintProof, proof))
        {
            return false;
        }
        PrintProof = proof;
        // 프루프가 달라지면 지금 들고 있는 현상본은 옛 색입니다. 버려야 다음 그리기에서
        // 새 프로파일로 다시 만듭니다.
        developed.Clear();
        return true;
    }

    private static bool Same(SoftProofSettings? left, SoftProofSettings? right)
    {
        if (left is null || right is null)
        {
            return left is null && right is null;
        }
        return left.IsEnabled == right.IsEnabled &&
            left.Simulation == right.Simulation &&
            left.WarnOutOfGamut == right.WarnOutOfGamut &&
            Math.Abs(left.PaperWhite.Red - right.PaperWhite.Red) < 1e-6 &&
            Math.Abs(left.PaperWhite.Green - right.PaperWhite.Green) < 1e-6 &&
            Math.Abs(left.PaperWhite.Blue - right.PaperWhite.Blue) < 1e-6 &&
            Math.Abs(left.BlackInk.Red - right.BlackInk.Red) < 1e-6 &&
            Math.Abs(left.BlackInk.Green - right.BlackInk.Green) < 1e-6 &&
            Math.Abs(left.BlackInk.Blue - right.BlackInk.Blue) < 1e-6;
    }

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
            // 인화 미리보기의 프루프를 그대로 실어 보냅니다. 색영역 경고 판정도 여기서
            // ICM 이 합니다 — 화소를 손으로 흉내 내지 않습니다.
            PreviewTrace.Write(
                $"req.print {frame.Id} auto={request.AutoLevels}/{request.AutoNeutralBalance} " +
                $"target={request.DevelopTarget} exposure={request.ExposureStops} " +
                $"contrast={request.Contrast} look={request.FilmEmulation} edge={edge} " +
                $"proof={(PrintProof is { IsEnabled: true } ? PrintProof.Simulation.ToString() : "off")}");
            DevelopExportResult result = exporter.Preview(
                request, edge, edge, pixels, null, PrintProof);
            if (!result.Succeeded || result.ImageWidth == 0U || result.ImageHeight == 0U)
            {
                return;
            }
            if (PreviewTrace.IsEnabled)
            {
                PreviewTrace.Write(
                    $"made.print {frame.Id} {result.ImageWidth}x{result.ImageHeight} " +
                    Negaflow.Shell.Develop.PreviewPixelStats.Describe(
                        pixels, (int)result.ImageWidth, (int)result.ImageHeight));
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

}
