using System.Text.Json;

namespace Negaflow.Shell;

public enum ScannerPluginStreamStatus
{
    Accepted,
    InvalidJson,
    InvalidEvent,
    ProtocolMismatch,
    RequestMismatch,
    SequenceViolation,
    TerminalViolation,
}

public sealed record ScannerPluginStreamEvent(
    string Type,
    ulong Sequence,
    JsonElement Payload);

public sealed record ScannerPluginStreamValidation(
    ScannerPluginStreamStatus Status,
    ScannerPluginStreamEvent? TerminalEvent)
{
    public bool IsSuccess => Status == ScannerPluginStreamStatus.Accepted && TerminalEvent is not null;
}

// Protocol v2 is deliberately strict: an adapter cannot turn a different request's result,
// a stale progress event, or a second terminal event into a Library frame.
public static class ScannerPluginProtocol
{
    public const int StreamProtocolVersion = 2;

    public static ScannerPluginStreamValidation ValidateV2(
        IEnumerable<string> lines,
        Guid requestId)
    {
        ArgumentNullException.ThrowIfNull(lines);
        if (requestId == Guid.Empty)
        {
            throw new ArgumentOutOfRangeException(nameof(requestId));
        }

        ulong previousSequence = 0;
        bool hasSequence = false;
        ScannerPluginStreamEvent? terminal = null;
        foreach (string line in lines)
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                return new(ScannerPluginStreamStatus.InvalidJson, null);
            }

            JsonDocument document;
            try
            {
                document = JsonDocument.Parse(line);
            }
            catch (JsonException)
            {
                return new(ScannerPluginStreamStatus.InvalidJson, null);
            }

            using (document)
            {
                JsonElement root = document.RootElement;
                if (root.ValueKind != JsonValueKind.Object ||
                    !TryGetInt32(root, "protocolVersion", out int protocolVersion) ||
                    protocolVersion != StreamProtocolVersion)
                {
                    return new(ScannerPluginStreamStatus.ProtocolMismatch, null);
                }
                if (!TryGetGuid(root, "requestID", out Guid actualRequest) || actualRequest != requestId)
                {
                    return new(ScannerPluginStreamStatus.RequestMismatch, null);
                }
                if (!TryGetUInt64(root, "sequence", out ulong sequence) ||
                    (hasSequence && sequence <= previousSequence))
                {
                    return new(ScannerPluginStreamStatus.SequenceViolation, null);
                }

                hasSequence = true;
                previousSequence = sequence;
                if (!TryGetString(root, "type", out string? type) ||
                    type is not ("progress" or "result" or "error"))
                {
                    return new(ScannerPluginStreamStatus.InvalidEvent, null);
                }
                if (terminal is not null)
                {
                    return new(ScannerPluginStreamStatus.TerminalViolation, null);
                }
                if (type == "progress")
                {
                    if (!TryGetFiniteUnitInterval(root, "fraction"))
                    {
                        return new(ScannerPluginStreamStatus.InvalidEvent, null);
                    }
                    continue;
                }
                if (type == "error" &&
                    (!TryGetString(root, "message", out string? message) ||
                     string.IsNullOrWhiteSpace(message)))
                {
                    return new(ScannerPluginStreamStatus.InvalidEvent, null);
                }

                terminal = new ScannerPluginStreamEvent(type, sequence, root.Clone());
            }
        }

        return terminal is null
            ? new(ScannerPluginStreamStatus.TerminalViolation, null)
            : new(ScannerPluginStreamStatus.Accepted, terminal);
    }

    private static bool TryGetInt32(JsonElement value, string name, out int result)
    {
        result = default;
        return value.TryGetProperty(name, out JsonElement property) && property.TryGetInt32(out result);
    }

    private static bool TryGetUInt64(JsonElement value, string name, out ulong result)
    {
        result = default;
        return value.TryGetProperty(name, out JsonElement property) && property.TryGetUInt64(out result);
    }

    private static bool TryGetGuid(JsonElement value, string name, out Guid result)
    {
        result = default;
        return value.TryGetProperty(name, out JsonElement property) &&
               property.ValueKind == JsonValueKind.String &&
               Guid.TryParseExact(property.GetString(), "D", out result);
    }

    private static bool TryGetString(JsonElement value, string name, out string? result)
    {
        result = null;
        if (!value.TryGetProperty(name, out JsonElement property) ||
            property.ValueKind != JsonValueKind.String)
        {
            return false;
        }
        result = property.GetString();
        return result is not null;
    }

    private static bool TryGetFiniteUnitInterval(JsonElement value, string name)
    {
        if (!value.TryGetProperty(name, out JsonElement property) ||
            property.ValueKind != JsonValueKind.Number || !property.TryGetDouble(out double result))
        {
            return false;
        }
        return double.IsFinite(result) && result is >= 0.0 and <= 1.0;
    }
}
