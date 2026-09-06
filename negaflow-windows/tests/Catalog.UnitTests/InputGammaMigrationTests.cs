using System.Text.Json.Nodes;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;

namespace Negaflow.Catalog.UnitTests;

internal static class InputGammaMigrationTests
{
    internal static void Run()
    {
        JsonObject payload = new() { ["params"] = new JsonObject { ["exposure"] = 0.5 }, ["future"] = "keep" };
        Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> tables = new()
        { [CatalogEntityTable.Frames] = [new("frame", payload)] };
        var legacy = new CatalogSnapshot(1, 1, "roll", tables);
        Check(CatalogVersionMigration.CanPromote(1), "gamma_v1_migration_exists");
        Check(CatalogVersionMigration.TryPromote(legacy, 1, out var promoted), "gamma_v1_promotes");
        Check(promoted.CatalogVersion == 2 && promoted.MinimumReaderVersion == 2, "gamma_v2_reader_contract");
        Check(promoted.ActiveRollId == "roll" && promoted.Rows(CatalogEntityTable.Frames).Count == 1, "gamma_migration_preserves_library");
        Check(JsonNode.DeepEquals(payload, promoted.Rows(CatalogEntityTable.Frames)[0].Payload), "gamma_migration_preserves_unknown_fields");
        promoted.Rows(CatalogEntityTable.Frames)[0].Payload["future"] = "changed";
        Check(payload["future"]!.GetValue<string>() == "keep", "gamma_migration_does_not_alias_source");

        byte[] backup = CatalogBackupCodec.SerializeCatalog(legacy);
        Check(CatalogBackupCodec.TryDeserializeCatalog(backup, out var decoded), "gamma_legacy_backup_readable");
        Check(decoded.CatalogVersion == 1 && decoded.MinimumReaderVersion == 1, "gamma_backup_retains_original_version_until_promotion");
        Check(CatalogVersionMigration.TryPromote(decoded, decoded.CatalogVersion, out var restored), "gamma_legacy_backup_promotes");
        restored.Rows(CatalogEntityTable.Frames)[0].Payload["params"]!["inputGamma"] = 1.2345;
        restored.Rows(CatalogEntityTable.Frames)[0].Payload["params"]!["baseScale"] = 1.5;
        Check(CatalogBackupCodec.TryDeserializeCatalog(CatalogBackupCodec.SerializeCatalog(restored), out var roundtrip), "gamma_v2_backup_roundtrip");
        Check(JsonNode.DeepEquals(restored.Rows(CatalogEntityTable.Frames)[0].Payload, roundtrip.Rows(CatalogEntityTable.Frames)[0].Payload),
            "gamma_backup_preserves_exact_parameters");
        var unsupported = new CatalogSnapshot(1, 99, null, tables);
        Check(!CatalogVersionMigration.TryPromote(unsupported, 1, out _), "gamma_unknown_reader_not_downgraded");
    }
}
