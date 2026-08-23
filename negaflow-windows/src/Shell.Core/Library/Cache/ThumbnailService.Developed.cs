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
