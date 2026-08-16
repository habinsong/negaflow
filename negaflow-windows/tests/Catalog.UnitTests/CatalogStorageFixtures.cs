using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.CatalogStorageFixtures;

namespace Negaflow.Catalog.UnitTests;

internal static class CatalogStorageFixtures
{
    internal static void SetStorageVersion(string catalogPath, int version) =>
        ExecuteFixtureSql(catalogPath, $"PRAGMA user_version={version}");

    internal static void SetCatalogVersion(string catalogPath, int version) =>
        ExecuteFixtureSql(
            catalogPath,
            $"UPDATE catalog_metadata SET catalog_version={version} WHERE singleton=1");

    internal static void ExecuteFixtureSql(string catalogPath, string sql)
    {
        SqliteConnectionStringBuilder builder = new()
        {
            DataSource = catalogPath,
            Mode = SqliteOpenMode.ReadWrite,
            Pooling = false,
        };
        using SqliteConnection connection = new(builder.ConnectionString);
        connection.Open();
        using SqliteCommand command = connection.CreateCommand();
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    internal static CatalogEntityRow Row(string id, string label) =>
        new(id, new JsonObject { ["label"] = label });

    internal static CatalogSnapshot Snapshot(
        string? activeRollId,
        params CatalogEntityRow[] frames) =>
        new(activeRollId, new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
        {
            [CatalogEntityTable.Frames] = frames,
        });

    internal static string FrameOrder(CatalogReadResult result) =>
        result.Snapshot is null
            ? "<none>"
            : string.Join(',', result.Snapshot.Rows(CatalogEntityTable.Frames)
                .Select(row => row.Id));

    internal static string FrameLabels(CatalogReadResult result) =>
        result.Snapshot is null
            ? "<none>"
            : string.Join(',', result.Snapshot.Rows(CatalogEntityTable.Frames)
                .Select(row => row.Payload["label"]!.GetValue<string>()));

}
