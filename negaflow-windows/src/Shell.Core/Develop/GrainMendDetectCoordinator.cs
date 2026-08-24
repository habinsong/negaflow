using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Library;

namespace Negaflow.Shell;

public sealed record GrainMendDetectOutcome(
    DevelopExportOutcomeKind Kind,
    uint Width,
    uint Height,
    DevelopRequestRefusal Refusal,
    string? FaultMessage,
    // macOS `DefectLabelField.automaticFalsePositiveRisk`. 전체 프레임 자동에서만 서고,
    // 성분을 하나도 버리지 않습니다 — 캡슐이 개수 대신 경고 문구를 냅니다.
    bool AutomaticFalsePositiveRisk = false,
    IGrainMendReviewProposal? ReviewProposal = null,
    GrainMendDetectionToken? DetectionToken = null) : IDisposable
{
    /// <summary>검출은 됐지만 고칠 것이 없었습니다. 실패가 아닙니다.</summary>
    public bool FoundNothing => Kind == DevelopExportOutcomeKind.Completed &&
        ReviewProposal is null;

    public void Dispose() => ReviewProposal?.Dispose();

    internal static GrainMendDetectOutcome Refused(DevelopRequestRefusal refusal) =>
        new(DevelopExportOutcomeKind.Refused, 0U, 0U, refusal, null);

    internal static GrainMendDetectOutcome Faulted(string message) =>
        new(DevelopExportOutcomeKind.Faulted, 0U, 0U, DevelopRequestRefusal.None, message);
}

/// <summary>한 번의 GrainMend 검출이 읽은 source와 전체 develop recipe의 불변 identity입니다.</summary>
public sealed class GrainMendDetectionToken
{
    private readonly byte[] recipeSha256;

    internal GrainMendDetectionToken(
        string frameId,
        string sourcePath,
        DefectSourceIdentity? sourceIdentity,
        byte[] recipeSha256)
    {
        FrameId = frameId;
        SourcePath = sourcePath;
        SourceIdentity = sourceIdentity;
        this.recipeSha256 = recipeSha256;
    }

    public string FrameId { get; }

    internal string SourcePath { get; }

    internal DefectSourceIdentity? SourceIdentity { get; }

    public bool Matches(GrainMendDetectionToken other)
    {
        ArgumentNullException.ThrowIfNull(other);
        return string.Equals(FrameId, other.FrameId, StringComparison.Ordinal) &&
            string.Equals(SourcePath, other.SourcePath, StringComparison.Ordinal) &&
            SourceIdentity == other.SourceIdentity &&
            recipeSha256.AsSpan().SequenceEqual(other.recipeSha256);
    }

    public bool MatchesRecipe(LibraryFrameSnapshot frame)
    {
        ArgumentNullException.ThrowIfNull(frame);
        return TryCreate(
                frame,
                ReadSourceIdentity(frame.SourcePath),
                out GrainMendDetectionToken? current) &&
            current is not null && Matches(current);
    }

    public Task<bool> MatchesRecipeAsync(LibraryFrameSnapshot frame)
    {
        ArgumentNullException.ThrowIfNull(frame);
        return Task.Run(() => MatchesRecipe(frame));
    }

    public static Task<bool> SameDevelopRecipeAsync(
        LibraryFrameSnapshot left,
        LibraryFrameSnapshot right)
    {
        ArgumentNullException.ThrowIfNull(left);
        ArgumentNullException.ThrowIfNull(right);
        return Task.Run(() =>
            TryCreate(left, null, out GrainMendDetectionToken? leftToken) &&
            TryCreate(right, null, out GrainMendDetectionToken? rightToken) &&
            leftToken is not null && rightToken is not null &&
            leftToken.Matches(rightToken));
    }

    internal bool MatchesPersistedSource(
        string frameId,
        string sourcePath,
        DefectSourceIdentity sourceIdentity) =>
        SourceIdentity is { } expected && expected == sourceIdentity &&
        string.Equals(FrameId, frameId, StringComparison.Ordinal) &&
        string.Equals(SourcePath, sourcePath, StringComparison.Ordinal);

    public static bool TryCreate(
        LibraryFrameSnapshot frame,
        out GrainMendDetectionToken? token) =>
        TryCreate(frame, ReadSourceIdentity(frame.SourcePath), out token);

    internal static bool TryCreate(
        LibraryFrameSnapshot frame,
        DefectSourceIdentity? sourceIdentity,
        out GrainMendDetectionToken? token)
    {
        ArgumentNullException.ThrowIfNull(frame);
        token = null;
        string unusedDestination = Path.ChangeExtension(frame.SourcePath, ".detect.png");
        DevelopRequestResult built = DevelopRequestFactory.Create(frame, unusedDestination);
        return built.Request is { } request &&
            TryCreate(frame, request, sourceIdentity, out token);
    }

    internal static bool TryCreate(
        LibraryFrameSnapshot frame,
        DevelopExportRequest request,
        DefectSourceIdentity? sourceIdentity,
        out GrainMendDetectionToken? token)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(request);
        token = null;
        try
        {
            token = new GrainMendDetectionToken(
                frame.Id,
                frame.SourcePath,
                sourceIdentity,
                SHA256.HashData(
                    DevelopedPreviewCacheRecipeCodec.Compose(request, frame.DefectRecipe)));
            return true;
        }
        catch (Exception error) when (error is JsonException or NotSupportedException or
            ArgumentException or OverflowException)
        {
            return false;
        }
    }

    internal static DefectSourceIdentity? ReadSourceIdentity(string sourcePath) =>
        DefectSourceIdentityReader.TryRead(sourcePath, out DefectSourceIdentity identity)
            ? identity
            : null;
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

    private readonly IDevelopExporter exporter;
    private readonly IUiDispatcher dispatcher;

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
        bool automatic,
        Action<GrainMendDetectOutcome> onCompleted)
    {
        return await RunAsync(
            frame,
            roi,
            GrainMendSensitivity.ToDetectionOptions(GrainMendSensitivity.Default, automatic),
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
        Action<GrainMendDetectOutcome> onCompleted,
        DevelopRun? run = null)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(onCompleted);
        Stopwatch clock = Stopwatch.StartNew();

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

        IGrainMendReviewProposal? proposal = null;
        try
        {
            DefectSourceIdentity? sourceBefore = null;
            DefectSourceIdentity? sourceAfter = null;
            GrainMendDetectionResult detected = await Task.Run(() =>
            {
                sourceBefore = GrainMendDetectionToken.ReadSourceIdentity(frame.SourcePath);
                GrainMendDetectionResult value = exporter.DetectGrainMend(request, roi, options, run);
                sourceAfter = GrainMendDetectionToken.ReadSourceIdentity(frame.SourcePath);
                return value;
            }).ConfigureAwait(false);
            proposal = detected.ReviewProposal;
            if (!detected.Result.Succeeded)
            {
                proposal?.Dispose();
                proposal = null;
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
            if (sourceBefore is null || sourceAfter is null || sourceBefore != sourceAfter ||
                !GrainMendDetectionToken.TryCreate(
                    frame, request, sourceAfter, out GrainMendDetectionToken? detectionToken))
            {
                proposal?.Dispose();
                proposal = null;
                return Deliver(
                    GrainMendDetectOutcome.Faulted("grain_mend_detection_input_changed"),
                    onCompleted);
            }

            if (proposal is null &&
                (detected.AcceptedPixels != 0UL || detected.Defects.Count != 0))
            {
                const string ownershipFailure =
                    "A non-empty GrainMend detection did not return review ownership.";
                WriteTrace(frame.Id, roi, options, clock.ElapsedMilliseconds, new
                {
                    outcome = "contract-failure",
                    reason = ownershipFailure,
                });
                return Deliver(GrainMendDetectOutcome.Faulted(ownershipFailure), onCompleted);
            }
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
                exactReviewCreated = proposal is not null,
            });
            GrainMendDetectOutcome outcome = new(
                DevelopExportOutcomeKind.Completed,
                detected.Width,
                detected.Height,
                DevelopRequestRefusal.None,
                null,
                detected.AutomaticFalsePositiveRisk,
                proposal,
                detectionToken);
            proposal = null;
            return Deliver(outcome, onCompleted);
        }
        catch (Exception error) when (error is NativeBootstrapException or
            OverflowException or ArgumentException)
        {
            proposal?.Dispose();
            WriteTrace(frame.Id, roi, options, clock.ElapsedMilliseconds, new
            {
                outcome = "exception",
                exception = error.GetType().Name,
            });
            return Deliver(GrainMendDetectOutcome.Faulted(error.Message), onCompleted);
        }
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

    private bool Deliver(
        GrainMendDetectOutcome outcome,
        Action<GrainMendDetectOutcome> onCompleted)
    {
        if (dispatcher.HasThreadAccess)
        {
            try
            {
                onCompleted(outcome);
                return true;
            }
            catch
            {
                outcome.Dispose();
                throw;
            }
        }
        // 큐에 못 넣었다는 것은 창이 닫혔다는 뜻입니다. 결과는 버립니다.
        if (!dispatcher.TryEnqueue(() =>
            {
                try
                {
                    onCompleted(outcome);
                }
                catch
                {
                    outcome.Dispose();
                    throw;
                }
            }))
        {
            outcome.Dispose();
            return false;
        }
        return true;
    }
}
