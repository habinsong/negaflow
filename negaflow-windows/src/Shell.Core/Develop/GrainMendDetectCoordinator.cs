using System.Diagnostics;
using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

public sealed record GrainMendDetectOutcome(
    DevelopExportOutcomeKind Kind,
    DefectEditItem? Edit,
    uint Width,
    uint Height,
    DevelopRequestRefusal Refusal,
    string? FaultMessage,
    // macOS `DefectLabelField.automaticFalsePositiveRisk`. 전체 프레임 자동에서만 서고,
    // 성분을 하나도 버리지 않습니다 — 캡슐이 개수 대신 경고 문구를 냅니다.
    bool AutomaticFalsePositiveRisk = false)
{
    /// <summary>검출은 됐지만 고칠 것이 없었습니다. 실패가 아닙니다.</summary>
    public bool FoundNothing => Kind == DevelopExportOutcomeKind.Completed && Edit is null;

    internal static GrainMendDetectOutcome Refused(DevelopRequestRefusal refusal) =>
        new(DevelopExportOutcomeKind.Refused, null, 0U, 0U, refusal, null);

    internal static GrainMendDetectOutcome Faulted(string message) =>
        new(DevelopExportOutcomeKind.Faulted, null, 0U, 0U, DevelopRequestRefusal.None, message);
}

/// <summary>
/// GrainMend 자동·가이드가 무엇을 고칠지 재는 한 번입니다. 결과를 <b>저장하지 않고</b>
/// 돌려줍니다.
/// </summary>
/// <remarks>
/// 저장하지 않는 것이 요점입니다. macOS 는 자동을 누르는 것만으로 사진을 바꾸지 않고, 찾은
/// 것을 보여 준 뒤 사용자가 받아들여야 반영합니다. 여기서 바로 써 버리면 상태 전환이
/// 달라집니다 — 그것도 macOS 와 맞춰야 하는 항목입니다.
/// </remarks>
public sealed class GrainMendDetectCoordinator
{
    private const string TraceEnvironmentVariable = "NEGAFLOW_GRAIN_MEND_TRACE";
    private const string TraceFileName = "grain-mend-detection.jsonl";
    private const string TraceMarkerFileName = "grain-mend-trace.enabled";
    private static readonly object TraceGate = new();

    /// <summary>
    /// 처음 잡아 두는 마스크 버퍼의 한 변입니다. 자동·가이드는 macOS 와 같이 <b>원본
    /// 해상도</b>로 검출하므로 프레임이 이보다 크면 그 프레임 크기로 다시 잡습니다.
    /// </summary>
    private const int InitialMaskDimension = 1800;

    private readonly IDevelopExporter exporter;
    private readonly IUiDispatcher dispatcher;
    private byte[] mask = new byte[InitialMaskDimension * InitialMaskDimension];

    /// <summary>
    /// 원본 해상도 검출은 화소마다 한 바이트를 냅니다. 버퍼가 작으면 마스크가 잘려 검출
    /// 결과가 조용히 사라지므로, 필요한 만큼 키워 두고 다음 검출에 다시 씁니다.
    /// </summary>
    private void EnsureMask(LibraryFrameSnapshot frame)
    {
        if (frame.SourceMetadata is not { } metadata)
        {
            return;
        }
        long required = checked((long)metadata.PixelWidth * metadata.PixelHeight);
        if (required > mask.Length && required <= int.MaxValue)
        {
            mask = new byte[(int)required];
        }
    }

    public GrainMendDetectCoordinator(IDevelopExporter exporter, IUiDispatcher dispatcher)
    {
        ArgumentNullException.ThrowIfNull(exporter);
        ArgumentNullException.ThrowIfNull(dispatcher);
        this.exporter = exporter;
        this.dispatcher = dispatcher;
    }

    /// <summary>
    /// <paramref name="roi"/> 는 검출 이미지 기준 정규 사각형입니다. 자동은 프레임 전체,
    /// 가이드는 사용자가 끈 사각형입니다.
    /// </summary>
    /// <returns>결과를 <paramref name="onCompleted"/> 로 전할 수 있었으면 참입니다.</returns>
    public async Task<bool> RunAsync(
        LibraryFrameSnapshot frame,
        DefectRect roi,
        Action<GrainMendDetectOutcome> onCompleted)
    {
        return await RunAsync(
            frame,
            roi,
            GrainMendSensitivity.ToDetectionOptions(GrainMendSensitivity.Default, IsWholeFrame(roi)),
            onCompleted).ConfigureAwait(false);
    }

    /// <summary>
    /// 현재 자동/가이드 검토 설정으로 재검출합니다. 후보가 수락되기 전에는 어떤 recipe도 쓰지
    /// 않으므로 감도 변경은 언제나 이 호출로만 끝납니다.
    /// </summary>
    public async Task<bool> RunAsync(
        LibraryFrameSnapshot frame,
        DefectRect roi,
        GrainMendDetectionOptions options,
        Action<GrainMendDetectOutcome> onCompleted)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(onCompleted);
        Stopwatch clock = Stopwatch.StartNew();
        EnsureMask(frame);

        // 검출은 파일을 쓰지 않지만 요청 팩토리는 목적지를 요구합니다.
        string unusedDestination = Path.ChangeExtension(frame.SourcePath, ".detect.png");
        DevelopRequestResult built = DevelopRequestFactory.Create(frame, unusedDestination);
        if (built.Request is not { } request)
        {
            WriteTrace(frame.Id, roi, options, clock.ElapsedMilliseconds, new
            {
                outcome = "refused",
                refusal = built.Refusal.ToString(),
            });
            return Deliver(GrainMendDetectOutcome.Refused(built.Refusal), onCompleted);
        }

        try
        {
            GrainMendDetectionResult detected = await Task.Run(
                () => exporter.DetectGrainMend(request, mask, roi, options)).ConfigureAwait(false);
            if (!detected.Result.Succeeded)
            {
                WriteTrace(frame.Id, roi, options, clock.ElapsedMilliseconds, new
                {
                    outcome = "native-failure",
                    stage = detected.Result.FailedStage.ToString(),
                    detected.Result.FailureName,
                });
                return Deliver(
                    GrainMendDetectOutcome.Faulted(detected.Result.FailureName),
                    onCompleted);
            }

            DefectEditItem? edit = GrainMendRegionEdit.From(
                mask.AsSpan(0, checked((int)detected.MaskByteCount)),
                checked((int)detected.Width),
                checked((int)detected.Height),
                detected.SourceWidth,
                detected.SourceHeight,
                detected.RoiX,
                detected.RoiY,
                detected.RoiWidth,
                detected.RoiHeight,
                detected.AcceptedPixels,
                automatic: IsWholeFrame(roi),
                detected.Defects);
            WriteTrace(frame.Id, roi, options, clock.ElapsedMilliseconds, new
            {
                outcome = "completed",
                detected.Width,
                detected.Height,
                detected.SourceWidth,
                detected.SourceHeight,
                detected.RoiX,
                detected.RoiY,
                detected.RoiWidth,
                detected.RoiHeight,
                detected.AcceptedPixels,
                detected.MaskByteCount,
                markedPixels = CountMarkedPixels(mask, detected.MaskByteCount),
                editCreated = edit is not null,
            });
            return Deliver(
                new GrainMendDetectOutcome(
                    DevelopExportOutcomeKind.Completed,
                    edit,
                    detected.Width,
                    detected.Height,
                    DevelopRequestRefusal.None,
                    null,
                    detected.AutomaticFalsePositiveRisk),
                onCompleted);
        }
        catch (Exception error) when (error is NativeBootstrapException or
            OverflowException or ArgumentException)
        {
            WriteTrace(frame.Id, roi, options, clock.ElapsedMilliseconds, new
            {
                outcome = "exception",
                exception = error.GetType().Name,
            });
            return Deliver(GrainMendDetectOutcome.Faulted(error.Message), onCompleted);
        }
    }

    private static long CountMarkedPixels(byte[] mask, ulong maskByteCount)
    {
        if (!TraceEnabled() || maskByteCount > (ulong)mask.Length)
        {
            return -1L;
        }
        long count = 0L;
        for (int index = 0; index < checked((int)maskByteCount); ++index)
        {
            if (mask[index] != 0)
            {
                ++count;
            }
        }
        return count;
    }

    private static bool TraceEnabled()
    {
        if (string.Equals(
            Environment.GetEnvironmentVariable(TraceEnvironmentVariable),
            "1",
            StringComparison.Ordinal))
        {
            return true;
        }

        try
        {
            return File.Exists(Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Negaflow",
                "Development",
                TraceMarkerFileName));
        }
        catch (Exception error) when (error is IOException or
            UnauthorizedAccessException or ArgumentException or NotSupportedException)
        {
            return false;
        }
    }

    private static void WriteTrace(
        string frameId,
        DefectRect roi,
        GrainMendDetectionOptions options,
        long elapsedMilliseconds,
        object result)
    {
        if (!TraceEnabled() ||
            StorageRootResolver.ResolveProduction().Roots is not { } roots)
        {
            return;
        }
        try
        {
            string line = JsonSerializer.Serialize(new
            {
                timestampUtc = DateTimeOffset.UtcNow,
                frameId,
                roi,
                options,
                elapsedMilliseconds,
                result,
            });
            lock (TraceGate)
            {
                Directory.CreateDirectory(roots.LogRoot);
                File.AppendAllText(
                    Path.Combine(roots.LogRoot, TraceFileName),
                    line + Environment.NewLine);
            }
        }
        catch (Exception error) when (error is IOException or
            UnauthorizedAccessException or ArgumentException or NotSupportedException)
        {
            // 진단 로그가 제품 동작을 바꿔서는 안 됩니다.
        }
    }

    private static bool IsWholeFrame(DefectRect roi) =>
        roi.X == 0.0 && roi.Y == 0.0 && roi.Width == 1.0 && roi.Height == 1.0;

    private bool Deliver(
        GrainMendDetectOutcome outcome,
        Action<GrainMendDetectOutcome> onCompleted)
    {
        if (dispatcher.HasThreadAccess)
        {
            onCompleted(outcome);
            return true;
        }
        // 큐에 못 넣었다는 것은 창이 닫혔다는 뜻입니다. 결과는 버립니다.
        return dispatcher.TryEnqueue(() => onCompleted(outcome));
    }
}
