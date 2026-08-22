using Negaflow.Interop;
using Negaflow.Shell.Library;

namespace Negaflow.Shell;

public sealed record PreviewOutcome(
    DevelopExportOutcomeKind Kind,
    byte[]? Pixels,
    uint Width,
    uint Height,
    DevelopExportResult? Result,
    DevelopRequestRefusal Refusal,
    string? FaultMessage,
    /// <summary>
    /// macOS <c>fullMaxDimension</c> 정착 패스의 결과입니다. 썸네일·인화가 기억하는
    /// <c>ScanFrame.developedImage</c> 는 정착본에서만 만들어집니다 — 인터랙티브 패스는
    /// 끄는 동안 수십 번 오므로 그때마다 34MB 를 복사하면 UI 스레드가 멎습니다.
    /// </summary>
    bool Settled = false,
    /// <summary>
    /// 이 그림이 어느 편집 상태의 것인지입니다. 요청마다 하나씩 올라갑니다.
    /// </summary>
    /// <remarks>
    /// 화면은 <b>자기가 그린 것보다 낮은 리비전을 버려야</b> 합니다. 배달은
    /// <c>dispatcher.TryEnqueue</c> 로 UI 큐에 실리므로 두 장이 연달아 실릴 수 있고,
    /// 그러면 나중에 처리되는 쪽이 <b>더 옛 그림</b>일 수 있습니다. 실제로 그 때문에
    /// 노출을 올렸다 내리면 내려간 그림이 화면에 안 남았습니다.
    /// </remarks>
    int Revision = 0,
    /// <summary>이 그림이 어느 프레임의 것인지입니다. 사진 전환 뒤 옛 장 배달을 버립니다.</summary>
    string? FrameId = null,
    /// <summary>정상 보기의 원본·레시피·엔진이 렌더 전과 같은지 확인하는 cache identity입니다.</summary>
    DevelopedPreviewCacheIdentity? CacheIdentity = null)
{
    internal static PreviewOutcome Refused(DevelopRequestRefusal refusal, int revision) =>
        new(DevelopExportOutcomeKind.Refused, null, 0, 0, null, refusal, null, false, revision);

    internal static PreviewOutcome Faulted(string message, int revision) =>
        new(DevelopExportOutcomeKind.Faulted, null, 0, 0, null,
            DevelopRequestRefusal.None, message, false, revision);

    internal static PreviewOutcome Cancelled() =>
        new(DevelopExportOutcomeKind.Cancelled, null, 0, 0, null,
            DevelopRequestRefusal.None, null);
}
