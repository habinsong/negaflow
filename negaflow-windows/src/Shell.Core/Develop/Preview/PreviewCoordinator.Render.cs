using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;

namespace Negaflow.Shell;

/// <summary>렌더 한 번을 엔진에 넣고 화면에 배달하는 자리입니다.</summary>
public sealed partial class PreviewCoordinator
{
    private async Task<LeasedOutcome> RenderAsync(PreviewRequest request, DevelopRun run)
    {
        LibraryFrameSnapshot frame = request.Frame;
        int revision = request.Revision;
        // 미리보기는 파일을 쓰지 않지만 요청 팩토리는 목적지를 요구합니다. 네이티브가 무시하는
        // 자리이므로 frame 옆의 이름을 넣어 두고, 실제로는 아무것도 만들어지지 않습니다.
        string unusedDestination = Path.ChangeExtension(frame.SourcePath, ".preview.png");
        bool rawSource;
        DevelopDebugStage? stage;
        lock (gate)
        {
            rawSource = uninvertedSource;
            stage = debugStage;
        }
        // 디버그 오버레이는 뒤 단계를 끈 요청으로 그 지점의 그림을 얻습니다. 지어낸 그림이
        // 아니라 같은 엔진이 낸 결과입니다.
        LibraryFrameSnapshot rendered = stage is { } wanted
            ? DevelopDebugFrames.Prepare(frame, wanted)
            : frame;
        DevelopRequestResult built = DevelopRequestFactory.Create(
            rendered,
            unusedDestination,
            uninvertedSource: rawSource);
        if (built.Request is not { } developRequest)
        {
            PreviewTrace.Write("RenderAsync refused " + built.Refusal + " rev=" + revision);
            return new LeasedOutcome(PreviewOutcome.Refused(built.Refusal, revision), -1);
        }

        // Read once, here, so the whole render uses one proof state even if the property
        // changes while it is inside the engine. That render is superseded anyway.
        SoftProofSettings? proof = SoftProof;
        if (PreviewTrace.IsEnabled)
        {
            PreviewTrace.Write(
                $"req.develop {frame.Id} auto={developRequest.AutoLevels}/" +
                $"{developRequest.AutoNeutralBalance} target={developRequest.DevelopTarget} " +
                $"exposure={developRequest.ExposureStops} contrast={developRequest.Contrast} " +
                $"look={developRequest.FilmEmulation} raw={rawSource} " +
                $"proof={(proof is { IsEnabled: true } ? proof.Simulation.ToString() : "off")}");
        }
        bool clippingOverlay = ClippingOverlayEnabled;
        // 단계 그림은 최종 결과가 아니므로 정착본 캐시에 넣지 않습니다 - 넣으면 오버레이를
        // 끈 뒤에도 그 그림이 나옵니다.
        DevelopedPreviewCacheIdentity? cacheIdentity =
            stage is null && !rawSource && proof is not { IsEnabled: true } && !clippingOverlay &&
            DevelopedPreviewCacheIdentityFactory.TryCreate(frame, out var createdIdentity)
                ? createdIdentity
                : null;

        try
        {
            uint interactiveEdge = InteractiveEdge();
            PreviewTrace.Write("RenderAsync start rev=" + revision + " edge=" + interactiveEdge);
            // 인터랙티브 상자가 이미 정착 치수면 뒤따르는 정착 패스가 없습니다. 그때는
            // 이 결과가 곧 정착본입니다 — macOS `cachedPreviewRaw` 의 정착 갈래와 같은 판정.
            bool interactiveIsFinal = !settleEnabled ||
                interactiveEdge >= DevelopPreviewProxy.FullMaxDimension - 0.5;
            lock (gate)
            {
                activeRunIsSettled = false;
            }
            LeasedOutcome interactive = await PreviewOnceAsync(
                developRequest,
                frame.Id,
                interactiveEdge,
                interactiveEdge,
                run,
                proof,
                clippingOverlay,
                settled: interactiveIsFinal,
                revision: revision,
                cacheIdentity: cacheIdentity).ConfigureAwait(false);
            PreviewTrace.Write(
                "RenderAsync interactive kind=" + interactive.Outcome.Kind +
                " final=" + interactiveIsFinal +
                " edge=" + interactiveEdge +
                " w=" + interactive.Outcome.Width +
                " h=" + interactive.Outcome.Height +
                " cancel=" + run.IsCancelRequested);
            if (interactiveIsFinal ||
                interactive.Outcome.Kind != DevelopExportOutcomeKind.Completed)
            {
                return interactive;
            }

            // 인터랙티브를 **여기서 곧바로 배달합니다.** macOS 도 인터랙티브 패스가
            // 끝나면 그 자리에서 `frame.developedImage` 를 갈아 끼웁니다
            // (`AppModel+DevelopRendering.swift:81-84`). 앞 판은 결과를 하나만
            // 돌려줬기 때문에, 손을 멈춰 정착이 성립하면 인터랙티브 그림은 버려지고
            // 정착본이 나올 때까지(이 기계 3600 에서 약 300 ms) 화면이 옛 그림이었습니다.
            //
            // **더 새 요청이 대기 중이어도 배달합니다.** 한때 여기서 `pending is not null`
            // 이면 다 그린 장을 버렸는데, 슬라이더를 끄는 동안에는 대기가 **항상** 있으므로
            // 끄는 내내 단 한 장도 화면에 오르지 않았습니다. 실측: 8ms 간격 60틱(480ms)
            // 드래그에서 렌더 4장이 끝났는데 배달은 0장, 첫 장이 손을 뗀 뒤 428ms 만에
            // 나왔습니다. 사용자가 "맨 마지막 위치의 값으로만 보인다"고 한 것이 이것입니다.
            // 지금 이 장은 화면에 있는 것보다 **분명히 새것**이고, 더 새 장이 오면
            // `ShowPreview` 의 리비전 검사가 이 장을 밀어냅니다 — 옛 그림이 남을 길은
            // 없습니다.
            Deliver(interactive, request.OnCompleted);

            if (!await WaitForSettleAsync(revision, run).ConfigureAwait(false))
            {
                // 이미 배달했습니다. 다시 돌려주면 같은 그림을 두 번 그립니다.
                return new LeasedOutcome(PreviewOutcome.Cancelled(), -1);
            }

            uint settled = DevelopPreviewProxy.BufferEdge(DevelopPreviewProxy.FullMaxDimension);
            lock (gate)
            {
                if (pending is not null || developRevision != revision || run.IsCancelRequested)
                {
                    return new LeasedOutcome(PreviewOutcome.Cancelled(), -1);
                }
                activeRunIsSettled = true;
            }
            // 정착이 끊겼으면 화면에는 이미 인터랙티브가 올라가 있습니다. 그것을 다시
            // 배달할 이유가 없습니다.
            return await PreviewOnceAsync(
                developRequest,
                frame.Id,
                settled,
                settled,
                run,
                proof,
                clippingOverlay,
                settled: true,
                revision: revision,
                cacheIdentity: cacheIdentity).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            // 취소는 예외가 아니라 다음 요청이 이겼다는 뜻입니다. 여기서 던지면
            // RunLoop 가 pending 을 지워 마지막 미리보기가 화면에 안 남습니다.
            return new LeasedOutcome(PreviewOutcome.Cancelled(), -1);
        }
        catch (Exception error)
        {
            PreviewTrace.Write("RenderAsync fault rev=" + revision + " " + error);
            return new LeasedOutcome(
                PreviewOutcome.Faulted(error.Message ?? error.GetType().Name, revision),
                -1);
        }
    }

    /// <summary>
    /// macOS <c>interactiveProxyDimension(displayTargetPixels:)</c> 그대로입니다.
    /// </summary>
    /// <remarks>
    /// 한때 여기서 실측 처리량으로 상자를 접었습니다. 속도는 붙었지만 **끄는 동안 그림이
    /// 뭉개져 보였고**, 사용자가 그것을 바로 잡아냈습니다. 해상도를 깎아 얻는 속도는 답이
    /// 아닙니다 — 캔버스가 쓰는 디바이스 픽셀 그대로 그리고, 속도는 파이프라인에서 냅니다.
    /// </remarks>
    private uint InteractiveEdge()
    {
        // 두 번째 렌더는 RunLoop 가 워커에서 이어집니다. 캔버스 ActualWidth 를
        // 그 스레드에서 읽으면 WinUI 가 던지고, 성공한 첫 장을 skip stale 한 뒤
        // 빈 Faulted 가 화면에 남았습니다(preview-trace 실측).
        //
        // 그래서 워커에서는 상수 2560 으로 떨어졌는데, 슬라이더를 끄는 동안의 렌더는
        // **전부 워커**입니다. 실제 preview-trace 에서 UI 스레드 렌더는 1280·1536·1792
        // 였고 워커 렌더 3,695 회가 2560 이었습니다. 캔버스가 1280 인데 2560 을 그리면
        // 화소가 네 배이고, 그 여분은 캔버스에 내려놓으며 그대로 버려집니다. 게다가
        // 장마다 치수가 오가면 raw 프록시와 표시 비트맵이 매번 다시 만들어집니다.
        //
        // UI 스레드에서 본 마지막 값을 기억해 워커가 그대로 씁니다. 창 크기가 바뀌면
        // 다음 UI 스레드 렌더가 갱신하므로 캔버스보다 작게 그리는 일은 없습니다.
        double display = DevelopPreviewProxy.InteractiveMaxDimension;
        if (displayTargetPixels is not null)
        {
            if (dispatcher.HasThreadAccess)
            {
                double measured = displayTargetPixels();
                if (measured > 0)
                {
                    display = measured;
                    Interlocked.Exchange(
                        ref lastDisplayTargetBits, BitConverter.DoubleToInt64Bits(measured));
                }
            }
            else
            {
                double remembered = BitConverter.Int64BitsToDouble(
                    Interlocked.Read(ref lastDisplayTargetBits));
                if (remembered > 0)
                {
                    display = remembered;
                }
            }
        }
        return DevelopPreviewProxy.BufferEdge(
            DevelopPreviewProxy.InteractiveProxyDimension(display));
    }

    /// <summary>UI 스레드에서 마지막으로 읽은 캔버스 표시 화소입니다.</summary>
    private long lastDisplayTargetBits;

    /// <summary>macOS <c>waitForDevelopSettle</c> — 0.14초 동안 새 요청이 없으면 true.</summary>
    private async Task<bool> WaitForSettleAsync(int revision, DevelopRun run)
    {
        DateTime deadline = DateTime.UtcNow + DevelopPreviewProxy.SettleWindow;
        while (DateTime.UtcNow < deadline)
        {
            if (run.IsCancelRequested)
            {
                return false;
            }

            lock (gate)
            {
                if (pending is not null || developRevision != revision)
                {
                    return false;
                }
            }

            try
            {
                await Task.Delay(25).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                return false;
            }
        }

        lock (gate)
        {
            return pending is null && developRevision == revision && !run.IsCancelRequested;
        }
    }

    private async Task<LeasedOutcome> PreviewOnceAsync(
        DevelopExportRequest developRequest,
        string frameId,
        uint width,
        uint height,
        DevelopRun run,
        SoftProofSettings? proof,
        bool clippingOverlay,
        bool settled,
        int revision,
        DevelopedPreviewCacheIdentity? cacheIdentity)
    {
        // 배달된 버퍼는 UI 스레드가 다 쓸 때까지 임대 중입니다. 여기서 기다리는 것이
        // "그리는 화소"와 "배달한 리비전"이 어긋나지 않게 하는 유일한 방법입니다.
        int lease = bufferIndex;
        bufferIndex ^= 1;
        await bufferLeases[lease].WaitAsync().ConfigureAwait(false);
        byte[] pixels = buffers[lease];
        DevelopExportResult result;
        try
        {
            PreviewTrace.Write(
                "PreviewOnce start frame=" + frameId +
                " " + width + "x" + height +
                " settled=" + settled +
                " rev=" + revision);
            System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();
            result = await Task.Run(() => exporter.Preview(
                developRequest,
                width,
                height,
                pixels,
                run,
                proof,
                clippingOverlay)).ConfigureAwait(false);
            PreviewTrace.Write(
                "PreviewOnce end ok=" + result.Succeeded +
                " cancel=" + result.Cancelled +
                " fail=" + (result.FailureName ?? "") +
                " w=" + result.ImageWidth +
                " h=" + result.ImageHeight +
                " ms=" + clock.ElapsedMilliseconds);
        }
        catch
        {
            ReleaseLease(lease);
            throw;
        }
        if (result.Cancelled || run.IsCancelRequested)
        {
            ReleaseLease(lease);
            return new LeasedOutcome(PreviewOutcome.Cancelled(), -1);
        }
        if (!result.Succeeded)
        {
            ReleaseLease(lease);
            return new LeasedOutcome(
                PreviewOutcome.Faulted(result.FailureName ?? "preview_failed", revision) with { FrameId = frameId },
                -1);
        }

        return new LeasedOutcome(
            new PreviewOutcome(
                DevelopExportOutcomeKind.Completed,
                pixels,
                result.ImageWidth,
                result.ImageHeight,
                result,
                DevelopRequestRefusal.None,
                null,
                settled,
                revision,
                frameId,
                cacheIdentity),
            lease);
    }

    private void ReleaseLease(int lease)
    {
        if (lease >= 0)
        {
            bufferLeases[lease].Release();
        }
    }

    private void Deliver(LeasedOutcome leased, Action<PreviewOutcome> onCompleted)
    {
        if (!CanDeliver(leased.Outcome.Revision))
        {
            ReleaseLease(leased.Lease);
            return;
        }
        if (dispatcher.HasThreadAccess)
        {
            try
            {
                if (CanDeliver(leased.Outcome.Revision))
                {
                    onCompleted(leased.Outcome);
                }
            }
            finally
            {
                ReleaseLease(leased.Lease);
            }
            return;
        }
        // 배달에 실패해도 루프는 계속 정리됩니다. 큐가 닫혔다는 뜻이므로 창이 사라지는 중입니다.
        // 임대는 **어느 쪽이든 반드시** 돌려줍니다 — 안 돌려주면 다음 렌더가 영영 멈춥니다.
        if (!dispatcher.TryEnqueue(() =>
            {
                try
                {
                    if (CanDeliver(leased.Outcome.Revision))
                    {
                        onCompleted(leased.Outcome);
                    }
                }
                finally
                {
                    ReleaseLease(leased.Lease);
                }
            }))
        {
            ReleaseLease(leased.Lease);
        }
    }

    private bool CanDeliver(int revision)
    {
        lock (gate)
        {
            return revision >= minimumDeliveryRevision;
        }
    }
}
