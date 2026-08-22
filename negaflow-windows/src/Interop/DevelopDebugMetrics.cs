namespace Negaflow.Interop;

/// <summary>
/// 현상이 실제로 잰 값입니다. macOS <c>DevelopDebugMetrics</c> 와 같은 넷입니다.
/// </summary>
/// <remarks>
/// 네거티브 반전이 돈 호출에서만 나옵니다. 포지티브·디지털 경로는 이 값을 재지 않으므로
/// <c>null</c> 이며, 화면은 지어낸 숫자 대신 아무 것도 적지 않습니다.
/// </remarks>
public sealed record DevelopDebugMetrics(
    float DminRed,
    float DminGreen,
    float DminBlue,
    float DmaxNormalizedRed,
    float DmaxNormalizedGreen,
    float DmaxNormalizedBlue,
    float BlackInputRed,
    float BlackInputGreen,
    float BlackInputBlue);
