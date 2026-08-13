using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

public sealed record GrainMendDetectOutcome(
    DevelopExportOutcomeKind Kind,
    DefectEditItem? Edit,
    uint Width,
    uint Height,
    DevelopRequestRefusal Refusal,
    string? FaultMessage)
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
    /// <summary>
    /// 검출 이미지의 긴 변 상한입니다. 네이티브 <c>grain_mend_maximum_detection_dimension</c>
    /// 과 같은 값이며, 마스크 버퍼를 한 번만 잡기 위해 여기서도 압니다.
    /// </summary>
    private const int MaximumDetectionDimension = 1800;

    private readonly IDevelopExporter exporter;
    private readonly IUiDispatcher dispatcher;
    private readonly byte[] mask =
        new byte[MaximumDetectionDimension * MaximumDetectionDimension];

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
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(onCompleted);

        // 검출은 파일을 쓰지 않지만 요청 팩토리는 목적지를 요구합니다.
        string unusedDestination = Path.ChangeExtension(frame.SourcePath, ".detect.png");
        DevelopRequestResult built = DevelopRequestFactory.Create(frame, unusedDestination);
        if (built.Request is not { } request)
        {
            return Deliver(GrainMendDetectOutcome.Refused(built.Refusal), onCompleted);
        }

        try
        {
            GrainMendDetectionResult detected = await Task.Run(
                () => exporter.DetectGrainMend(request, mask, roi)).ConfigureAwait(false);
            if (!detected.Result.Succeeded)
            {
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
                automatic: IsWholeFrame(roi));
            return Deliver(
                new GrainMendDetectOutcome(
                    DevelopExportOutcomeKind.Completed,
                    edit,
                    detected.Width,
                    detected.Height,
                    DevelopRequestRefusal.None,
                    null),
                onCompleted);
        }
        catch (Exception error) when (error is NativeBootstrapException or
            OverflowException or ArgumentException)
        {
            return Deliver(GrainMendDetectOutcome.Faulted(error.Message), onCompleted);
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
