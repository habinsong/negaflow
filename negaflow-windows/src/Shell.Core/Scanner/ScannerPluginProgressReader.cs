using System.Text.Json;

namespace Negaflow.Shell;

/// <summary>
/// 스캔이 <b>도는 동안</b> 흘러나오는 진행 한 줄을 읽습니다.
/// </summary>
/// <remarks>
/// <see cref="ScannerPluginProtocol.ValidateV2"/> 는 프로세스가 끝난 뒤 전체 줄을 놓고 계약을
/// 검사하는 자리입니다 — 차례·중복·요청 일치를 엄격히 봅니다. 그것은 그대로 두어야 합니다.
/// 여기서는 <b>화면에 그릴 값</b>만 읽습니다. 읽지 못한 줄은 조용히 건너뜁니다 — 진행률 표시가
/// 스캔의 성패를 바꾸어서는 안 됩니다.
///
/// 플러그인이 보내는 모양(<c>wire/event.h</c> <c>ScanEventV2</c>):
/// <code>
/// {"protocolVersion":2,"type":"progress","requestID":"…","sequence":7,
///  "phase":"scanningRGB","fraction":0.42,"message":"…"}
/// </code>
/// </remarks>
public static class ScannerPluginProgressReader
{
    /// <summary>진행 한 줄이면 그 내용을, 아니면 <see langword="null"/> 을 돌려줍니다.</summary>
    public static ScanProgressReport? TryRead(string line, Guid requestId)
    {
        if (string.IsNullOrWhiteSpace(line))
        {
            return null;
        }
        try
        {
            using JsonDocument document = JsonDocument.Parse(line);
            JsonElement root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !root.TryGetProperty("type", out JsonElement type) ||
                type.ValueKind != JsonValueKind.String ||
                !string.Equals(type.GetString(), "progress", StringComparison.Ordinal))
            {
                return null;
            }
            // 다른 요청의 늦은 진행 줄이 지금 화면을 흔들지 않게 합니다.
            if (requestId != Guid.Empty &&
                (!root.TryGetProperty("requestID", out JsonElement request) ||
                 request.ValueKind != JsonValueKind.String ||
                 !Guid.TryParseExact(request.GetString(), "D", out Guid actual) ||
                 actual != requestId))
            {
                return null;
            }
            if (!root.TryGetProperty("phase", out JsonElement phase) ||
                phase.ValueKind != JsonValueKind.String ||
                ScanProgressState.Parse(phase.GetString()) is not { } parsed)
            {
                return null;
            }
            double? fraction = null;
            if (root.TryGetProperty("fraction", out JsonElement value) &&
                value.ValueKind == JsonValueKind.Number &&
                value.TryGetDouble(out double number) &&
                double.IsFinite(number))
            {
                fraction = Math.Clamp(number, 0.0, 1.0);
            }
            string message = root.TryGetProperty("message", out JsonElement text) &&
                text.ValueKind == JsonValueKind.String
                ? text.GetString() ?? string.Empty
                : string.Empty;
            return new ScanProgressReport(parsed, fraction, message);
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
