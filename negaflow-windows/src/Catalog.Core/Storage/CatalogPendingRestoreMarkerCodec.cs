using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

internal static class CatalogPendingRestoreMarkerCodec
{
    public static byte[] Serialize(CatalogPendingRestoreMarker marker) =>
        CatalogJson.SerializeCanonical(new JsonObject
        {
            ["version"] = marker.Version,
            ["directoryName"] = marker.DirectoryName,
            ["sourceGenerationID"] = marker.SourceGenerationId,
            ["scheduledAt"] = marker.ScheduledAt.ToUniversalTime()
                .ToString("O", CultureInfo.InvariantCulture),
            ["phase"] = PhaseName(marker.Phase),
        });

    public static bool TryDeserialize(
        ReadOnlySpan<byte> data,
        out CatalogPendingRestoreMarker marker)
    {
        marker = null!;
        try
        {
            if (JsonNode.Parse(data) is not JsonObject root ||
                root["version"] is not JsonValue versionValue ||
                !versionValue.TryGetValue(out int version) ||
                version < CatalogPendingRestoreMarker.MinimumSupportedVersion ||
                version > CatalogPendingRestoreMarker.CurrentVersion ||
                root["directoryName"] is not JsonValue directoryValue ||
                !directoryValue.TryGetValue(out string? directoryName) ||
                root["sourceGenerationID"] is not JsonValue generationValue ||
                !generationValue.TryGetValue(out string? sourceGenerationId) ||
                root["scheduledAt"] is not JsonValue scheduledValue ||
                !scheduledValue.TryGetValue(out string? scheduledText) ||
                !DateTimeOffset.TryParse(
                    scheduledText,
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.RoundtripKind,
                    out DateTimeOffset scheduledAt))
            {
                return false;
            }

            bool hasPhase = root.TryGetPropertyValue("phase", out JsonNode? phaseNode);
            if (root.Count != (hasPhase ? 5 : 4) ||
                root.Any(property => property.Key is not
                    ("version" or "directoryName" or "sourceGenerationID" or
                     "scheduledAt" or "phase")))
            {
                return false;
            }

            CatalogPendingRestorePhase phase = CatalogPendingRestorePhase.Scheduled;
            if (hasPhase &&
                (phaseNode is not JsonValue phaseValue ||
                 !phaseValue.TryGetValue(out string? phaseText) ||
                 !TryParsePhase(phaseText, out phase)))
            {
                return false;
            }
            if (version >= CatalogPendingRestoreMarker.CurrentVersion && !hasPhase)
            {
                return false;
            }

            marker = new CatalogPendingRestoreMarker(
                version,
                directoryName,
                sourceGenerationId,
                scheduledAt.ToUniversalTime(),
                phase);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    public static bool Matches(
        CatalogPendingRestoreMarker first,
        CatalogPendingRestoreMarker second) =>
        first.Version == second.Version &&
        first.DirectoryName == second.DirectoryName &&
        first.SourceGenerationId == second.SourceGenerationId &&
        first.ScheduledAt.EqualsExact(second.ScheduledAt) &&
        first.Phase == second.Phase;

    private static string PhaseName(CatalogPendingRestorePhase phase) => phase switch
    {
        CatalogPendingRestorePhase.Scheduled => "scheduled",
        CatalogPendingRestorePhase.Applied => "applied",
        _ => throw new ArgumentOutOfRangeException(nameof(phase)),
    };

    private static bool TryParsePhase(
        string? value,
        out CatalogPendingRestorePhase phase)
    {
        phase = value switch
        {
            "scheduled" => CatalogPendingRestorePhase.Scheduled,
            "applied" => CatalogPendingRestorePhase.Applied,
            _ => default,
        };
        return value is "scheduled" or "applied";
    }
}
